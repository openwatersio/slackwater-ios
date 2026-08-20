# World Basemap Floor (Plan B) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

> **This repo's standing warning applies to this document** (CLAUDE.md, "Plans and briefs
> are intent, not source"): every Swift block below is hand-written and has never been
> compiled. Line numbers were read from source on 2026-08-19 and drift. If a code block or
> stated fact looks wrong against the file in front of you, check it and say so — across
> the last two plans, ~10 defects traced to the plan and ~0 to implementers who verified.

**Goal:** Deliver spec §2 of `docs/superpowers/specs/2026-08-16-global-coverage-design.md` — a bundled worldwide basemap floor so no station on earth opens onto blank water, downloadable region packs restoring detail (US+Canada, UK & Ireland), and the bundle shrinking ~104 MB → ~79 MB.

**Architecture:** Replace the three national tilesets (`land-usca`, `seamap-natl`, `seascape-natl`) with three world cuts at the measured knees (land z0-6, seamap z0-7, seascape z0-5). Add a pack layer: a `PackStore` resolver (packs directory → app bundle) behind every resource lookup, a `MapPackService` (background `URLSession`, Application Support/MapPacks), region tiers in the style between the world floor and the Salish tier, and remote `pmtiles://https://…` sources as the free online fallback for undownloaded regions. Packs are hosted on a new public GitHub Pages repo (`Range`/206 verified — the constraint that has bitten twice).

**Tech Stack:** tippecanoe/pmtiles/tile-join/ogr2ogr (tile builds), MapLibre Native 6.9 (`pmtiles://` support), XcodeGen, XCTest.

## Global Constraints

- **Bundle ceiling: ≤ 104 MB** (spec success criterion 4). Target after Task 2: ~79 MB of Resources.
- **This branch is `feat/world-basemap-floor` in worktree `../slackwater-ios-wt-world-basemap`.** slackwater-ios is branch-and-PR on every machine; never commit to `main`; never merge your own PR. Before opening the PR: `git log --oneline origin/main..HEAD` must be only this branch's commits.
- **Tests run via `./scripts/test.sh` only** (self-serializes on `/tmp/slackwater-test.lock`; concurrent xcodebuild runs SIGKILL each other). Fast compile check: `lockf -t 0 /tmp/slackwater-test.lock xcodebuild build-for-testing -project Slackwater.xcodeproj -scheme Slackwater -destination 'platform=iOS Simulator,name=iPhone 17' -clonedSourcePackagesDirPath build/SourcePackages 2>&1 | tail -20`.
- **`tile-join` traps** (CLAUDE.md): always `-pk` (default 500 KB ceiling silently drops features); always copy the extract's header back (`pmtiles show --header-json` → `pmtiles edit`), else bounds become the whole planet; output is not byte-deterministic — a no-change rebuild diff is not content drift.
- **Resources are auto-globbed**: `project.yml` `sources: [Slackwater]` picks up everything in `Slackwater/Resources/`; adding/removing artifacts needs `xcodegen generate` (scripts/test.sh runs it), no project.yml edit.
- **Outbound gate:** the tiles-repo README and any upstream-visible text get Bryan's review before publish. Creating the public tiles repo is a **Bryan gate** (Task 3).
- **Attribution:** OSM-derived land requires "© OpenStreetMap contributors" wherever it draws — already carried on every land source; keep it on pack and remote sources.

**Spec deviations, decided here (flag in PR description):**
1. **Host is ours, not Brandon's.** Spec §2 names `tiles.openwaters.io`; investigation (2026-08-19) found that is Brandon's infra with no publishing path for us. Packs ship from a new `sailingnaturali/slackwater-tiles` GitHub Pages repo. The host lives in one constant (`MapPackService.host`) so it can move later. Custom domain deferred: the app is TestFlight-only, so re-pointing before App Store costs nothing.
2. **The UK pack gains `land-uk.pmtiles` (z0-12).** The spec's table has no land row for the UK pack, but criterion 3 says "Salish-grade detail" — a z0-6 world land floor overzoomed to z12 is visibly polygonal coastline. Small artifact (measure; expect single-digit MB).
3. **No UK seascape.** z0-10 is 54 MB (the one number in the spec table that breaks the pack budget); the world z0-5 depth floor shows through. Revisit if a shallower UK depth cut measures sane.

---

### Task 1: World tile cuts (build scripts + artifacts)

No Swift. Parameterize the one hardcoded script, add world outputs, build and commit three artifacts. Requires `pmtiles`, `tippecanoe`, `ogr2ogr` (`brew install pmtiles tippecanoe gdal`), ~1 GB of downloads, ~30 min of CPU.

**Files:**
- Modify: `tools/build-land.sh` (clip/zoom/out currently hardcoded at `:40-45`, `:58`)
- Modify: `tools/build-seamap.sh` (add world cut via its existing `cut()` helper, `:101-123`)
- Modify: `tools/build-seascape.sh` (add world extract, `:54-57`)
- Create: `Slackwater/Resources/land-world.pmtiles`, `Slackwater/Resources/seamap-world.pmtiles`, `Slackwater/Resources/seascape-world.pmtiles`

**Interfaces:**
- Produces: the three `*-world.pmtiles` artifacts Task 2 wires in, and env-var hooks (`LAND_CLIP`, `LAND_MAXZOOM`, `LAND_SIMPLIFICATION`, `LAND_OUT`; `SEAMAP_WORLD_*`; `SEASCAPE_WORLD_*`) Task 3 reuses for the UK cuts.
- Consumes: nothing from other tasks.

- [ ] **Step 1: Parameterize `build-land.sh`**

Replace the hardcoded clip/zoom/output with env-defaulted vars, keeping the US+CA multipolygon as the default so a bare run still reproduces `land-usca.pmtiles`:

```sh
# after WORK=…:
OUT=${LAND_OUT:-Slackwater/Resources/land-usca.pmtiles}
MAXZOOM=${LAND_MAXZOOM:-9}
SIMPLIFICATION=${LAND_SIMPLIFICATION:-8}
CLIP_WKT=${LAND_CLIP:-"MULTIPOLYGON(\
((-180 14,-52 14,-52 75,-180 75,-180 14)),\
((165 50,180 50,180 56,165 56,165 50)),\
((143 12,147 12,147 17,143 17,143 12)),\
((165 18,168 18,168 20,165 20,165 18)),\
((-172 -16,-168 -16,-168 -12,-172 -12,-172 -16)))"}
```

