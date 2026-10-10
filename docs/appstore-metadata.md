# App Store metadata

The listing Slackwater submits, and the rules any edit to it is written against.

## Coverage, as every field below states it

Tides are worldwide. Currents are the United States and Canada. Any copy that describes the app as North American is wrong; any copy that implies currents are worldwide is also wrong, and it is the more expensive mistake.

| What ships               | Count | Where it comes from                                          |
| ------------------------ | ----- | ------------------------------------------------------------ |
| Bundled tide stations    | 4,782 | 3,262 NOAA, 1,520 TICON across 105 countries and territories |
| Bundled current stations | 2,534 | NOAA                                                         |
| Canadian tide stations   | 1,057 | CHS, fetched once per station, then offline for good         |
| Canadian current passes  | 22    | CHS, same fetch-once model                                   |
| Listed but blank         | 139   | Stations we cannot publish numbers for                       |

Refresh the counts before submitting, and any time coverage changes:

```
node -e '
const bySource = (arr) => arr.reduce((c, s) => (c[s.id.split("/")[0]] = (c[s.id.split("/")[0]] || 0) + 1, c), {});
const i = require("./Slackwater/Resources/station-index.json");
console.log("bundled tide stations", i.tides.length, bySource(i.tides));
console.log("bundled current stations", i.currents.length, bySource(i.currents));
console.log("Canadian tide stations", require("./Slackwater/Resources/chs-stations.json").length);
console.log("Canadian current passes", require("./Slackwater/Resources/chs-current-gates.json").length);
console.log("listed but blank", require("./Slackwater/Resources/unavailable-stations.json").length);
// country isnt in the committed data, but every TICON id embeds an ISO 3166-1 alpha-3 code
const ticonCountries = new Set(i.tides.filter((s) => s.id.startsWith("ticon/")).map((s) => s.id.match(/-([a-z]{3})-[a-z0-9_]+$/)[1]));
console.log("countries and territories", ticonCountries.size);
'
```

Round down in copy. "More than 4,700" survives a catalog change; "4,782" needs an App Store review to correct.

## Name & subtitle

| Field        | Value                           | Limit        |
| ------------ | ------------------------------- | ------------ |
| **Name**     | `Slackwater — Tides & Currents` | 30 (29 used) |
| **Subtitle** | `Offline worldwide predictions` | 30 (29 used) |

The name already indexes "tides" and "currents", so the subtitle spends all 30 characters on words the name does not have: the differentiator, the coverage, and a third indexable noun. Never name a region here — currents will outgrow one before the listing is next reviewed.

## Keywords (≤100 chars, name/subtitle words omitted)

```
chart,table,slack,ebb,flood,marine,kayak,paddle,fishing,sailing,noaa,chs,harbor,harbour,salish sea
```

(98 characters.)

The rules this set follows, for whoever edits it next:

- **Never repeat a word from the name or subtitle.** Apple indexes those fields and combines across them, so `chart` and `table` pair with "tides" and "currents" for free. `tide chart` would waste ten characters buying nothing.
- **Activity terms travel.** Kayak, paddle, fishing, sailing and marine are how a non-boater finds a tide app in any country.
- **Name the data sources.** People search `noaa` and `chs` directly, and both read as credibility in the listing.
- **Spell for both sides of the Atlantic where Apple does not stem.** `harbor` and `harbour` are separate terms, and worldwide coverage means most harbours are spelled the second way.
- **One regional anchor: `salish sea`.** Almost nobody targets it, it is the densest cluster of validated current gates, and it is the home audience. Drop it when currents ship outside North America and the characters are needed for a term that covers the new water — not before, and not to chase `tide chart`, which Garmin owns.

Deliberately out: `gulf islands`, `juan de fuca`, `puget sound`, `knot`, `boating` (low value; `boating` is implied by the category).

## Category

**Primary: Weather. Secondary: Navigation.**

Weather is where tide apps live — Tide Guide and Tides Near Me both sit there, so it is where tide-app browsers and chart rankings are. Navigation carries an implication the app disclaims on every screen ("not for navigation"), so it stays secondary: the discovery surface without a primary shelf that contradicts the disclaimer.

## Promotional text (170 chars max, editable without review)

> Tide and current predictions worldwide, offline on your phone. Works on the water, on the beach, in the anchorage — no bars and nothing to load. Free, no account.

(162 characters.)

