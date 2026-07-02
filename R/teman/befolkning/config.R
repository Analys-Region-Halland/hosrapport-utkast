# config.R — Befolkning & vårdbehov: öppna källor om befolkningens
# struktur, förväntade vårdbehov och ohälsa.
# EN sektion ("befolkning") i årsvyn, med tre delar:
#   demografi : beskrivande mått utan målriktning (grått chip)
#   behov     : statens behovsindex ur kostnadsutjämningen (neutral)
#   ohalsa    : rankade mått mot målet topp 3 bland regionerna
#
# Datakällor (alla öppna): SCB PxWeb (befolkning + kostnadsutjämning),
# Försäkringskassan (ohälsotal/sjukpenningtal) och Kolada (åtgärdbar
# dödlighet). Hämtning: R/hamta/befolkning-vardbehov.R.

befolkning_tema <- list(
  id          = "befolkning",
  namn        = "Befolkning & vårdbehov",
  bara_arsvyn = TRUE,
  signal_typ  = "ranking",
  ranking     = list(grans_gron = 3, grans_gul = 7),
  datakalla   = "data/befolkning-vardbehov.rds",
  fokus_region = "13",    # Hallands län
  riket_id     = "00",
  kpi_prefix   = "bef-",
  jmf_etikett  = "år",
  sektion_intro = function(n_kpi, n_delar) {
    paste0("Kapitlet beskriver befolkningens sammansättning, förväntade",
           " vårdbehov och ohälsa utifrån ", n_kpi,
           " mått från SCB, Försäkringskassan och Socialstyrelsen,",
           " samtliga från öppna källor.")
  },

  delar = list(
    list(id = "demografi", namn = "Befolkningen och åldrandet",
         kpier = c("folkmangd", "andel_80", "forsorjningskvot")),
    list(id = "behov", namn = "Förväntat vårdbehov",
         kpier = c("standardkostnad_hsv")),
    list(id = "ohalsa", namn = "Ohälsa i befolkningen",
         kpier = c("ohalsotal", "sjukpenningtal", "atgardbar_dodlighet"))
  )
)