The intermediate `.fgb` name must vary with the clip or the `[ -f ] ||` guard serves a stale
clip: derive it, e.g. `FGB="$WORK/land-$(echo "$CLIP_WKT$MAXZOOM" | shasum | cut -c1-8).fgb"`,
and use `$FGB` in both the ogr2ogr guard and the tippecanoe input. Use `$MAXZOOM`,
`-S "$SIMPLIFICATION"`, `-o "$OUT"` in the tippecanoe line. Keep `LAND_WORK` as-is (it is
the re-download skip).

- [ ] **Step 2: Build the world land cut, with a size gate**

```sh
export LAND_WORK=~/tile-work   # persistent: skips the 925 MB re-download for Task 3
LAND_CLIP="MULTIPOLYGON(((-180 -85,180 -85,180 85,-180 85,-180 -85)))" \
LAND_MAXZOOM=6 LAND_OUT=Slackwater/Resources/land-world.pmtiles tools/build-land.sh
ls -la Slackwater/Resources/land-world.pmtiles
```

The spec's ~5 MB is **estimated, unmeasured**. Gate: if the artifact exceeds **8 MB**, retry
with `LAND_SIMPLIFICATION=16`; if still over, drop to `LAND_MAXZOOM=5`. Record the measured
size in the commit message — the spec's table gets corrected in Task 9.

- [ ] **Step 3: Add world outputs to build-seamap.sh and build-seascape.sh**

In `build-seamap.sh`, after the two existing `cut` calls (the `cut()` helper already takes
bbox/maxzoom/out — this is one more call):

```sh
WORLD_BBOX=${SEAMAP_WORLD_BBOX:--180,-85,180,85}
WORLD_MAXZOOM=${SEAMAP_WORLD_MAXZOOM:-7}
cut "$WORLD_BBOX" "$WORLD_MAXZOOM" Slackwater/Resources/seamap-world.pmtiles "${LAYERS[@]}"
```

In `build-seascape.sh`, after the natl extract:

```sh
pmtiles extract "$ARCHIVE" Slackwater/Resources/seascape-world.pmtiles \
  --bbox="${SEASCAPE_WORLD_BBOX:--180,-85,180,85}" --maxzoom="${SEASCAPE_WORLD_MAXZOOM:-5}"
```

- [ ] **Step 4: Run both, verify sizes and headers**

```sh
tools/build-seamap.sh && tools/build-seascape.sh
pmtiles show --header-json Slackwater/Resources/seamap-world.pmtiles   # bounds ≈ -180,-85,180,85; maxzoom 7
pmtiles show --header-json Slackwater/Resources/seascape-world.pmtiles # maxzoom 5
ls -la Slackwater/Resources/*-world.pmtiles
```

Expected: seamap-world ≈ 22 MB, seascape-world ≈ 4.8 MB (spec's measured numbers; a large
deviation means the upstream archive moved — stop and say so). Note the seamap/seascape
scripts also re-download style/sprites/glyphs and re-cut the salish/natl artifacts;
`git diff --stat` will show byte-noise on untouched `.pmtiles` (the tile-join
non-determinism) — `git checkout -- <path>` anything whose only change is that noise.

- [ ] **Step 5: Commit** (artifacts + scripts only — nothing else)

```sh
git add tools/build-land.sh tools/build-seamap.sh tools/build-seascape.sh \
  Slackwater/Resources/land-world.pmtiles Slackwater/Resources/seamap-world.pmtiles \
  Slackwater/Resources/seascape-world.pmtiles
git commit -m "tools: cut the world floor — land z0-6, seamap z0-7, seascape z0-5"
```

---

### Task 2: Swap the bundle to the world floor

The style stops reading the three national tilesets and reads the three world ones; the national artifacts leave the bundle (−56.6 MB, +~32 MB). **This task alone delivers success criterion 2** — every station on earth opens on drawn land.

**Files:**
- Modify: `Slackwater/MapScreen.swift` (`landSources` `:300`, `landLayers` `:313`, `national()` `:475-487`, `localFallbackStyle` `:499-560`, `composeStyle` `:568`, `MapStyler` `:612-630`)
- Delete: `Slackwater/Resources/land-usca.pmtiles`, `seamap-natl.pmtiles`, `seascape-natl.pmtiles` (from the bundle — Task 3 recovers them from git for the pack)
- Test: `SlackwaterTests/NationalScaleTests.swift` (`:294-311`, `:322-344`, `:387-418`, census `:22-36`, frame test `:168-173` — callers pass land URLs)

**Interfaces:**
- Consumes: Task 1's `*-world.pmtiles`.
- Produces: `tiered(_ layers: [[String: Any]], suffix: String, source: String) -> [[String: Any]]` (the generalized `national()` — Task 6 reuses it with `"usca"`/`"uk"`); `landLayers(_ sources: [String]) -> [[String: Any]]`; `localFallbackStyle(landUrl:worldUrl:)` and `composeStyle(_:landUrl:worldUrl:)` (renamed second parameter).

- [ ] **Step 1: Update the tests to the world names (RED)**

In `NationalScaleTests.swift`: everywhere the three tier tests assert `land-usca` /
`seamap-natl` / `seascape-natl` sources, ids, or draw order, substitute `land-world` /
`seamap-world` / `seascape-world`; layer-id suffix expectations `-natl` → `-world`. The
census test (`:22-36`) drops the three deleted artifacts and gains the three world ones.
Add the bundle-ceiling guard to the census test:

```swift
func testBundledTilesStayUnderTheCeiling() throws {
    let urls = Bundle(for: type(of: self)).urls(forResourcesWithExtension: "pmtiles", subdirectory: nil)
        ?? []
    // Resources live in the app bundle, not the test bundle:
    let tiles = Bundle.main.urls(forResourcesWithExtension: "pmtiles", subdirectory: nil) ?? urls
    let bytes = tiles.compactMap { try? FileManager.default.attributesOfItem(atPath: $0.path)[.size] as? Int }
        .reduce(0, +)
    XCTAssertLessThan(bytes, 80_000_000, "the world-floor bundle budget (spec criterion 4)")
}
```

