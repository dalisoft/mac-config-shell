#!/bin/sh
set -eu

if [ "$#" -eq 0 ]; then
  exit 1
fi

case "$1" in
*.mkv)
  filename="${1%.mkv}"
  echo "Found MKV file, starting conversion"

  ffmpeg -y -i "$1" \
    -movflags use_metadata_tags \
    -map 0:v \
    -c:v copy \
    -map 0:a \
    -c:a copy \
    -map 0:s \
    -c:s mov_text \
    "$filename.mp4"

  echo "Done"
  ;;
*)
  echo "No MKV file found"
  ;;
esac
