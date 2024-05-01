#!/bin/bash
set -eu

if [ "${1: -4}" = ".mkv" ]; then
  filename="${1%.*}"
  echo "Found mkv file, starting convertation"
  ffmpeg -y -i "$1" \
    -movflags use_metadata_tags \
    -map 0:v \
    -c:v copy \
    -map 0:a \
    -c:a copy \
    -map 0:s \
    -c:s mov_text \
    -strict unofficial \
    "$filename.mp4"
  echo "Done"
else
  echo "No MKV file found"
fi
