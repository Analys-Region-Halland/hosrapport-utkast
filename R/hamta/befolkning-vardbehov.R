# befolkning-vardbehov.R — Hämtar öppna data om befolkning, förväntat
# vårdbehov och ohälsa för samtliga län + riket:
#
#   SCB PxWeb (BE0101 BefolkningNy)  : folkmängd per ettårsklass →
#                                      folkmängd, andel 80+, försörjningskvot
#   SCB PxWeb (OE0115 KostutLT)      : standardkostnad hälso- och sjukvård
#                                      kr/inv ur kostnadsutjämningen
#   Försäkringskassan (öppna data)   : ohälsotalet + sjukpenningtalet per län
#                                      (decembervärde per år = årssnapshot)
#   Kolada v3 (N79191)               : hälsopolitiskt åtgärdbar dödlighet
#
# Resultat: data/befolkning-vardbehov.rds — samma kontrakt som
# fohm-folkhalsa.rds ($indikatorer med riktning hog/lag/neutral, $data i
# långformat med etikett). Bearbetas av R/gemensam/ranking-tema.R.
#
# Användning: source("R/hamta/befolkning-vardbehov.R")

library(pxweb)
library(dplyr)
library(jsonlite)

SCB_BAS <- "https://api.scb.se/OV0104/v1/doris/sv/ssd"
FK_BAS  <- "https://www.forsakringskassan.se/api/sprstatistikrapportera/public/v1"

REGIONER <- c(
  "00" = "Riket",
  "01" = "Stockholm",       "03" = "Uppsala",         "04" = "Södermanland",
  "05" = "Östergötland",    "06" = "Jönköping",       "07" = "Kronoberg",
  "08" = "Kalmar",          "09" = "Gotland",         "10" = "Blekinge",
  "12" = "Skåne",           "13" = "Halland",         "14" = "Västra Götaland",
  "17" = "Värmland",        "18" = "Örebro",          "19" = "Västmanland",
  "20" = "Dalarna",         "21" = "Gävleborg",       "22" = "Västernorrland",
  "23" = "Jämtland",        "24" = "Västerbotten",    "25" = "Norrbotten"
)
LAN_KODER <- names(REGIONER)

START_AR <- 2011L

# ══════════════════════════════════════════════
#  1. SCB: Befolkning per ettårsklass → tre mått
# ══════════════════════════════════════════════

cat("Hämtar befolkningsstruktur (SCB BE0101)...\n")
BEF_URL <- paste0(SCB_BAS, "/BE/BE0101/BE0101A/BefolkningNy")

# Tillgängliga år ur tabellens metadata (undvik anrop på år som inte finns)
bef_meta <- fromJSON(BEF_URL, simplifyVector = FALSE)
bef_tid <- NULL
for (v in bef_meta$variables) {
  if (identical(v$code, "Tid")) bef_tid <- unlist(v$values)
}
bef_ar <- bef_tid[as.integer(bef_tid) >= START_AR]

# Ett anrop per år — hela uttaget i ett svep spränger cellgränsen (150 000)
bef <- bind_rows(lapply(bef_ar, function(a) {
  px <- pxweb_get(BEF_URL, query = pxweb_query(list(
    Region = LAN_KODER,
    Civilstand = "*",
    Alder = "*",
    Kon = c("1", "2"),
    ContentsCode = "BE0101N1",
    Tid = a
  )))
  d <- as.data.frame(px, column.name.type = "text", variable.value.type = "code")
  names(d)[ncol(d)] <- "antal"
  names(d) <- tolower(names(d))
  # Ålder som heltal ("100+" → 100, ev. totalrader utgår via NA)
  d |>
    mutate(alder_num = suppressWarnings(as.integer(sub("\\+", "", .data[["ålder"]]))),
           ar = as.integer(.data[["år"]])) |>
    filter(!is.na(alder_num)) |>
    group_by(region_id = region, ar, alder_num) |>
    summarise(antal = sum(antal), .groups = "drop")
}))

bef_matt <- bef |>
  group_by(region_id, ar) |>
  summarise(
    folkmangd = sum(antal),
    andel_80  = round(100 * sum(antal[alder_num >= 80]) / sum(antal), 1),
    forsorjningskvot = round(100 * (sum(antal[alder_num <= 19]) + sum(antal[alder_num >= 65])) /
                               sum(antal[alder_num >= 20 & alder_num <= 64]), 1),
    .groups = "drop"
  )

