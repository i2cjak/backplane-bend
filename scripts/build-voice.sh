#!/bin/sh
# Build the voice helper into one executable: dist/backplane-voice.
# Speech to text with OpenAI (see tools/voice/README.md); no dependencies.
set -e
root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root/tools/voice"
mkdir -p "$root/dist"
bun build.ts "$root/dist/backplane-voice"
ls -la "$root/dist/backplane-voice"
