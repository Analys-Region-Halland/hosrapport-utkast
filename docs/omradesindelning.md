# Områdesindelning för HoS-rapporten — researchunderlag och motivering

*Uppdaterad 2026-07-02. Underlag för den taxonomi som implementeras i
`app/src/taxonomy.ts` och visas som kategoriboxar på rapportens startsida.*

## Frågan

Rapporten hade "placeholder-områden" utan förankring i hur hälso- och
sjukvård faktiskt följs upp. HOS-avdelningens egen skiss (Behov → Vad vi
levererar → Hur vi levererar → Förebyggande → Externa effekter) är en bra
logisk kedja men ingen färdig rapportindelning. Vi behövde en indelning som
är (a) vedertagen — känns igen av professionen, (b) ändamålsenlig — varje
område har en tydlig ägare och datakälla, och (c) begriplig för läsaren.

## Vad etablerade ramverk gör

### Svenska förlagor

| Källa | Indelning |
|---|---|
| SKR Hälso- och sjukvårdsrapporten 2025 | Livslängd/överlevnad → insatser per vårdform (primärvård, somatik, psykiatri) → screening → väntetider → patientsäkerhet → resursanvändning → befolkningens åsikter |
| Socialstyrelsen "God vård" | Sex kvalitetsområden: kunskapsbaserad, säker, individanpassad, effektiv, jämlik, tillgänglig |
| Vården i siffror | Två parallella lager: tematisk indelning (tillgänglighet, säker vård, kostnader…) + sjukdomstillstånd (≈ NPO:s 26 programområden) |
| Regionernas nämndrapporter (Skåne, Stockholm, Östergötland) | Tillgänglighet, produktion, kvalitet/patientsäkerhet, medarbetare, ekonomi |
| Närsjukvården Hallands egen uppföljningsrapport | Sammanfattning, kvalitetsstyrning, medarbetare, målstyrning, ekonomi |
| God och nära vård (Socialstyrelsens uppföljning) | Tillgänglighet, kontinuitet, delaktighet, samverkan, resursförskjutning mot primärvård |

### Internationella förlagor

| Källa | Indelning |
|---|---|
| OECD Health at a Glance | Hälsoläge, riskfaktorer, tillgänglighet, kvalitet & utfall, kostnader, personal, läkemedel, äldreomsorg |
| NHS Oversight Framework 2025/26 | Access, effectiveness & experience, patient safety, people & workforce, finance & productivity, improving health & reducing inequality |
| WHO HSPA (2022) | Funktioner (styrning, resurser, finansiering, vårdproduktion) → mellanliggande mål (tillgänglighet, kvalitet, effektivitet) → slutmål (hälsa, ekonomiskt skydd, personcentrering) |
| CIHI (Kanada) | Inputs → outputs (tillgänglig, kvalitativ vård) → utfall, med sociala bestämningsfaktorer |
| Danmarks "8 nationale mål" | Sammanhängande förlopp, kroniker/äldre, överlevnad & patientsäkerhet, kvalitet, snabb utredning, patientinvolvering, jämlikhet, effektivitet |
| Donabedian | Struktur → process → utfall |
| IHI Quintuple Aim | Befolkningshälsa, patientupplevelse, kostnad, medarbetare, jämlikhet |

### Vad som återkommer överallt

Nästan alla ramverk landar i samma ~6 block: **(1) befolkningens
hälsa/behov, (2) tillgänglighet, (3) kvalitet & patientsäkerhet,
(4) patientupplevelse, (5) personal, (6) ekonomi/effektivitet** — ofta
ordnade som en kausal kedja (behov → leverans → resultat) snarare än en
platt lista, och med sjukdomsgrupper (NPO) som *understruktur* snarare än
ytterstruktur.

## Vald indelning

