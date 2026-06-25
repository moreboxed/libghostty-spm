#!/bin/zsh
set -euo pipefail

cd "$(dirname "$0")/.."
if [ ! -f .root ]; then
    echo "[*] malformed project structure"
    exit 1
fi

GHOSTTY_SOURCE_DIR="${1:-}"

OUTPUT_DIR="${2:-$PWD/build/release-xcframeworks}"

rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

if [ -n "${LIBGHOSTTY_STAGING:-}" ] && [ -f "$LIBGHOSTTY_STAGING/lib/libghostty.a" ]; then
    echo "[*] using prebuilt libghostty staging from $LIBGHOSTTY_STAGING"
    cp -R "$LIBGHOSTTY_STAGING" "$OUTPUT_DIR/libghostty-staging"
elif [ -n "$GHOSTTY_SOURCE_DIR" ] && [ -f "$GHOSTTY_SOURCE_DIR/include/ghostty.h" ]; then
    echo "[*] will build libghostty from $GHOSTTY_SOURCE_DIR"
elif [ -n "$GHOSTTY_SOURCE_DIR" ]; then
    echo "[!] ghostty source not found: $GHOSTTY_SOURCE_DIR"
    exit 1
else
    echo "[!] usage: $0 <ghostty_source_dir> [output_dir] (or set LIBGHOSTTY_STAGING)"
    exit 1
fi

DERIVED_DATA_PATH="$OUTPUT_DIR/derived"
ARCHIVE_DIR="$OUTPUT_DIR/archives"
STAGE_DIR="$OUTPUT_DIR/stage"
mkdir -p "$DERIVED_DATA_PATH" "$ARCHIVE_DIR" "$STAGE_DIR"

if [ -f "$OUTPUT_DIR/libghostty-staging/lib/libghostty.a" ]; then
    echo "[*] using prebuilt libghostty staging"
else
    echo "[*] building libghostty core (arm64 macOS)"
    ./Script/build-ghostty.sh "$GHOSTTY_SOURCE_DIR" "aarch64-macos" "$OUTPUT_DIR/libghostty-staging"
fi

LIBGHOSTTY_A="$OUTPUT_DIR/libghostty-staging/lib/libghostty.a"
LIBGHOSTTY_HEADERS="$OUTPUT_DIR/libghostty-staging/include"

if [ ! -f "$LIBGHOSTTY_A" ]; then
    echo "[!] libghostty.a not found"
    exit 1
fi

# Build Swift modules with library evolution enabled.
# Archiving any top-level scheme also builds its static dependencies.
SWIFT_SCHEMES=(GhosttyKit GhosttyTerminal GhosttyTheme ShellCraftKit)

for scheme in "${SWIFT_SCHEMES[@]}"; do
    echo "[*] archiving $scheme"
    xcodebuild archive \
        -scheme "$scheme" \
        -destination 'generic/platform=macOS' \
        -archivePath "$ARCHIVE_DIR/$scheme" \
        -derivedDataPath "$DERIVED_DATA_PATH" \
        -configuration Release \
        BUILD_LIBRARY_FOR_DISTRIBUTION=YES \
        SKIP_INSTALL=NO \
        2>&1 | tail -5
done

build_swift_framework() {
    local module="$1"
    local fw="$STAGE_DIR/$module.framework"
    mkdir -p "$fw/Modules/$module.swiftmodule" "$fw/Headers"

    # Find the archived .o file for this module.
    local o_file
    o_file=$(find "$ARCHIVE_DIR" -path "*/Products/*" -name "$module.o" -type f | head -1)
    if [ -z "$o_file" ] || [ ! -f "$o_file" ]; then
        echo "[!] missing archived object for $module"
        exit 1
    fi

    libtool -static -no_warning_for_no_symbols -o "$fw/$module" "$o_file"

    # Swift module interface artifacts.
    local sm_dir
    sm_dir=$(find "$DERIVED_DATA_PATH" -path "*/BuildProductsPath/Release/$module.swiftmodule" -type d | head -1)
    if [ -z "$sm_dir" ] || [ ! -d "$sm_dir" ]; then
        echo "[!] missing swiftmodule for $module"
        exit 1
    fi
    cp -R "$sm_dir"/* "$fw/Modules/$module.swiftmodule/"

    # Generated Objective-C header, if any.
    local header
    header=$(find "$DERIVED_DATA_PATH" -path "*/Objects-normal/*/$module-Swift.h" -type f | head -1)
    if [ -n "$header" ] && [ -f "$header" ]; then
        cp "$header" "$fw/Headers/"
        cat > "$fw/Modules/module.modulemap" <<MM
framework module $module {
    umbrella header "$module-Swift.h"
    export *
    module * { export * }
}
MM
    else
        cat > "$fw/Modules/module.modulemap" <<MM
framework module $module {
    export *
}
MM
    fi

    cat > "$fw/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>$module</string>
    <key>CFBundleIdentifier</key>
    <string>com.moreboxed.libghostty-spm.$module</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$module</string>
    <key>CFBundlePackageType</key>
    <string>FMWK</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
</dict>
</plist>
PLIST

    xcodebuild -create-xcframework -framework "$fw" -output "$OUTPUT_DIR/$module.xcframework" > /dev/null
    echo "[*] created $module.xcframework"
}

# libghostty is the C core; package it as its own xcframework.
echo "[*] packaging libghostty"
mkdir -p "$STAGE_DIR/libghostty.framework/Headers" "$STAGE_DIR/libghostty.framework/Modules"
cp "$LIBGHOSTTY_A" "$STAGE_DIR/libghostty.framework/libghostty"
cp -R "$LIBGHOSTTY_HEADERS/" "$STAGE_DIR/libghostty.framework/Headers/"
cp "$STAGE_DIR/libghostty.framework/Headers/module.modulemap" "$STAGE_DIR/libghostty.framework/Modules/module.modulemap"
cat > "$STAGE_DIR/libghostty.framework/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>libghostty</string>
    <key>CFBundleIdentifier</key>
    <string>com.moreboxed.libghostty-spm.libghostty</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>libghostty</string>
    <key>CFBundlePackageType</key>
    <string>FMWK</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
</dict>
</plist>
PLIST
xcodebuild -create-xcframework -framework "$STAGE_DIR/libghostty.framework" -output "$OUTPUT_DIR/libghostty.xcframework" > /dev/null
echo "[*] created libghostty.xcframework"

# Swift modules. MSDisplayLink is a dependency and its object lives inside the
# GhosttyTerminal archive, but its swiftmodule is in DerivedData.
build_swift_framework MSDisplayLink
build_swift_framework GhosttyKit
build_swift_framework GhosttyTerminal
build_swift_framework GhosttyTheme
build_swift_framework ShellCraftKit

# Zip each xcframework for release distribution.
echo "[*] zipping xcframeworks"
for xcf in "$OUTPUT_DIR"/*.xcframework; do
    name=$(basename "$xcf")
    (
        cd "$OUTPUT_DIR"
        ditto -c -k --sequesterRsrc --keepParent "$name" "$name.zip"
    )
    echo "[*] $name.zip"
done

echo "[*] release artifacts ready in $OUTPUT_DIR"
ls -la "$OUTPUT_DIR"/*.xcframework.zip
