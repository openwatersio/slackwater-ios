#!/usr/bin/env bash
# Build Resources/seamap.pmtiles and Resources/seamap-natl.pmtiles + the sprite
# and layer slice that go with them — the OFFLINE CHART: buoys, beacons, lights,
# rocks, wrecks, obstructions, restricted areas and seamap's own land, from Open
# Waters Seamap.
#
# Companion to build-land.sh. That one builds the land SILHOUETTE (and still
# does — seamap's own land layer stops at its bbox, and the app needs a
# continental floor outside it). This one builds what floats on the water.
#
# TWO ARTIFACTS, the same split as the two land tilesets and for the same reason
# (#30). One clip cannot do both jobs:
#
#   seamap.pmtiles       Salish Sea, z0-12, 8.5 MB — home water, where a station
#                        hero at z12.5 has to look right.
#   seamap-natl.pmtiles  US + Canada east of the antimeridian, z0-9, 28.8 MB —
#                        everywhere else: coarse past z9, never bare.
#
# The planet archive is 24.9 GB and we take ~37 MB of it. That is not a 24.9 GB
# download: PMTiles is range-addressable and the CDN sends `accept-ranges`, so
# `pmtiles extract` fetches only the directory pages and the tiles inside the
# bbox. No local copy of the planet is ever made.
#
# Why z12 in home water and not z14 (sizes before the strip below):
#   z11 13 MB   z12 25 MB   z13 42 MB   z14 71 MB
# The chart's job here is to tell you what is around a station, and past z12
# the added detail is soundings-and-berths territory that a tides app does not
# answer questions about. z14 nearly triples the bundle for that.
#
# Why z9 nationally, and why not z9 EVERYWHERE — after the strip, national costs
# z8 15.4 MB · z9 28.8 MB · z10 49.2 MB. The point marks survive the coarser cut
# almost intact (over one Boundary Pass tile, z9 against its 64 z12 children:
# buoys 15/14, light_major 9/10, light_minor 45/43, landmarks 109/113). What z12
# actually buys is rocks — 17 against 61 — plus weed, finer line geometry, and
# 13 m of coordinate precision instead of z9's. Rocks are not a detail you drop
# from home water, which is why the Salish cut stays.
#
# THE STRIP: `pmtiles extract` is bbox-and-zoom only, so the extract arrives with
# all six of seamap's source-layers — `land`, `light`, `seamark`, `water`,
# `waterway`, `wetland`. The style slice references three. `water`, `waterway`
# and `wetland` were 17.4 MB of an artifact that shipped at 25.9, downloaded and
# bundled and never drawn. `tile-join` keeps the ones the slice names, which is a
# straight 67% off with nothing to see: 25.9 MB -> 8.5 MB.
#
# The layer slice is a VERBATIM copy of the seamap-source layers from the
# published style.json, text-* included: the glyph PBFs the labels need are
# bundled below. Which layers the app then declines to draw is MapScreen's
# `SEAMAP_OMIT`, not this script's business — keeping that decision in code
# and this artifact upstream-faithful means changing our mind about TSS is a
# one-line edit, not a rebuild.
#
# Requires: pmtiles, tippecanoe (for tile-join), python3, curl — all `brew install`able.
set -euo pipefail
cd "$(dirname "$0")/.."

# The Salish box, the same clip slackwater-web's build-land.sh uses for
# land.pmtiles — home water, and the two artifacts must agree on where that is.
BBOX=${SEAMAP_BBOX:--125.5,47.0,-122.0,50.5}
MAXZOOM=${SEAMAP_MAXZOOM:-12}
# And the national box, the second artifact — CONUS, Alaska east of the
# antimeridian, and Hawaii. `pmtiles extract` takes one bbox, so the western
# Aleutians and the Pacific territories are not in it; the bundled stations
# there still open onto `land-usca`, which is what they get today.
NATL_BBOX=${SEAMAP_NATL_BBOX:--180,15,-52,72}
NATL_MAXZOOM=${SEAMAP_NATL_MAXZOOM:-9}
# Each build is a dated immutable archive; there is no "latest" alias, so the
# date is a pin. Bump it to re-cut against a newer OSM snapshot.
BUILD=${SEAMAP_BUILD:-2026-08-03}
BASE="https://tiles.openwaters.io/seamap"

# The slice comes first now: the strip below derives its keep-list from it, so
# the two cannot drift.
curl -fsS "$BASE/style.json" -o /tmp/seamap-style.json
python3 tools/slice-layers.py /tmp/seamap-style.json seamap Slackwater/Resources/seamap-layers.json

# Sprite artwork is GPL-3.0 (style/sprites/PROVENANCE.md upstream); this app is
# GPL v3. Both scales — MapLibre Native picks by device.
for f in freenauticalchart.json freenauticalchart.png \
         freenauticalchart@2x.json freenauticalchart@2x.png; do
  curl -fsS "$BASE/sprites/$f" -o "Slackwater/Resources/$f"
done

# Every source-layer the slice actually reads, asked of the slice rather than
# listed here — an upstream style that starts drawing `water` then keeps `water`,
# instead of shipping a chart with a hole in it.
#
# Minus `land`, which the app draws from its own tilesets instead (MapScreen's
# SEAMAP_OMIT drops the two layers that read it). Nationally it is 92% of the
# extract — 468 MB against 28.8 for everything else — and in the Salish box it is
# a second, coarser copy of `land.pmtiles`, which covers the same water at z0-14
# against seamap's z12.
LAYERS=()
while IFS= read -r layer; do
  [ "$layer" = land ] || LAYERS+=("$layer")
done < <(python3 -c '
import json, sys
print("\n".join(sorted({l["source-layer"] for l in json.load(open(sys.argv[1])) if "source-layer" in l})))
' Slackwater/Resources/seamap-layers.json)

# extract the box, strip to the named source-layers, put the bounds back.
cut() {
  local bbox=$1 maxzoom=$2 out=$3; shift 3
  local flags=() layer raw
  for layer in "$@"; do flags+=(-l "$layer"); done
  raw=$(mktemp -d)/cut.pmtiles
  echo "==> $out — bbox $bbox, z0-$maxzoom, keeping: $*"
  pmtiles extract "$BASE/$BUILD.pmtiles" "$raw" --bbox="$bbox" --maxzoom="$maxzoom"
  # -pk: tile-join's default 500 KB ceiling DROPS features to stay under it, and
  # silently. Nothing here is near it (with and without the flag the output
  # differs by the six bytes the flag adds to the metadata), but a strip that
  # quietly loses buoys is the one failure this step could have.
  tile-join -pk -f "${flags[@]}" -o "$out" "$raw"
  # tile-join rewrites the header bounds to the whole planet — the tiles are
  # still only the box, but MapLibre builds its TileJSON from this header and
  # would ask for tiles that cannot exist. The extract already carries the right
  # bounds, so copy its header over rather than recomputing one.
  pmtiles show --header-json "$raw" > "$raw.header"
  pmtiles edit "$out" --header-json="$raw.header"
  rm -f "$raw" "$raw.header"
}

cut "$BBOX" "$MAXZOOM" Slackwater/Resources/seamap.pmtiles "${LAYERS[@]}"
cut "$NATL_BBOX" "$NATL_MAXZOOM" Slackwater/Resources/seamap-natl.pmtiles "${LAYERS[@]}"

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
