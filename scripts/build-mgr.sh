#!/usr/bin/env bash
# Build Metal Gear Rising: Revengeance for the PS4 (ps4-kit, x86-64 Jaguar). Run in WSL:
#   scripts/build-mgr.sh sdk          the ReXGlue runtime libraries only (no game files needed)
#   scripts/build-mgr.sh host         the host tools: the code generator (rexglue) and XenosRecomp
#   scripts/build-mgr.sh codegen      the game's C++ from your default.xex (app/generated)
#   scripts/build-mgr.sh shaders      the game's shaders from your media/data000.cpk (SPIR-V cache)
#   scripts/build-mgr.sh app          the eboot (game code + SDK + Renut/plume Vulkan + RADV)
#
#   ~/mgr-build/src/mgr-nx-deko   upstream checkout (tuancapoo/mgr-nx-deko), branch ps4
#   ~/mgr-build/src/rexglue-sdk   rexglue-sdk v0.10.0 (c94f5eb): the third-party sources the fork
#                                 does not carry (copied into sdk/thirdparty by this script)
#   ~/mgr-build/src/dxc-bin       renderbag/dxc-bin 737ac9f (XenosRecomp's DXC, copied into its thirdparty)
#   ~/mgr-build/game              your extracted disc: default.xex + media/ (upstream's tools/extract_iso.py)
#   ~/mgr-build/build-sdk         the CMake build of the SDK for the PS4
#   ~/mgr-build/build-host        the host build of the SDK (code generator)
#   ~/mgr-build/build-xenos       XenosRecomp (host)
#   ~/mgr-build/shaders           the shader containers and the SPIR-V cache (game data: never distribute)
#
# A second tree for an A/B build (2026-11-04, the optimised codegen): MGR_SRC=<a copy of the checkout>,
# MGR_APP_BUILD=<its build folder>; MGR_FLAVOR=optimised for the codegen step (default: classic).
set -euo pipefail
source "$HOME/ps4-kit/toolchain/env.sh"
MGR="$HOME/mgr-build"
SRC="${MGR_SRC:-$MGR/src/mgr-nx-deko}"
UP="$MGR/src/rexglue-sdk"
GAME="${MGR_GAME:-$MGR/game}"
HERE="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$MGR/logs"

# The fork's own third-party files (the patched FFmpeg ones) win over upstream's.
if [ ! -f "$SRC/sdk/thirdparty/fmt/CMakeLists.txt" ]; then
    rsync -a --ignore-existing --exclude=.git "$UP/thirdparty/" "$SRC/sdk/thirdparty/"
fi
DXC="$SRC/app/thirdparty/reblue-XenosRecomp/thirdparty/dxc-bin"
if [ ! -f "$DXC/bin/x64/dxc-linux" ]; then
    cp -r "$MGR/src/dxc-bin/bin" "$MGR/src/dxc-bin/lib" "$DXC/"
fi
# The PS4's FFmpeg configuration (patches/ffmpeg): config.h picks config_ps4_x86_64.h for __PS4__. FFmpeg's own
# .gitignore hides both from the fork's git, so they are not in patches/mgr-ps4.patch.
for f in config.h config_ps4_x86_64.h; do
    cmp -s "$HERE/patches/ffmpeg/$f" "$SRC/sdk/thirdparty/FFmpeg/$f" || cp "$HERE/patches/ffmpeg/$f" "$SRC/sdk/thirdparty/FFmpeg/$f"
done

# The host build needs a few X11/Wayland development packages (libwayland-dev libx11-xcb-dev libxau-dev libxcb1-dev
# libxdmcp-dev): installed, or unpacked into host-deps/root (apt-get download + dpkg -x); SDL3 is built with its
# dummy drivers only.
HOST_DEPS="$MGR/host-deps/root"
host_env() {
    export PKG_CONFIG_PATH="$HOST_DEPS/usr/lib/x86_64-linux-gnu/pkgconfig:$HOST_DEPS/usr/share/pkgconfig"
}