*Justerad efter avstämning med HOS-avdelningen 2026-07-02: kapacitet och
miljö ligger under Resurser & förutsättningar, psykiatri följs inom
vårdformerna i stället för som egen box, IVO och patientnämnden delar
område under Kvalitet & patientsäkerhet, och interna uppföljningsrapporter
fick en egen kategori efter de externa.*

Sju kategorier, ordnade som HOS-avdelningens kedja, med områden under varje.
Områden är antingen **aktiva** (har data i rapporten) eller **planerade**
(placeholder med beskrivning av tänkt innehåll):

1. **Behov & befolkning** — *varför vi gör det vi gör*
   Befolkning & vårdbehov ✓ (SCB: demografi + kostnadsutjämningens behovsindex, FK: ohälsotal/sjukpenningtal, Kolada: åtgärdbar dödlighet) · Folkhälsa & prevention ✓ (FoHM:s indikatorer efter folkhälsopolitikens åtta målområden + hälsoutfall, topp 3-ranking mot övriga län)
2. **Tillgänglighet** — *vad vi levererar*
   Vårdgaranti & väntetider (1177, 3-dagarsgaranti, 90 dagar, SVF)
3. **Vårdens verksamheter** — *hur vi levererar, per vårdform*
   Primärvård & nära vård ✓ · Akutflöde ✓ · Slutenvård ✓ · Ambulans & prehospital vård · Läkemedel & diagnostik
   (Diagnosområden som psykiatri följs inom vårdformerna och under Medicinska resultat, inte som egna toppområden.)
4. **Kvalitet & patientsäkerhet** — *gör vi rätt sak rätt*
   Säker vård & vårdskador · Medicinska resultat (per sjukdomsgrupp/NPO) · Patientupplevelse (NPE) · IVO & patientnämnd
5. **Resurser & förutsättningar**
   Personal & bemanning ✓ · Ekonomi ✓ (Kolada/SCB räkenskapssammandrag: nettokostnad, behovsjusterad avvikelse mot referenskostnad, kostnad per vårdform, DRG-produktivitet) · Vårdplatser & kapacitet · Miljö & hållbarhet
6. **Externa rapporter & ramverk** — *sammanställda existerande ramverk*
   Hälso- och sjukvårdsrapporten (SKR) ✓
7. **Interna uppföljningsrapporter** — *vår egen uppföljning*
   Region Hallands uppföljningsrapporter · Förvaltningarnas månadsrapporter

(✓ = aktivt område med data idag; Primärvård och Personal har demodata.)

### Motivering av avvikelser från HOS-skissen

- **"Förebyggande åtgärder"** har inte egen kategori — levnadsvanor och
  våld i nära relationer bor under Behov & befolkning (Folkhälsa &
  prevention), i linje med OECD:s "risk factors". En egen kategori med ett
  enda område ger tunn läsning.
- **"Externa effekter (oönskade)"** = Säker vård & vårdskador, placerat
  under Kvalitet & patientsäkerhet där alla svenska och internationella
  ramverk har det.
- **Tillgänglighet** ligger som egen kategori (inte under "Vad vi
  levererar" som samlingsnamn) eftersom det är den mest efterfrågade och
  mest standardiserade uppföljningsdimensionen i svensk vård.
- **Generella dimensioner** (tid, organisation, utveckling) är inte
  kategorier utan rapportens *mekanik*: tidsvyerna (dag→år),
  avdelningsnedbrytningarna och signalmodellen finns i alla områden.

### Principer framåt

- Sjukdomsgrupper/NPO används som **understruktur** (delar inom området
  Medicinska resultat), inte som egna toppområden — samma mönster som
  SKR-kapitlet redan använder med sina sex delar.
- Externa ramverk återges med sin ursprungsindelning intakt (som
  SKR-rapportens sex delar) och ramas in i kategorin Externa rapporter, så
  att läsaren ser att indelningen är källans, inte vår.
- Ett område bör ha en tydlig dataägare och minst 3–4 indikatorer innan
  det aktiveras.
