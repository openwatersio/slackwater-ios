#!/usr/bin/env bash
# Build Resources/seascape.pmtiles + the layer slice that goes with it — the
# OFFLINE BATHYMETRY: depth areas and contours, from Open Waters Seascape.
#
# Third of three basemap builders. build-land.sh makes the land silhouette,
# build-seamap.sh what floats on the water, and this one what is under it.
#
# The planet archive is 7.3 GB and we take ~35 MB of it, in 45 range requests
# and six seconds — the same trick build-seamap.sh explains at length.
#
# WHY THE URL LOOKS LIKE THAT: Seascape publishes no downloadable archive yet
# (openwatersio/seascape#121 — the planet build costs its author real money and
# he is working out how to recover it). Brandon handed over this one build
# directly on 2026-08-08. It is a content-addressed R2 path with no `latest`
# alias and no dated sibling, so the hash IS the pin. If Seascape starts
# publishing properly, this becomes a dated URL like seamap's.
#
# WHAT YOU GET OFFLINE, AND WHAT YOU DON'T: of the four seascape-vector layers,
# `depth-areas` (fill) and `contour-lines` (line) draw. `soundings` and
# `contour-labels` are symbol layers whose only content is text, stripped
# below — bundled and inert, for the unit reason explained at the strip. Depth
# shading is separate again: it lives on the seascape-dem raster source as a
# `color-relief` layer MapLibre Native will not render, so it is no loss here
# that it isn't bundled.
#
# The unit query param only ever reaches text fields, which this strips — so
# the slice is unit-agnostic and ?unit=ft is arbitrary. Glyphs shipped for
# seamap (#29), but this slice KEEPS stripping: un-stripping would bake one
# unit into an offline artifact the app's unit setting can't reach. Lighting
# up soundings offline means two slices or a load-time rewrite — a separate
# decision.
#
# Requires: pmtiles, python3, curl. `brew install pmtiles`.
set -euo pipefail
cd "$(dirname "$0")/.."

# The Salish box, same clip as seamap.pmtiles and land.pmtiles — home water,
# and the artifacts must agree on where that is.
BBOX=${SEASCAPE_BBOX:--125.5,47.0,-122.0,50.5}
# z12 to match seamap. The archive goes to z15 and the cost curve is steep
# (global z0-6 is 46 MB, global z0-8 is 1.1 GB); inside the box z12 is 35 MB.
MAXZOOM=${SEASCAPE_MAXZOOM:-12}
ARCHIVE=${SEASCAPE_ARCHIVE:-https://pub-f8e3a6cde1304526acfa7eae3e9c78ec.r2.dev/seascape/c52dbf49d7ff89eb0be8a95356ea14260a5d98c2/vector.pmtiles}

pmtiles extract "$ARCHIVE" Slackwater/Resources/seascape.pmtiles \
  --bbox="$BBOX" --maxzoom="$MAXZOOM"

curl -fsS "https://tiles.openwaters.io/seascape/style.json?unit=ft" -o /tmp/seascape-style.json
# seascape-vector only: the dem and coverage sources are not bundled, and a
# layer pointing at a missing source is a style MapLibre refuses to load.
python3 tools/slice-layers.py /tmp/seascape-style.json seascape-vector Slackwater/Resources/seascape-layers.json --strip-text

ls -la Slackwater/Resources/seascape.pmtiles Slackwater/Resources/seascape-layers.json
