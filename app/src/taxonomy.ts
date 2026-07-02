// ════════════════════════════════════════════════════════════
//  taxonomy.ts — Rapportens områdesindelning (enda sanningskällan)
//
//  Kategorier ordnade som en logisk kedja, med förlagor i etablerade
//  ramverk (OECD Health at a Glance, NHS Oversight Framework, WHO HSPA,
//  Socialstyrelsens "God vård", SKR:s öppna jämförelser) och i den
//  indelning HOS-avdelningen skissat (Behov → Vad vi levererar →
//  Hur vi levererar → Förebyggande → Externa effekter):
//
//    01 Behov & befolkning        — varför vi gör det vi gör
//    02 Tillgänglighet            — vad vi levererar
//    03 Vårdens verksamheter      — hur vi levererar, per vårdform
//       (diagnosområden som psykiatri följs inom vårdformerna, inte
//        som egna toppområden)
//    04 Kvalitet & patientsäkerhet— gör vi rätt sak rätt, oönskade effekter
//    05 Resurser & förutsättningar— personal, ekonomi, kapacitet, miljö
//    06 Externa rapporter         — sammanställda existerande ramverk
//    07 Interna rapporter         — regionens egna uppföljningsrapporter
//
//  Ett område är antingen AKTIVT (finns i datamanifestet, klickbart)
//  eller PLANERAT (placeholder: beskrivning av tänkt innehåll, ingen data).
//  Aktiva områden matchas mot manifestet via id — namnet i manifestet
//  vinner om de skiljer sig. Områden som dyker upp i manifestet utan
//  taxonomi-post hamnar i en "Övrigt"-kategori (säkerhetsnät).
// ════════════════════════════════════════════════════════════

export interface OmradeDef {
  id: string;
  namn: string;
  /** Kort redaktionell beskrivning (max ~2 meningar). */
  beskrivning: string;
  /** true = placeholder utan data — visas nedtonat med "Planerat"-märke. */
  planerad?: boolean;
  /** Exempel på tänkta indikatorer/källor (visas för planerade områden). */
  exempel?: string;
}

export interface KategoriDef {
  id: string;
  namn: string;
  /** Kort fråga/deviskicker ovanför kategorinamnet. */
  kicker: string;
  beskrivning: string;
  omraden: OmradeDef[];
}