case "${1:-sdk}" in
sdk)
    B="$MGR/build-sdk"
    echo "== configure"
    ps4_cmake -S "$SRC/sdk" -B "$B" -G Ninja -DCMAKE_BUILD_TYPE=Release \
        -DREXGLUE_PLATFORM_PS4=ON -DREXGLUE_BUILD_HOST_TOOLS=OFF -DREXGLUE_USE_VULKAN=ON \
        -DREXGLUE_ENABLE_TRACY=OFF -DREXGLUE_BUILD_TESTS=OFF \
        > "$MGR/logs/configure-sdk.log" 2>&1 || { tail -40 "$MGR/logs/configure-sdk.log"; exit 1; }
    echo "== build ${MGR_TARGETS:-rexcore}"
    ninja -C "$B" -k 0 ${MGR_TARGETS:-rexcore} > "$MGR/logs/build-sdk.log" 2>&1 \
        || { grep -E "error:|FAILED" "$MGR/logs/build-sdk.log" | head -80; exit 1; }
    echo "sdk built"
    ;;
host)
    host_env
    echo "== code generator (rexglue)"
    cmake -S "$SRC/sdk" -B "$MGR/build-host" -G Ninja -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_C_COMPILER=clang-21 -DCMAKE_CXX_COMPILER=clang++-21 \
        -DCMAKE_C_FLAGS=-march=x86-64-v2 -DCMAKE_CXX_FLAGS=-march=x86-64-v2 \
        -DCMAKE_SHARED_LINKER_FLAGS="-L$HOST_DEPS/usr/lib/x86_64-linux-gnu" \
        -DCMAKE_EXE_LINKER_FLAGS="-L$HOST_DEPS/usr/lib/x86_64-linux-gnu" \
        -DREXGLUE_BUILD_HOST_TOOLS=ON -DREXGLUE_ENABLE_TRACY=OFF -DREXGLUE_USE_VULKAN=ON -DREXGLUE_SDL_HEADLESS=ON \
        > "$MGR/logs/configure-host.log" 2>&1 || { tail -40 "$MGR/logs/configure-host.log"; exit 1; }
    ninja -C "$MGR/build-host" rexglue > "$MGR/logs/build-host.log" 2>&1 \
        || { grep -E "error:|FAILED|cannot find" "$MGR/logs/build-host.log" | head -40; exit 1; }
    echo "== XenosRecomp"
    cmake -S "$SRC/app/thirdparty/reblue-XenosRecomp" -B "$MGR/build-xenos" -G Ninja -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_C_COMPILER=clang-21 -DCMAKE_CXX_COMPILER=clang++-21 -DXENOS_RECOMP_RENUT=ON -DXENOS_RECOMP_DXIL=OFF \
        > "$MGR/logs/configure-xenos.log" 2>&1 || { tail -40 "$MGR/logs/configure-xenos.log"; exit 1; }
    ninja -C "$MGR/build-xenos" XenosRecomp > "$MGR/logs/build-xenos.log" 2>&1 \
        || { grep -E "error:|FAILED" "$MGR/logs/build-xenos.log" | head -40; exit 1; }
    echo "host tools built"
    ;;