This field sits directly above the description and is the one piece of copy that can change without a review — use it for anything time-sensitive. Keep it problem-first like the description rather than leading with a station count, or the two read as a spec sheet twice over.

## Description

**Angle: problem first.** The App Store truncates after roughly three lines before "…more", so those lines are all most people ever read. They carry the problem and the solution. Everything establishing _why the numbers are trustworthy_ — sources, validation, counts — sits near the end, where it reassures the people who scroll rather than gatekeeping the people who don't.

Three rules that are easy to break by accident:

- **Placement beats phrasing inside the first 200 characters.** "Offline" earns its spot in the second sentence because that is character 52, inside the collapsed view. A better sentence past the fold is worse than a plain one above it.
- **Currents are named as North American every time coverage is claimed.** The provenance block is the only place the limit appears, so it cannot be trimmed for length.
- **The last lines link the Terms of Use and Privacy Policy.** App Review 3.1.2 requires a Terms of Use link in the description for an app that sells a subscription, and rejects the submission without one. Slackwater uses Apple's standard EULA, so the link goes to Apple's page and the custom EULA field in App Store Connect stays empty. The purchase screen links the same two pages (`PremiumPurchaseControls.swift`).

Full text:

> Every tide app works fine at home. Slackwater works offline, where you need
> it — on the water, on the beach, in the anchorage — no bars and nothing to
> load. Thousands of stations worldwide, already on your phone.
>
> No spinner. No "no internet connection". No waiting on a server that isn't
> coming. You open it, and the answer is there.
>
> And it does the part most tide apps skip. Heights are the easy half. The
> harder question is the current: when does the pass go slack? How hard is it
> running at max? Can you get through before it turns?
>
> WORKS WHERE THERE IS NO SIGNAL
> The predictions are computed on your phone, not fetched. Down a dead-end
> road, out at the point, in an anchorage, or with the boat's electronics
> down — you get the same answer you would have got at the dock.
>
> CURRENTS, NOT JUST TIDES
> A curve for the whole day, with slack, max flood and max ebb marked. Drag
> your thumb across it to read any moment. Every current station shows the
> tide at its reference port on the same screen.
>
> A MAP THAT WORKS OFFLINE TOO
> Every station on a map. The coastline you have already looked at stays on
> your phone and draws again with zero bars.
>
> FREE, NO ACCOUNT, NO ADS
> The offline core is free and stays free.
>
> WHERE THE NUMBERS COME FROM
> Tides for more than 4,700 stations across a hundred countries are built in
> with nothing to download, each one from the national authority that
> publishes it and checked against that authority's own tide datums before it
> ships. Currents cover the United States and Canada: every NOAA current
> station, plus Canadian passes from the Salish Sea to Haida Gwaii and Cape
> Breton. Canadian stations build their own model from the Canadian
> Hydrographic Service's published predictions, then work offline for good. A
> few stations are listed but blank — where we cannot publish numbers we
> trust, we say so instead of guessing.
>
> Predictions are not observations — conditions vary with weather and river
> flow. Not for navigation.
>
> Terms of Use: https://www.apple.com/legal/internet-services/itunes/dev/stdeula/
>
> Privacy Policy: https://slackwater.xyz/privacy/

## Spanish (Mexico) and French (Canada)

App Store Connect localizations `es-MX` and `fr-CA`. A listing locale is independent of the app's string catalogs, so `es-MX` needs no `es-MX` translation of the app. ASO tools report that the US store indexes Spanish (Mexico) alongside English (US) and the Canadian store indexes French (Canada) alongside English (Canada); Apple does not document this. With no English (Canada) listing, the Canadian store shows English (US). Screenshots fall back to the English (US) set, and What's New, required in every localization of an update, can carry the English notes until they are translated.

The rules above hold, with three additions:

- **Every coverage claim names currents as the United States and Canada**, the promotional text included.
- **Keywords skip every word in the English (US) name, subtitle and keywords**, since both stores index these beside English. The one repeat is French `table`: Apple combines words across one localization's fields but does not document combining across localizations, so `table` stays to keep "table des marées" whole.
- **Spanish puts "Tabla de mareas" in the name.** "Mareas y corrientes" does not fit beside the brand in 30 characters, and "tabla de mareas" is the Spanish search for a tide app the way `tide chart` is the English one. Currents move to the subtitle.

### Spanish (Mexico)

