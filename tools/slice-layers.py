#!/usr/bin/env python3
"""Slice a MapLibre style.json for offline bundling: keep the layers whose
source is <source>, strip every text-* key (labels need glyphs, glyphs are a
remote URL an offline chart cannot fetch), dump the layer array as JSON.

Usage: slice-layers.py <style.json> <source> <out.json>
"""
import json
import sys

style_path, source, out_path = sys.argv[1:4]
style = json.load(open(style_path))
out = []
for layer in style["layers"]:
    if layer.get("source") != source:
        continue
    for key in ("layout", "paint"):
        block = layer.get(key)
        if block:
            for k in [k for k in block if k.startswith("text-")]:
                block.pop(k)
    out.append(layer)
json.dump(out, open(out_path, "w"))
print(f"{len(out)} {source} layers: " + ", ".join(l["id"] for l in out))