Run: `lockf -t 0 /tmp/slackwater-test.lock xcodebuild build-for-testing …` then the suite —
expected: the renamed assertions FAIL (sources don't exist yet).

- [ ] **Step 2: Rewire MapScreen**

`landSources`/`landLayers` become source-list driven (fill ids keep the source's name, coasts
keep the `-coast` suffix — same shape as today, floor first, detailed last):

```swift
private func landSources(_ urls: [String: String]) -> [String: Any] {
    urls.mapValues { landSource($0) }
}
/// Floor-first source order; all fills, then all coasts (a coast line must not
/// hide under a later fill).
private func landLayers(_ sources: [String]) -> [[String: Any]] {
    sources.map { ["id": $0, "type": "fill", "source": $0, "source-layer": "land",
                   "paint": ["fill-color": LAND_TONE]] }
    + sources.map { ["id": "\($0)-coast", "type": "line", "source": $0, "source-layer": "land",
                     "paint": COASTLINE] }
}
```

`national()` generalizes (Task 6 reuses it):

```swift
/// A slice aimed at a coarser tier of the same tileset (#30): same layers, each
/// id suffixed and each source repointed, so several zoom tiers coexist in one style.
private func tiered(_ layers: [[String: Any]], suffix: String, source: String) -> [[String: Any]] {
    layers.map { layer in
        var t = layer
        t["id"] = "\(layer["id"] as? String ?? "")-\(suffix)"
        t["source"] = source
        return t
    }
}
```

In `localFallbackStyle` and `composeStyle`: parameter `uscaUrl` → `worldUrl`, land source
key `land-usca` → `land-world` (order: `["land-world", "land"]`), and the two natl blocks
become world blocks reusing the same slices:

```swift
if let world = offlineLayers("seascape-world", slice: "seascape",
                             attribution: "© Open Waters: Seascape") {
    sources["seascape-world"] = world.source
    style["sources"] = sources
    insertAboveLand(tiered(world.layers, suffix: "world", source: "seascape-world"))
}
// … seamap-world identically, slice: "seamap", suffix "world".
```

In `MapStyler`: `uscaUrl` → `worldUrl { pmtilesUrl("land-world") }`, and the two callers of
`localFallbackStyle`/`composeStyle` follow. Comments referencing "US+Canada z0-9 floor"
update to "the world at z0-6/7/5".

- [ ] **Step 3: Delete the national artifacts, regenerate, compile**

```sh
git rm Slackwater/Resources/land-usca.pmtiles Slackwater/Resources/seamap-natl.pmtiles \
       Slackwater/Resources/seascape-natl.pmtiles
xcodegen generate
lockf -t 0 /tmp/slackwater-test.lock xcodebuild build-for-testing -project Slackwater.xcodeproj \
  -scheme Slackwater -destination 'platform=iOS Simulator,name=iPhone 17' \
  -clonedSourcePackagesDirPath build/SourcePackages 2>&1 | tail -20
```

- [ ] **Step 4: Run the suite, and look at the map**

```sh
SLACKWATER_SIMS='iPhone 17' ./scripts/test.sh
```

Expected: PASS, including the renamed tier tests and the ceiling guard. Then the visual
check the repo's history demands: run `testM53MapAtContinentalZoom` and **open**
`/tmp/slackwater-shots/m53-map-continental.png` — the continent must be drawn. If a
simulator is handy, also launch with `-openMap -mapZoom 5 -networkKillSwitch` centered on
the UK (set `SALISH_CENTER` temporarily or scrub manually) and confirm Newhaven sits on
coastline, not blank sea.

- [ ] **Step 5: Commit**

```sh
git add Slackwater/MapScreen.swift SlackwaterTests/NationalScaleTests.swift
git commit -m "app: the basemap floor goes worldwide — no station opens on blank water"
```

---

### Task 3: Region pack artifacts + the tiles host  **(Bryan gate)**

Build the UK cuts, assemble both packs, create the public hosting repo, verify `Range`/206.

**Files:**
- Create: `tools/build-uk-pack.sh` (thin driver over the Task 1 env hooks)
- Create (new repo `sailingnaturali/slackwater-tiles`): `packs/seamap-usca.pmtiles`, `packs/seascape-usca.pmtiles`, `packs/land-usca.pmtiles`, `packs/seamap-uk.pmtiles`, `packs/land-uk.pmtiles`, `README.md`

**Interfaces:**
- Consumes: Task 1's env hooks; the pre-Task-2 national artifacts from git (`git show`).
- Produces: the five pack files live at `https://sailingnaturali.github.io/slackwater-tiles/packs/<file>` — the URLs Task 5's catalog hardcodes. Measured byte sizes for the catalog.

- [ ] **Step 1: Bryan gate — repo + README**

Creating a **public** repo is publish-adjacent: confirm the repo name
(`sailingnaturali/slackwater-tiles`) and hand Bryan the README draft (what the files are,
licences: OSM/ODbL for land, Seamap/Seascape upstream attribution, "not for navigation")
for review **before** `gh repo create`. Do not proceed on silence.

- [ ] **Step 2: Build the UK cuts**

```sh
# UK & Ireland bbox from the spec: -11,49.5,3,61
SEAMAP_BBOX=-11,49.5,3,61 SEAMAP_MAXZOOM=12 SEAMAP_WORLD_MAXZOOM=0 …
```

…except `build-seamap.sh` unconditionally writes the salish/natl/world outputs too — so
`tools/build-uk-pack.sh` instead calls the pieces directly, reusing the script's own
`cut()` pattern (copy it — extract, `tile-join -pk` strip to the same keep-list derived
from `seamap-layers.json`, header copy-back):

```sh
#!/usr/bin/env bash
# UK & Ireland region pack: seamap z0-12 + land z0-12. No seascape — the z0-10
# depth cut measured 54 MB (spec §2 table); the world z0-5 floor shows through.
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=${PACK_OUT:-/tmp/slackwater-packs}
mkdir -p "$OUT"
BBOX="-11,49.5,3,61"
BASE="https://tiles.openwaters.io/seamap"; BUILD=${SEAMAP_BUILD:-2026-08-03}
# keep-list: same derivation as build-seamap.sh (drop `land`)
LAYERS=() ; while IFS= read -r layer; do [ "$layer" = land ] || LAYERS+=(-l "$layer"); done < <(python3 -c '
import json,sys; print("\n".join(sorted({l["source-layer"] for l in json.load(open(sys.argv[1])) if "source-layer" in l})))' Slackwater/Resources/seamap-layers.json)
raw=$(mktemp -d)/uk.pmtiles
pmtiles extract "$BASE/$BUILD.pmtiles" "$raw" --bbox="$BBOX" --maxzoom=12
tile-join -pk -f "${LAYERS[@]}" -o "$OUT/seamap-uk.pmtiles" "$raw"
pmtiles show --header-json "$raw" > "$raw.header"
pmtiles edit "$OUT/seamap-uk.pmtiles" --header-json="$raw.header"
LAND_CLIP="MULTIPOLYGON(((-11 49.5,3 49.5,3 61,-11 61,-11 49.5)))" \
  LAND_MAXZOOM=12 LAND_OUT="$OUT/land-uk.pmtiles" tools/build-land.sh
ls -la "$OUT"
```

Run it (`LAND_WORK=~/tile-work` reuses Task 1's download). Gates: seamap-uk ≈ 16 MB
(spec-measured); land-uk **measure it** — if over 10 MB, `LAND_SIMPLIFICATION=16`.

- [ ] **Step 3: Recover the US+CA pack files from git and stage everything**

```sh
git show origin/main:Slackwater/Resources/seamap-natl.pmtiles   > /tmp/slackwater-packs/seamap-usca.pmtiles
git show origin/main:Slackwater/Resources/seascape-natl.pmtiles > /tmp/slackwater-packs/seascape-usca.pmtiles
git show origin/main:Slackwater/Resources/land-usca.pmtiles     > /tmp/slackwater-packs/land-usca.pmtiles
```

(The rename is deliberate: pack files are named by region so a future pack never collides
with a bundle resource name.)

- [ ] **Step 4: Create the repo, publish, enable Pages** (after the Step 1 go)

```sh
gh auth status
gh repo create sailingnaturali/slackwater-tiles --public --clone
cd slackwater-tiles && mkdir packs && cp /tmp/slackwater-packs/*.pmtiles packs/
# + the Bryan-approved README.md
git add -A && git commit -m "packs: usca + uk region tilesets" && git push
gh api -X POST repos/sailingnaturali/slackwater-tiles/pages -f 'source[branch]=main' -f 'source[path]=/'
```

- [ ] **Step 5: Verify Range/206 — the load-bearing check**

PMTiles cannot be read without it (this has bitten twice: Brandon's Worker, Workbox precache):

```sh
curl -sI -r 0-16383 https://sailingnaturali.github.io/slackwater-tiles/packs/seamap-uk.pmtiles | head -5
# Expected: HTTP/2 206, content-range: bytes 0-16383/<total>
pmtiles show --header-json https://sailingnaturali.github.io/slackwater-tiles/packs/seamap-uk.pmtiles
# Expected: the UK bounds, maxzoom 12 — proves a remote pmtiles read end to end
```

If Pages does not return 206, STOP — the hosting choice is wrong and the fallback is
Cloudflare R2 (new token; Bryan decision). Record the measured file sizes (they go in
Task 5's catalog).

- [ ] **Step 6: Commit the driver script in slackwater-ios**

```sh
git add tools/build-uk-pack.sh
git commit -m "tools: UK & Ireland pack cuts — seamap z0-12, land z0-12"
```

---

### Task 4: PackStore — one resolver behind every resource lookup

**Files:**
- Create: `Slackwater/MapPacks.swift` (PackStore only, this task)
- Modify: `Slackwater/MapScreen.swift` (`offlineLayers` `:452-459`, `bundledGlyphs` `:490-497`, `MapStyler.pmtilesUrl` `:624-630`), `Slackwater/CurrentStation.swift:41`
- Test: `SlackwaterTests/MapPackTests.swift`

**Interfaces:**
- Produces: `enum PackStore { static var dir: URL; static func url(_ name: String, ext: String) -> URL? }` — packs directory first, `Bundle.main` second, nil when neither. Tasks 5/6 consume `dir` and `url`.
- Consumes: nothing (pure lookup; no service yet).

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import Slackwater

final class MapPackTests: XCTestCase {
    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: PackStore.dir)
    }

    func testResolverPrefersAnInstalledPackFileOverTheBundle() throws {
        try FileManager.default.createDirectory(at: PackStore.dir, withIntermediateDirectories: true)
        let planted = PackStore.dir.appendingPathComponent("seamap-layers.json")
        try Data("[]".utf8).write(to: planted)
        XCTAssertEqual(PackStore.url("seamap-layers", ext: "json"), planted)
    }

    func testResolverFallsBackToTheBundle() {
        XCTAssertEqual(PackStore.url("seamap-layers", ext: "json"),
                       Bundle.main.url(forResource: "seamap-layers", withExtension: "json"))
    }

    func testResolverReturnsNilWhenNeitherExists() {
        XCTAssertNil(PackStore.url("no-such-tileset", ext: "pmtiles"))
    }
}
```

- [ ] **Step 2: Run to verify RED** — `PackStore` unresolved; compile failure is the RED here (build-for-testing under the lock).

- [ ] **Step 3: Implement PackStore**

```swift
// Slackwater — GPL v3. Region map packs (Plan B, 2026-08-16 spec §2): the one
// resolver every bundled-resource lookup routes through. A file in the packs
// directory wins over the bundle, so a downloaded pack can extend or replace
// any shipped artifact without the style code knowing which is which.
import Foundation

enum PackStore {
    /// Application Support/MapPacks — same home as ChsChunks/ChsModels.
    static var dir: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MapPacks")
    }

    static func url(_ name: String, ext: String) -> URL? {
        let packed = dir.appendingPathComponent("\(name).\(ext)")
        if FileManager.default.fileExists(atPath: packed.path) { return packed }
        return Bundle.main.url(forResource: name, withExtension: ext)
    }
}
```

- [ ] **Step 4: Route the six call sites through it**

- `MapScreen.swift` `offlineLayers`: both `Bundle.main.url(forResource: name, withExtension: "pmtiles")` → `PackStore.url(name, ext: "pmtiles")` and the `-layers` json lookup → `PackStore.url("\(slice ?? name)-layers", ext: "json")`; the sprite guard likewise (`PackStore.url(sprite, ext: "json")`) — note the sprite base derivation (`deletingPathExtension`) is unchanged.
- `bundledGlyphs()`: the probe → `PackStore.url("\(OFFLINE_LABEL_FONT[0])-0-255", ext: "pbf")`. Keep the existing comment's warning: the whole glyph directory derives from this one file's parent, so a pack shipping glyphs must ship **every** range together.
- `MapStyler.pmtilesUrl`: → `PackStore.url(name, ext: "pmtiles")`.
- `CurrentStation.swift:41` `bundled<T>`: → `PackStore.url(resource, ext: "json")`. (No pack ships catalogs yet; this is the spec's sixth site, routed now so a future data pack needs no code.)

- [ ] **Step 5: Run the suite** — `SLACKWATER_SIMS='iPhone 17' ./scripts/test.sh`. The new tests PASS; the existing style tests still PASS (resolver is bundle-equivalent when no pack is installed).

- [ ] **Step 6: Commit**

```sh
git add Slackwater/MapPacks.swift Slackwater/MapScreen.swift Slackwater/CurrentStation.swift \
  SlackwaterTests/MapPackTests.swift
git commit -m "app: PackStore — packs directory resolves ahead of the bundle"
```

---

### Task 5: MapPackService — catalog, background download, delete

**Files:**
- Modify: `Slackwater/MapPacks.swift` (add MapPack, MapPackService)
- Modify: `Slackwater/SlackwaterApp.swift` (UIApplicationDelegateAdaptor for background-session relaunch)
- Test: `SlackwaterTests/MapPackTests.swift`

**Interfaces:**
- Consumes: `PackStore.dir` (Task 4); measured pack sizes (Task 3).
- Produces (Tasks 6/7 consume): `struct MapPack: Identifiable { let id: String; let title: String; let files: [String]; let bytes: Int64 }`, `MapPack.catalog: [MapPack]`, `MapPackService.host: String`, `@MainActor final class MapPackService: NSObject, ObservableObject` with `@Published private(set) var states: [String: PackState]`, `enum PackState: Equatable { case absent, downloading(Double), installed, failed }`, `func download(_ pack: MapPack)`, `func delete(_ pack: MapPack)`, `func installed(_ pack: MapPack) -> Bool`, `var backgroundCompletion: (() -> Void)?`.

- [ ] **Step 1: Write the failing tests** (state machine + disk, no network — the kill-switch discipline)

```swift
func testCatalogFilesAreUniqueAndNeverShadowASalishBundleResource() {
    let files = MapPack.catalog.flatMap(\.files)
    XCTAssertEqual(files.count, Set(files).count)
    for f in files {  // a pack must never occlude a bundled artifact by name
        XCTAssertNil(Bundle.main.url(forResource: f, withExtension: "pmtiles"), f)
    }
}

func testInstalledIsDerivedFromEveryFileOnDisk() throws {
    let pack = MapPack.catalog.first { $0.id == "uk" }!
    let service = MapPackService()          // non-shared: tests never touch the singleton's session
    XCTAssertFalse(service.installed(pack))
    try FileManager.default.createDirectory(at: PackStore.dir, withIntermediateDirectories: true)
    for f in pack.files.dropLast() {
        try Data([0x50]).write(to: PackStore.dir.appendingPathComponent("\(f).pmtiles"))
    }
    XCTAssertFalse(service.installed(pack), "a partial pack is not installed")
    try Data([0x50]).write(to: PackStore.dir.appendingPathComponent("\(pack.files.last!).pmtiles"))
    XCTAssertTrue(service.installed(pack))
}

func testDeleteRemovesTheFilesAndTheState() throws {
    let pack = MapPack.catalog.first { $0.id == "uk" }!
    try FileManager.default.createDirectory(at: PackStore.dir, withIntermediateDirectories: true)
    for f in pack.files {
        try Data([0x50]).write(to: PackStore.dir.appendingPathComponent("\(f).pmtiles"))
    }
    let service = MapPackService()
    service.delete(pack)
    XCTAssertFalse(service.installed(pack))
    XCTAssertEqual(service.states[pack.id], .absent)
}
```

- [ ] **Step 2: RED** (compile failure under the lock), **Step 3: implement**

```swift
struct MapPack: Identifiable {
    let id: String
    let title: String
    let files: [String]      // pmtiles basenames on the host and in PackStore.dir
    let bytes: Int64         // measured in Task 3; UI display + ETA only

    // ponytail: hardcoded two-pack catalog; a remote manifest when a pack
    // ships that predates the app version that knows it.
    static let catalog: [MapPack] = [
        MapPack(id: "usca", title: "US & Canada",
                files: ["seamap-usca", "seascape-usca", "land-usca"],
                bytes: 56_600_000),                       // ← replace with Task 3 measurements
        MapPack(id: "uk", title: "UK & Ireland",
                files: ["seamap-uk", "land-uk"],
                bytes: 22_000_000),                       // ← replace with Task 3 measurements
    ]
}

@MainActor
final class MapPackService: NSObject, ObservableObject {
    static let shared = MapPackService()
    /// One constant so the host can move (e.g. to tiles.openwaters.io if that
    /// collaboration firms up) without touching style or UI code.
    static let host = "https://sailingnaturali.github.io/slackwater-tiles/packs"

    enum PackState: Equatable { case absent, downloading(Double), installed, failed }
    @Published private(set) var states: [String: PackState] = [:]
    var backgroundCompletion: (() -> Void)?
    private var tasks: [Int: (pack: MapPack, file: String)] = [:]   // taskIdentifier → what it fetches

    override init() {
        super.init()
        for pack in MapPack.catalog {
            states[pack.id] = installed(pack) ? .installed : .absent
        }
    }

    func installed(_ pack: MapPack) -> Bool {
        pack.files.allSatisfy {
            FileManager.default.fileExists(atPath: PackStore.dir.appendingPathComponent("\($0).pmtiles").path)
        }
    }

    func delete(_ pack: MapPack) {
        for f in pack.files {
            try? FileManager.default.removeItem(at: PackStore.dir.appendingPathComponent("\(f).pmtiles"))
        }
        states[pack.id] = .absent
    }

    // Background session: survives suspension mid-download (spec §2 Delivery;
    // ODR rejected — purgeable; Background Assets rejected — an extension
    // target for a file copy).
    private lazy var session = URLSession(
        configuration: .background(withIdentifier: "org.openwaters.slackwater.packs"),
        delegate: PackDelegate(service: self), delegateQueue: nil)

    func download(_ pack: MapPack) {
        guard !networkKillSwitch, states[pack.id] != .installed else { return }
        states[pack.id] = .downloading(0)
        for f in pack.files where !FileManager.default.fileExists(
                atPath: PackStore.dir.appendingPathComponent("\(f).pmtiles").path) {
            let task = session.downloadTask(with: URL(string: "\(Self.host)/\(f).pmtiles")!)
            tasks[task.taskIdentifier] = (pack, f)
            task.resume()
        }
    }

    // Called by the delegate (already hopped to the main actor).
    func finished(_ taskID: Int, tmp: URL?, error: Error?) {
        guard let (pack, file) = tasks.removeValue(forKey: taskID) else { return }
        let fm = FileManager.default
        if let tmp {
            try? fm.createDirectory(at: PackStore.dir, withIntermediateDirectories: true)
            let dest = PackStore.dir.appendingPathComponent("\(file).pmtiles")
            try? fm.removeItem(at: dest)
            try? fm.moveItem(at: tmp, to: dest)
        }
        if error != nil { states[pack.id] = .failed; return }
        if installed(pack) { states[pack.id] = .installed }
    }

    func progressed(_ taskID: Int, fraction: Double) {
        guard let (pack, _) = tasks[taskID], case .downloading = states[pack.id] else { return }
        // ponytail: per-file fraction on a multi-file pack jumps around; a
        // byte-weighted aggregate when someone minds.
        states[pack.id] = .downloading(fraction)
    }
}

/// The nonisolated delegate: the background session calls it on its own queue.
/// GOTCHA: `didFinishDownloadingTo`'s file dies when the callback returns, so
/// the move happens HERE, synchronously — only the bookkeeping hops actors.
private final class PackDelegate: NSObject, URLSessionDownloadDelegate {
    weak var service: MapPackService?
    init(service: MapPackService) { self.service = service }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        let fm = FileManager.default
        let hold = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? fm.moveItem(at: location, to: hold)
        let id = downloadTask.taskIdentifier
        let ok = (downloadTask.response as? HTTPURLResponse)?.statusCode == 200
        Task { @MainActor [weak service] in
            service?.finished(id, tmp: ok ? hold : nil,
                              error: ok ? nil : ChsError.failed("HTTP"))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }
        let id = task.taskIdentifier
        Task { @MainActor [weak service] in service?.finished(id, tmp: nil, error: error) }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let id = downloadTask.taskIdentifier
        let f = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        Task { @MainActor [weak service] in service?.progressed(id, fraction: f) }
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        Task { @MainActor [weak service] in
            service?.backgroundCompletion?()
            service?.backgroundCompletion = nil
        }
    }
}
```

Verify `ChsError.failed` exists and is reachable from here (it lives in ChsFitService.swift);
if it is fileprivate, define a local `PackError`. **Check the actor story compiles** — the
`@MainActor` init constructing a nonisolated delegate, and `MapPackService()` in tests
(annotate the test class `@MainActor` if XCTest complains).

In `SlackwaterApp.swift`:

```swift
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     handleEventsForBackgroundURLSession identifier: String,
                     completionHandler: @escaping () -> Void) {
        MapPackService.shared.backgroundCompletion = completionHandler
    }
}
// in SlackwaterApp:
@UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
```

- [ ] **Step 4: Suite green** (`SLACKWATER_SIMS='iPhone 17' ./scripts/test.sh`), **Step 5: one observed live download** — on a simulator, tap nothing: from a debug launch, call `MapPackService.shared.download(MapPack.catalog[1])` (or wait for Task 7's UI) and confirm the two UK files land in Application Support/MapPacks and `states["uk"] == .installed`. This is the "test immediately" rule: the downloader must be seen downloading once before the UI task builds on it.

- [ ] **Step 6: Commit**

```sh
git add Slackwater/MapPacks.swift Slackwater/SlackwaterApp.swift SlackwaterTests/MapPackTests.swift
git commit -m "app: MapPackService — background pack downloads into Application Support"
```

---

### Task 6: Region tiers in the style — local when installed, remote when online

**Files:**
- Modify: `Slackwater/MapScreen.swift` (`offlineLayers`, `localFallbackStyle`, `composeStyle`)
- Test: `SlackwaterTests/NationalScaleTests.swift` (or MapPackTests — implementer's call)

**Interfaces:**
- Consumes: `tiered(_:suffix:source:)` and `landLayers(_:)` (Task 2), `PackStore` (Task 4), `MapPack.catalog` / `MapPackService.host` (Task 5).
- Produces: `func packTileUrl(_ file: String) -> String?` — `pmtiles://<local file>` when installed, `pmtiles://https://<host>/<file>.pmtiles` when absent-but-online (the spec's free fallback), nil when absent-and-killswitched.

