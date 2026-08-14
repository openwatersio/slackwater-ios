#!/usr/bin/env bash
# Build Resources/seamap.pmtiles + the sprite and layer slice that go with it —
# the OFFLINE CHART: buoys, beacons, lights, rocks, wrecks, obstructions,
# restricted areas and seamap's own land, from Open Waters Seamap.
#
# Companion to build-land.sh. That one builds the land SILHOUETTE (and still
# does — seamap's own land layer stops at its bbox, and the app needs a
# continental floor outside it). This one builds what floats on the water.
#
# The planet archive is 24.9 GB and we take ~25 MB of it. That is not a 24.9 GB
# download: PMTiles is range-addressable and the CDN sends `accept-ranges`, so
# `pmtiles extract` fetches only the directory pages and the tiles inside the
# bbox — 103 requests, ~15 seconds. No local copy of the planet is ever made.
#
# Why z12 and not z14:
#   z11 13 MB   z12 25 MB   z13 42 MB   z14 71 MB
# The chart's job here is to tell you what is around a station, and past z12
# the added detail is soundings-and-berths territory that a tides app does not
# answer questions about. z14 nearly triples the bundle for that.
#
# The layer slice is a VERBATIM copy of the seamap-source layers from the
# published style.json, text-* included: the glyph PBFs the labels need are
# bundled below. Which layers the app then declines to draw is MapScreen's
# `SEAMAP_OMIT`, not this script's business — keeping that decision in code
# and this artifact upstream-faithful means changing our mind about TSS is a
# one-line edit, not a rebuild.
#
# Requires: pmtiles, python3, curl. `brew install pmtiles`.
set -euo pipefail
cd "$(dirname "$0")/.."

# The Salish box, the same clip slackwater-web's build-land.sh uses for
# land.pmtiles — home water, and the two artifacts must agree on where that is.
BBOX=${SEAMAP_BBOX:--125.5,47.0,-122.0,50.5}
MAXZOOM=${SEAMAP_MAXZOOM:-12}
# Each build is a dated immutable archive; there is no "latest" alias, so the
# date is a pin. Bump it to re-cut against a newer OSM snapshot.
BUILD=${SEAMAP_BUILD:-2026-08-03}
BASE="https://tiles.openwaters.io/seamap"

pmtiles extract "$BASE/$BUILD.pmtiles" Slackwater/Resources/seamap.pmtiles \
  --bbox="$BBOX" --maxzoom="$MAXZOOM"

# Sprite artwork is GPL-3.0 (style/sprites/PROVENANCE.md upstream); this app is
# GPL v3. Both scales — MapLibre Native picks by device.
for f in freenauticalchart.json freenauticalchart.png \
         freenauticalchart@2x.json freenauticalchart@2x.png; do
  curl -fsS "$BASE/sprites/$f" -o "Slackwater/Resources/$f"
done

curl -fsS "$BASE/style.json" -o /tmp/seamap-style.json
python3 tools/slice-layers.py /tmp/seamap-style.json seamap Slackwater/Resources/seamap-layers.json

# Glyphs (#29). The slice's labels reference two versatiles stacks —
# noto_sans_regular everywhere, open_sans_regular_italic for hazard depths,
# racon and light characteristics — so bundle those, latin ranges only: a
# Salish Sea chart carries no CJK. 7680-7935 is Latin Extended Additional
# (the ḵ in BC Indigenous place names), 8192-8447 general punctuation; the
# italic stack labels digits and ASCII light characteristics, so it skips
# both. Both fonts are OFL — licence bundled as glyphs-OFL.txt.
GLYPHS="https://tiles.versatiles.org/assets/glyphs"
for range in 0-255 256-511 7680-7935 8192-8447; do
  curl -fsS "$GLYPHS/noto_sans_regular/$range.pbf" \
    -o "Slackwater/Resources/noto_sans_regular-$range.pbf"
done
for range in 0-255 256-511; do
  curl -fsS "$GLYPHS/open_sans_regular_italic/$range.pbf" \
    -o "Slackwater/Resources/open_sans_regular_italic-$range.pbf"
done

ls -la Slackwater/Resources/seamap.pmtiles Slackwater/Resources/seamap-layers.json \
       Slackwater/Resources/*.pbf