| Field        | Value                          | Limit        |
| ------------ | ------------------------------ | ------------ |
| **Name**     | `Slackwater — Tabla de mareas` | 30 (28 used) |
| **Subtitle** | `Corrientes sin conexión`      | 30 (23 used) |

Keywords:

```
pesca,vela,velero,lancha,barco,buceo,remo,marea,alta,baja,puerto,playa,internet,estoa,náutica
```

(94 bytes.) `alta` and `baja` pair with `marea` for the everyday "marea alta" and "marea baja"; `internet` pairs with the subtitle's "sin".

Promotional text:

> Mareas de todo el mundo y corrientes de EE. UU. y Canadá, sin conexión en tu celular. En el agua, en la playa, en el fondeadero, sin señal. Gratis y sin registro.

(162 characters.)

Description:

> Todas las apps de mareas funcionan bien en casa. Slackwater funciona sin conexión, donde lo necesitas: en el agua, en la playa, en el fondeadero, sin señal y sin nada que cargar. Miles de estaciones en todo el mundo, ya en tu celular.
>
> Nada de pantallas de carga. Nada de "No hay conexión a internet". Nada de esperar a un servidor que no va a responder. Abres la app y la respuesta ya está ahí.
>
> Y hace la parte que casi todas las apps de mareas se saltan. Las alturas son la mitad fácil. La pregunta difícil es la corriente: ¿a qué hora llega la estoa al paso? ¿Qué tan fuerte corre en su máximo? ¿Alcanzas a cruzar antes de que cambie?
>
> FUNCIONA DONDE NO HAY SEÑAL
> Las predicciones se calculan en tu celular, no se descargan. Al final de un camino de terracería, en la punta, en un fondeadero o sin la electrónica del barco, obtienes la misma respuesta que en el muelle.
>
> CORRIENTES, NO SOLO MAREAS
> Una curva para todo el día, con la estoa, el máximo flujo y el máximo reflujo marcados. Desliza el dedo sobre ella para leer cualquier momento. Cada estación de corriente muestra en la misma pantalla la marea de su puerto de referencia.
>
> UN MAPA QUE TAMBIÉN FUNCIONA SIN CONEXIÓN
> Todas las estaciones en un mapa. La costa que ya consultaste se queda en tu celular y se vuelve a dibujar sin señal.
>
> GRATIS, SIN REGISTRO, SIN ANUNCIOS
> Lo esencial funciona sin conexión, es gratis y lo seguirá siendo.
>
> DE DÓNDE VIENEN LOS DATOS
> Las mareas de más de 4,700 estaciones en un centenar de países ya vienen en la app, sin nada que descargar. Cada una proviene de la autoridad nacional que la publica y se verifica contra los niveles de referencia de esa misma autoridad antes de publicarse. Las corrientes cubren Estados Unidos y Canadá: todas las estaciones de corriente de NOAA, más los pasos canadienses desde el mar Salish hasta Haida Gwaii y la isla del Cabo Bretón. Cada estación canadiense arma su propio modelo a partir de las predicciones que publica el Servicio Hidrográfico de Canadá y desde ahí funciona sin conexión para siempre. Algunas estaciones aparecen en la lista pero en blanco: donde no podemos publicar números confiables, lo decimos en vez de adivinar.
>
> Las predicciones no son observaciones: las condiciones cambian con el clima y el caudal de los ríos. No usar para la navegación.
>
> Términos de uso: https://www.apple.com/legal/internet-services/itunes/dev/stdeula/
>
> Aviso de privacidad: https://slackwater.xyz/privacy/

### French (Canada)

| Field        | Value                            | Limit        |
| ------------ | -------------------------------- | ------------ |
| **Name**     | `Slackwater — Marées & courants` | 30 (30 used) |
| **Subtitle** | `Prévisions hors ligne, partout` | 30 (30 used) |

Keywords:

```
table,marée,haute,basse,pêche,voile,voilier,bateau,pagaie,plongée,étale,plaisance,fleuve,shc
```

(96 bytes.) `shc` is the Service hydrographique du Canada, the French name for CHS. `fleuve` is the regional anchor, as `salish sea` is in English: Quebec calls the St. Lawrence "le fleuve", and its tide stations are the francophone home water.

Promotional text:

> Marées du monde entier et courants des États-Unis et du Canada, hors ligne sur votre téléphone. Sur l’eau, à la plage, au mouillage, sans réseau. Gratuit, sans compte.