bef_lang <- bind_rows(
  bef_matt |> transmute(kpi = "folkmangd", region_id, ar, varde = folkmangd),
  bef_matt |> transmute(kpi = "andel_80", region_id, ar, varde = andel_80),
  bef_matt |> transmute(kpi = "forsorjningskvot", region_id, ar, varde = forsorjningskvot)
) |>
  mutate(etikett = as.character(ar))

# ══════════════════════════════════════════════
#  2. SCB: Standardkostnad hälso- och sjukvård (kostnadsutjämningen)
# ══════════════════════════════════════════════

cat("Hämtar standardkostnad hälso- och sjukvård (SCB OE0115)...\n")
# Regionkoder i tabellen: "00" för riket, "NNL" för nuvarande regioner
# (Gotland = "0980L"). Historiska huvudmän (Malmöhus m.fl.) utesluts.
KOSTUT_REGIONER <- c("00", "01L", "03L", "04L", "05L", "06L", "07L", "08L",
                     "0980L", "10L", "12L", "13L", "14L", "17L", "18L",
                     "19L", "20L", "21L", "22L", "23L", "24L", "25L")

px_kost <- pxweb_get(
  paste0(SCB_BAS, "/OE/OE0115/OE0115A/KostutLT"),
  query = pxweb_query(list(
    Region = KOSTUT_REGIONER,
    Delmodell = "Hälsa",
    ContentsCode = "OE0115A4",
    Tid = "*"
  ))
)
kost_kod <- as.data.frame(px_kost, column.name.type = "text", variable.value.type = "code")
names(kost_kod)[ncol(kost_kod)] <- "varde"
names(kost_kod) <- tolower(names(kost_kod))

kost_lang <- kost_kod |>
  rename(region_raw = region, ar = "år") |>
  mutate(
    region_id = ifelse(region_raw == "00", "00",
                       ifelse(region_raw == "0980L", "09",
                              sub("L$", "", region_raw))),
    ar = as.integer(ar),
    etikett = as.character(ar),
    kpi = "standardkostnad_hsv"
  ) |>
  filter(ar >= START_AR, !is.na(varde)) |>
  select(kpi, region_id, ar, etikett, varde)

# ══════════════════════════════════════════════
#  3. Försäkringskassan: ohälsotalet + sjukpenningtalet
# ══════════════════════════════════════════════
#  Full dump per dataset (kön ALL, ålder ALL), länstotaler = kommun_kod
#  "ALL_<län>", riket = lan_kod "ALL". Månadsserier: decembervärdet
#  används som årssnapshot (måtten är rullande 12-månadersmått).

hamta_fk <- function(dataset, tabell, matt_kod, kpi_id) {
  cat("Hämtar ", kpi_id, " (Försäkringskassan)...\n", sep = "")
  url <- paste0(FK_BAS, "/", dataset, "/", tabell, ".json?kon_kod=ALL&aldersklass_kod=ALL")
  raw <- fromJSON(url, simplifyVector = FALSE)

  rader <- lapply(raw, function(r) {
    d <- r$dimensions
    if (!identical(d$kon_kod, "ALL") || !identical(d$aldersklass_kod, "ALL")) return(NULL)
    lan <- if (identical(d$lan_kod, "ALL")) "00" else d$lan_kod
    # Länstotal: kommun_kod "ALL_<län>"; riket: "ALL_ALL"
    if (!identical(d$kommun_kod, paste0("ALL_", if (lan == "00") "ALL" else lan))) return(NULL)
    v <- r$observations[[matt_kod]]$value
    if (is.null(v)) return(NULL)
    # Månadsnyckeln heter "manad" i vissa dataset och "man" i andra
    man <- if (!is.null(d$manad)) d$manad else d$man
    tibble(region_id = lan, ar = as.integer(d$ar), manad = man, varde = as.numeric(v))
  })

  bind_rows(rader) |>
    filter(manad == "12", region_id %in% LAN_KODER, ar >= START_AR) |>
    transmute(kpi = kpi_id, region_id, ar, etikett = as.character(ar), varde)
}

fk_ohalsotal <- hamta_fk("ohm-ohalsotal", "SJPohttal", "oht", "ohalsotal")
fk_sjptal    <- hamta_fk("ohm-sjptal", "SJPsjptal", "spt", "sjukpenningtal")

# ══════════════════════════════════════════════
#  4. Kolada: hälsopolitiskt åtgärdbar dödlighet (N79191)
# ══════════════════════════════════════════════

