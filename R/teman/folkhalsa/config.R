# config.R — Folkhälsa: Folkhälsomyndighetens indikatorer (Folkhälsodata)
# EN sektion ("folkhalsa") i årsvyn, med delar enligt folkhälsopolitikens
# åtta målområden plus hälsoutfall — samma indelning som FoHM:s egen databas
# (mappen A_Mo8 "Folkhälsan i Sverige").
#
# Indikatorurval, API-sökvägar och riktning per indikator bor i
# R/hamta/fohm-folkhalsa.R (metadatat följer med i .rds-filen).
# Halland highlightas; övriga län blir kontextlinjer, Riket streckad.
# Signal: ranking bland de 21 länen — "i fas" = topp 3, "bevaka" = 4–7,
# "avvikelse" = plats 8 eller lägre.

folkhalsa_tema <- list(
  id          = "folkhalsa",
  namn        = "Folkhälsa & prevention",
  bara_arsvyn = TRUE,
  signal_typ  = "ranking",
  ranking     = list(grans_gron = 3, grans_gul = 7),
  datakalla   = "data/fohm-folkhalsa.rds",
  fokus_region = "13",    # Hallands län
  riket_id     = "00",
  kpi_prefix   = "fohm-",
  jmf_etikett  = "mätning",
  sektion_intro = function(n_kpi, n_delar) {
    paste0("Folkhälsokapitlet jämför ", n_kpi,
           " indikatorer från Folkhälsomyndigheten mellan regionerna,",
           " indelade efter folkhälsopolitikens målområden.")
  },

  # Delar = folkhälsopolitikens målområden, i propositionens ordning
  # (prop. 2017/18:249), plus hälsoutfall sist. kpier = interna id:n
  # från hämtningsskriptet.
  delar = list(
    list(id = "mo1", namn = "Det tidiga livets villkor",
         kpier = c("tobak_graviditet", "forskola")),
    list(id = "mo2", namn = "Kunskaper, kompetenser och utbildning",
         kpier = c("gymnasiebehorighet")),
    list(id = "mo3", namn = "Arbete, arbetsförhållanden och arbetsmiljö",
         kpier = c("arbetsloshet", "sysselsattning")),
    list(id = "mo4", namn = "Inkomster och försörjningsmöjligheter",
         kpier = c("lag_ek_standard", "barnfattigdom")),
    list(id = "mo5", namn = "Boende och närmiljö",
         kpier = c("radsla_ute")),
    list(id = "mo6", namn = "Levnadsvanor",
         kpier = c("rokning", "fysisk_aktivitet")),
    list(id = "mo7", namn = "Kontroll, inflytande och delaktighet",
         kpier = c("lag_tillit")),
    list(id = "mo8", namn = "En jämlik och hälsofrämjande hälso- och sjukvård",
         kpier = c("avstatt_tandvard")),
    list(id = "halsa", namn = "Hälsan i befolkningen",
         kpier = c("sjalvskattad_halsa", "medellivslangd"))
  )
)