(167 characters.)

Description:

> Toutes les applis de marées fonctionnent bien à la maison. Slackwater fonctionne hors ligne, là où vous en avez besoin : sur l’eau, sur la plage, au mouillage, sans réseau et sans rien à charger. Des milliers de stations partout dans le monde, déjà sur votre téléphone.
>
> Pas de roue qui tourne. Pas de message « Aucune connexion Internet ». Pas d’attente pour un serveur qui ne répondra pas. Vous ouvrez l’appli, et la réponse est là.
>
> Et elle fait ce que la plupart des applis de marées négligent. Les hauteurs, c’est la moitié facile. La vraie question, c’est le courant : à quelle heure la passe sera-t-elle étale ? Quelle force atteint-il au maximum ? Aurez-vous le temps de passer avant la renverse ?
>
> FONCTIONNE LÀ OÙ IL N’Y A PAS DE RÉSEAU
> Les prévisions sont calculées sur votre téléphone, pas téléchargées. Au bout d’un chemin de terre, sur la pointe, au mouillage ou sans l’électronique du bord, vous obtenez la même réponse qu’au quai.
>
> DES COURANTS, PAS SEULEMENT DES MARÉES
> Une courbe pour toute la journée, avec l’étale, le flot max. et le jusant max. indiqués. Glissez le doigt dessus pour lire n’importe quel moment. Chaque station de courant affiche, sur le même écran, la marée à son port de référence.
>
> UNE CARTE QUI FONCTIONNE AUSSI HORS LIGNE
> Toutes les stations sur une carte. La côte que vous avez déjà consultée reste sur votre téléphone et s’affiche de nouveau sans réseau.
>
> GRATUIT, SANS COMPTE, SANS PUB
> L’essentiel fonctionne hors ligne, est gratuit et le restera.
>
> D’OÙ VIENNENT LES DONNÉES
> Les marées de plus de 4 700 stations dans une centaine de pays sont intégrées, sans rien à télécharger. Chacune provient de l’autorité nationale qui la publie et est vérifiée par rapport aux niveaux de référence de cette même autorité avant sa mise en ligne. Les courants couvrent les États-Unis et le Canada : toutes les stations de courant de la NOAA, plus des passes canadiennes de la mer des Salish à Haida Gwaii et au Cap-Breton. Chaque station canadienne bâtit son propre modèle à partir des prévisions publiées par le Service hydrographique du Canada, puis fonctionne hors ligne pour de bon. Quelques stations sont listées mais vides : là où nous ne pouvons pas publier de chiffres fiables, nous le disons plutôt que de deviner.
>
> Les prévisions ne sont pas des observations : les conditions varient selon la météo et le débit des rivières. Non destiné à la navigation.
>
> Conditions d’utilisation : https://www.apple.com/legal/internet-services/itunes/dev/stdeula/
>
> Politique de confidentialité : https://slackwater.xyz/privacy/

## What's New (4,000 chars max)

This field is the version's release notes without the beta testing instructions, so the two can never disagree:

```sh
sed -e '1,2d' -e '/^Worth testing:/,$d' docs/release-notes/1.14.0.md
```

[`release-notes/README.md`](release-notes/README.md) documents the format. 1.14.0 introduces the app rather than listing changes, because a first version has nothing to compare itself to; every version after it leads with what changed.

## Privacy (App Store Connect "App Privacy" answers)

- **Data collection: none.** No analytics, no tracking, no accounts, no third-party SDKs that phone home. Answer "Data Not Collected" throughout.
- **Location** is requested (When In Use, optional) to rank nearby stations. It is used on-device only and never transmitted, so under Apple's definitions it is not "collection" and creates no privacy-label entry. Declining leaves the app fully functional.
- **Tracking (ATT): No.**
- **Network requests the app makes**, none carrying identity beyond IP:
  - `api-iwls.dfo-mpo.gc.ca` — Canadian station predictions, fetched once per station for on-device fitting, under DFO's own terms.
  - `tiles.openfreemap.org` — basemap style and tiles when the map is open and online, cached on the device afterwards.
- **In-app purchases** settle through StoreKit. Apple handles the transaction; no personal data reaches us, and the answers above do not change when Premium goes on sale.

Re-answer this section whenever a new host appears in the app. `grep -rhoE "https://[a-z0-9.-]+" --include="*.swift" Slackwater/` lists every one.