cat("Hämtar hälsopolitiskt åtgärdbar dödlighet (Kolada N79191)...\n")
kolada_raw <- fromJSON(
  paste0("https://api.kolada.se/v3/data/kpi/N79191/year/",
         paste(START_AR:(as.integer(format(Sys.Date(), "%Y"))), collapse = ",")),
  simplifyVector = FALSE
)

kolada_lang <- bind_rows(lapply(kolada_raw$values, function(r) {
  # Region-id:n i Kolada: "0000" = riket, "0013" = Region Halland
  rid <- sub("^00", "", r$municipality)
  if (r$municipality == "0000") rid <- "00"
  if (!rid %in% LAN_KODER) return(NULL)
  v <- Filter(function(x) identical(x$gender, "T"), r$values)
  if (length(v) == 0 || is.null(v[[1]]$value)) return(NULL)
  tibble(kpi = "atgardbar_dodlighet", region_id = rid, ar = as.integer(r$period),
         etikett = as.character(r$period), varde = as.numeric(v[[1]]$value))
}))

# ══════════════════════════════════════════════
#  5. Metadata + spara
# ══════════════════════════════════════════════

indikatorer_meta <- tribble(
  ~id, ~namn, ~title, ~beskrivning, ~kalla, ~enhet, ~riktning,
  "folkmangd", "Folkmängd",
    "Folkmängd den 31 december, antal",
    "Antal folkbokförda invånare i länet vid årets slut.",
    "SCB, befolkningsstatistiken", "antal", "neutral",
  "andel_80", "Andel 80 år och äldre",
    "Befolkning 80 år och äldre, andel (%)",
    "Andel av befolkningen som är 80 år eller äldre. Gruppen har det i särklass största vårdbehovet per invånare och driver slutenvårds- och omsorgsbehovet.",
    "SCB, befolkningsstatistiken", "procent", "neutral",
  "forsorjningskvot", "Demografisk försörjningskvot",
    "Demografisk försörjningskvot, antal per 100 i arbetsför ålder",
    "Antal invånare 0-19 år och 65+ per 100 invånare 20-64 år. Ju högre kvot, desto större försörjningsbörda på den arbetsföra befolkningen.",
    "SCB, befolkningsstatistiken", "antal", "neutral",
  "standardkostnad_hsv", "Standardkostnad hälso- och sjukvård",
    "Standardkostnad hälso- och sjukvård i kostnadsutjämningen, kr/invånare",
    "Statens modellberäknade förväntade vårdkostnad per invånare utifrån befolkningens kön, ålder och socioekonomi (kostnadsutjämningens vårdbehovsmatris). Ett rent behovsindex, opåverkat av regionens eget utbud.",
    "SCB, kostnadsutjämningen", "antal", "neutral",
  "ohalsotal", "Ohälsotalet",
    "Ohälsotalet, dagar per person 16-64 år",
    "Antal utbetalda dagar med sjukpenning, rehabiliteringspenning samt sjuk- och aktivitetsersättning per person 16-64 år under en tolvmånadersperiod. Decembervärde per år.",
    "Försäkringskassan", "antal", "lag",
  "sjukpenningtal", "Sjukpenningtalet",
    "Sjukpenningtalet, dagar per person 16-64 år",
    "Antal utbetalda dagar med sjukpenning och rehabiliteringspenning per person 16-64 år under en tolvmånadersperiod. Decembervärde per år.",
    "Försäkringskassan", "antal", "lag",
  "atgardbar_dodlighet", "Hälsopolitiskt åtgärdbar dödlighet",
    "Hälsopolitiskt åtgärdbar dödlighet, antal per 100 000 invånare 0-74 år",
    "Dödsfall före 75 års ålder i sjukdomar som bedöms möjliga att förebygga genom hälsopolitiska insatser (bland annat levnadsvanerelaterade diagnoser och olyckor). Treårsmedelvärde.",
    "Socialstyrelsens dödsorsaksregister via Kolada (N79191)", "antal", "lag"
)

data_lang <- bind_rows(bef_lang, kost_lang, fk_ohalsotal, fk_sjptal, kolada_lang) |>
  mutate(region = unname(REGIONER[region_id])) |>
  select(kpi, region_id, region, ar, etikett, varde) |>
  filter(!is.na(varde))

resultat <- list(
  indikatorer = indikatorer_meta,
  data        = data_lang,
  hamtad      = Sys.time()
)

saveRDS(resultat, "data/befolkning-vardbehov.rds")
cat("\nSparat: data/befolkning-vardbehov.rds —", nrow(data_lang), "rader,",
    n_distinct(data_lang$kpi), "indikatorer\n")
