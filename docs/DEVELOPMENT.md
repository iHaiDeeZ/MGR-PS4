# Development notes

How the PS4 port of [mgr-nx-deko](https://github.com/tuancapoo/mgr-nx-deko) is built, what it changes and what was
learned on the way. For building and installing, see the [README](../README.md#getting-started).

## What upstream is

- **CPU:** the game's `default.xex` (PowerPC) statically recompiled to C++ by ReXGlue, a Xenia-derived SDK (forked in
  `sdk/`, base rexglue-sdk v0.10.0). The recompiled code is made from the user's own game.
- **GPU:** not Xenia's PM4/Xenos emulation. The game's Direct3D calls are hooked and drawn by the Renut renderer
  (`app/src/renut_engine`) through plume (`app/thirdparty/plume`), which has Vulkan, D3D12, Metal and deko3d back ends.
  The Switch build uses deko3d.
- **Shaders:** the game's 1,202 shader containers in `media/data000.cpk` go through XenosRecomp to HLSL, then SPIR-V.

## The layout

`scripts/build-mgr.sh` (WSL) works on these folders:

| Folder | What |
|---|---|
| `~/mgr-build/src/mgr-nx-deko` | upstream at `patches/BASE.txt` (`d4bc16e`), branch `ps4` = the base + `patches/mgr-ps4.patch` |
| `~/mgr-build/src/rexglue-sdk` | rexglue-sdk v0.10.0 (`c94f5eb`) with its submodules: the third-party sources the fork doesn't carry, copied into `sdk/thirdparty` |
| `~/mgr-build/src/dxc-bin` | renderbag/dxc-bin `737ac9f`: XenosRecomp's DXC |
| `~/mgr-build/game` | your extracted disc (`default.xex` + `media/`) |
| `~/mgr-build/build-sdk`, `build-host`, `build-xenos`, `build-app` | the SDK for the PS4 alone (`sdk` step), the host code generator, XenosRecomp, the eboot |
| `~/mgr-build/shaders` | the shader containers, the SPIR-V cache and the shaders captured on the console (game data: never distribute) |
| `~/mgr-build/oelf/vXX.YY.elf` | the unstripped ELF of each package, for symbolizing crash logs and profiles |

`patches/ffmpeg/` is the PS4's FFmpeg configuration (`config.h` picks `config_ps4_x86_64.h` for `__PS4__`); FFmpeg's
`.gitignore` hides both from the fork's git, so the build script copies them in. `scripts/save-patch.sh` exports the
checkout's changes to `patches/mgr-ps4.patch` (new files as intent-to-add entries; `app/codegen_flavor.toml`, which the
codegen step writes, is left out).

`MGR_SRC` and `MGR_APP_BUILD` point the script at a second checkout and build folder, for A/B builds.

## The PS4 route

The rule: a full x86-64 conversion. Everything is built from the SDK's x86-64 paths for the Jaguar, and PS4 code is
written for x86-64. The Switch's `*_switch.cpp` files are only a map of the OS gaps; none of their AArch64 code (fiber
assembly, fault decoding, NEON) is carried over.