- **Privacy manifests.** `Slackwater/PrivacyInfo.xcprivacy` and `SlackwaterWidgets/PrivacyInfo.xcprivacy` declare no tracking, no collected data, and the required-reason APIs each target uses: `UserDefaults` (`CA92.1`, and `1C8F.1` for the App Group) and file modification dates (`C617.1`). Both targets compile `ChsCurrentGate.swift`, which reads a file's modification date, so the two files are identical. Re-check them when a target starts using another [required-reason API](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api); App Store Connect reports a gap by email (ITMS-91053), not in the upload log.

## Accessibility Nutrition Labels

Claim only what the app does today. These labels appear on the product page and a wrong one is a support burden and a trust cost, not a marketing win — an omitted label costs nothing but the label itself.

Verify each answer against Apple's current published criteria before submitting; the summary below is what the code supports, not a reading of the criteria.

| Label                        | Answer today   | Evidence                                                                                                                                                                  |
| ---------------------------- | -------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Dark Interface               | Yes            | The app is dark-only (`UIUserInterfaceStyle: Dark` in `project.yml`).                                                                                                     |
| Captions, Audio Descriptions | Not applicable | No audio or video.                                                                                                                                                        |
| Larger Text                  | Not yet        | The lead, its pad and the pills scale, and chart labels stay fixed by contract (`docs/scrubber.md` § 5). The platform audit reports partial support on station names, distances, sun times and the `MonoLabel` eyebrows, and clipping on "MY LOCATION" and the moon tile; card-layout work, tracked in #500. |
| VoiceOver                    | Yes            | Labels, traits and values cover cards, lists, headers and downloads; the scrubber is one adjustable control with a dated spoken value and next/previous-event actions.    |
| Reduced Motion               | Yes            | Honoured for the sky's stars, every scrubber landing and the pill settle fade (`TimelineTests` tripwires).                                                                 |
| Sufficient Contrast          | Not yet        | `AccessibilityAuditTests` measures rendered contrast on the list and both details; secondary text clears 4.5:1 on the dark grounds. Caption text over the sky (the header's region line, the lead's time) cannot reach 4.5:1 on the twilight-to-day band with any single ink (`ColourAndFormTests.testLeadInkClearsLargeTextContrastOnEverySky`); a design change, tracked in #499. |
| Differentiate Without Color  | Yes            | Every state has a carrier besides its colour — distinct high/low glyphs, a set arrow with a compass word, slack named in words, speeds printed at maxima — and `ColourAndFormTests.testEveryStateHasANonColourCarrier` pins each one (`docs/scrubber.md` § 25). |
| Voice Control                | Yes            | Every control has a name: the platform audit's element-description check passes on the list and both details (`AccessibilityAuditTests`).                                 |

Each "not yet" row names the issue that closes it; [`scrubber.md`](scrubber.md) § 18 lists the scrubber's own remaining deviations. `AccessibilityAuditTests` runs the platform audit over the station list and both detail kinds on every CI run, so a regression in a claimed row fails the build. Re-check this table whenever one of those issues lands — the labels are editable without a full review, so shipping honest labels now and upgrading them later costs nothing.

## Review notes (for the App Review box)

> All predictions are computed on-device from public harmonic data. The app is
> explicitly marked "not for navigation" in-app (every detail footer, the map,
> and Settings). Location permission is optional and used only to sort the
> station list; deny it and search/browse works identically. No account needed.

## Before submission