- [ ] **Step 1: Failing tests**

```swift
func testAnInstalledPackTierDrawsBetweenTheWorldFloorAndTheSalishDetail() throws {
    try FileManager.default.createDirectory(at: PackStore.dir, withIntermediateDirectories: true)
    // plant a fake installed UK pack (style building reads paths, not tile bytes)
    for f in ["seamap-uk", "land-uk"] {
        try Data([0x50]).write(to: PackStore.dir.appendingPathComponent("\(f).pmtiles"))
    }
    defer { try? FileManager.default.removeItem(at: PackStore.dir) }
    let style = localFallbackStyle(landUrl: "", worldUrl: "")
    let sources = style["sources"] as! [String: Any]
    let url = (sources["seamap-uk"] as! [String: Any])["url"] as! String
    XCTAssertTrue(url.hasPrefix("pmtiles://file:"), "installed pack reads the local file")
    let ids = (style["layers"] as! [[String: Any]]).map { $0["id"] as! String }
    // world floor under the pack tier, pack tier under the Salish detail, pins on top
    XCTAssertLessThan(ids.firstIndex(of: "seamark-world") ?? .max,   // adjust to a real seamap layer id
                      ids.firstIndex(of: "seamark-uk") ?? .max)
    XCTAssertLessThan(ids.firstIndex(of: "seamark-uk") ?? .max,
                      ids.firstIndex(of: "station-clusters") ?? .max)
}

func testAnAbsentPackFallsBackToTheRemoteArchive() {
    let style = localFallbackStyle(landUrl: "", worldUrl: "")
    let sources = style["sources"] as! [String: Any]
    guard let uk = sources["seamap-uk"] as? [String: Any] else {
        return XCTFail("absent pack should still have a remote source when online")
    }
    XCTAssertTrue((uk["url"] as! String).hasPrefix("pmtiles://https://"))
}
```

