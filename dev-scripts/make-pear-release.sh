#!/bin/sh
# Builds the macOS arm64 release tarball that PearSilicon downloads:
#
#   PearLegacyEngine-<version>-macos-arm64.tar.gz
#
# The archive extracts as PearLegacyEngine/ with the binary, the runtime
# dylibs (including the Metal-backed ANGLE in touchHLE_dylibs/angle), the
# fonts and the option files, which is the layout PearSilicon searches for.
#
# Usage: dev-scripts/make-pear-release.sh [--no-build]
#
# Set PEAR_DYNARMIC_ROOT to build the CPU backend from the PearLegacyJIT fork
# instead of the bundled vendor/dynarmic submodule.
set -e

REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$REPO_ROOT"

BUILD=1
if [ "$1" = "--no-build" ]; then
    BUILD=0
fi

DESC=$(git describe --tags --long 2>/dev/null || echo "")
case "$DESC" in
    *-0-g*) VERSION=${DESC%%-0-g*} ;;
    "")
        echo "error: no release tag found; tag the release first." >&2
        exit 1 ;;
    *)
        echo "error: HEAD is not on a tag ($DESC); tag it before releasing." >&2
        exit 1 ;;
esac

if [ "$BUILD" = "1" ]; then
    echo ">> Building touchHLE (release)"
    if [ -n "$PEAR_DYNARMIC_ROOT" ]; then
        echo ">> CPU backend: PearLegacyJIT at $PEAR_DYNARMIC_ROOT"
    else
        echo ">> CPU backend: bundled vendor/dynarmic"
    fi
    cargo build --release
fi

BINARY="target/release/touchHLE"
if [ ! -x "$BINARY" ]; then
    echo "error: $BINARY is missing." >&2
    exit 1
fi

ANGLE_SRC=""
for candidate in "$PEAR_ANGLE_LIB_DIR" "vendor/angle/out/MacMetal"; do
    if [ -n "$candidate" ] && [ -f "$candidate/libEGL.dylib" ]; then
        ANGLE_SRC="$candidate"
        break
    fi
done
if [ -z "$ANGLE_SRC" ]; then
    echo "error: ANGLE's libEGL.dylib was not found." >&2
    echo "       build vendor/angle for the Metal backend or set PEAR_ANGLE_LIB_DIR." >&2
    exit 1
fi

NAME="PearLegacyEngine-$VERSION-macos-arm64"
STAGE=$(mktemp -d)/PearLegacyEngine
mkdir -p "$STAGE"
cp "$BINARY" "$STAGE/touchHLE"
cp -R touchHLE_dylibs touchHLE_fonts "$STAGE/"
# SwiftShader and the Vulkan validation layer are unused by the Metal path.
mkdir -p "$STAGE/touchHLE_dylibs/angle"
for lib in "$ANGLE_SRC"/*.dylib; do
    case "$(basename "$lib")" in
        libVkLayer_khronos_validation.dylib|libvk_swiftshader.dylib) continue ;;
    esac
    cp "$lib" "$STAGE/touchHLE_dylibs/angle/"
done
for f in touchHLE_default_options.txt touchHLE_options.txt OPTIONS_HELP.txt; do
    [ -f "$f" ] && cp "$f" "$STAGE/"
done

OUT="$REPO_ROOT/$NAME.tar.gz"
rm -f "$OUT"
( cd "$(dirname "$STAGE")" && tar -czf "$OUT" PearLegacyEngine )
rm -rf "$(dirname "$STAGE")"

echo ">> $OUT ($(du -h "$OUT" | cut -f1))"