codegen)
    # tools/codegen.ps1 -Flavor classic, on Linux: the generator's own x86-64 output, no post-codegen pass but the
    # MGR jump-table repair (tools/post_codegen.py: mgr_repair_branches.py). The optimised flavour's AArch64 passes
    # (pch_neon_shuffles, vec_byteswap, guest_cas) are not used: the PS4 port is a full x86-64 conversion.
    REXGLUE="$SRC/sdk/out/linux-amd64/rexglue"
    [ -x "$REXGLUE" ] || { echo "no $REXGLUE: run '$0 host' first" >&2; exit 1; }
    [ -f "$GAME/default.xex" ] || { echo "no $GAME/default.xex (extract your disc there)" >&2; exit 1; }
    mkdir -p "$SRC/assets" "$SRC/out"
    ln -sfn "$GAME" "$SRC/assets/game_root"
    FLAVOR="${MGR_FLAVOR:-classic}"
    if [ "$FLAVOR" = optimised ]; then
        # The optimised flavour's generator options (app/perf_overrides.toml: guest registers as C++ locals, no MSR
        # fences, inline conversions...), which only change how the C++ is written, and its source passes; not its
        # three AArch64 rewrites (post_codegen.py skips them for "codegen-arch: x86-64").
        { echo "# optimised codegen for the PS4 (scripts/build-mgr.sh codegen, MGR_FLAVOR=optimised): app/perf_overrides.toml."
          echo "# codegen-arch: x86-64"
          cat "$SRC/app/perf_overrides.toml"; } > "$SRC/app/codegen_flavor.toml"
    else
        printf '%s\n' "# classic codegen: no extra options (scripts/build-mgr.sh codegen, as tools\\codegen.ps1 -Flavor classic)." \
            "# Included by sa2_manifest.toml." > "$SRC/app/codegen_flavor.toml"
    fi
    echo "== codegen ($FLAVOR) from $GAME/default.xex"
    (cd "$SRC/app" && REX_MAX_JUMP_TABLE_ENTRIES=1024 REXGLUE_DUMP_IMAGE="$SRC/out/default_image.bin" \
        LD_LIBRARY_PATH="$SRC/sdk/out/linux-amd64" "$REXGLUE" codegen sa2_manifest.toml > "$MGR/logs/codegen.log" 2>&1) \
        || { tail -30 "$MGR/logs/codegen.log"; exit 1; }
    tail -5 "$MGR/logs/codegen.log"
    (cd "$SRC" && REXSDK_DIR="$SRC/sdk" python3 -I tools/post_codegen.py) || exit 1
    # PPC's fused multiply-adds as REX_FMA: a multiply and an add on the Jaguar, which has no FMA unit (std::fma was
    # libm's software emulation there, a third of Wwise's audio thread in the first profile).
    (cd "$SRC" && python3 -I tools/ps4_unfused_fma.py --gen app/generated/default) || exit 1
    echo "codegen done: $SRC/app/generated"
    ;;
shaders)
    # tools/extract_mgr_cpk_shaders.py + tools/win/build_mgr_deko_shaders.ps1, on Linux: the 1,202 shader containers
    # from data000.cpk, then XenosRecomp (Renut, SPIR-V only) into the shader cache the build compiles in.
    [ -x "$MGR/build-xenos/XenosRecomp/XenosRecomp" ] || { echo "run '$0 host' first" >&2; exit 1; }
    mkdir -p "$MGR/tools" "$MGR/shaders"
    if [ ! -x "$MGR/tools/cpk_shader_scan" ]; then
        clang++-21 -O2 -std=c++17 -D_fseeki64=fseeko -D_FILE_OFFSET_BITS=64 \
            "$SRC/tools/installer_probe/cpk_shader_scan.cpp" -o "$MGR/tools/cpk_shader_scan"
    fi
    if [ ! -d "$MGR/shaders/containers" ]; then
        python3 -I "$SRC/tools/extract_mgr_cpk_shaders.py" "$GAME" --out "$MGR/shaders/containers" \
            --scanner "$MGR/tools/cpk_shader_scan"
    fi
    # The shaders Renut captured on the console because the cache lacked them (/data/MGR/shader_capture: built into
    # default.xex, not in data000.cpk), as gpu.cmake's collect_captured_shaders.cmake adds them on the PC.
    mkdir -p "$MGR/shaders/captures"
    for f in "$MGR/shaders/captures/"*.bin; do
        [ -f "$f" ] && cp -n "$f" "$MGR/shaders/containers/"
    done
    mkdir -p "$MGR/shaders/spirv" "$MGR/shaders/hlsl" "$MGR/shaders/renut_gpu"
    echo "== XenosRecomp: $(ls "$MGR/shaders/containers" | wc -l) containers"
    BANJO_DEKO3D_SPIRV_DIR="$MGR/shaders/spirv" "$MGR/build-xenos/XenosRecomp/XenosRecomp" "$MGR/shaders/containers" \
        "$MGR/shaders/renut_gpu/shader_cache.cpp" "$SRC/app/thirdparty/reblue-XenosRecomp/XenosRecomp/shader_common.h" \
        "$MGR/shaders/hlsl" > "$MGR/logs/shaders.log" 2>&1 || { tail -30 "$MGR/logs/shaders.log"; exit 1; }
    tail -5 "$MGR/logs/shaders.log"
    ls -la "$MGR/shaders/renut_gpu/shader_cache.cpp"
    ;;
