#!/bin/sh
# Generates the bundled episodes from scripts/episodes/*.txt with the macOS
# text-to-speech voice Samantha. The audio is synthetic.
#
# Run from the repository root, then regenerate the Xcode project so the new
# files are added to the app target:
#
#   scripts/make-audio.sh
#   xcodegen generate
#
# The duration and size printed for each file are measurements of the
# generated audio, used in docs/PERFORMANCE.md.

set -eu

VOICE="Samantha"
SOURCE_DIR="scripts/episodes"
OUTPUT_DIR="WristCue/Resources/Audio"

if ! say -v '?' | grep -q "^$VOICE "; then
    echo "The voice $VOICE is not installed." >&2
    echo "Add it in System Settings > Accessibility > Spoken Content > System Voice > Manage Voices." >&2
    exit 1
fi

mkdir -p "$OUTPUT_DIR"

for text in "$SOURCE_DIR"/*.txt; do
    name=$(basename "$text" .txt)
    output="$OUTPUT_DIR/$name.m4a"
    say -v "$VOICE" -f "$text" -o "$output" --data-format=aac
    duration=$(afinfo "$output" | awk '/estimated duration/ { print $3 }')
    bytes=$(wc -c < "$output" | tr -d ' ')
    words=$(wc -w < "$text" | tr -d ' ')
    echo "$name.m4a: $duration s, $bytes bytes, $words words"
done
