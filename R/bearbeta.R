# bearbeta.R — Aggregera daglig data, kör signalmodeller, bygg JSON-struktur
#
# Förutsätter att följande är laddade (via pipeline.R eller manuellt):
#   paket.R, gemensam/helgdagar.R, gemensam/signal-modell.R,
#   teman/register.R, gemensam/formatering.R, gemensam/aggregering.R,
#   gemensam/analystext.R
#
# Input:  data/radata-hos.rds, data/radata-dept.rds
# Output: data/bearbetad-hos.rds

source("paket.R")
source("R/gemensam/helgdagar.R")
source("R/gemensam/signal-modell.R")
source("R/teman/register.R")
source("R/gemensam/formatering.R")
source("R/gemensam/aggregering.R")
source("R/gemensam/analystext.R")
source("R/gemensam/bygg-sektion.R")
source("R/teman/kolada/bearbeta.R")
source("R/gemensam/ranking-tema.R")
source("R/teman/folkhalsa/bearbeta.R")
source("R/teman/befolkning/bearbeta.R")
source("R/teman/ekonomi/bearbeta.R")

# ══════════════════════════════════════════════
#  LADDA DATA
# ══════════════════════════════════════════════
#  SÖM FÖR DATAKÄLLA: dessa två .rds-filer ÄR kontraktet mellan
#  inläsningssteget och bearbetningen. Demogeneratorn (R/hamta/demo-data.R)
#  skriver dem idag. För att koppla in en riktig källa (databas/API):
#  byt ut hämtningssteget så att det skriver SAMMA struktur:
#    radata-hos.rds : tibble(datum, <ett kolumn per total-KPI i kpi_meta$id>)
#    radata-dept.rds: tibble(datum, kpi_id, dept, varde)  [långformat]
#  Resten av pipelinen (denna fil, signal-modell, export) är källagnostisk.

radata <- readRDS("data/radata-hos.rds")
dept_radata <- readRDS("data/radata-dept.rds")

rapport_datum <- max(radata$datum)
start_datum   <- min(radata$datum)
slut_datum    <- rapport_datum

# Faktisk körningstidpunkt (ersätter tidigare hårdkodat "08:00")
kor_tidpunkt  <- format(Sys.time(), "%H:%M")

# ══════════════════════════════════════════════
#  PIVOTISERA OCH AGGREGERA
# ══════════════════════════════════════════════

dag_full <- radata |>
  pivot_longer(-datum, names_to = "kpi_id", values_to = "varde") |>
  left_join(kpi_meta |> select(id, aggregering, enhet), by = c("kpi_id" = "id")) |>
  mutate(
    vecka_start   = floor_date(datum, "week", week_start = 1),
    manad_start   = floor_date(datum, "month"),
    kvartal_start = floor_date(datum, "quarter"),
    ar_start      = floor_date(datum, "year")
  )

agg_dag     <- aggregera_period(dag_full, "datum")
agg_vecka   <- aggregera_period(dag_full, "vecka_start")
agg_manad   <- aggregera_period(dag_full, "manad_start")
agg_kvartal <- aggregera_period(dag_full, "kvartal_start")
agg_ar      <- aggregera_period(dag_full, "ar_start")

# ══════════════════════════════════════════════
#  FILTRERA KOMPLETTA PERIODER
# ══════════════════════════════════════════════

perioder <- filtrera_kompletta_perioder(rapport_datum)

agg_vecka   <- agg_vecka   |> filter(period <= perioder$max$vecka)
agg_manad   <- agg_manad   |> filter(period <= perioder$max$manad)
agg_kvartal <- agg_kvartal |> filter(period <= perioder$max$kvartal)
agg_ar      <- agg_ar      |> filter(period <= perioder$max$ar)

# ══════════════════════════════════════════════
#  SIGNALBERÄKNING — GLM + Conformal Prediction
# ══════════════════════════════════════════════

kalender <- bygg_kalender(start_datum, slut_datum)
cat("K\u00f6r signalmodeller...\n")

# ── Total-KPI signaler ──
pred <- list(dag = tibble(), vecka = tibble(), manad = tibble(),
             kvartal = tibble(), ar = tibble())

for (i in seq_len(nrow(kpi_meta))) {
  kid <- kpi_meta$id[i]
  df  <- radata |> transmute(ds = datum, y = .data[[kid]])
  res <- kor_kpi_signal(df, kalender, kpi_meta$familj[i], kpi_meta$aggregering[i])
  for (niva in names(pred)) {
    pred[[niva]] <- bind_rows(pred[[niva]], res[[niva]] |> mutate(kpi_id = kid))
  }
  cat(sprintf("  %s (%s): klar\n", kid, res$modell_namn))
}

# ── Avdelningssignaler ──
dept_pred <- list(dag = tibble(), vecka = tibble(), manad = tibble(),
                  kvartal = tibble(), ar = tibble())

