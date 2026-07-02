# ranking-tema.R — Generisk byggare för ranking-teman (årsvyn)
#
# Bygger EN sektion med delar utifrån ett tema (config) och en .rds-fil med:
#   $indikatorer : id, namn, title, beskrivning, kalla, enhet,
#                  riktning ("hog" | "lag" | "neutral")
#   $data        : kpi, region_id, region, ar (int, sorterings-/periodår),
#                  etikett (visningsperiod, t.ex. "2021-2024" eller "2024"),
#                  varde
#
# Signal: ranking bland regionerna mot målet topp 3 (i fas = topp 3,
# bevaka = 4–7, avvikelse = 8+; trösklar från tema$ranking). Neutrala
# mått (riktning = "neutral") rankas inte: de får grått chip (utan_mal),
# ingen topp 3-zon och en beskrivande analystext.
#
# Tema-fält utöver kolada-mönstret:
#   $sektion_intro : function(n_kpi, n_delar) -> inledande mening i
#                    sektionsanalysen (källa och indelning beskrivs där)
#   $jmf_etikett   : etikett för förändringschippet ("år" eller "mätning")
#
# Används av teman/folkhalsa och teman/befolkning. Kräver dplyr.

bygg_ranking_sektion <- function(tema) {
  fil <- tema$datakalla
  if (!file.exists(fil)) {
    cat("OBS: ", fil, " saknas — hoppar över ", tema$namn, "\n", sep = "")
    return(NULL)
  }

  cat("Bygger ", tema$namn, "...\n", sep = "")
  src <- readRDS(fil)
  fokus <- tema$fokus_region
  riket <- tema$riket_id
  jmf_etikett <- tema$jmf_etikett %||% "år"

  dat <- src$data |> filter(!is.na(varde))

  riktning_for <- function(kpi_id) {
    r <- src$indikatorer$riktning[src$indikatorer$id == kpi_id]
    if (length(r) == 1) r else "hog"
  }

  # Rank för fokusregionen ett givet år, bland regioner med värde (ej Riket).
  rank_ar <- function(df_ar, riktning) {
    df_r <- df_ar |> filter(region_id != riket)
    i <- which(df_r$region_id == fokus)
    if (length(i) == 0 || riktning == "neutral") return(NULL)
    v <- if (riktning == "lag") df_r$varde else -df_r$varde
    list(rank = rank(v, ties.method = "min")[i], n = nrow(df_r))
  }

  g_gron <- tema$ranking$grans_gron
  g_gul  <- tema$ranking$grans_gul
  sig_fn <- function(rank, n) {
    if (is.null(rank)) return("gron")
    if (rank <= g_gron) "gron" else if (rank <= g_gul) "gul" else "rod"
  }

  bygg_kpi <- function(kpi_id) {
    meta <- src$indikatorer |> filter(id == kpi_id)
    if (nrow(meta) == 0) return(NULL)
    d <- dat |> filter(kpi == kpi_id)
    d_fokus <- d |> filter(region_id == fokus) |> arrange(ar)
    if (nrow(d_fokus) < 1) return(NULL)

    riktning <- riktning_for(kpi_id)
    enhet <- meta$enhet[1]
    dec <- if (enhet == "procent") 1 else if (max(abs(d_fokus$varde)) >= 1000) 0 else 1
    namn <- meta$namn[1]

    rank_per_ar <- lapply(d_fokus$ar, function(a) rank_ar(d |> filter(ar == a), riktning))
    signaler <- vapply(rank_per_ar, function(r) sig_fn(r$rank, r$n), character(1))

    tidsserie <- lapply(seq_len(nrow(d_fokus)), function(j) {
      list(period  = paste0(d_fokus$ar[j], "-01-01"),
           etikett = d_fokus$etikett[j],
           varde   = round(d_fokus$varde[j], dec),
           signal  = signaler[j])
    })

    senaste_ar  <- max(d_fokus$ar)
    senaste_val <- d_fokus$varde[d_fokus$ar == senaste_ar]
    senaste_eti <- d_fokus$etikett[d_fokus$ar == senaste_ar]
    senaste_rk  <- rank_per_ar[[length(rank_per_ar)]]
    status      <- signaler[length(signaler)]
    forandring  <- if (nrow(d_fokus) >= 2) {
      round(senaste_val - d_fokus$varde[nrow(d_fokus) - 1], dec)
    } else 0

    d_riket <- d |> filter(region_id == riket) |> arrange(ar)
    riket_serie <- if (nrow(d_riket) > 0) {
      lapply(seq_len(nrow(d_riket)), function(j) {
        list(period  = paste0(d_riket$ar[j], "-01-01"),
             etikett = d_riket$etikett[j],
             varde   = round(d_riket$varde[j], dec))
      })
    } else NULL
    riket_senaste <- if (nrow(d_riket) > 0) tail(d_riket$varde, 1) else NA

    referens <- if (!is.na(riket_senaste)) {
      list(period  = paste0(senaste_ar, "-01-01"),
           etikett = paste0("Riket ", tail(d_riket$etikett, 1)),
           varde   = round(riket_senaste, dec),
           forandring = round(senaste_val - riket_senaste, dec))
    } else NULL

    # Topp 3-band (riktningsmedvetet) — inte för neutrala mått
    topp3_band <- if (riktning == "neutral") NULL else {
      d_reg <- d |> filter(region_id != riket)
      ar_lista <- sort(unique(d_reg$ar))
      rader <- lapply(ar_lista, function(a) {
        v <- d_reg$varde[d_reg$ar == a]
        if (length(v) < 2) return(NULL)
        sorterat <- sort(v, decreasing = (riktning == "hog"))
        tredje <- sorterat[min(3, length(sorterat))]
        list(period  = paste0(a, "-01-01"),
             etikett = as.character(a),
             lo = round(min(sorterat[1], tredje), dec),
             hi = round(max(sorterat[1], tredje), dec))
      })
      rader <- Filter(Negate(is.null), rader)
      if (length(rader) >= 2) rader else NULL
    }

    kontext_serier <- d |>
      filter(!region_id %in% c(fokus, riket)) |>
      arrange(region, ar) |>
      group_by(region_id, region) |>
      group_map(function(g, key) {
        list(id   = key$region_id,
             namn = key$region,
             tidsserie = lapply(seq_len(nrow(g)), function(j) {
               list(period  = paste0(g$ar[j], "-01-01"),
                    etikett = g$etikett[j],
                    varde   = round(g$varde[j], dec))
             }))
      })

    status_fg <- if (length(signaler) >= 2) signaler[length(signaler) - 1] else status

    # Analystext: position och nivå, målsättning, utveckling, relativt läge.
    # Fast ordning; neutrala mått får beskrivande text. Inga em-streck.
    fmt_v <- function(x) format(round(x, dec), big.mark = " ", decimal.mark = ",",
                                trim = TRUE, scientific = FALSE)
    suffix <- if (enhet == "procent") " procent" else ""

    i0 <- max(1, nrow(d_fokus) - 5)
    v0 <- d_fokus$varde[i0]; eti0 <- d_fokus$etikett[i0]

    analystext <- if (riktning == "neutral") {
      utv <- if (nrow(d_fokus) >= 2) {
        rel <- abs(senaste_val - v0) / max(abs(v0), 1e-9)
        if (rel < 0.03) paste0(" Nivån har varit i huvudsak stabil sedan ", eti0, ".")
        else paste0(" Sedan ", eti0, " har nivån ",
                    if (senaste_val > v0) "ökat" else "minskat",
                    " från ", fmt_v(v0), " till ", fmt_v(senaste_val), ".")
      } else ""
      riket_txt <- if (is.na(riket_senaste)) "" else {
        paste0(" Rikets nivå är ", fmt_v(riket_senaste), suffix, ".")
      }
      paste0(namn, " ligger på ", fmt_v(senaste_val), suffix, " (", senaste_eti, ").",
             utv, riket_txt,
             " Måttet beskriver befolkningens struktur eller behov och färgsätts därför inte.")
    } else {
      r <- senaste_rk$rank; m <- senaste_rk$n

      nulage <- paste0("Region Halland redovisar ett utfall på ",
                       fmt_v(senaste_val), suffix, " (", senaste_eti, ")",
                       " och placerar sig på plats ", r, " av ", m,
                       " bland regionerna.")

      mal_txt <- if (status == "gron") {
        " Placeringen möter målsättningen om en plats bland de tre främsta regionerna."
      } else if (status == "gul") {
        paste0(" Resultatet ligger strax under målsättningen om en plats bland de tre",
               " främsta: regionen står utanför topp 3 men håller sig i det övre skiktet.")
      } else {
        " Resultatet ligger under målsättningen om en plats bland de tre främsta regionerna."
      }

      utv_txt <- if (nrow(d_fokus) >= 2) {
        f <- if (riktning == "lag") v0 - senaste_val else senaste_val - v0
        rel <- abs(f) / max(abs(v0), 1e-9)
        if (rel < 0.03) paste0(" Nivån har varit i huvudsak stabil sedan ", eti0, ".")
        else if (f > 0) paste0(" Sedan ", eti0, " har utfallet förbättrats, från ",
                               fmt_v(v0), " till ", fmt_v(senaste_val), ".")
        else paste0(" Sedan ", eti0, " har utfallet försämrats, från ",
                    fmt_v(v0), " till ", fmt_v(senaste_val), ".")
      } else ""

      pos_txt <- {
        i0r <- max(1, length(rank_per_ar) - 5)
        r0 <- rank_per_ar[[i0r]]$rank
        if (!is.null(r0) && length(rank_per_ar) >= 4) {
          d_r <- r0 - r
          if (d_r >= 2) paste0(" Placeringen bland regionerna har samtidigt stärkts, från plats ",
                               r0, " till plats ", r, ".")
          else if (d_r <= -2) paste0(" Placeringen bland regionerna har samtidigt försvagats, från plats ",
                                     r0, " till plats ", r, ".")
          else ""
        } else ""
      }

      riket_txt <- if (is.na(riket_senaste)) "" else {
        diff <- senaste_val - riket_senaste
        battre <- if (riktning == "lag") diff < 0 else diff > 0
        if (abs(diff) < 0.01 * max(abs(riket_senaste), 1e-9)) {
          paste0(" Sett till riket ligger regionen i paritet med rikssnittet på ",
                 fmt_v(riket_senaste), suffix, ".")
        } else if (battre) {
          paste0(" Sett till riket står sig regionen bättre än rikssnittet på ",
                 fmt_v(riket_senaste), suffix, ".")
        } else {
          paste0(" Sett till riket står sig regionen sämre än rikssnittet på ",
                 fmt_v(riket_senaste), suffix, ".")
        }
      }

      paste0(nulage, mal_txt, utv_txt, pos_txt, riket_txt)
    }

    kpi_obj <- list(
      id          = paste0(tema$kpi_prefix, tolower(kpi_id)),
      namn        = namn,
      enhet       = enhet,
      inverterad  = riktning == "lag",
      senaste     = round(senaste_val, dec),
      forandring  = forandring,
      forandringar = list(list(etikett = jmf_etikett, varde = forandring)),
      status      = status,
      status_fg   = status_fg,
      analystext  = analystext,
      beskrivning = paste0(meta$title[1], " — ", meta$beskrivning[1],
                           " Källa: ", meta$kalla[1], "."),
      tidsserie   = tidsserie,
      kontext_serier = kontext_serier
    )
    if (!is.null(riket_serie)) kpi_obj$riket_serie <- riket_serie
    if (!is.null(referens))    kpi_obj$referens    <- referens
    if (!is.null(topp3_band))  kpi_obj$topp3_band  <- topp3_band
    if (!is.null(senaste_rk)) {
      kpi_obj$rank    <- senaste_rk$rank
      kpi_obj$rank_av <- senaste_rk$n
    }
    if (riktning == "neutral") kpi_obj$utan_mal <- TRUE
    kpi_obj
  }

  # ── Översiktsbedömningar (rankade mått; neutrala redovisas separat) ──
  bedom_nulage <- function(n_gron, n_rod, n) {
    if (n_rod == 0 && n_gron >= n / 2) "ett starkt läge"
    else if (n_gron >= 0.4 * n) "ett förhållandevis starkt läge"
    else if (n_rod > n_gron) "ett ansträngt läge"
    else "ett blandat läge"
  }
  bedom_utveckling <- function(d_gron, d_rod) {
    if (d_gron > 0) paste0("en förbättring jämfört med föregående mätning (", d_gron, " fler i fas)")
    else if (d_gron < 0) paste0("en försvagning jämfört med föregående mätning (", abs(d_gron), " färre i fas)")
    else if (d_rod < 0) "en viss förbättring jämfört med föregående mätning (färre utanför)"
    else if (d_rod > 0) "en viss försvagning jämfört med föregående mätning (fler utanför)"
    else "ett i stort sett oförändrat läge jämfört med föregående mätning"
  }

  ar_neutral <- function(k) isTRUE(k$utan_mal)

  del_analys <- function(namn, kpier) {
    rankade  <- Filter(Negate(ar_neutral), kpier)
    n_neutral <- length(kpier) - length(rankade)
    if (length(rankade) == 0) {
      return(paste0(namn, " omfattar ", length(kpier),
                    if (length(kpier) == 1) " beskrivande mått" else " beskrivande mått",
                    " utan målriktning. De redovisar befolkningens struktur",
                    " och behov och färgsätts inte."))
    }
    statusar <- vapply(rankade, function(k) k$status, character(1))
    fg       <- vapply(rankade, function(k) k$status_fg %||% k$status, character(1))
    n <- length(rankade)
    n_gron <- sum(statusar == "gron"); n_gul <- sum(statusar == "gul"); n_rod <- sum(statusar == "rod")
    d_gron <- n_gron - sum(fg == "gron"); d_rod <- n_rod - sum(fg == "rod")
    neutral_txt <- if (n_neutral > 0) paste0(" Därtill redovisas ", n_neutral,
                                             " beskrivande mått utan målriktning.") else ""
    paste0(namn, " omfattar ", n,
           if (n == 1) " rankad indikator." else " rankade indikatorer.",
           " Av dessa är ", n_gron,
           " i fas med målet topp ", g_gron, ", ", n_gul,
           " ligger under bevakning (plats ", g_gron + 1, "–", g_gul,
           ") och ", n_rod, " hamnar utanför (plats ", g_gul + 1,
           " eller lägre). Sammantaget visar delen ",
           bedom_nulage(n_gron, n_rod, n), ", och ", bedom_utveckling(d_gron, d_rod), ".",
           neutral_txt)
  }

  # ── Bygg delar i konfigurerad ordning + fånga oklassade ──
  klassade <- unlist(lapply(tema$delar, function(d) d$kpier))
  oklassade <- setdiff(src$indikatorer$id, klassade)
  del_lista <- tema$delar
  if (length(oklassade) > 0) {
    cat("  OBS: ", length(oklassade), " oklassade KPI:er läggs i Övrigt: ",
        paste(oklassade, collapse = ", "), "\n", sep = "")
    del_lista <- c(del_lista, list(list(id = paste0(tema$id, "-ovrigt"),
                                        namn = "Övrigt", kpier = oklassade)))
  }

  alla_kpier <- list()
  delar <- list()
  for (del in del_lista) {
    kpier <- Filter(Negate(is.null), lapply(del$kpier, bygg_kpi))
    if (length(kpier) == 0) next
    statusar <- vapply(kpier, function(k) k$status, character(1))
    delar[[length(delar) + 1]] <- list(
      id      = del$id,
      namn    = del$namn,
      analys  = del_analys(del$namn, kpier),
      kpi_ids = as.list(vapply(kpier, function(k) k$id, character(1)))
    )
    alla_kpier <- c(alla_kpier, kpier)
    cat(sprintf("  %s: %d indikatorer (%d grön, %d gul, %d röd)\n",
                del$namn, length(kpier), sum(statusar == "gron"),
                sum(statusar == "gul"), sum(statusar == "rod")))
  }

  # Sektionsövergripande analys: temats intro + statusräkning på rankade mått
  rankade_t <- Filter(Negate(ar_neutral), alla_kpier)
  statusar <- vapply(rankade_t, function(k) k$status, character(1))
  fg_alla  <- vapply(rankade_t, function(k) k$status_fg %||% k$status, character(1))
  n_gron_t <- sum(statusar == "gron"); n_gul_t <- sum(statusar == "gul"); n_rod_t <- sum(statusar == "rod")
  n_neutral_t <- length(alla_kpier) - length(rankade_t)
  neutral_txt <- if (n_neutral_t > 0) paste0(" Därtill redovisas ", n_neutral_t,
                                             " beskrivande mått utan målriktning.") else ""
  sek_analys <- paste0(
    tema$sektion_intro(length(alla_kpier), length(delar)), " ",
    "Region Halland är i fas med målet topp ", g_gron, " för ", n_gron_t,
    if (length(rankade_t) > 0) paste0(" av ", length(rankade_t), " rankade indikatorer") else " indikatorer",
    ", ligger under bevakning för ", n_gul_t,
    " och utanför för ", n_rod_t,
    ". Sammantaget visar kapitlet ", bedom_nulage(n_gron_t, n_rod_t, max(length(rankade_t), 1)),
    ", och ", bedom_utveckling(n_gron_t - sum(fg_alla == "gron"),
                               n_rod_t - sum(fg_alla == "rod")), ".",
    neutral_txt)

  cat(tema$namn, "tillagd i årsvyn\n")

  list(list(
    id     = tema$id,
    namn   = tema$namn,
    analys = sek_analys,
    kpier  = alla_kpier,
    delar  = delar
  ))
}
