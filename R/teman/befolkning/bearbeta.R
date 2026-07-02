# bearbeta.R — Befolkning & vårdbehov: tunn wrapper över den generiska
# ranking-byggaren (R/gemensam/ranking-tema.R). Neutrala mått (demografi,
# behovsindex) hanteras där via riktning = "neutral" i metadatat.

bearbeta_befolkning <- function() bygg_ranking_sektion(befolkning_tema)
