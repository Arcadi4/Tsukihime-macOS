#!/usr/bin/env bash
# Builds the player as a self-contained macOS .app (Tsukihime.app), signs it, and optionally notarizes it.
#
#   tools/setup/publish_macos.sh [OUTPUT-FOLDER] [extra dotnet publish options...]
#
# OUTPUT defaults to artifacts/macos-arm64. TSUKI_RID picks the runtime (osx-arm64, or osx-x64 for an Intel Mac).
# TSUKI_CODESIGN_IDENTITY signs with that Developer ID identity; unset means an ad-hoc signature, which runs on the
# machine that built it and after right-click > Open (or `xattr -dr com.apple.quarantine Tsukihime.app`) elsewhere.
# TSUKI_NOTARY_PROFILE names a `xcrun notarytool store-credentials` profile; with it the app is zipped, submitted,
# waited for, and the ticket stapled, so Gatekeeper accepts it on any Mac without those steps.
#
# FFmpeg is not in the bundle unless third_party/ffmpeg/macos/lib holds the four libraries (FfmpegLibrary.RequiredDlls):
# the player then loads the Homebrew FFmpeg 9 the player installs (docs/MACOS.md).
set -euo pipefail

tsuki_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
tsuki_output=${1:-"$tsuki_root/artifacts/macos-arm64"}
tsuki_rid=${TSUKI_RID:-osx-arm64}
tsuki_stage="$tsuki_output/stage"
tsuki_app="$tsuki_output/Tsukihime.app"
tsuki_identity=${TSUKI_CODESIGN_IDENTITY:--}
tsuki_entitlements="$tsuki_root/tools/setup/macos/Entitlements.plist"
tsuki_version=$(sed -n 's:.*<Version>\([^<]*\)</Version>.*:\1:p' "$tsuki_root/src/Tsuki.App/Tsuki.App.csproj" | head -n 1)
if [ -z "$tsuki_version" ]; then
    printf 'Tsuki.App.csproj has no <Version>\n' >&2
    exit 1
fi

rm -rf "$tsuki_app" "$tsuki_stage"
mkdir -p "$tsuki_output"

dotnet publish "$tsuki_root/src/Tsuki.App" -c Release -r "$tsuki_rid" \
    --self-contained true -o "$tsuki_stage" --nologo "${@:2}"

mkdir -p "$tsuki_app/Contents/MacOS" "$tsuki_app/Contents/Resources/docs" \
    "$tsuki_app/Contents/Resources/licenses" "$tsuki_app/Contents/Frameworks"
cp -R "$tsuki_stage"/. "$tsuki_app/Contents/MacOS/"
rm -rf "$tsuki_stage"

# Resources carries what the Linux archive keeps at its root: the icon, the player's guide and the notices.
cp "$tsuki_root/assets/icon/tsukihime.icns" "$tsuki_app/Contents/Resources/"
cp "$tsuki_root/docs/SETUP_GUIDE.md" "$tsuki_root/docs/MACOS.md" "$tsuki_app/Contents/Resources/docs/"
cp "$tsuki_root/LICENSE" "$tsuki_app/Contents/Resources/licenses/LICENSE.txt"
cp "$tsuki_root/src/Tsuki.Launcher/Licenses/MPL-2.0.txt" "$tsuki_app/Contents/Resources/licenses/knife-MPL-2.0.txt"
cp "$tsuki_root/src/Tsuki.Launcher/Licenses/SDL3-zlib.txt" "$tsuki_app/Contents/Resources/licenses/SDL3-zlib.txt"
cp "$tsuki_root/docs/THIRD_PARTY.md" "$tsuki_app/Contents/Resources/licenses/THIRD_PARTY.md"

# Bundled FFmpeg (optional): the player looks in Contents/Frameworks first, then at Homebrew.
if [ -d "$tsuki_root/third_party/ffmpeg/macos/lib" ]; then
    cp "$tsuki_root/third_party/ffmpeg/macos/lib/libavutil.61.dylib" \
       "$tsuki_root/third_party/ffmpeg/macos/lib/libswresample.7.dylib" \
       "$tsuki_root/third_party/ffmpeg/macos/lib/libavcodec.63.dylib" \
       "$tsuki_root/third_party/ffmpeg/macos/lib/libavformat.63.dylib" \
       "$tsuki_app/Contents/Frameworks/"
    cp "$tsuki_root/src/Tsuki.Launcher/Licenses/LGPL-3.0.txt" "$tsuki_app/Contents/Resources/licenses/FFmpeg-LGPL.txt"
    cp "$tsuki_root/src/Tsuki.Launcher/Licenses/GPL-3.0.txt" "$tsuki_app/Contents/Resources/licenses/FFmpeg-GPL-3.0.txt"
    cp "$tsuki_root/src/Tsuki.Launcher/Licenses/FFmpeg-SOURCE.txt" "$tsuki_app/Contents/Resources/licenses/FFmpeg-SOURCE.txt"
fi

sed "s/__VERSION__/$tsuki_version/g" "$tsuki_root/tools/setup/macos/Info.plist" > "$tsuki_app/Contents/Info.plist"

# Hardened runtime, with the JIT entitlements, over the whole bundle. --deep is what makes this work: .NET's managed
# assemblies and the native runtime live beside the program in Contents/MacOS, and codesign treats each PE/Mach-O file
# there as nested code that must carry a signature of its own before the bundle can be sealed.
codesign --force --deep --options runtime --entitlements "$tsuki_entitlements" --sign "$tsuki_identity" "$tsuki_app"
codesign --verify --deep --strict "$tsuki_app"

if [ -n "${TSUKI_NOTARY_PROFILE:-}" ]; then
    ditto -c -k --keepParent "$tsuki_app" "$tsuki_output/Tsukihime.zip"
    xcrun notarytool submit "$tsuki_output/Tsukihime.zip" --keychain-profile "$TSUKI_NOTARY_PROFILE" --wait
    xcrun stapler staple "$tsuki_app"
fi

printf 'macOS build: %s\n' "$tsuki_app"
if [ "$tsuki_identity" = "-" ]; then
    printf 'Ad-hoc signed: this Mac runs it directly; elsewhere use right-click > Open, or "xattr -dr com.apple.quarantine Tsukihime.app".\n'
fi