**Before writing the ordering assertion, read `seamap-layers.json` for a real layer id** —
"seamark" above is a guess, and the id in the style carries the tier suffix. The remote
test must account for `networkKillSwitch` being false in unit tests (it is — no launch
args) — but see Step 2's kill-switch handling.

- [ ] **Step 2: Implement**

```swift
/// A pack tileset's source URL: the downloaded file when installed; the
/// range-addressable remote archive when not (PMTiles over HTTP — the free
/// online fallback, spec §2); nil offline, so the style honestly omits it.
func packTileUrl(_ file: String) -> String? {
    if let local = PackStore.url(file, ext: "pmtiles") {
        return "pmtiles://\(local.absoluteString)"
    }
    guard !networkKillSwitch else { return nil }
    return "pmtiles://\(MapPackService.host)/\(file).pmtiles"
}
```

In `localFallbackStyle`, after the world tiers and **before** the Salish blocks (detailed
inserted last still wins collisions), add the pack tiers. Packs reuse the bundled slices
(`seamap-*` reads `seamap`'s slice; `land-*` uses `landLayers`; `seascape-usca` reads
`seascape`'s slice). Shape:

Pack **land** goes through the Task 2 source-list machinery, not this loop: build the land
list dynamically — `["land-world"] + packLandFiles.compactMap { packTileUrl($0) != nil ? $0 : nil } + ["land"]`
— and feed it to `landSources(_:)`/`landLayers(_:)`, with each pack land source's URL coming
from `packTileUrl`. The loop below handles only seamap/seascape pack files:

```swift
for pack in MapPack.catalog {
    for file in pack.files where !file.hasPrefix("land") {
        guard let url = packTileUrl(file) else { continue }
        let slice = file.hasPrefix("seamap") ? "seamap" : "seascape"
        guard let tier = offlineLayers(file, slice: slice, url: url,
                                       attribution: slice == "seamap"
                                           ? "© Open Waters: Seamap © OpenStreetMap contributors"
                                           : "© Open Waters: Seascape") else { continue }
        sources[file] = tier.source
        style["sources"] = sources
        insertAboveLand(tiered(tier.layers, suffix: pack.id, source: file))
    }
}
```

One structural note the implementer owns: `offlineLayers` today derives the tiles URL from
the resource name; it needs an optional `url: String? = nil` parameter that overrides the
`PackStore` lookup, so a **remote** source can carry the slice's layers. Keep it one
function. Depth ordering *within* a region between its land and its seamarks follows from
the existing insert-above-land anchor; verify against the Step 1 ordering test.

Mirror the same pack loop in `composeStyle` (the online Seascape-composed style must also
carry pack tiers, or downloading a pack would only improve the offline map).

- [ ] **Step 3: Suite green, then the observed check** — with the Task 5 UK download installed
on a simulator, launch with `-networkKillSwitch -openMap -mapZoom 8` and manually pan to the
Solent (or temporarily point `SALISH_CENTER` at 50.75,-1.1): chart marks and coastline must
draw **offline**. Screenshot it for the PR. This is success criterion 3's evidence.

- [ ] **Step 4: Commit**

```sh
git add Slackwater/MapScreen.swift SlackwaterTests/
git commit -m "app: region pack tiers — local when downloaded, remote archive when online"
```

---

### Task 7: Region packs UI in Settings

**Files:**
- Modify: `Slackwater/MapPacks.swift` (add `MapPackListView`)
- Modify: `Slackwater/SettingsView.swift` (new section after "Offline downloads", `:42-57` is the template)
- Test: `SlackwaterUITests/ScreenshotTests.swift`

**Interfaces:**
- Consumes: `MapPackService.shared` (`states`, `download`, `delete`), `MapPack.catalog`.
- Produces: accessibility identifiers `map-packs` (settings row), `map-pack-row-<id>` (rows) — the UI test keys on these.

- [ ] **Step 1: Failing UI test**

```swift
func testMapPacksListsTheCatalog() throws {
    let app = launch(["-seedGate", "-networkKillSwitch"])   // match the file's existing launch helper
    app.buttons["settings"].tap()                            // verify the real identifier in SettingsView
    app.buttons["map-packs"].tap()
    XCTAssertTrue(app.staticTexts["US & Canada"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["UK & Ireland"].exists)
    save(app.screenshot(), as: "map-packs")                  // match the file's screenshot helper
}
```

**Copy the launch/screenshot helper invocations from a neighbouring test in the same file**
(e.g. `testM4Settings` at `:482-490`) — the names above are placeholders for whatever that
file actually uses, and the settings-gear identifier must be read from `SettingsView`/
`MapHeader`, not guessed.

- [ ] **Step 2: RED, Step 3: implement**

In `SettingsView` body, after the "Offline downloads" section (same `section(_:content:)`
card + `NavigationLink` + chevron shape — copy `:42-57` verbatim and re-label):

```swift
section("Region map packs") {
    NavigationLink { MapPackListView() } label: {
        HStack {
            Text("\(MapPack.catalog.filter { packs.states[$0.id] == .installed }.count) of \(MapPack.catalog.count) downloaded")
            Spacer()
            Image(systemName: "chevron.right")
        }
        .foregroundStyle(SN.leaf)
    }
    .accessibilityIdentifier("map-packs")
}
```

(`@ObservedObject private var packs = MapPackService.shared` joins the existing `chs`
observation at `:10`.)

`MapPackListView` — one row per catalog entry, mirroring `OfflineManagerList`'s row idiom
(MonoLabel name, status line, trailing button):

```swift
struct MapPackListView: View {
    @ObservedObject private var service = MapPackService.shared

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(MapPack.catalog) { pack in
                    row(pack)
                        .accessibilityIdentifier("map-pack-row-\(pack.id)")
                }
                Text("Without a pack, detail past the world chart needs a connection.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .padding()
        }
        .navigationTitle("Region map packs")
    }

    @ViewBuilder private func row(_ pack: MapPack) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(pack.title)
                Text(ByteCountFormatter.string(fromByteCount: pack.bytes, countStyle: .file))
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Spacer()
            switch service.states[pack.id] ?? .absent {
            case .absent:
                Button("Download") { service.download(pack) }
            case .downloading(let f):
                ProgressView(value: f).frame(width: 80)
            case .installed:
                Button("Remove", role: .destructive) { service.delete(pack) }
            case .failed:
                Button("Retry") { service.download(pack) }
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(SN.cardFill))
    }
}
```

Match the card fill/stroke tokens to what `SettingsView.section` actually uses. Keep the
"Data & attribution" section honest — the map credits at `:70-72` already name OSM/Seamap/
Seascape, which cover pack content; verify, don't assume.

- [ ] **Step 4: Suite + open the screenshot** (`/tmp/slackwater-shots/map-packs.png` — both rows visible, Download buttons legible), **Step 5: commit**

```sh
git add Slackwater/MapPacks.swift Slackwater/SettingsView.swift SlackwaterUITests/ScreenshotTests.swift
git commit -m "app: region map packs — download and remove from Settings"
```

---

### Task 8: Pin source off the style-build path — restore the 0.30 s budget

Carried from Plan A (spec §2, carried-over item 1): the frame test was loosened 0.30 s →
0.75 s because `localFallbackStyle` builds the 4,699-station pin GeoJSON synchronously. Move
the pin build off the construction path; put the strict budget back.

**Files:**
- Modify: `Slackwater/MapScreen.swift` (`stationSource()` `:335-341`, `MapStyler.applyChsTones` `:688-714`)
- Test: `SlackwaterTests/NationalScaleTests.swift:143-173`

**Interfaces:**
- Consumes: `PinFeaturesCache.shared` (unchanged), the existing `applyChsTones` detached-push mechanism.
- Produces: no new API — `stationSource()` returns an empty FeatureCollection; the full pin set arrives via the existing post-style-load push.

- [ ] **Step 1: Tighten the test (RED)**

In `testPinLayerBuildsInsideAFrame`, `0.75` → `0.30`, and update its doc comment (`:143-167`)
with the mechanism change. Run the single test in isolation (under the lock):

```sh
lockf /tmp/slackwater-test.lock xcodebuild test -project Slackwater.xcodeproj -scheme Slackwater \
  -destination 'platform=iOS Simulator,name=iPhone 17' -clonedSourcePackagesDirPath build/SourcePackages \
  -only-testing:SlackwaterTests/NationalScaleTests/testPinLayerBuildsInsideAFrame 2>&1 | tail -20
```

Expected: FAIL (~0.57 s measured cold on Plan A).

- [ ] **Step 2: Implement**

`stationSource()` stops paying for the world:

```swift
private func stationSource() -> [String: Any] {
    [
        // Empty at construction: 4,699 stations × ~40 constituents is a ~0.5 s
        // cold build (Plan A measurement), which must not sit on the style
        // path. applyChsTones pushes the real features after every style load.
        "type": "geojson", "data": ["type": "FeatureCollection", "features": [[String: Any]]()],
        "cluster": true, "clusterMaxZoom": CLUSTER_MAX_ZOOM, "clusterRadius": 46,
    ]
}
```

`applyChsTones` currently bails to "neutral is honest" when no CHS tones exist
(`guard !tones.isEmpty else { return nil }`) — that guard must now push the **untoned** pin
set instead of returning nil, or a fresh install would show an empty map:

```swift
let geojson = await Task.detached(priority: .utility) { () -> Data? in
    let tones = chsPinTones(at: appNow(), tideRecords: tides, currentRecords: currents)
    let geojson = tones.isEmpty
        ? PinFeaturesCache.shared.snapshot()          // no CHS sync yet: full pins, neutral CHS
        : PinFeaturesCache.shared.update(tones: tones)
    return try? JSONSerialization.data(withJSONObject: geojson)
}.value
```

Rename the method (`pushPins`?) and its doc comment — it is now the pin source's *only*
producer, not just the CHS colourist. **Trace both callers/mechanisms before editing:** the
style loads twice (fallback, then Seascape), and `mapView(_:didFinishLoading:)` is where
the push re-arms; verify the UI map-tap tests (`handleTap` hit-testing) still find pins —
they wait on elements, and the detached build lands in well under their timeouts, but this
is exactly the "green suite, blank chart" shape CLAUDE.md warns about.

- [ ] **Step 3: Prove the pins still arrive.** The unit suite cannot see the async push
(it never constructs an `MLNMapView`). The evidence is: (a) the isolated frame test now
PASSES under 0.30 s, (b) the full iPhone leg of the suite passes — the pin-tap UI tests
(`handleTap` consumers) fail if pins never land, and (c) **open a map screenshot** and see
dots. All three, not one.

- [ ] **Step 4: Commit**

```sh
git add Slackwater/MapScreen.swift SlackwaterTests/NationalScaleTests.swift
git commit -m "app: pin source builds off the style path — frame budget back to 0.30s"
```

---

### Task 9: Docs, spec status, coupled surfaces, PR

**Files:**
- Modify: `docs/superpowers/specs/2026-08-16-global-coverage-design.md` (status header + §2 table corrections)
- Modify: `CLAUDE.md` (the stations→currents coupling entry: "six records" → eleven, add the bit-twice fact — spec §2 carried-over item 2 asked for exactly this)
- Modify: `README.md` (if it describes the bundled map tiers — read it first)

- [ ] **Step 1: Spec header** — mark §2 / criteria 2, 3, 4 delivered, with the three deviations from this plan's Global Constraints (our host, UK land added, no UK seascape) and the measured artifact sizes replacing the table's estimates.

- [ ] **Step 2: CLAUDE.md coupling correction** — the `stations.json`→`currents.json` entry: correct six → eleven, add that the coupling bit twice on one branch undetected. One paragraph, no new section.

- [ ] **Step 3: Full suite** — `./scripts/test.sh --full` (both simulators; budget ~40 min; remember `testM51PromotionInterruptsAnInFlightDownload` fails ~2/3 of full runs under load — re-run it in isolation before blaming this branch).

- [ ] **Step 4: Verify branch hygiene and open the PR**

```sh
git log --oneline origin/main..HEAD   # only this branch's commits — rebase --onto if not
git push -u origin feat/world-basemap-floor
gh pr create --title "World basemap floor + region packs (Plan B)" --body "…"
```

PR body: the spec §2 mapping, the three deviations, bundle math (104 → measured), the
Solent offline screenshot, and the Task 3 host verification output. **Do not merge** — the
merge is Bryan's. Internal repo, so opening the PR needs no pre-approval; the tiles-repo
README already got its outbound review in Task 3.

---

## Success criteria → task map

| Spec criterion | Delivered by |
|---|---|
| 2. Real chart at every zoom, anywhere, no pack | Tasks 1-2 |
| 3. UK pack → Solent at Salish-grade detail, airplane mode | Tasks 3-7 (evidence: Task 6 Step 3 screenshot) |
| 4. Bundle ≤ 104 MB | Task 2 (ceiling test) |
| Carried-over 1 (frame budget) | Task 8 |
| Carried-over 2 (CLAUDE.md correction) | Task 9 |