| Upstream part | PS4 |
|---|---|
| SDK platform layer (`*_switch.cpp`) | the SDK's own POSIX files (`*_posix.cpp`) with PS4 branches, the Switch fork's tuning where it isn't ARM code, and `*_ps4.cpp` where OpenOrbis differs |
| Guest memory (4.5 GB window, mirrors at `0xA0`/`0xC0`/`0xE0`, faults for MMIO and write watches) | the window reserved with `sceKernelReserveVirtualRange`; physical memory is direct memory, committed in 64 KB chunks on first touch (zeroed privately before it is mapped, so no other thread's writes are lost) and mapped at every mirror (`sceKernelEnableDmemAliasing`); the 360's 4 KB permissions kept on 16 KB kernel pages |
| Renderer: plume deko3d | plume's **Vulkan** back end on ps4-kit's Mesa RADV (only `VK_KHR_swapchain` is required) and the kit's VideoOut swapchain |
| Shaders: DKSH package | SPIR-V compiled into the eboot (`BANJO_RENUT_SHADER_CACHE_CPP`); RADV's pipeline cache in `/data/MGR` |
| Code generation: `-march=armv8-a` | the x86-64 path of `rexglue_helpers.cmake` (`-msse4.1`) plus `-march=btver2` (Jaguar: AVX, no AVX2, no FMA) |
| Audio (`switch_audio_system.cpp`) | `sceAudioOut` |
| Input (`switch_input_driver.cpp`) | `scePad` |
| Files: `sdmc:/switch/mgr-nx-deko/` | `/data/MGR/` (`PS4_DIAG_DATA_DIR`), the game in `/data/MGR/game_root` |

### The PS4 files

| File | What |
|---|---|
| `sdk/src/core/guest_memory_ps4.{h,cpp}` | the window, direct memory in 64 KB chunks, every view mapped with its own access, logical 4 KB permissions on 16 KB pages |
| `sdk/src/core/memory_ps4.cpp` | the `rex::memory` API on top; allocation granularity 64 KB, so the `0xE0000000` heap has the 4 KB host offset (`PhysicalHostOffset`, `REX_PHYS_HOST_OFFSET`), as on Windows |
| `sdk/src/core/exception_handler_ps4.cpp` | FreeBSD `mcontext`; sibling faults (an allowed 4 KB page in a closed 16 KB page) single-stepped with the trap flag; unhandled faults chained to the kit's crash log |
| `sdk/src/core/fiber_ps4.cpp` | an x86-64 System V stack switch (libkernel has no `makecontext`) |
| `sdk/src/core/dynlib_ps4.cpp`, `seh_ps4.cpp` | no `dlopen`; SEH faults are fatal (no throw out of signal frames) |
| `threading_posix.cpp` (PS4 branches) | `pthread_suspend_np`/`pthread_resume_np` for suspension; user APCs queued for alertable points (no signals: they froze earlier ports inside libkernel waits); thread stacks from direct memory (`ps4_stack`, a 16 KB guard page under each, a pool of 8); no robust mutexes |
| `sdk/src/core/clock_posix.cpp` (PS4 branch) | host ticks = the TSC (`sceKernelGetTscFrequency` + `rdtsc`) |
| `sdk/src/audio/ps4/ps4_audio_system.cpp` | one `sceAudioOut` port, 48 kHz float stereo, 256-sample grain (one 360 audio frame), paced by the blocking output; 5.1 folded with the SDK's `StereoFold`; `audio_mute` |
| `sdk/src/input/ps4/ps4_input_driver.cpp` | DS4 through `scePad`, slot n = the n-th signed-in user; rumble; the SDL driver's keystroke logic |
| `sdk/include/rex/ui/ps4_imgui_input.h` | the DS4 for the SDK's ImGui (Cross accepts, Circle goes back); the game gets a neutral pad while a window has the navigation focus |
| `sdk/src/ui/window_ps4.cpp`, `windowed_app_context_ps4.cpp`, `windowed_app_main_ps4.cpp`, `include/rex/ui/surface_ps4.h` | a 1920x1080 VideoOut window, always focused; the UI loop on a condition variable; `main` leaves through `exit()` |
| `sdk/cmake/rexglue_ps4.cmake` | the runtime linked whole-archive, the PS4 system libraries (ScePad, SceUserService, SceAudioOut) |
| `sdk/src/system/wait_report.cpp` | the `[waits]` and `[clock]` report (below) |
| `app/mgr_src/mgr_ps4.cpp`, `mgr_ps4_menu.{h,cpp}` | the data folder, the frame counter and the L3+R3 quick menu |

Link details: zstd's trace hooks are off (`ZSTD_TRACE=0`: create-fself refuses weak undefined symbols, so they would
become imports), `--undefined=getaddrinfo` (the kit's DNS wrap without netfs), and the export caller is a `__thread`
variable (an `extern thread_local` gives create-fself a weak `_ZTH` import).

## Code generation

`MGR_FLAVOR=optimised scripts/build-mgr.sh codegen` (the releases since v00.07) gives the generator
`app/perf_overrides.toml`'s options (guest CR/CTR/XER/reservation, non-volatile and non-argument registers as C++
locals, no MSR fences, no `lr` stores, modeless FP moves and compares, inline conversions and divisions) and runs the
flavour's source passes (`pch_no_volatile`, `loop_barriers`, `indirect_calls`, `direct_calls`, `pch_cold_traps`,
`flush_mode_flow`, `ro_constants`, `float_loads`, `frame_traffic`, `loop_locals`, `leaf_locals`). Its three AArch64
rewrites (`guest_cas`, `vec_byteswap`, `pch_neon_shuffles`) are skipped: `# codegen-arch: x86-64` in
`app/codegen_flavor.toml` tells `tools/post_codegen.py`. They only change how the C++ is written, so the port stays a
full x86-64 conversion. `MGR_FLAVOR=classic` is the generator's own output with only MGR's jump-table repair.