- [ ] Screenshots uploaded. Apple takes 1–10 per device size. The required iPhone slot is "iPhone with Dynamic Island (medium display)", which accepts only 1206×2622 or 1179×2556; the 6.9" set (1320×2868) fills the optional large-display slot and is not scaled into the required one. A universal app needs the 6.3" iPhone and 13" iPad (2064×2752) sets, and the 6.9" set is worth adding. `SlackwaterUITests/AppStoreScreenshots.swift` shoots each from a pinned clock, location fix and favorites, so a re-run reproduces them:

  ```
  WALK=AppStoreScreenshots SHOT_DIR=/tmp/slackwater-appstore/iphone-6.3 \
    SLACKWATER_SIM='iPhone 18 Pro' ./scripts/screenshots.sh
  WALK=AppStoreScreenshots SHOT_DIR=/tmp/slackwater-appstore/iphone-6.9 ./scripts/screenshots.sh
  WALK=AppStoreScreenshots SHOT_DIR=/tmp/slackwater-appstore/ipad-13 \
    SLACKWATER_SIM='iPad Pro 13-inch (M5)' ./scripts/screenshots.sh
  ```

  Five frames, numbered in upload order: currents on slack, a mixed tide mid-rise, the scrubber parked at night, the nearby list with its three groups, and the map. None may show Premium or imply navigation use. The iPhone 18 Pro shoots 1206×2622; the script's default, the iPhone 18 Pro Max, shoots 1320×2868.

  The watch app makes an Apple Watch set required too. App Store Connect takes one watch size for every localization and scales it down, so shoot the largest, Ultra (422×514), from the same pinned clock, fix and favorites as the phone:

  ```
  WALK=WatchAppStoreScreenshots SHOT_DIR=/tmp/slackwater-appstore/watch ./scripts/screenshots.sh
  ```

  Four frames: the list where the wearer is, that place's tide, the crown scrubbed off now, and Deception Pass's current.

  The iPhone Duo set is optional and takes either screen's size: the cover (1398×2034) or the inner screen (2853×2007). The inner screen is the one worth showing, unfolded in landscape with the sidebar beside the detail. Unfold the simulator in Xcode's device view first and leave it open; the `scripts/screenshots.sh` header has both commands.
- [ ] Mac screenshots uploaded if distributing on Mac. Apple accepts 1280×800, 1440×900, 2560×1600, or 2880×1800 ([specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/)). Run the installed Mac app, then use the guided capture session:

  ```sh
  ./scripts/mac-screenshots.sh --set
  ./scripts/mac-screenshots.sh --verify
  ```

  The script prompts you to choose each screen, resizes the normal Mac window before every capture, and saves five numbered PNGs in `/tmp/slackwater-appstore/mac`. It captures the actual running app, including its Mac sidebar and title bar. It uses live app state: the clock, location, favorites, selected dates, and map camera are not seeded. On Mac, choose a local place and scroll its detail to Nearby for frame four, keeping Favorites visible in the sidebar. Choose a nighttime schedule row or scrub the graph for frame three. Double-click the map to zoom, then click empty water to clear its preview card for frame five. Wait for reading updates and map tiles before confirming each prompt. Inspect the resulting images before uploading in filename order; `app-version.txt` records the captured version and build.

  `--size` only sizes the window; `--capture 02-tide` captures the current screen without prompting. `SHOT_DIR` overrides the output directory. The default sizes the window to 1280×800 points and exports 2560×1600 pixels on Retina. `MAC_PIXELS=1280x800` supports a non-Retina display; `MAC_PIXELS=1440x900` or `2880x1800` uses a 1440×900 point window. The main display must have room for the entire window. The script refuses full screen, ambiguous windows, wrong aspect ratios, and upscaling. Exports are opaque sRGB PNGs, with rounded window corners flattened onto a dark background and no window shadow.

  macOS requires Accessibility and Screen Recording access for the terminal or app hosting the script. Enable these under System Settings → Privacy & Security if denied. Run exactly one Slackwater app; `MAC_BUNDLE_ID` can select a particular running build when both the old `org.openwaters.slackwater` and current `io.openwaters.slackwater` identities are installed. Xcode command-line tools supply the Swift compiler; no additional packages or simulator are needed. Generated screenshots and helper binaries stay outside tracked source.

  Focused export checks cover alpha removal, native-size and downsampled output, invalid dimensions, and rejection of distorted or upscaled images:

  ```sh
  xcrun swiftc -D SCREENSHOT_TEST scripts/mac-screenshot.swift scripts/mac-screenshot-tests.swift \
    -o /tmp/slackwater-mac-screenshot-checks
  /tmp/slackwater-mac-screenshot-checks
  ```
- [ ] Station counts re-derived and rounded down, in every localization.
- [ ] A native speaker has read the Spanish (Mexico) and French (Canada) copy.
- [ ] Support URL `https://slackwater.xyz/support/`. Marketing URL `https://slackwater.xyz`.
- [ ] Premium listed as an in-app purchase if it is on sale by submission; the description's "the offline core is free and stays free" is written to stay true either way.
- [ ] Description ends with the Terms of Use and Privacy Policy links, and the Privacy Policy URL field is `https://slackwater.xyz/privacy/`.
- [ ] Accessibility Nutrition Labels answered against Apple's current criteria, claiming only the rows that are yes.
