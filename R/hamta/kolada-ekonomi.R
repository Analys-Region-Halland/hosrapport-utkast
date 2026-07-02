# kolada-ekonomi.R — Hämtar hälso- och sjukvårdens verksamhetsekonomi för
# samtliga regioner + riket via Kolada API v3 (underliggande källa: SCB:s
# räkenskapssammandrag för regioner samt nationella KPP/DRG-statistiken).
#
#   N70061  Nettokostnad hälso- och sjukvård totalt (inkl. läkemedel), kr/inv
#   N70038  Referenskostnad hälso- och sjukvård (inkl. läkemedel), kr/inv
#           → används för att BERÄKNA nettokostnadsavvikelsen (%):
#             (faktisk - referens) / referens. Referenskostnaden är statens
#             förväntade kostnad utifrån vårdbehovsmatrisen, så avvikelsen
#             är det jämförbara måttet mellan regioner.
#   N71000  Kostnad primärvård (exkl. läkemedel), kr/inv
#   N72000  Kostnad specialiserad somatisk vård (exkl. läkemedel), kr/inv
#   N74000  Kostnad specialiserad psykiatrisk vård (exkl. läkemedel), kr/inv
#   N70059  Nettokostnad läkemedel totalt (exkl. tandvård), kr/inv
#   U79065  Kostnad per producerad DRG-poäng, öppen somatisk sjukhusvård
#   U79066  Kostnad per producerad DRG-poäng, sluten somatisk sjukhusvård
#
# Resultat: data/kolada-ekonomi.rds — samma kontrakt som övriga
# ranking-teman ($indikatorer med riktning, $data i långformat).
#
# Användning: source("R/hamta/kolada-ekonomi.R")

library(dplyr)
library(jsonlite)

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

KPIER <- c(
  nettokostnad_hsv  = "N70061",
  referenskostnad   = "N70038",
  kostnad_primarvard = "N71000",
  kostnad_somatik   = "N72000",
  kostnad_psykiatri = "N74000",
  kostnad_lakemedel = "N70059",
  drg_oppen         = "U79065",
  drg_sluten        = "U79066"
)

hamta_kolada <- function(kpi_id, internt_id) {
  cat("  ", internt_id, " (", kpi_id, ")...\n", sep = "")
  ar_lista <- paste(START_AR:(as.integer(format(Sys.Date(), "%Y"))), collapse = ",")
  raw <- fromJSON(
    paste0("https://api.kolada.se/v3/data/kpi/", kpi_id, "/year/", ar_lista),
    simplifyVector = FALSE
  )
  bind_rows(lapply(raw$values, function(r) {
    # Region-id:n i Kolada: "0000" = riket, "0013" = Region Halland
    rid <- if (r$municipality == "0000") "00" else sub("^00", "", r$municipality)
    if (!rid %in% LAN_KODER) return(NULL)
    v <- Filter(function(x) identical(x$gender, "T"), r$values)
    if (length(v) == 0 || is.null(v[[1]]$value)) return(NULL)
    tibble(kpi = internt_id, region_id = rid, ar = as.integer(r$period),
           etikett = as.character(r$period), varde = as.numeric(v[[1]]$value))
  }))
}

cat("Hämtar", length(KPIER), "ekonominyckeltal från Kolada...\n")
data_ram <- bind_rows(mapply(hamta_kolada, KPIER, names(KPIER), SIMPLIFY = FALSE))

# ── Beräkna nettokostnadsavvikelsen (%): faktisk mot referenskostnad ──
avvikelse <- data_ram |>
  filter(kpi %in% c("nettokostnad_hsv", "referenskostnad")) |>
  select(kpi, region_id, ar, etikett, varde) |>
  tidyr::pivot_wider(names_from = kpi, values_from = varde) |>
  filter(!is.na(nettokostnad_hsv), !is.na(referenskostnad), referenskostnad > 0) |>
  transmute(kpi = "nettokostnadsavvikelse", region_id, ar, etikett,
            varde = round(100 * (nettokostnad_hsv - referenskostnad) / referenskostnad, 1))