- The passes' pch macros have three forms: off, the Switch's bare form, and the PC's verifying form (each use loads,
  compares and counts in one shared global). `ro_constants.py`, `flush_mode_flow.py` and `indirect_calls.py` give
  `__PS4__` the bare forms.
- `tools/ps4_unfused_fma.py` rewrites the generated `std::fma` calls (11,909) as `REX_FMA`, a multiply and an add: the
  Jaguar has no FMA unit, and libm's software `fma` was a third of the audio thread in the first profile. A result
  can differ from the fused one in its last bit; Xenia does the same on CPUs without FMA.
- The host generator embeds `sdk/resources/templates` when it is built: after a template change, run
  `scripts/build-mgr.sh host` before the codegen.
- Not done: LTO across the generated units. The kit links with OpenOrbis's `ld.lld` of LLVM 12, which can't read
  clang 21's bitcode.

## Renderer

- plume's PS4 branches: a headless surface, `ps4kit::vk_get_instance_proc_addr`, the VideoOut 1920x1080 swapchain.
  Renut's native window is the VideoOut window. The SDK's ImGui (the only copy, as on the Switch) draws the quick
  menu and the frame counter in Renut's overlay, over every presented frame.
- With Renut, `ConfigureRuntime` clears the SDK's graphics system, so the SDK's own Vulkan presenter is unused.
- FSR 1 (`app/src/renut_engine/gpu/backend/present.cpp`, `video.cpp`, `shaders/host/fsr_{easu,rcas}_ps.hlsl`): EASU
  upscales the frame into a target of the back buffer's size, RCAS sharpens it onto the back buffer and applies the
  game's gamma ramp; only when the frame is smaller than its place on screen. `renut_fsr` (on),
  `renut_fsr_sharpness` (0.2 stops). `ffx_a.h`'s three vector ternaries are `select()` for DXC's `-HV 2021`.
- The real-time cutscenes ask for `D3DPRESENT_INTERVAL_TWO`; `sa2_renut_vblank_pacing` keeps it, so they run at 30
  as on the 360.
- Shaders missing from the cache (built into `default.xex`, not in `data000.cpk`) are captured on the console to
  `/data/MGR/shader_capture`; `scripts/build-mgr.sh shaders` merges `~/mgr-build/shaders/captures/*.bin` into the
  next cache.

## Diagnostics

- `/data/MGR/logs/mgr_NNN.log` (one for every session), ps4-kit's `boot-trace.log` and `crash.log`. Symbolize a crash
  address with `~/mgr-build/oelf/vXX.YY.elf` (ELF address = `rip - 0x400000`; libc's functions have no DWARF, so take
  the nearest symbol from `llvm-nm`).
- `[movie]` lines: every `*.usm` the game opens (`opened (N MB)`), then `reads ended` or `reads STOPPED before its end`
  with how far it was read, once nothing was read from it for 3 s (plain and scatter reads).
