# PROJEKT-METODIK: HoS-rapport

## Syfte

Hälso- och sjukvårdens (HoS) uppföljningsrapport för Region Halland. En React-dashboard som visualiserar nyckeltal (KPI:er) med statistisk anomalidetektering (conformal prediction) i realtid. Verktyget ger beslutsfattare snabb överblick av läget och möjlighet att generera strukturerade rapporter.

## Projekttyp

**Typ B: React/Vite-app** — R sköter datapipeline, React/TypeScript/D3 sköter frontend.

## R-pipeline — Struktur och moduler

### Mappstruktur

```
R/
├── pipeline.R                    # Orchestrator — kör allt i ordning
├── bearbeta.R                   # Orkestrerar: aggregering + signaler + monterar vyer via bygg-sektion.R
├── exportera.R                  # Validerar kontrakt + skriver split-JSON (manifest + en fil per vy-sektion) → app/public/data/
├── hamta/
│   └── demo-data.R              # Syntetisk demodata (ersätts med API i produktion)
├── teman/                       # En mapp per sektion — här läggs nya sektioner till
│   ├── register.R               # Samlar alla configs → kpi_meta, dept_config
│   ├── primarvard/
│   │   └── config.R             # KPI-definitioner: pv_besok, digital_kontakt, telefon_svar
│   ├── akutflode/
│   │   └── config.R             # KPI-definitioner: beläggning, akutbesök, väntetid, ambulans
│   ├── slutenvard/
│   │   └── config.R             # KPI-definitioner: inläggningar, utskrivningsklara
│   ├── personal/
│   │   └── config.R             # KPI-definitioner: sjukfrånvaro, övertid, inhyrd
│   ├── patientenkat/            # (urkopplad — ersatt av kolada/)
│   │   ├── config.R             # NPE-dimensioner (helhetsintryck, respekt, etc.)
│   │   └── bearbeta.R           # Läser Excel, beräknar ranking-signaler
│   ├── kolada/
│   │   ├── config.R             # Koladas HoS-rapport: sektioner (Koladas indelning), riktning per KPI
│   │   └── bearbeta.R           # Läser data/kolada-hos.rds, kvartilranking med Halland i fokus
│   ├── folkhalsa/
│   │   ├── config.R             # FoHM: delar = folkhälsopolitikens 8 målområden + hälsoutfall
│   │   └── bearbeta.R           # Wrapper över gemensam/ranking-tema.R
│   ├── befolkning/
│   │   ├── config.R             # SCB/FK/Kolada: demografi, behovsindex, ohälsa
│   │   └── bearbeta.R           # Wrapper över gemensam/ranking-tema.R
│   └── ekonomi/
│       ├── config.R             # Kolada: nettokostnad, behovsjusterad avvikelse, DRG
│       └── bearbeta.R           # Wrapper över gemensam/ranking-tema.R
├── gemensam/                    # Delade moduler (inget beroende sinsemellan)
│   ├── helgdagar.R              # Svensk kalender (röda dagar, klämdagar, skollov)
│   ├── signal-modell.R          # GLM + conformal: kor_kpi_signal (produktion), kor_signal (diagnostik)
│   ├── aggregering.R            # aggregera_period, periodfiltrering, referensberäkning
│   ├── formatering.R            # Etiketter (V13, mar 26), fmt_varde, lag_specs
│   ├── analystext.R             # analystext_kpi, _sektion, _global
│   ├── bygg-sektion.R          # Generisk byggare: bygg_vy + generera_undernivaer (via ctx, ingen closure)
│   └── kontrakt.R               # validera_kontrakt — hård grind R→JSON före export
├── test-signal.R                # Fristående signaltest
└── granskningsrapport.R         # Pedagogisk HTML-rapport
```

### Ny sektion — steg för steg

1. Skapa `R/teman/{namn}/config.R` med id, namn, kpier (tibble), avdelningar (lista)
2. Lägg till `source("R/teman/{namn}/config.R")` i `R/teman/register.R`
3. Lägg till temat i `dagliga_teman` (eller som specialfall likt patientenkäten)
4. Lägg in området i taxonomin: `app/src/taxonomy.ts` (kategori + beskrivning;
   områden utan data ligger kvar som `planerad: true` tills pipelinen levererar)
