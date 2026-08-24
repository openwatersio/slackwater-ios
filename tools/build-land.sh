#!/usr/bin/env bash
# Build both bundled OSM coastline land floors:
# land-usca.pmtiles (US + Canada, z0-9) and land.pmtiles (Salish Sea, z0-14).
#
# The app ships TWO land tilesets, and the split is the whole basemap decision
# (M53). One artifact cannot do both jobs:
#
#   land.pmtiles       Salish Sea, z0-14. Home water, where a station hero at
#                      z12.5 has to look right.
#   land-usca.pmtiles  US + Canada, z0-9, ~21 MB — this file. Everywhere
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
SRC_URL="https://osmdata.openstreetmap.de/download/land-polygons-complete-4326.zip"
# GDAL's arg parser reads a leading "-180" as an option, so the clip goes in as
# WKT rather than four bare numbers (an empty tileset is the silent failure).
CLIP_WKT="MULTIPOLYGON(\
((-180 14,-52 14,-52 75,-180 75,-180 14)),\
((165 50,180 50,180 56,165 56,165 50)),\
((143 12,147 12,147 17,143 17,143 12)),\
((165 18,168 18,168 20,165 20,165 18)),\
((-172 -16,-168 -16,-168 -12,-172 -12,-172 -16)))"
SALISH_CLIP_WKT="POLYGON((-125.5 47,-122 47,-122 50.5,-125.5 50.5,-125.5 47))"

if [ ! -f "$WORK/land_polygons.shp" ]; then
  curl -fL "$SRC_URL" -o "$WORK/land.zip"
  unzip -q -j "$WORK/land.zip" -d "$WORK"
fi

# -nlt PROMOTE_TO_MULTI: the source mixes Polygon and MultiPolygon; without it
# ogr2ogr fixes the FlatGeobuf layer type to Polygon and dies on the first
# MultiPolygon feature ("Mismatched geometry type").
[ -f "$WORK/usca-land.fgb" ] || ogr2ogr -f FlatGeobuf -nlt PROMOTE_TO_MULTI \
  -clipsrc "$CLIP_WKT" "$WORK/usca-land.fgb" "$WORK/land_polygons.shp"
[ -f "$WORK/salish-land.fgb" ] || ogr2ogr -f FlatGeobuf -nlt PROMOTE_TO_MULTI \
  -clipsrc "$SALISH_CLIP_WKT" "$WORK/salish-land.fgb" "$WORK/land_polygons.shp"
# A line layer over clipped polygons strokes the artificial closing edge across
# water (#108). Derive boundaries from the unsplit source first, then clip the
# lines so they simply stop at tile and region edges.
[ -f "$WORK/usca-coast.fgb" ] || ogr2ogr -f FlatGeobuf -nlt PROMOTE_TO_MULTI \
  -clipsrc "$CLIP_WKT" -dialect SQLite \
  -sql 'SELECT ST_Boundary(geometry) AS geometry FROM land_polygons' \
  "$WORK/usca-coast.fgb" "$WORK/land_polygons.shp"
[ -f "$WORK/salish-coast.fgb" ] || ogr2ogr -f FlatGeobuf -nlt PROMOTE_TO_MULTI \
  -clipsrc "$SALISH_CLIP_WKT" -dialect SQLite \
  -sql 'SELECT ST_Boundary(geometry) AS geometry FROM land_polygons' \
  "$WORK/salish-coast.fgb" "$WORK/land_polygons.shp"

tippecanoe -Z0 -z9 -S 8 --coalesce-densest-as-needed --force \
  -L land:"$WORK/usca-land.fgb" -L coast:"$WORK/usca-coast.fgb" \
  -o Slackwater/Resources/land-usca.pmtiles
tippecanoe -Z0 -z14 --coalesce-densest-as-needed --force \
  -L land:"$WORK/salish-land.fgb" -L coast:"$WORK/salish-coast.fgb" \
  -o Slackwater/Resources/land.pmtiles

ls -la Slackwater/Resources/land-usca.pmtiles Slackwater/Resources/land.pmtiles
