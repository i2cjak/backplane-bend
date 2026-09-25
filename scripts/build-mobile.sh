#!/bin/sh
# Build the phone apps' shared Bend client and the Android APK.
#   mobile/build/assets/bridge.js   src/mobile (Bend) + bridge.js, one script
#   dist/backplane-android.apk      when an Android SDK is found
# The iOS app is built on a Mac: mobile/ios/build.sh (see mobile/README.md).
set -eu
cd "$(dirname "$0")/.."
out=$(bend src/mobile/app.bend --check-only 2>&1) || { echo "$out"; exit 1; }
case $out in *"All terms check"*) ;; *) echo "$out"; exit 1 ;; esac
rm -rf build/mobile-web
bend src/mobile/index.html -o build/mobile-web >/dev/null
mkdir -p mobile/build/assets
cat build/mobile-web/chunk-*.js > mobile/build/assets/bridge.js
# the kept state's name: the apps keep it across builds with the same types
printf '\nglobalThis.BackplaneStateKey = "%s";\n' "$(python3 scripts/state-key.py)" >> mobile/build/assets/bridge.js
echo "mobile/build/assets/bridge.js ($(wc -c < mobile/build/assets/bridge.js) bytes)"
[ "${1:-}" = "--js" ] && exit 0
sdk=${ANDROID_HOME:-$HOME/.local/opt/android-sdk}
if [ -d "$sdk" ]; then
  export ANDROID_HOME="$sdk"
  [ -n "${JAVA_HOME:-}" ] || [ ! -d "$HOME/.local/opt/jdk17" ] || export JAVA_HOME="$HOME/.local/opt/jdk17"
  (cd mobile/android && ./gradlew -q assembleRelease)
  mkdir -p dist
  cp mobile/android/app/build/outputs/apk/release/app-release.apk dist/backplane-android.apk
  ls -la dist/backplane-android.apk
else
  echo "no Android SDK at $sdk: skipping the APK"
fi
