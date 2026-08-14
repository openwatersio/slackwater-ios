#!/usr/bin/env python3
"""Slice a MapLibre style.json for offline bundling: keep the layers whose
source is <source>, dump the layer array as JSON.

--strip-text drops every text-* key. Seamap keeps its text (the app bundles
the glyph PBFs its labels need — see build-seamap.sh); seascape strips it,
because its text bakes in the ?unit= the style was fetched with and the
offline slice must stay unit-agnostic.

Usage: slice-layers.py <style.json> <source> <out.json> [--strip-text]
"""
import json
import sys

style_path, source, out_path = sys.argv[1:4]
strip_text = "--strip-text" in sys.argv[4:]
style = json.load(open(style_path))
out = []
for layer in style["layers"]:
    if layer.get("source") != source:
        continue
    if strip_text:
        for key in ("layout", "paint"):
            block = layer.get(key)
            if block:
                for k in [k for k in block if k.startswith("text-")]:
                    block.pop(k)
    out.append(layer)
json.dump(out, open(out_path, "w"))
print(f"{len(out)} {source} layers: " + ", ".join(l["id"] for l in out))