export const TAXONOMI: KategoriDef[] = [
  {
    id: "behov",
    namn: "Behov & befolkning",
    kicker: "Varför vi gör det vi gör",
    beskrivning:
      "Befolkningens sammansättning, hälsoläge och vårdbehov: grunden för planering och prioritering.",
    omraden: [
      {
        id: "befolkning",
        namn: "Befolkning & vårdbehov",
        beskrivning: "Befolkningens sammansättning, förväntade vårdbehov och ohälsa, från SCB, Försäkringskassan och Socialstyrelsen.",
      },
      {
        id: "folkhalsa",
        namn: "Folkhälsa & prevention",
        beskrivning: "Folkhälsomyndighetens indikatorer efter folkhälsopolitikens åtta målområden, med Halland jämfört mot övriga regioner.",
      },
    ],
  },
  {
    id: "tillganglighet",
    namn: "Tillgänglighet",
    kicker: "Vad vi levererar",
    beskrivning:
      "Hur snabbt invånarna får kontakt, bedömning och behandling: vårdgarantins alla steg.",
    omraden: [
      {
        id: "vardgaranti",
        namn: "Vårdgaranti & väntetider",
        beskrivning: "Väntetider till kontakt, bedömning, operation och utredning.",
        planerad: true,
        exempel: "Telefontillgänglighet 1177, medicinsk bedömning inom 3 dagar, operation/åtgärd inom 90 dagar, standardiserade vårdförlopp (SVF).",
      },
    ],
  },
  {
    id: "verksamhet",
    namn: "Vårdens verksamheter",
    kicker: "Hur vi levererar",
    beskrivning:
      "Produktion och flöden per vårdform, från nära vård till slutenvård. Diagnosområden som psykiatri följs inom respektive vårdform, inte som egna områden.",
    omraden: [
      {
        id: "primarvard",
        namn: "Primärvård & nära vård",
        beskrivning: "Besök, digitala kontakter och telefontillgänglighet i den nära vården, inklusive första linjens psykiska hälsa.",
      },
      {
        id: "akutflode",
        namn: "Akutflöde",
        beskrivning: "Tillgänglighet, väntetider och flöden i den akuta vårdkedjan.",
      },
      {
        id: "slutenvard",
        namn: "Slutenvård",
        beskrivning: "Beläggning, vårdtider och utskrivningsklara inom slutenvården, somatisk såväl som psykiatrisk vård.",
      },
      {
        id: "ambulans",
        namn: "Ambulans & prehospital vård",
        beskrivning: "Uppdrag, responstider och sjuktransporter.",
        planerad: true,
        exempel: "Responstid prio 1, uppdragsvolymer, avlämningstider på akutmottagning.",
      },
      {
        id: "lakemedel",
        namn: "Läkemedel & diagnostik",
        beskrivning: "Läkemedelsanvändning och diagnostiska flöden.",
        planerad: true,
        exempel: "Läkemedelskostnader, följsamhet till rekommenderad lista, svarstider röntgen och labb.",
      },
    ],
  },
  {
    id: "kvalitet",
    namn: "Kvalitet & patientsäkerhet",
    kicker: "Gör vi rätt sak rätt",
    beskrivning:
      "Vårdens resultat, säkerhet och hur patienterna upplever den.",
    omraden: [
      {
        id: "sakervard",
        namn: "Säker vård & vårdskador",
        beskrivning: "Undvikbara skador och vårdrelaterade infektioner.",
        planerad: true,
        exempel: "Vårdrelaterade infektioner (VRI), trycksår, markörbaserad journalgranskning, överbeläggningarnas patientsäkerhetspåverkan.",
      },
      {
        id: "resultat",
        namn: "Medicinska resultat",
        beskrivning: "Behandlingsresultat för stora sjukdomsgrupper.",
        planerad: true,
        exempel: "Resultat per sjukdomsgrupp enligt nationella riktlinjer och kvalitetsregister: stroke, hjärtinfarkt, diabetes, cancer (indelning enligt nationella programområden).",
      },
      {
        id: "patientupplevelse",
        namn: "Patientupplevelse",
        beskrivning: "Patienternas omdömen från Nationell Patientenkät.",
        planerad: true,
        exempel: "Helhetsintryck, bemötande, delaktighet och tillgänglighet ur Nationell Patientenkät (NPE).",
      },
      {
        id: "ivo-patientnamnd",
        namn: "IVO & patientnämnd",
        beskrivning: "Tillsynsärenden och patienternas klagomål, samlade från båda källorna.",
        planerad: true,
        exempel: "IVO:s tillsynsbeslut och sjukhustillsyn, klagomål enligt patientsäkerhetslagen, patientnämndens ärenden per verksamhet och kategori.",
      },
    ],
  },
  {
    id: "resurser",
    namn: "Resurser & förutsättningar",
    kicker: "Det vi levererar med",
    beskrivning:
      "Personal, ekonomi, kapacitet och miljö: förutsättningarna för allt ovan.",
    omraden: [
      {
        id: "personal",
        namn: "Personal & bemanning",
        beskrivning: "Sjukfrånvaro, övertid och beroendet av inhyrd personal.",
      },
      {
        id: "ekonomi",
        namn: "Ekonomi",
        beskrivning: "Resultat, kostnadsutveckling och produktivitet.",
        planerad: true,
        exempel: "Resultat mot budget, nettokostnadsutveckling, kostnad per DRG-poäng, köpt vård.",
      },
      {
        id: "kapacitet",
        namn: "Vårdplatser & kapacitet",
        beskrivning: "Disponibla vårdplatser och hur väl kapaciteten räcker till.",
        planerad: true,
        exempel: "Disponibla vårdplatser, överbeläggningar och utlokaliseringar, operationskapacitet, kapacitetsplanering.",
      },
      {
        id: "miljo",
        namn: "Miljö & hållbarhet",
        beskrivning: "Vårdens miljöpåverkan, utsläpp och lokaler.",
        planerad: true,
        exempel: "Klimatutsläpp, energianvändning, lokalyta och lokalkostnader, läkemedels miljöpåverkan, avfall.",
      },
    ],
  },
  {
    id: "externa",
    namn: "Externa rapporter & ramverk",
    kicker: "Omvärldens blick",
    beskrivning:
      "Sammanställningar av etablerade externa ramverk, med Halland jämfört mot övriga regioner.",
    omraden: [
      {
        id: "skr",
        namn: "Hälso- och sjukvårdsrapporten (SKR)",
        beskrivning: "SKR:s öppna jämförelser från Kolada, 76 indikatorer i sex delar.",
      },
    ],
  },
  {
    id: "interna",
    namn: "Interna uppföljningsrapporter",
    kicker: "Vår egen uppföljning",
    beskrivning:
      "Regionens och förvaltningarnas egna återkommande rapporter, samlade i sitt ursprungliga format.",
    omraden: [
      {
        id: "uppfoljningsrapporter",
        namn: "Region Hallands uppföljningsrapporter",
        beskrivning: "Uppföljningsrapporterna till regionstyrelsen.",
        planerad: true,
        exempel: "Uppföljningsrapport 1 och 2 samt årsredovisningens hälso- och sjukvårdsavsnitt.",
      },
      {
        id: "manadsrapporter",
        namn: "Förvaltningarnas månadsrapporter",
        beskrivning: "Månadsuppföljning från vårdförvaltningarna.",
        planerad: true,
        exempel: "Månadsrapporter från Hallands sjukhus, Närsjukvården, Psykiatrin och Ambulanssjukvården.",
      },
    ],
  },
];

/** Kategori för ett områdes-id, eller undefined om oklassat. */
export function kategoriForOmrade(omradeId: string): KategoriDef | undefined {
  return TAXONOMI.find((k) => k.omraden.some((o) => o.id === omradeId));
}

/** Områdesdefinition för ett id, eller undefined. */
export function omradeDef(omradeId: string): OmradeDef | undefined {
  for (const k of TAXONOMI) {
    const o = k.omraden.find((o) => o.id === omradeId);
    if (o) return o;
  }
  return undefined;
}