5. Klar — bearbeta.R plockar upp nya KPI:er automatiskt via kpi_meta

### Områdesindelning (taxonomi)

Rapportens kategorier och områden (aktiva + planerade) definieras i
`app/src/taxonomy.ts` — startsidans kategoriboxar, rapportens kategorietiketter
och TOC-grupperingen läser alla därifrån. Researchunderlag och motivering:
`docs/omradesindelning.md`.

### Pipeline-flöde

```
source("R/pipeline.R")
  │
  ├── R/hamta/demo-data.R       → data/radata-hos.rds, data/radata-dept.rds
  ├── R/bearbeta.R              → data/bearbetad-hos.rds
  └── R/exportera.R             → app/public/data/index.json + {vy}-{sektion}.json
```

### Metadata — en enda källa

`R/teman/register.R` bygger `kpi_meta` och `dept_config` från tema-configs.
Alla filer som behöver KPI-metadata sourcar `register.R` — ingen duplicering.

## Datapipeline

R-skripten i `R/` hämtar data, bearbetar, kör conformal prediction och exporterar till JSON.
Frontend **lazy-laddar data per vy** (`app/src/data/load.ts`): ett manifest (`app/public/data/index.json` med vy-metadata + sektionslista) och en fil per `{vy}-{sektion}.json`. Endast den aktiva vyns sektioner hämtas (parallellt, cachat) — t.ex. Dag-vyn ≈ 68 KB i stället för 3 MB; tunga årsvyn laddas först vid klick. Datan bakas **inte** in i JS-bunten (~320 KB i stället för ~3,4 MB). Delningsgränsen är vald där UI:t faktiskt väntar med att ladda (vy-byte).

### Tidsupplösningar (vyer)

| Vy | Id | Aggregerad tidsserie | Dagsnivå (toggle) | Etikett-format |
|----|-----|---------------------|-------------------|----------------|
| Dag | `dag` | 14 dagar | — | `18 mar` |
| Vecka | `vecka` | Alla kompletta veckor (~274) | 7 dagar (senaste hela vecka) | `V13` |
| Månad | `manad` | Alla kompletta månader (~63) | ~30 dagar (senaste hela månad) | `mar 26` |
| Kvartal | `kvartal` | Alla kompletta kvartal (~21) | ~90 dagar (senaste hela kvartal) | `Q1 26` |
| År | `ar` | Alla kompletta år (~5) | ~365 dagar (senaste hela år) | `2025` |

### Periodhantering

- **Bara kompletta perioder** visas i aggregerade vyer. Inkompletta perioder exkluderas.
- **Dagsnivå** (dag-toggle) visar alltid senaste *kompletta* period — inte den pågående.
- **Referens**: Varje KPI har `referens` (samma period föregående år) med värde och förändring.
- **Dagsammanfattning** (`dagar_sammanfattning`): antal dagar i fas vs avvikelse per KPI per vy.
- **Dag-vyn** (standalone): 14 dagar + `referens_serie` (samma 14 dagar föregående år, visas som streckad linje).

### Datastruktur (per KPI)

Fältnamnen nedan är verifierade mot `data/hos-data.json` och `app/src/types.ts`. Varje tidsseriepunkt bär **två** conformal-band: ett inre 80 %-band (`*_80`) och ett yttre 95 %-band.

