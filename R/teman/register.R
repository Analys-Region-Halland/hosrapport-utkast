# register.R — Samlar alla tema-konfigurationer
# En enda källa för kpi_meta, dept_config och sektioner.
#
# Ny sektion? Lägg till tre rader:
#   1. source("R/teman/{namn}/config.R")
#   2. Lägg till i alla_teman
#   3. Klar.

source("R/teman/primarvard/config.R")
source("R/teman/akutflode/config.R")
source("R/teman/slutenvard/config.R")
source("R/teman/personal/config.R")
source("R/teman/kolada/config.R")
source("R/teman/folkhalsa/config.R")
source("R/teman/befolkning/config.R")

# Teman med daglig data (conformal prediction).
# Ordningen här styr visningsordningen i rapporten.
dagliga_teman <- list(primarvard, akutflode, slutenvard, personal)

# Alla teman (inklusive specialfall som Kolada- och FoHM-årsindikatorerna)
alla_teman <- c(dagliga_teman, list(kolada_tema, folkhalsa_tema, befolkning_tema))

# ── kpi_meta: en rad per KPI med sektion-info ──
kpi_meta <- bind_rows(lapply(dagliga_teman, function(tema) {
  tema$kpier |> mutate(sektion_id = tema$id, sektion_namn = tema$namn)
}))

# ── dept_config: avdelningsnamn per KPI ──
dept_config <- unlist(
  lapply(dagliga_teman, function(tema) tema$avdelningar),
  recursive = FALSE
)