app)
    # The eboot: the generated game code, the SDK, Renut on plume's Vulkan back end, RADV (ps4-kit).
    [ -f "$SRC/app/generated/default/sources.cmake" ] || { echo "run '$0 codegen' first" >&2; exit 1; }
    CACHE="$MGR/shaders/renut_gpu/shader_cache.cpp"
    [ -f "$CACHE" ] || { echo "run '$0 shaders' first" >&2; exit 1; }
    B="${MGR_APP_BUILD:-$MGR/build-app}"
    echo "== configure"
    ps4_cmake -S "$SRC/app" -B "$B" -G Ninja -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_PROJECT_sa2_INCLUDE="$PS4_KIT/ps4-kit.cmake" -DPS4_KIT_NETFS=OFF \
        -DREXSDK_DIR="$SRC/sdk" -DREXGLUE_PLATFORM_PS4=ON -DREXGLUE_BUILD_HOST_TOOLS=OFF -DREXGLUE_USE_VULKAN=ON \
        -DREXGLUE_ENABLE_TRACY=OFF -DREXGLUE_BUILD_TESTS=OFF -DMGR_RENUT_RENDERER=ON \
        -DBANJO_RENUT_SHADER_CACHE_CPP="$CACHE" -DRENUT_SHADER_DUMP_DIR="$MGR/shaders/containers" \
        -DRENUT_ASSETS_DIR="$GAME" \
        > "$MGR/logs/configure-app.log" 2>&1 || { tail -40 "$MGR/logs/configure-app.log"; exit 1; }
    # Each generated chunk takes ~1.5 GB of RAM to compile.
    mem_mb=$(( $(awk '/^MemAvailable:/ {print $2}' /proc/meminfo) / 1024 ))
    JOBS=$(( mem_mb / 1500 )); [ "$JOBS" -lt 1 ] && JOBS=1; [ "$JOBS" -gt "$(nproc)" ] && JOBS=$(nproc)
    echo "== build (${MGR_TARGETS:-sa2_eboot}, -j$JOBS)"
    ninja -C "$B" -k 0 -j"$JOBS" ${MGR_TARGETS:-sa2_eboot} > "$MGR/logs/build-app.log" 2>&1 \
        || { grep -E "error:|FAILED|undefined symbol|missing module" "$MGR/logs/build-app.log" | head -80; exit 1; }
    echo "app built"
    ;;
pkg)
    # out/MGR-vXX.YY.pkg (MGR_VERSION=00.01). The game itself is not in it: copy your extracted disc to the
    # console's /data/MGR/game_root (default.xex + media/).
    VERSION="${MGR_VERSION:-00.00}"
    EBOOT="${MGR_APP_BUILD:-$MGR/build-app}/sa2_eboot/eboot.bin"
    [ -f "$EBOOT" ] || { echo "no $EBOOT: run '$0 app' first" >&2; exit 1; }
    STAGE="$MGR/stage"
    rm -rf "$STAGE"
    mkdir -p "$STAGE/sce_sys"
    cp "$EBOOT" "$STAGE/eboot.bin"
    if [ -f "$HERE/sce_sys/icon0.png" ]; then
        cp "$HERE/sce_sys/icon0.png" "$STAGE/sce_sys/"
    else
        # The game's cover (upstream app/icon_mgr.jpg), at the PS4's size.
        python3 -c "from PIL import Image; import sys; Image.open(sys.argv[1]).convert('RGB').resize((512, 512), Image.LANCZOS).save(sys.argv[2])" \
            "$SRC/app/icon_mgr.jpg" "$STAGE/sce_sys/icon0.png"
    fi
    [ -f "$HERE/sce_sys/pic1.png" ] && cp "$HERE/sce_sys/pic1.png" "$STAGE/sce_sys/"
    PKG="$(bash "$PS4_KIT/scripts/make-pkg.sh" "$STAGE" MGRR00001 "Metal Gear Rising: Revengeance" "$VERSION" MGR \
        "$PSB/out" | tail -1)"
    mkdir -p "$HERE/out" "$MGR/oelf"
    cp "$PKG" "$HERE/out/MGR-v$VERSION.pkg"
    cp "${MGR_APP_BUILD:-$MGR/build-app}/sa2" "$MGR/oelf/v$VERSION.elf" 2>/dev/null || true
    ls -la "$HERE/out/MGR-v$VERSION.pkg"
    ;;
*)
    echo "usage: $0 sdk|host|codegen|shaders|app|pkg" >&2
    exit 2
    ;;
esac
