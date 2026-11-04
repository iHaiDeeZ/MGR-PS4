# Credits and licences

This repository holds build scripts, one patch (`patches/mgr-ps4.patch`) against
[tuancapoo/mgr-nx-deko](https://github.com/tuancapoo/mgr-nx-deko) at the commit in `patches/BASE.txt`, and the PS4
configuration of FFmpeg (`patches/ffmpeg/`). The patched files keep their own licences.

| Part | Where | Licence |
|---|---|---|
| mgr-nx-deko (tuancapoo), built on sa2-nx (ChanseyIsTheBest), masseffect-nx (NebadasSwifty), nfsmw-nx (StevensND) and NFSMW Recompiled (madelrandel-blip) | the upstream repository; the patch changes its `app/` and `tools/` | GPL-3.0 (upstream `LICENSE`) |
| ReXGlue SDK v0.10.0 (Tom Clay), with portions from [Xenia](https://xenia.jp) (Ben Vanik and the Xenia contributors), and the Switch layer of nfsmw-nx (StevensND) | upstream's `sdk/`; the patch adds the PS4 platform layer and changes the runtime | BSD-3-Clause (upstream `sdk/LICENSE`) |
| Renut (masterspike52), with the adaptations of banjo-nx and sa2-nx | upstream's `app/src/renut_engine`; the patch adds FSR 1 to the present and PS4 branches | no licence file upstream; sa2-nx documents a project-specific permission from its author (upstream `THIRD_PARTY_NOTICES.md`) |
| [plume](https://github.com/renderbag/plume) (renderbag) | upstream's `app/thirdparty/plume`; the patch adds the PS4 surface to its Vulkan back end | MIT |
| [XenosRecomp](https://github.com/hedge-dev/XenosRecomp) (hedge-dev and contributors; reblue fork) | upstream's `app/thirdparty/reblue-XenosRecomp`, run at build time | MIT |
| DirectXShaderCompiler binaries ([renderbag/dxc-bin](https://github.com/renderbag/dxc-bin)) | build host only (XenosRecomp) | University of Illinois/NCSA, with LLVM's terms |
| AMD FidelityFX Super Resolution 1 (`ffx_a.h`, `ffx_fsr1.h`) | added by the patch, `app/src/renut_engine/gpu/shaders/host/` | MIT (in the files) |
| [FFmpeg](https://ffmpeg.org) (the XMA and WMA decoders) | `sdk/thirdparty/FFmpeg`, from rexglue-sdk's submodule; `patches/ffmpeg/` is the PS4 configuration | LGPL-2.1-or-later (configured without GPL parts) |
| The SDK's other libraries (fmt, spdlog, toml++, Dear ImGui, xxHash, SIMDe, glslang, SPIRV-Tools, Vulkan Memory Allocator and the rest) | `sdk/thirdparty`, from rexglue-sdk v0.10.0 (`c94f5eb`) and its submodules | their own licences, listed in upstream's `THIRD_PARTY_NOTICES.md` |
| ps4-kit (iHaiDeeZ): toolchain setup, runtime, Mesa RADV for the PS4, VideoOut swapchain, crash log, profiler, packaging | linked at build time, not in this repository | not published yet |
| [Mesa](https://mesa3d.org) RADV | built by ps4-kit | MIT |
| [OpenOrbis](https://github.com/OpenOrbis) toolchain ([PacBrew](https://github.com/PacBrew)) | build host | GPL-3.0 (tools), the C library under its own licences |

This port's own code in the patch (the PS4 files `sdk/src/**/*_ps4.*`, `sdk/src/audio/ps4/`, `sdk/src/input/ps4/`,
`sdk/include/rex/ui/ps4_imgui_input.h`, `sdk/src/system/wait_report.cpp`, `app/mgr_src/mgr_ps4*`,
`tools/ps4_unfused_fma.py`, and the PS4 branches in upstream files) is under the licence of the folder it is in:
BSD-3-Clause in `sdk/`, MIT in `app/thirdparty/plume`, GPL-3.0 elsewhere. The build scripts and the rest of this
repository are GPL-3.0 (`LICENSE`).

The game itself (code, art, sound, text) belongs to its owners. Nothing from it is in this repository or its
releases: the build reads your `default.xex` and `media/` on your own machine. The package's icon is the cover art
upstream ships as `app/icon_mgr.jpg` (Konami's), read from your checkout at build time. The banner of this README is
original art drawn by `scripts/make-banner.py`.