for (i in seq_len(nrow(kpi_meta))) {
  kid  <- kpi_meta$id[i]
  fam  <- kpi_meta$familj[i]
  atyp <- kpi_meta$aggregering[i]
  depts <- dept_radata |> filter(kpi_id == kid) |> pull(dept) |> unique()

  for (d in depts) {
    dept_id <- paste0(kid, "-", tolower(gsub(" ", "", d)))
    df <- dept_radata |>
      filter(kpi_id == kid, dept == d) |>
      transmute(ds = datum, y = varde)
    res <- kor_kpi_signal(df, kalender, fam, atyp)
    for (niva in names(dept_pred)) {
      dept_pred[[niva]] <- bind_rows(dept_pred[[niva]],
        res[[niva]] |> mutate(kpi_id = dept_id))
    }
  }
  cat(sprintf("  %s avdelningar: klar\n", kid))
}

# ── Kontext för den generiska byggaren (bygg-sektion.R) ──
# All run-specifik indata skickas explicit — inga closure-beroenden.
ctx <- list(
  kpi_meta      = kpi_meta,
  dept_radata   = dept_radata,
  dept_pred     = dept_pred,
  rapport_datum = rapport_datum,
  kor_tidpunkt  = kor_tidpunkt
)

# ══════════════════════════════════════════════
#  FÖRÄNDRING OCH STATUS
# ══════════════════════════════════════════════

agg_dag     <- agg_dag     |> lagg_till_forandring() |> lagg_till_signal(pred$dag)
agg_vecka   <- agg_vecka   |> lagg_till_forandring() |> lagg_till_signal(pred$vecka)
agg_manad   <- agg_manad   |> lagg_till_forandring() |> lagg_till_signal(pred$manad)
agg_kvartal <- agg_kvartal |> lagg_till_forandring() |> lagg_till_signal(pred$kvartal)
agg_ar      <- agg_ar      |> lagg_till_forandring() |> lagg_till_signal(pred$ar)

# ══════════════════════════════════════════════
#  BYGG VY-STRUKTUR + UNDERAVDELNINGAR
# ══════════════════════════════════════════════
# Flyttat till R/gemensam/bygg-sektion.R (bygg_vy + generera_undernivaer).
# Anropas nedan med ctx — ingen closure mot yttre scope.

# ══════════════════════════════════════════════
#  PERIODETIKETTER
# ══════════════════════════════════════════════

period_dag <- paste0(day(rapport_datum), " ", sv_man[month(rapport_datum)],
                     " ", year(rapport_datum))

senaste_vecka_d <- max(agg_vecka$period)
period_vecka <- paste0("vecka ", isoweek(senaste_vecka_d), ", ",
                       isoyear(senaste_vecka_d))

senaste_manad_d <- max(agg_manad$period)
period_manad <- paste0(sv_man[month(senaste_manad_d)], " ",
                       year(senaste_manad_d)) |>
  str_to_sentence()

senaste_kvartal_d <- max(agg_kvartal$period)
period_kvartal <- paste0("kvartal ", quarter(senaste_kvartal_d), ", ",
                         year(senaste_kvartal_d))

senaste_ar_d <- max(agg_ar$period)
period_ar <- as.character(year(senaste_ar_d))

# ══════════════════════════════════════════════
#  GENERERA ALLA VYER
# ══════════════════════════════════════════════

# Dagvyn visar ALLTID minst ett \u00e5r (365 dagar) \u2014 s\u00e4song/kontext, inte bara
# senaste tiden. Conformal-signaler finns f\u00f6r hela dagsserien.
agg_dag_ar <- agg_dag |>
  group_by(kpi_id) |>
  slice_tail(n = 365) |>
  ungroup()

resultat <- list(
  dag     = bygg_vy(agg_dag_ar,  "dag",     "Dags\u00f6versikt",      period_dag,
                    "f\u00f6reg. dag",     etikett_dag,     999, pred$dag,
                    ctx = ctx),
  vecka   = bygg_vy(agg_vecka,   "vecka",   "Vecko\u00f6versikt",     period_vecka,
                    "f\u00f6reg. vecka",   etikett_vecka,   999, pred$vecka,
                    dag_full, pred$dag,
                    perioder$max$vecka, perioder$nasta$vecka, ctx = ctx),
  manad   = bygg_vy(agg_manad,   "manad",   "M\u00e5nads\u00f6versikt",    period_manad,
                    "f\u00f6reg. m\u00e5nad",   etikett_manad,   999, pred$manad,
                    dag_full, pred$dag,
                    perioder$max$manad, perioder$nasta$manad, ctx = ctx),
  kvartal = bygg_vy(agg_kvartal, "kvartal", "Kvartals\u00f6versikt",  period_kvartal,
                    "f\u00f6reg. kvartal", etikett_kvartal, 999, pred$kvartal,
                    dag_full, pred$dag,
                    perioder$max$kvartal, perioder$nasta$kvartal, ctx = ctx),
  ar      = bygg_vy(agg_ar,      "ar",      "\u00c5rs\u00f6versikt",       period_ar,
                    "f\u00f6reg. \u00e5r",      etikett_ar,      999, pred$ar,
                    dag_full, pred$dag,
                    perioder$max$ar, perioder$nasta$ar, ctx = ctx)
)