```json
{
  "id": "belaggning",
  "namn": "Beläggningsgrad",
  "enhet": "procent",
  "inverterad": true,
  "senaste": 96.3,
  "forandring": -2.3,
  "forandringar": [{ "etikett": "vecka", "varde": -2.3 }, { "etikett": "månad", "varde": 1.1 }],
  "status": "gron",
  "analystext": "Beläggningsgraden ligger på 96,3 procent ...",
  "beskrivning": "Andel disponibla vårdplatser som är belagda ...",
  "tidsserie": [{ "period": "2026-03-31", "etikett": "31 mar", "varde": 96.3, "yhat": 96.5,
                  "yhat_lower_80": 94.1, "yhat_upper_80": 98.9,
                  "yhat_lower": 92.4, "yhat_upper": 100.6, "signal": "gron" }],
  "dagar": [{ "period": "2026-03-23", "etikett": "23 mar", "varde": 94.7, "...": "samma fält som tidsserie" }],
  "dagar_sammanfattning": { "n_dagar": 7, "n_i_fas": 5, "n_bevaka": 1, "n_avvikelse": 1 },
  "referens": { "period": "2025-03-24", "etikett": "V13", "varde": 95.9, "forandring": -2.3 },
  "referens_serie": [{ "period": "2025-03-18", "etikett": "18 mar", "varde": 95.1, "...": "dag-vy: samma 14 dagar föreg. år" }],
  "kontext_serier": [{ "id": "vastra_gotaland", "namn": "Västra Götaland", "tidsserie": [...] }],
  "riket_serie": [{ "period": "2024-01-01", "etikett": "2024", "varde": 83.5 }],
  "undernivaer": [{ "id": "belaggning-halmstad", "namn": "Halmstad", "senaste": 88.5, "forandring": 1.2, "status": "gron", "tidsserie": [...], "dagar": [...] }]
}
```

- `yhat_lower_80` / `yhat_upper_80`: **inre** 80 %-band (målläge / "i fas").
- `yhat_lower` / `yhat_upper`: **yttre** 95 %-band (gräns mot avvikelse).
- `signal`: `"gron"` (inom 80 %), `"gul"` (mellan 80–95 %), `"rod"` (utanför 95 %).
- `kontext_serier` / `riket_serie` finns bara för jämförelseindikatorer (Patientenkäten).

### VyData-metadata

```json
{
  "vy": "vecka",
  "etikett": "Veckoöversikt",
  "period": "vecka 13, 2026",
  "dagar_period": { "start": "2026-03-23", "slut": "2026-03-29", "etikett": "V13" },
  "nasta_period": { "datum": "2026-04-05", "etikett": "5 apr 2026" }
}
```

## Frontend-arkitektur

### Aggregerat / Dag toggle

En toggle-switch **Aggregerat | Dag** finns på tre platser:

1. **Dashboard** (App.tsx) — under vy-väljaren, visas bara för vecka/månad/kvartal/år
2. **ChartModal** (popup-graf) — i toolbaren
3. **ReportView** (rapport) — per indikator, ovanför FacetedChart

Vid dag-toggle:
- KPI-kort visar `kpi.dagar` istället för `kpi.tidsserie`
- Underavdelningar byter också till `sub.dagar`
- Graferna anpassas automatiskt (tunnare linjer, inga individuella punkter vid >30 datapunkter)

### KPI-kort (KpiCard)

Kortet har en fast struktur: signalband, titel, storsiffra, tre inforader och minigraf. Inforadernas innehåll varierar beroende på indikatortyp.

**Gemensam struktur (alla varianter):**
- **Signalband** (3px topp) — färg baserat på conformal signal
- **Titel** med hover-tooltip (indikatorns definition)
- **Hero-värde** (28px, bold mono)
- **Tre inforader** — se varianter nedan
- **MiniChart** (90px) — D3-graf med prediktionsband, adaptiv linjestyrka
- **Ingen information under grafen**
- **Avdelningar** — expanderbar grid, klick öppnar ChartModal

#### Variant 1: Standard-KPI (dygnsdata)

Indikatorer med dygnsdata och conformal prediction (beläggning, väntetid, akutbesök etc.).

| Rad | Label | Innehåll |
|-----|-------|----------|
| 1 | Förväntat läge | yhat + 95%-intervall + signalchip |
| 2 | Målläge | yhat + 80%-intervall + signalchip |
| 3 | Förändring | vs samma period föregående år, färgkodad riktning |

**Förväntat läge** är det statistiska måttet — modellens prediktion med konfidensintervall. Det behöver inte nödvändigtvis vara samma som målläge. Förväntat läge svarar på "vad förutspår modellen?", målläge svarar på "var vill vi vara?". I dagsläget härleds båda från conformal prediction (95%- resp 80%-bandet), men målläge kan framöver sättas till verksamhetens egna riktvärden oberoende av den statistiska modellen.

#### Variant 2: Jämförelseindikatorer (Patientenkäten m.fl.)

Årsindikatorer utan dygnsdata, med jämförelser mot andra regioner (`kontext_serier`). Visas bara i årsvyn.

