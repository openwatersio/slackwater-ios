#!/usr/bin/env python3
"""Whole-arc-minute fingerprint of AyeTides' public station list.

    curl -A 'Mozilla/5.0' -o stations.js https://www.hahnsoftware.com/resources/stations.js
    python3 ayetides-station-fingerprint.py stations.js

A coordinate transcribed from a printed harmonic table sits on a whole arc-minute;
one fetched from a modern source does not. The file stores four decimals of a degree,
which puts a whole-minute value up to 0.003 arc-min off an integer, so the threshold
is 0.004: the residual histogram is empty between 0.004 and 0.01. See
ayetides-station-database-2026-09-04.md.
"""
import collections, re, sys

US = {'Alabama','Alaska','California','Connecticut','Delaware','Florida','Georgia','Hawaii',
      'Louisiana','Maine','Maryland','Massachusetts','Mississippi','New Hampshire','New Jersey',
      'New York','North Carolina','Oregon','Pennsylvania','Rhode Island','South Carolina','Texas',
      'Virginia','Washington','Puerto Rico','Guam','American Samoa','Virgin Islands',
      'Northern Mariana Islands','District of Columbia','Ohio','Michigan','Illinois','Wisconsin',
      'Minnesota','Indiana'}
TOL = 0.004  # arc-minutes

rows = re.findall(r'\[\s*(-?\d+\.?\d*)\s*,\s*(-?\d+\.?\d*)\s*,\s*"((?:[^"\\]|\\.)*)"\s*\]',
                  open(sys.argv[1]).read())
resid = lambda v: abs(abs(float(v)) * 60 - round(abs(float(v)) * 60))
region = lambda n: n.rsplit(',', 1)[-1].strip() if ',' in n else '?'

by = collections.defaultdict(lambda: [0, 0])
for lat, lon, name in rows:
    r = region(re.sub(r'\s*Current$', '', name))
    by[r][0] += 1
    by[r][1] += max(resid(lat), resid(lon)) < TOL

tot = lambda keys: [sum(by[r][i] for r in keys) for i in (0, 1)]
us, non = tot([r for r in by if r in US]), tot([r for r in by if r not in US])
cur = sum(n.rstrip().endswith('Current') for _, _, n in rows)
print(f'{len(rows)} entries: {len(rows)-cur} tide, {cur} current; {len(by)} regions')
print(f'US     {us[0]:5d}  whole-minute {100*us[1]/us[0]:3.0f}%')
print(f'non-US {non[0]:5d}  whole-minute {100*non[1]/non[0]:3.0f}%  ({non[1]} stations)')
for r, (n, w) in sorted(by.items(), key=lambda kv: -kv[1][0])[:40]:
    print(f'{r:28s} {n:5d} {100*w/n:4.0f}%')

assert len(rows) > 12000 and 100 * non[1] / non[0] > 60 and 100 * us[1] / us[0] < 15