# ── Dag-vy: referensserie (samma år föregående år) ──
dag_start  <- min(agg_dag_ar$period)
dag_slut   <- max(agg_dag_ar$period)
ref_start  <- dag_start - years(1)
ref_slut   <- dag_slut - years(1)

agg_dag_ref <- agg_dag |>
  filter(period >= ref_start, period <= ref_slut)

for (si in seq_along(resultat$dag$sektioner)) {
  for (ki in seq_along(resultat$dag$sektioner[[si]]$kpier)) {
    kid <- resultat$dag$sektioner[[si]]$kpier[[ki]]$id
    km  <- kpi_meta |> filter(id == kid)
    dec <- if (km$enhet == "procent") 1 else 0

    ref_df <- agg_dag_ref |>
      filter(kpi_id == kid) |>
      arrange(period) |>
      left_join(
        pred$dag |> filter(kpi_id == kid) |> select(-kpi_id),
        by = "period"
      ) |>
      transmute(
        period  = format(period, "%Y-%m-%d"),
        etikett = etikett_dag(period),
        varde,
        yhat          = round(yhat, dec),
        yhat_lower_80 = round(yhat_lower_80, dec),
        yhat_upper_80 = round(yhat_upper_80, dec),
        yhat_lower    = round(yhat_lower, dec),
        yhat_upper    = round(yhat_upper, dec),
        signal
      ) |>
      as.data.frame()

    if (nrow(ref_df) > 0) {
      resultat$dag$sektioner[[si]]$kpier[[ki]]$referens_serie <- ref_df
    }
  }
}

# ══════════════════════════════════════════════
#  BEFOLKNING & FOLKHÄLSA — Enbart i årsvyn, FÖRST i sektionsordningen
#  (kategorin Behov & befolkning inleder rapporten i taxonomin;
#  befolkning före folkhälsa, samma ordning som taxonomin)
# ══════════════════════════════════════════════

folkhalsa_sektioner <- bearbeta_folkhalsa()
if (length(folkhalsa_sektioner) > 0) {
  resultat$ar$sektioner <- c(folkhalsa_sektioner, resultat$ar$sektioner)
}

befolkning_sektioner <- bearbeta_befolkning()
if (length(befolkning_sektioner) > 0) {
  resultat$ar$sektioner <- c(befolkning_sektioner, resultat$ar$sektioner)
}

# ══════════════════════════════════════════════
#  EKONOMI — Enbart i årsvyn, efter de dagliga sektionerna
#  (kategorin Resurser & förutsättningar, före Externa rapporter)
# ══════════════════════════════════════════════

ekonomi_sektioner <- bearbeta_ekonomi()
if (length(ekonomi_sektioner) > 0) {
  resultat$ar$sektioner <- c(resultat$ar$sektioner, ekonomi_sektioner)
}

# ══════════════════════════════════════════════
#  KOLADA: HÄLSO- OCH SJUKVÅRDSRAPPORTEN — Enbart i årsvyn
# ══════════════════════════════════════════════

kolada_sektioner <- bearbeta_kolada()
if (length(kolada_sektioner) > 0) {
  resultat$ar$sektioner <- c(resultat$ar$sektioner, kolada_sektioner)

  # Uppdatera global analys f\u00f6r \u00e5rsvyn med NPE
  alla_kpier_ar <- unlist(lapply(resultat$ar$sektioner, \(s) lapply(s$kpier, \(k) k$status)), use.names = FALSE)
  n_rod_total <- sum(alla_kpier_ar == "rod")
  n_gul_total <- sum(alla_kpier_ar == "gul")
  status_str <- if (n_rod_total == 0 && n_gul_total == 0) "en stabil situation utan avvikelser"
                else if (n_rod_total == 0) "en i huvudsak stabil situation"
                else if (n_rod_total <= 2) "en anstr\u00e4ngd men hanterbar situation"
                else "en anstr\u00e4ngd situation med flera avvikelser"
  resultat$ar$analys <- paste0(
    "H\u00e4lso- och sjukv\u00e5rden i Region Halland uppvisar ", status_str,
    " under ", tolower(period_ar), ".")
}

# ══════════════════════════════════════════════
#  SPARA
# ══════════════════════════════════════════════

saveRDS(resultat, "data/bearbetad-hos.rds")
cat("Bearbetning klar: 5 vyer genererade\n")