- `[waits]` (`kernel_wait_report`, the menu's "Log the game's long waits"; period `kernel_wait_report_s`, 30 s): each
  guest wait (`XObject::Wait`, `WaitMultiple`, `SignalAndWait`, `XThread::Delay`) records its objects, kind, timeout,
  whether it is alertable, the guest `lr` (0 in the optimised flavour, which elides `lr` stores) and the host address
  of the kernel export's caller (`REX_HOOK` stores `__builtin_return_address(0)`). Every period the log lists each
  guest thread waiting 2 s or more.
- `[clock]`: once, the host tick rate and what `clock_getres` says; every period, the guest time against real time
  (`1.000x` when right).
- The CPU profile (the menu's button): ps4-kit's burst profiler samples every thread for 8 s into
  `/data/MGR/profiles/profile_<n>.txt`, numbered per session (each session's first overwrites `profile_1.txt`).
  `ps4-kit/scripts/profile.py --elf ~/mgr-build/oelf/vXX.YY.elf` names the functions.

## History

| Version | What |
|---|---|
| v00.01 | First package. Vulkan on RADV, swapchain flips, guest memory, the game's D3D device and Renut's render thread came up; then a crash in Renut's `RegisterGuestShader` reading a shader through the `0xE0000000` window: every view started at no access, while the 360 reads physical memory through any window. Views take their access since v00.02 |
| v00.02 | Two shaders captured and merged; a naming race in `PosixThread::set_name` fixed (an upstream double free). Then `CreateThread` failed with `C0000017`: libkernel takes thread stacks from flexible memory, 27 guest threads asked for 16 MB each |
| v00.03 | Guest stacks from direct memory, the Switch fork's thread reaper. Then a null title device from `VdGlobalDevice`: Renut's `GuestPtr` was `base + address` off Windows and missed the PS4's 4 KB offset of the `0xE0000000` heap |
| v00.04 | **Works.** Menus 60 fps, real-time cutscenes 30 (the game's interval), gameplay 28-37 fps at 360p, CPU-bound on the game thread (27-35 ms a frame) |
| v00.05 | 720p, FSR 1, the DS4 for ImGui, the frame counter and the L3+R3 quick menu, the `[movie]` lines |
| v00.06 | The optimised codegen: crashed at start (a null critical section in the C runtime's start-up). The D-form macros lacked the PS4's 4 KB offset, because the generator carried an old copy of the template |
| v00.07 | The rebuilt generator, the PS4's bare macro forms, the unfused multiply-adds: heavy play 47-49 fps at 1080p (game thread 16-21 ms a frame, against 33-35 in v00.05), up to 60 elsewhere |
| v00.08 | The `[waits]` report, the `[movie]` line on scatter reads, the PC's census counters off (an atomic add per kernel call on one shared counter) |
| v00.09 | The clock on the TSC: the game ran too fast and the story movies stalled (below) |

### The clock (v00.09)

The SDK's `clock_posix.cpp` took the host tick rate from `clock_getres(CLOCK_MONOTONIC_RAW)` as `1e9 / resolution`
and the ticks from `clock_gettime` of the same clock, in nanoseconds. FreeBSD's `kern_clock_getres` answers
`1e9 / timecounter frequency + 1` ns: 2 ns for a timecounter of 0.5-1 GHz, so the SDK believed in a 500 MHz tick while
it counted nanoseconds, and `KeQueryPerformanceCounter`, the system time and the uptime ran twice as fast. MGR's
engine steps its world from that time. At 30 fps a cap on its steps a frame hid it (v00.04 and v00.05 looked right);
at 50-60 fps the game ran up to twice as fast. The story movies (MPEG-1 video at 29.97 fps timed by that clock, two
ADX tracks, 6 channels and mono, in real time) stalled and restarted, and a pause and resume put them back in step for
a while. The PS4 now counts the TSC, as ps4-kit's `clock_gettime(CLOCK_MONOTONIC)` does, which also saves a system
call per guest clock read. The fix hasn't been confirmed on a console yet: the `[clock]` lines will show `1.000x`.

## The first profile

Taken with v00.05 in heavy play at 1080p (game thread 30-36 ms a frame): Wwise's audio thread 94 % busy, a third of
it in libm's software `fma`; the game's render thread 40 %, mostly waiting in guest kernel waits; Renut's render
thread 42 %, 80 % of it idle; the job threads 8-32 %, mostly waiting. No game thread was CPU-bound: the long frame was
the threads waiting on one another, which the optimised codegen and the unfused multiply-adds cut by about 1.7x.

## Next

- Renut's render thread: 81 % busy in v00.07 (17 ms a frame), so it caps a frame at about 58 fps. Its stream checks
  hash about 545 MB/s of guest vertex data (11.7 MB a frame).
- LTO across the generated units needs a linker that reads clang 21's bitcode.
