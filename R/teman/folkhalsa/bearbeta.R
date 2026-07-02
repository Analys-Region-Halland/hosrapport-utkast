# bearbeta.R — Folkhälsa: tunn wrapper över den generiska ranking-byggaren
# (R/gemensam/ranking-tema.R). All logik — topp 3-ranking, riket som
# referens, kontextlinjer, analystexter — bor i bygg_ranking_sektion();
# temats indelning och texter bor i config.R.

bearbeta_folkhalsa <- function() bygg_ranking_sektion(folkhalsa_tema)
