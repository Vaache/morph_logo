#!/usr/bin/env bash
# Renders the default splash of an SVG to doc/media/<name>.gif.
# Usage: tool/render_logo.sh <logo.svg> <name> [background ARGB] [ink ARGB]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SVG="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
NAME="$2"
FRAMES="${TMPDIR:-/tmp}/morph_logo_frames/$NAME"
OUT="$ROOT/doc/media"

rm -rf "$FRAMES"
mkdir -p "$OUT"
(cd "$ROOT" && LOGO_SVG="$SVG" LOGO_OUT="$FRAMES" LOGO_BG="${3:-FFF6F4F0}" LOGO_INK="${4:-FF222223}" \
  flutter test test/media/render_logo_test.dart)

ffmpeg -y -loglevel error -framerate 30 -i "$FRAMES/%04d.png" \
  -vf "fps=30,scale=360:-1:flags=lanczos,split[s0][s1];[s0]palettegen=max_colors=160:stats_mode=diff[p];[s1][p]paletteuse=dither=bayer:bayer_scale=5" \
  -loop 0 "$OUT/$NAME.gif"
du -h "$OUT/$NAME.gif"