| Rad | Label | Innehåll |
|-----|-------|----------|
| 1 | Ranking | Plats X av Y, med signalchip |
| 2 | Målläge | Signalchip (baserat på ranking: topp 3 = grön, 4–7 = gul, 8+ = röd) |
| 3 | Förändring | vs föregående år, färgkodad riktning |

Ranking beräknas i frontend från `kontext_serier` (alla andra regioner). MiniChart visar Hallands tidsserie med kontextlinjer (gråa, alla regioner) och rikssnitt (streckad).

#### Variant 3: Dagvy (dag-toggle aktiv)

Visas när användaren slår på dag-toggle i vecka/månad/kvartal/år.

| Rad | Label | Innehåll |
|-----|-------|----------|
| 1 | Historiskt läge | X/Y i fas (dagar inom 80%-bandet) |
| 2 | Målläge | X/Y dagar (dagar inom 95%-bandet, dvs ej avvikelse) |
| 3 | Förändring | – (ej applicerbart) |

Dag-vyn (standalone) visar referenslinje från föregående år (streckad grå) med y-domän som inkluderar referensvärden.

### Särskilda årsindikatorer

Vissa indikatorer har bara årsdata och saknar dygnsunderlag. Sedan 2026-06 är det **Koladas Hälso- och sjukvårdsrapport** (KPI-grupp `G2KPI138906`, 76 indikatorer) som utgör helårsdelen — den ersatte den tidigare Patientenkät-sektionen (`R/teman/patientenkat/` finns kvar urkopplad). Dessa indikatorer:

- Finns bara i **årsvyn** (`ar`), som **EN sektion** `skr` ("Hälso- och
  sjukvårdsrapporten (SKR)" — ett kort på huvudsidan) med **sex tematiska
  delar** via sektionsfältet `delar` (samma indelning som SKR-rapporten i
  Jämföraren): Patienters och befolkningens syn på vården, Tillgänglighet och
  väntetider, Säker vård, Kunskapsbaserad vård och måluppfyllelse,
  Sjukdomsförekomst och resultat, Kostnader och produktivitet
- Varje del har **egen översiktsanalys** (`delar[].analys`); frontend renderar
  delrubrik (`.del-plate`) + ett integrerat översiktskort (räknare: antal/inom
  förväntat/utanför + AI-analys + delens egen signalöversikt) + indikatorkort
  per del, och nästlar TOC:n (`delSektioner()` i `ReportView.tsx`). Den stora
  heatmapen överst i rapporten utelämnar sektioner med delar.
- Indikatornamn förkortas för visning (enhets-/årssuffix trimmas i
  `kort_namn()`, manuella undantag i config `kortnamn`); fullständig
  Kolada-titel + definition ligger i `beskrivning` (infoknappen)
- Jämförarens grupperingsträd är **inte** åtkomligt via öppna API:t (403) —
  tilldelningen KPI → del underhålls manuellt i `R/teman/kolada/config.R`;
  oklassade KPI:er hamnar i en automatisk "Övrigt"-del i stället för att tyst
  försvinna, och kontraktet validerar att `delar[].kpi_ids` refererar
  befintliga KPI:er
- Har **ingen** conformal prediction — signalen baseras på Hallands ranking
  bland regionerna per år: **i fas = topp 3**, bevaka = plats 4–7, avvikelse =
  plats 8 eller lägre (trösklar i config `ranking$grans_gron`/`grans_gul`)
- Riktning (högre/lägre är bättre, eller neutral) saknas i Kolada-API:t och
  underhålls manuellt i `R/teman/kolada/config.R` (`riktning_lag`, `riktning_neutral`);
  neutrala volymmått färgsätts inte (alltid grön + förklarande analystext)
- Har `kontext_serier` med övriga 20 regioners tidsserier (gråa linjer) och
  `riket_serie` med rikssnittet (streckad linje); tidsserier från 2016 (`min_ar`)
- Datakälla: `data/kolada-hos.rds`, hämtas med `R/hamta/kolada-hos.R`
  (rKolada 0.3.1 mot Kolada API v3 — v2-API:t är nedstängt)

### Grafarkitektur — charts/

All D3-ritlogik ligger i `app/src/charts/` som rena funktioner utan React-beroende. Komponenterna i `components/` är tunna wrappers (ResizeObserver + ref → anropa chart-funktion → returnera cleanup).

```
app/src/charts/
├── types.ts          # Pt, BandPt, TidsserieSeries, TidsserieOpts, Margins
├── constants.ts      # SIGNAL_COLORS, SIGNAL_LABELS, FONT, FONT_MONO, DEPT_COLORS
├── tidsserie.ts      # tidsserie(container, series, opts) — gemensam D3-ritfunktion
└── sparkline.ts      # computeSparkline(data, height) — ren geometri (ingen D3)
```

**tidsserie()** är den centrala ritfunktionen. Den ritar linje, prediktionsband (95%/80%), gridlines, kontextlinjer, riket-linje, referenslinje, crosshair + tooltip. Beteendet styrs via `TidsserieOpts`:

| Flagga | Effekt | Används av |
|--------|--------|------------|
| `compact: true` | Mindre typsnitt, tunnare linjer, 3 y-ticks | MiniChart |
| `showEndLabels: true` | Slutetiketter med anti-collision | ChartModal |
| `showBrackets: true` | Bracket-stil på x-axeln | FacetedChart |
| `showTitle: true` | Panelrubrik i SVG | FacetedChart (grid) |
| `tooltipAccentBorder: true` | Tooltip med signalfärgad vänsterkant | MiniChart |
| `denseThreshold: N` | Tröskel för adaptiv stil (tunna linjer, inga prickar) | Alla |

**parseTidsserie()** och **parseSimpleSerie()** konverterar från `TidsseriePoint[]` till D3-redo `Pt[]`/`BandPt[]`.

**computeSparkline()** returnerar ren geometri (polyline-sträng, polygon-strängar, punktkoordinater) utan DOM-åtkomst — React-komponenten hanterar rendering och hover.

### Grafkomponenter (wrappers)

| Komponent | Fil | Chart-funktion | Beskrivning |
|-----------|-----|---------------|-------------|
| **MiniChart** | `KpiCard.tsx` | `tidsserie()` | 90px inline-graf. `compact: true`, `denseThreshold: 60`. |
| **ChartModal** | `ChartModal.tsx` | `tidsserie()` | Popup-graf. `showEndLabels: true`, `margins.r: 100`. |
| **FacetedChart** | `FacetedChart.tsx` | `tidsserie()` | 2x2 grid. `showBrackets: true`, `showTitle: true` i grid-läge. |
| **Sparkline** | `Sparkline.tsx` | `computeSparkline()` | SVG sparkline med React-hover/tooltip. |
| **TufteStrip** | `TufteStrip.tsx` | (via Sparkline) | Grid med sparkline-paneler. |

### ChartModal design

- **Titel**: KPI-namn + avdelning om tillämpligt (t.ex. "Beläggningsgrad, Halmstad")
- **Undertitel**: Vy + period + Region Halland
- **Slutetiketter** vid linjeslut: "Faktiskt", "Förväntat", "Föreg. år" — med `resolveOverlap` anti-collision (iterativ relaxering, H→V→H connectors)
- **Ingen text under grafen** — analystext och legend borttagna
- **Hover**: crosshair + tooltip med faktiskt/förväntat per tidpunkt

### FacetedChart design

- **2x2 grid** med individuella y-axlar per panel
- **Panelrubrik**: serienamn i färg (inget värde)
- **Vy-etiketter** på x-axeln: använder `etikett`-fältet från data (V1, jan 21, Q1 21 etc.)
- **Adaptiv**: inga individuella punkter vid >30 datapunkter, tunnare linje
- **Aggregerat/Dag toggle** per indikator i rapporten

### Vyer och rapporter

| Komponent | Fil | Beskrivning |
|-----------|-----|-------------|
| **App** | `App.tsx` | Huvudvy med vy-väljare + Aggregerat/Dag toggle + stats-bar |
| **Section** | `Section.tsx` | Sektionsblock med KpiCard-grid + "Generera delrapport" |
| **ReportView** | `ReportView.tsx` | Fullskärmsrapport. Används för BÅDE huvudrapport och delrapport (med `sectionId`-prop). |

### Huvudrapport vs Delrapport

Samma komponent (`ReportView`) — delrapport filtreras med `sectionId`:

- **Huvudrapport**: alla sektioner, innehållsförteckning, global analys, titel "Hälso- och sjukvården"
- **Delrapport**: en sektion, titel = sektionsnamn, ingen TOC, ingen global analys, inget "Kapitel X"

Redigeringar delas via samma `localStorage`-nycklar (`${vy}:${targetId}`).

### Rapportens dokumentstruktur

```
Logo (Region Halland)
VY-ETIKETT (Daglig uppföljning)
Hälso- och sjukvården / Sektionsnamn     ← h1, Source Serif 4, 36px
Dagsöversikt — 31 mars 2026              ← undertitel
──── (accentlinje 48px)

[Sammanfattning: antal indikatorer, inom/utanför förväntat]
[Innehållsförteckning]                    ← bara huvudrapport
[Global AI-analys + kommentarer]          ← bara huvudrapport

KAPITEL 1                                 ← bara huvudrapport
Kapacitet och flöden                      ← h2, Source Serif 4, 28px
[Sektionsanalys]

Beläggningsgrad                           ← h3, Source Serif 4, 20px
────────────────────────── (tunn linje)
96,3% · förväntat 96,5% · V1 2021–V13 2026
[AI-analys + kommentarer]
┌────────────────────────────────────┐
│ [Aggregerat | Dag]  toggle         │
│ [FacetedChart — 2x2 grid]          │
└────────────────────────────────────┘
```

### Anti-collision (slutetiketter)

Används i ChartModal. Baserat på kommundata-projektets `resolveOverlap`:

```typescript
function resolveOverlap(labels, minGap, yMin, yMax) {
  // Iterativ relaxering (max 20 iterationer)
  // Symmetrisk shift: (minGap - gap) / 2
  // Boundary clamp: [yMin + 6, yMax - 6]
  // Connector: H→V→H linje från naturalY till yPos
}
```

## Anomalidetektering

GLM + **villkorlig** conformal prediction ger ett inre 80 %- och ett yttre 95 %-prediktionsintervall per KPI, tidsvy OCH avdelning. Tre-nivå-signal (sedan 2026-04-01). Full metodik: se `SIGNAL-METODIK.md`.

- `yhat`: förväntat värde (GLM-prediktion)
- `yhat_lower_80` / `yhat_upper_80`: inre 80 %-band
- `yhat_lower` / `yhat_upper`: yttre 95 %-band
- `signal`: `"gron"` (inom 80 %), `"gul"` (80–95 %), `"rod"` (utanför 95 %)
- Kalibrering sker **villkorligt** per dagskategori (vardag vs specialdag/helg) — bredare band på helger.
- Signaler beräknas separat per aggregeringsnivå (egen conformal-kalibrering, inte hopräknade dagssignaler) OCH per avdelning.
- Implementation: `R/gemensam/signal-modell.R` — huvudfunktion `kor_kpi_signal()`.

## Typsnitt

| Typsnitt | Användning |
|----------|-----------|
| Source Serif 4 | Rapportrubriker (h1–h3), graftitlar, ChartModal-titel |
| IBM Plex Sans | Brödtext, etiketter, tooltip-text |
| IBM Plex Mono | Siffervärden, hero-värden i KPI-kort |
| Lexend Deca | App-rubrik (topbar), sektionsrubriker i dashboard |

## Färger

Conformal signal:
- Grön (#16a34a): Inom förväntat intervall
- Röd (#dc2626): Utanför förväntat intervall

Accent:
- #00664D (Grön 1): Rubriker, accentlinjer
- #00AB60 (Grön 2): Vy-etiketter, kapitel-overlines

Avdelningsfärger: `#2DB8F6`, `#6473D9`, `#FF5F4A`, `#FFD939`, `#895B42`, `#00AB60`

## Teknikstack

- **Frontend**: React 19, TypeScript, Vite, D3.js
- **Datapipeline**: R med tidyverse, lubridate, jsonlite
- **Signalmodell**: GLM (gaussian/nb/gamma) + split conformal prediction
- **Typsnitt**: Google Fonts
- **Lagring**: localStorage för redigeringar (vy-specifik med prefix)
- **Export**: Minifierad JSON (~3 MB) via `jsonlite::toJSON(auto_unbox = TRUE, na = "null", force = TRUE)`

## Bygga och köra

**Datapipeline (R):**
```r
source("R/pipeline.R")   # hela kedjan: demo-data → bearbeta → exportera
```
Producerar **split-JSON** i `app/public/data/` (manifest `index.json` + en fil per vy-sektion), som Vite serverar och frontend lazy-laddar per vy. Genväg: `npm run data:build` (i `app/`) kör hela R-pipelinen från repo-roten.

**Frontend (i `app/`):**
```bash
npm install
npm run dev      # Vite dev-server
npm run build    # tsc + vite build → app/dist/
npm run lint
```
Deploy-bas är `/hosrapport/` (se `app/vite.config.ts`) — anpassat för GitHub Pages-liknande subkatalog.

**Lokal hostning (stabil, utanför OneDrive):**
```powershell
powershell -ExecutionPolicy Bypass -File .\verktyg\hosta-lokalt.ps1
```
Bygger appen, speglar `app/dist` till `%LOCALAPPDATA%\hosrapport-site` och startar
en fristående node-server (`verktyg/server.mjs`) på http://localhost:8137/hosrapport/.
Servern överlever terminalen (PID i `server.pid`; skriptet stoppar/ersätter tidigare
instans). Varför kopian: OneDrive-synk kan låsa filer i repomappen och ge sporadiska
404 från servrar som läser direkt därifrån — kör om skriptet efter varje ny build/dataexport.
`vite preview` fungerar för snabbtitt men dör med terminalen och läser ur OneDrive.

**Publik hostning:** `.github/workflows/deploy.yml` bygger och deployar till GitHub
Pages vid push till `master`. JSON-datan i `app/public/data/` är spårad i git och
måste committas efter pipelinekörning för att följa med deployen.

**Validering av signalmodellen:**
```r
source("R/granskningsrapport.R")  # → rapport/signal-granskning.html (manuell, ej i pipeline)
source("R/test-signal.R")         # fristående signaltest → data/signal-test-resultat.rds
```

## Utvecklingsanteckningar — förbättrings- och utvecklingsområden

> Denna sektion är till för att underlätta omfattande vidareutveckling. Den fångar känd teknisk skuld, konventioner och fallgropar som inte syns i koden. Verifierad mot källkoden 2026-05-29.

### Konventioner (följ dessa vid ändringar)

- **All KPI-metadata har EN källa**: `R/teman/register.R` bygger `kpi_meta`. Lägg aldrig till KPI-fält genom att duplicera — utöka tema-config + register.
- **Metodik före kod**: ändringar i signalmetodik dokumenteras i `SIGNAL-METODIK.md` först, sedan i `R/gemensam/signal-modell.R`.
- **D3-ritlogik är ren**: all ritlogik bor i `app/src/charts/` (utan React). Komponenter i `components/` är tunna wrappers. Lägg inte D3-kod i komponenter.
- **En ritfunktion**: `tidsserie()` ritar allt; styr beteende via `TidsserieOpts`-flaggor, skapa inte parallella ritfunktioner.
- **Språk**: kod, kommentarer och UI är på svenska. Behåll det.

### Känd dokumentations-drift (åtgärda gärna)

- `SIGNAL-METODIK.md` rad 4–5 refererar `R/kap01-hamta.R` och `R/kap02-bearbeta.R` — dessa filer **finns inte längre**. De heter nu `R/hamta/demo-data.R` och `R/bearbeta.R`. (Övrig metodik i den filen är korrekt.)

### Känd teknisk skuld (R)

- ✅ **Åtgärdat (Fas 0):** ~~Manuell JSON-synk~~ — frontend läser nu kanoniska `data/hos-data.json` via Vite-aliaset `@data`; dubbletten i `app/src/data/` är borttagen.
- ✅ **Åtgärdat (Fas 0):** ~~Hårdkodad tidsstämpel `uppdaterad = "08:00"`~~ — nu `format(Sys.time(), "%H:%M")` i `R/bearbeta.R`.
- ✅ **Åtgärdat (Fas 2):** ~~Två signalpipelines~~ — `kor_kpi_signal()` (produktion) och `kor_signal()` (diagnostik) är nu tydligt avgränsade och dokumenterade i `signal-modell.R`; delar samma kärna.
- ✅ **Åtgärdat (Fas 2):** ~~`bearbeta.R`-monolit~~ — generisk bygg-logik utbruten till `R/gemensam/bygg-sektion.R` (ctx-mönster, inga closure-beroenden).
- ✅ **Åtgärdat (Fas 2):** ~~NPE-ranking hårdkodad för 21 regioner~~ — antal regioner härleds från datan; trösklar i `patientenkat`-config (`signal_typ="ranking"`).
- **NPE-ranking hårdkodad** för 21 regioner (grön ≤3, gul ≤7, röd >7) i `R/teman/patientenkat/bearbeta.R`. Ingen felhantering om Excel-strukturen (rad 4 = år, 5–25 = regioner, 26 = Riket) ändras — då kraschar inläsningen.
- **Patientenkäten faller tyst bort** om `data/npe_primarvard.xlsx` saknas (returnerar `NULL`, ingen markering i JSON).
- **Ingen modell-persistens**: alla GLM:er tränas om från grunden varje körning. För produktion med riktigt API behövs omträningsstrategi och ev. sparade modeller.
- **Demodata är syntetisk** (`R/hamta/demo-data.R`) — ska ersättas med riktig API-/datakälla i produktion. Injicerade anomalier (se `SIGNAL-METODIK.md` §6.3) finns för att validera signalsystemet.

### Känd teknisk skuld (frontend)

- ✅ **Åtgärdat (Fas 0):** ~~Oanvänd kod~~ — `CommentBlock.tsx`, `TufteStrip.tsx`, `SummaryModal.tsx`, `Sparkline.tsx`, `charts/sparkline.ts`, `stores/comments.ts`, `VComment`-typen, `demo-dag.json` (båda) och oanvänd `App.css` är borttagna.
- ✅ **Åtgärdat (Fas 0):** ~~Död prop `editMode`~~ — borttagen ur `App.tsx` och `Section.tsx`.
- **KPI-definitioner**: `KpiData.beskrivning` finns i typen och datan, men `KpiCard.tsx` har även en egen hårdkodad `DEFINITIONS`-tabell. Bör enhetligt komma från datan.
- **Generisk README**: `app/README.md` är fortfarande Vite-mallen.

### Naturliga utvecklingsspår

1. **Riktig datakälla** — ersätt `R/hamta/demo-data.R` med API/databas; behåll samma `radata-hos.rds`/`radata-dept.rds`-kontrakt så resten av pipelinen är oförändrad.
2. **Målläge frikopplat från statistik** — i dag härleds både "förväntat läge" (95 %) och "målläge" (80 %) ur conformal-modellen. Verksamhetens egna riktvärden kan läggas som separat fält per KPI (se KpiCard variant 1).
3. **Fler sektioner/KPI:er** — följ "Ny sektion — steg för steg" ovan.
4. **Automatiserad validering** — koppla `granskningsrapport.R`-kvalitetskrav (se `SIGNAL-METODIK.md` §7.2) till ett test som failar pipelinen vid otillräcklig täckning.
5. **Persistens av redigeringar** — i dag `localStorage` per webbläsare (`hos-rapport-content-blocks`, nyckel `${vy}:${targetId}`). För delning mellan användare krävs backend.

### Filkartor (snabbreferens)

| Vill ändra... | Gå till |
|---------------|---------|
| Signalmetodik / conformal | `R/gemensam/signal-modell.R` + `SIGNAL-METODIK.md` |
| Lägg till KPI/sektion | `R/teman/{namn}/config.R` + `R/teman/register.R` |
| Kalender (helgdagar/lov) | `R/gemensam/helgdagar.R` |
| Aggregering/perioder | `R/gemensam/aggregering.R` |
| Etiketter/talformat | `R/gemensam/formatering.R` |
| Analystexter | `R/gemensam/analystext.R` |
| Grafritning (all) | `app/src/charts/tidsserie.ts` |
| KPI-kortets layout | `app/src/components/KpiCard.tsx` |
| Rapportvy | `app/src/components/ReportView.tsx` |
| Datatyper (kontrakt R↔TS) | `app/src/types.ts` |
