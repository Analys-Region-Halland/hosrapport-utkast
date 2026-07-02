# config.R — Ekonomi: hälso- och sjukvårdens verksamhetsekonomi.
# EN sektion ("ekonomi") i årsvyn under Resurser & förutsättningar,
# tre delar:
#   kostnadsniva  : nettokostnad (neutral) + nettokostnadsavvikelse mot
#                   referenskostnad (rankad — det behovsjusterade och
#                   därmed jämförbara måttet)
#   vardformer    : kostnad per vårdform, kr/inv (neutrala strukturmått)
#   produktivitet : kostnad per DRG-poäng (rankade)
#
# Datakälla: Kolada v3 (SCB:s räkenskapssammandrag + nationella KPP/DRG).
# Hämtning: R/hamta/kolada-ekonomi.R.

ekonomi_tema <- list(
  id          = "ekonomi",
  namn        = "Ekonomi",
  bara_arsvyn = TRUE,
  signal_typ  = "ranking",
  ranking     = list(grans_gron = 3, grans_gul = 7),
  datakalla   = "data/kolada-ekonomi.rds",
  fokus_region = "13",
  riket_id     = "00",
  kpi_prefix   = "eko-",
  jmf_etikett  = "år",
  sektion_intro = function(n_kpi, n_delar) {
    paste0("Kapitlet följer hälso- och sjukvårdens verksamhetsekonomi",
           " utifrån ", n_kpi, " nyckeltal ur SCB:s räkenskapssammandrag",
           " och den nationella KPP/DRG-statistiken, hämtade via Kolada.",
           " Jämförbarheten mellan regioner bärs av den behovsjusterade",
           " nettokostnadsavvikelsen och kostnaden per DRG-poäng.")
  },

  delar = list(
    list(id = "kostnadsniva", namn = "Kostnadsnivå och behovsjustering",
         kpier = c("nettokostnad_hsv", "nettokostnadsavvikelse")),
    list(id = "vardformer", namn = "Kostnad per vårdform",
         kpier = c("kostnad_primarvard", "kostnad_somatik",
                   "kostnad_psykiatri", "kostnad_lakemedel")),
    list(id = "produktivitet", namn = "Produktivitet",
         kpier = c("drg_oppen", "drg_sluten"))
  )
)
