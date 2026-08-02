#!/usr/bin/env bash
# Build Resources/land-usca.pmtiles — the CONTINENTAL land floor: OSM coastline
# land polygons for the US (states + territories) and Canada, z0-9.
#
# The app ships TWO land tilesets, and the split is the whole basemap decision
# (M53). One artifact cannot do both jobs:
#
#   land.pmtiles       Salish Sea, z0-14, 4.8 MB — built by slackwater-web's
#                      scripts/build-land.sh, the web's exact artifact. Home
#                      water, where a station hero at z12.5 has to look right.
#   land-usca.pmtiles  US + Canada, z0-9, ~14.5 MB — this file. Everywhere
#                      else: never blank, coarse when you zoom past z9.
#
# Why not one:
#   - Salish detail everywhere is impossible. The same pipeline over US+Canada
#     costs 4.8 MB at z6, 9.9 at z7, 17.5 at z8, 29.8 at z9 and 48.7 at z10 with
#     tippecanoe's default simplification. z14 nationally is hundreds of MB.
#   - Merging the two into one tileset (tile-join) is worse than either: the
#     merged maxzoom would be 14, so MapLibre stops overzooming at z9 and the
#     land goes BLANK outside the Salish above z9 — the one outcome ruled out.
#   - `-S 8` (double the default 4) is the size lever that costs least: ~300 m
#     of coastline tolerance at z9, half the bytes (29.8 MB -> 14.5 MB). Under a
#     nautical chart this layer is a silhouette, not a survey.
#
# The clip is a MULTIPOLYGON, not a box: the mainland box plus the four bundled
# outliers — the western Aleutians across the antimeridian (Massacre Bay, Attu),
# Guam/Saipan, Wake, and American Samoa. Every one is there because a bundled
# NOAA station sits on it, and a bundled station may never open onto a blank map.
#
# Requires: ogr2ogr (gdal), tippecanoe — both `brew install`able.
# Source download is ~925 MB; the whole run is ~15 minutes.
set -euo pipefail
cd "$(dirname "$0")/.."

WORK=${LAND_WORK:-$(mktemp -d)}
mkdir -p "$WORK"
SRC_URL="https://osmdata.openstreetmap.de/download/land-polygons-split-4326.zip"
# GDAL's arg parser reads a leading "-180" as an option, so the clip goes in as
# WKT rather than four bare numbers (an empty tileset is the silent failure).
CLIP_WKT="MULTIPOLYGON(\
((-180 14,-52 14,-52 75,-180 75,-180 14)),\
((165 50,180 50,180 56,165 56,165 50)),\
((143 12,147 12,147 17,143 17,143 12)),\
((165 18,168 18,168 20,165 20,165 18)),\
((-172 -16,-168 -16,-168 -12,-172 -12,-172 -16)))"

if [ ! -f "$WORK/land_polygons.shp" ]; then
  curl -fL "$SRC_URL" -o "$WORK/land.zip"
  unzip -q -j "$WORK/land.zip" -d "$WORK"
fi

# -nlt PROMOTE_TO_MULTI: the source mixes Polygon and MultiPolygon; without it
# ogr2ogr fixes the FlatGeobuf layer type to Polygon and dies on the first
# MultiPolygon feature ("Mismatched geometry type").
[ -f "$WORK/usca-land.fgb" ] || ogr2ogr -f FlatGeobuf -nlt PROMOTE_TO_MULTI \
  -clipsrc "$CLIP_WKT" "$WORK/usca-land.fgb" "$WORK/land_polygons.shp"

tippecanoe -Z0 -z9 -S 8 -l land --coalesce-densest-as-needed --force \
  -o Slackwater/Resources/land-usca.pmtiles "$WORK/usca-land.fgb"

ls -la Slackwater/Resources/land-usca.pmtiles