# Referenskostnaden var bara ett beräkningsunderlag — visas inte som eget mått
data_lang <- data_ram |>
  filter(kpi != "referenskostnad") |>
  bind_rows(avvikelse) |>
  mutate(region = unname(REGIONER[region_id])) |>
  select(kpi, region_id, region, ar, etikett, varde) |>
  filter(!is.na(varde))

indikatorer_meta <- tribble(
  ~id, ~namn, ~title, ~beskrivning, ~kalla, ~enhet, ~riktning,
  "nettokostnad_hsv", "Nettokostnad hälso- och sjukvård",
    "Nettokostnad hälso- och sjukvård totalt (inkl. läkemedel), kr/invånare",
    "Regionens nettokostnad för hälso- och sjukvård inklusive läkemedel, per invånare. Nivån speglar både behov, ambition och effektivitet och färgsätts därför inte.",
    "SCB räkenskapssammandraget via Kolada (N70061)", "antal", "neutral",
  "nettokostnadsavvikelse", "Nettokostnadsavvikelse mot referenskostnad",
    "Nettokostnadsavvikelse hälso- och sjukvård, procent",
    "Faktisk nettokostnad i förhållande till referenskostnaden, statens förväntade kostnad utifrån befolkningens kön, ålder och socioekonomi. Positiv avvikelse betyder högre kostnad än vad behoven motiverar; måttet är därmed jämförbart mellan regioner. Beräknad som (N70061 - N70038) / N70038.",
    "SCB räkenskapssammandraget och kostnadsutjämningen via Kolada, egen beräkning", "procent", "lag",
  "kostnad_primarvard", "Kostnad primärvård",
    "Kostnad för primärvård (exkl. läkemedel), kr/invånare",
    "Regionens kostnad för primärvård per invånare. Ett strukturmått: nivån speglar hur vården är organiserad snarare än hur bra den är.",
    "SCB räkenskapssammandraget via Kolada (N71000)", "antal", "neutral",
  "kostnad_somatik", "Kostnad specialiserad somatisk vård",
    "Kostnad för specialiserad somatisk vård (exkl. läkemedel), kr/invånare",
    "Regionens kostnad för specialiserad somatisk vård per invånare.",
    "SCB räkenskapssammandraget via Kolada (N72000)", "antal", "neutral",
  "kostnad_psykiatri", "Kostnad specialiserad psykiatrisk vård",
    "Kostnad för specialiserad psykiatrisk vård (exkl. läkemedel), kr/invånare",
    "Regionens kostnad för specialiserad psykiatrisk vård per invånare.",
    "SCB räkenskapssammandraget via Kolada (N74000)", "antal", "neutral",
  "kostnad_lakemedel", "Nettokostnad läkemedel",
    "Nettokostnad läkemedel totalt (exkl. tandvård), kr/invånare",
    "Regionens nettokostnad för läkemedel per invånare, förmånsläkemedel och rekvisitionsläkemedel sammantaget.",
    "SCB räkenskapssammandraget via Kolada (N70059)", "antal", "neutral",
  "drg_oppen", "Kostnad per DRG-poäng, öppen somatisk vård",
    "Kostnad per producerad DRG-poäng i öppen somatisk sjukhusvård, kr",
    "Kostnad per producerad DRG-poäng i öppen specialiserad somatisk vård. DRG-poängen viktar vårdproduktionen efter resurstyngd, så måttet jämför produktivitet mellan regioner.",
    "Nationella KPP/DRG-statistiken via Kolada (U79065)", "antal", "lag",
  "drg_sluten", "Kostnad per DRG-poäng, sluten somatisk vård",
    "Kostnad per producerad DRG-poäng i sluten somatisk sjukhusvård, kr",
    "Kostnad per producerad DRG-poäng i sluten specialiserad somatisk vård. DRG-poängen viktar vårdproduktionen efter resurstyngd, så måttet jämför produktivitet mellan regioner.",
    "Nationella KPP/DRG-statistiken via Kolada (U79066)", "antal", "lag"
)

resultat <- list(
  indikatorer = indikatorer_meta,
  data        = data_lang,
  hamtad      = Sys.time()
)

saveRDS(resultat, "data/kolada-ekonomi.rds")
cat("\nSparat: data/kolada-ekonomi.rds —", nrow(data_lang), "rader,",
    n_distinct(data_lang$kpi), "indikatorer\n")
