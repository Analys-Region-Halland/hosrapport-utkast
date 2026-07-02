import { useEffect, useRef, useState } from "react";
import * as d3 from "d3";
import type { Section, KpiData, TidsseriePoint } from "../types";
import { SIGNAL_COLORS, SIGNAL_BG, SIGNAL_LABELS, FONT, FONT_MONO, NEUTRAL_LINE, signalColor } from "../charts/constants";
import { fmtVarde, fmtSuffix } from "../utils/format";
import { kortBeskrivning } from "../utils/definitions";
import { useResizeWidth } from "../hooks/useResizeWidth";
import MiniTrend from "./MiniTrend";

// ════════════════════════════════════════════════════════════
//  SignalTimeline — överblick som signal-lanes (state timeline).
//
//  En lane per indikator: vänster = namn · nuvärde · status; höger =
//  en tidslinje där intilliggande perioder med SAMMA signal smälter ihop
//  till proportionerliga fält. Skalar till vilken täthet som helst (31
//  dagar eller 365) — allt i EN vy, inga tunna cellsträck, ingen scroll.
//  Hover var som helst på lanen → exakt periodvärde + förväntat + föreg.
//  år + MiniTrend. Hover på namnet → vad indikatorn mäter.
// ════════════════════════════════════════════════════════════

const parseDate = d3.timeParse("%Y-%m-%d");

interface Props {
  sektioner: Section[];
  vy: string;
  visaDagar?: boolean;
  onCellClick?: (kpi: KpiData) => void;
}

type Hover =
  | { kind: "cell"; kpi: KpiData; serie: TidsseriePoint[]; refSerie?: TidsseriePoint[]; point?: TidsseriePoint; etikett: string; prevYear: number | null; x: number; yTop: number; yBot: number }
  | { kind: "name"; kpi: KpiData; x: number; yTop: number; yBot: number }
  | { kind: "status"; kpi: KpiData; x: number; yTop: number; yBot: number };

function aktivSerie(kpi: KpiData, visaDagar: boolean): TidsseriePoint[] {
  return visaDagar && kpi.dagar && kpi.dagar.length > 0 ? kpi.dagar : kpi.tidsserie;
}

function prevYearValue(serie: TidsseriePoint[], period: string, effVy: string): number | null {
  const cur = parseDate(period);
  if (!cur) return null;
  const target = new Date(cur.getFullYear() - 1, cur.getMonth(), cur.getDate()).getTime();
  const tol = effVy === "dag" ? 4 : effVy === "vecka" ? 6 : effVy === "manad" ? 20 : effVy === "kvartal" ? 50 : 220;
  let best: number | null = null, bestDiff = Infinity;
  for (const p of serie) {
    const d = parseDate(p.period);
    if (!d) continue;
    const diff = Math.abs(d.getTime() - target) / 86_400_000;
    if (diff < bestDiff) { bestDiff = diff; best = p.varde; }
  }
  return best != null && bestDiff <= tol ? best : null;
}

function appendGlyph(parent: d3.Selection<SVGGElement, unknown, null, undefined>, cx: number, cy: number, sig: "gul" | "rod") {
  const d = sig === "gul"
    ? `M${cx},${cy - 4.2} L${cx + 4.2},${cy + 3.6} L${cx - 4.2},${cy + 3.6} Z`
    : `M${cx},${cy - 4.8} L${cx + 4.8},${cy} L${cx},${cy + 4.8} L${cx - 4.8},${cy} Z`;
  parent.append("path").attr("d", d).attr("fill", "rgba(255,255,255,0.96)").attr("pointer-events", "none");
}

export default function SignalTimeline({ sektioner, vy, visaDagar = false, onCellClick }: Props) {
  const [outerRef, width] = useResizeWidth();
  const svgRef = useRef<HTMLDivElement>(null);
  const [hover, setHover] = useState<Hover | null>(null);

  useEffect(() => {
    const el = svgRef.current;
    const allaKpier = sektioner.flatMap((s) => s.kpier);
    if (!el || width === 0 || allaKpier.length === 0) return;
    el.innerHTML = "";

    const effVy = visaDagar ? "dag" : vy;

    // Gemensam tidsaxel = den längsta aktiva serien.
    const langst = allaKpier.reduce<TidsseriePoint[]>((best, k) => {
      const s = aktivSerie(k, visaDagar);
      return s.length > best.length ? s : best;
    }, []);
    const kolumner = langst.map((p) => ({ period: p.period, etikett: p.etikett }));
    const N = kolumner.length;
    if (N === 0) return;

    const flera = sektioner.length > 1;
    const laneH = 18, topH = 34, sectionLabelH = 24;
    // Generös namnkolumn — namnen ska få plats utan att kapas
    const leftW = Math.min(364, Math.max(232, Math.round(width * 0.42)));
    const rightPad = 10;
    const x0 = leftW + 6;
    const timelineW = Math.max(40, width - x0 - rightPad);

    const xAt = (i: number) => Math.round(x0 + (i / N) * timelineW);
    const center = (i: number) => Math.round(x0 + ((i + 0.5) / N) * timelineW);

    // Namnen radbryts (max 2 rader) i stället för att kapas — hela texten
    // ska synas. Mindre typsnitt än tidigare; rader med 2 textrader blir högre.
    const nameFont = 11.5;
    const nameLineH = 12.5;
    const wrapName = (namn: string, maxW: number): string[] => {
      const maxChars = Math.max(8, Math.floor(maxW / (nameFont * 0.56)));
      if (namn.length <= maxChars) return [namn];
      const ord = namn.split(" ");
      let rad1 = ""; let i = 0;
      while (i < ord.length) {
        const prov = rad1 ? rad1 + " " + ord[i] : ord[i];
        if (prov.length <= maxChars || !rad1) { rad1 = prov; i++; } else break;
      }
      const rest = ord.slice(i).join(" ");
      return rest ? [rad1, rest] : [rad1];
    };

    // Radlayout — lanes sorteras efter status (avvikelse → bevaka → i fas)
    // inom varje grupp; variabel radhöjd för radbrutna namn.
    const STATUS_ORDNING: Record<string, number> = { rod: 0, gul: 1, gron: 2 };
    type Entry =
      | { kind: "section"; namn: string; y: number }
      | { kind: "row"; kpi: KpiData; y: number; h: number; lines: string[]; tagW: number; tagX: number };
    const entries: Entry[] = [];
    let yCur = topH;
    for (const sek of sektioner) {
      if (flera) { entries.push({ kind: "section", namn: sek.namn, y: yCur }); yCur += sectionLabelH; }
      const sorterade = [...sek.kpier].sort(
        (a, b) => (STATUS_ORDNING[a.status] ?? 3) - (STATUS_ORDNING[b.status] ?? 3),
      );
      for (const kpi of sorterade) {
        const statusLabel = SIGNAL_LABELS[kpi.status] || "";
        const tagW = Math.round(statusLabel.length * 9.5 * 0.6 + 14);
        const tagX = leftW - 8 - tagW;
        const lines = wrapName(kpi.namn, tagX - 18 - 8);
        const h = lines.length > 1 ? 44 : 34;
        entries.push({ kind: "row", kpi, y: yCur, h, lines, tagW, tagX });
        yCur += h;
      }
    }
    const totalH = yCur + 6;

    const svg = d3.select(el).append("svg")
      .attr("width", width).attr("height", totalH).style("display", "block")
      .style("shape-rendering", "geometricPrecision");
    const root = svg.append("g");
    const defs = svg.append("defs");

    // ── Delad tidsaxel överst ──
    root.append("line")
      .attr("x1", x0).attr("x2", x0 + timelineW).attr("y1", topH - 8).attr("y2", topH - 8)
      .attr("stroke", "#e8e8e4").attr("stroke-width", 1);
    // Datumetiketter: jämnt fördelade i pixelrymden, snäppta till närmaste
    // kolumn → bara så många som ryms, aldrig överlapp.
    const axFontPx = 9.5;
    const axLabels = kolumner.map((c) => c.etikett);
    const axMaxW = Math.max(...axLabels.map((l) => l.length)) * axFontPx * 0.6;
    const axPad = Math.min(axMaxW / 2, timelineW / 2);
    const axCount = Math.max(2, Math.floor(timelineW / (axMaxW + 22)) + 1);
    const axChosen = new Set<number>();
    for (let k = 0; k < axCount; k++) {
      const tx = x0 + axPad + (k / (axCount - 1)) * (timelineW - 2 * axPad);
      let bi = 0, bd = Infinity;
      for (let i = 0; i < N; i++) { const d = Math.abs(center(i) - tx); if (d < bd) { bd = d; bi = i; } }
      axChosen.add(bi);
    }
    for (const i of axChosen) {
      const cx = center(i);
      root.append("line").attr("x1", cx).attr("x2", cx).attr("y1", topH - 8).attr("y2", topH - 5)
        .attr("stroke", "#d8d8d4").attr("stroke-width", 0.8);
      root.append("text")
        .attr("x", Math.max(x0 + axPad, Math.min(x0 + timelineW - axPad, cx))).attr("y", topH - 13)
        .attr("text-anchor", "middle").attr("fill", "#9a9a96")
        .attr("font-family", FONT_MONO).attr("font-size", `${axFontPx}px`)
        .text(axLabels[i]);
    }

    // Gemensam markörlinje (visas vid hover)
    const marker = root.append("line")
      .attr("stroke", "#1a1a1a").attr("stroke-width", 1).attr("opacity", 0).attr("pointer-events", "none");

    const fitText = (sel: d3.Selection<SVGTextElement, unknown, null, undefined>, maxW: number) => {
      const node = sel.node();
      if (!node || node.getComputedTextLength() <= maxW) return;
      let t = node.textContent || "";
      while (t.length > 1 && node.getComputedTextLength() > maxW) { t = t.slice(0, -1); node.textContent = t + "…"; }
    };

    for (const e of entries) {
      if (e.kind === "section") {
        root.append("text")
          .attr("x", 2).attr("y", e.y + sectionLabelH - 8)
          .attr("fill", "#00664D").attr("font-family", FONT)
          .attr("font-size", "10.5px").attr("font-weight", 600).attr("letter-spacing", "0.06em")
          .text(e.namn.toUpperCase());
        continue;
      }

      const kpi = e.kpi;
      const rowY = Math.round(e.y);
      const rowH = e.h;
      const laneY = rowY + (rowH - laneH) / 2;
      const laneCy = laneY + laneH / 2;
      const serie = aktivSerie(kpi, visaDagar);
      const sigByPeriod = new Map<string, "gron" | "gul" | "rod" | undefined>();
      for (const p of serie) sigByPeriod.set(p.period, p.signal);

      // Statusprick + namn (radbrutet) + statustagg (jämte namnet)
      const statusLabel = SIGNAL_LABELS[kpi.status] || "";
      const statusColor = SIGNAL_COLORS[kpi.status] || "#888";
      const statusBg = SIGNAL_BG[kpi.status] || "#f0f0ee";
      const tagFont = 9.5, tagH = 15;
      const { tagW, tagX, lines } = e;

      root.append("circle").attr("cx", 7).attr("cy", laneCy).attr("r", 3.5)
        .attr("fill", statusColor);
      const lineYs = lines.length > 1
        ? [laneCy - nameLineH / 2 + 4, laneCy + nameLineH / 2 + 4]
        : [laneCy + 4];
      lines.forEach((rad, li) => {
        const label = root.append("text")
          .attr("x", 18).attr("y", lineYs[li])
          .attr("fill", "#2b2b2b").attr("font-family", FONT).attr("font-size", `${nameFont}px`)
          .text(rad);
        fitText(label, tagX - 18 - 8);
      });

      // ── Lane-bakgrund + klippt segmentlager (rundade ändar) ──
      const clipId = `lane-${kpi.id}-${rowY}`;
      defs.append("clipPath").attr("id", clipId)
        .append("rect").attr("x", x0).attr("y", laneY).attr("width", timelineW).attr("height", laneH).attr("rx", 4);
      root.append("rect").attr("x", x0).attr("y", laneY).attr("width", timelineW).attr("height", laneH)
        .attr("rx", 4).attr("fill", "#eeeeea");
      const lane = root.append("g").attr("clip-path", `url(#${clipId})`);

      // Slå ihop intilliggande perioder med samma signal → proportionerliga fält
      type Run = { sig: "gron" | "gul" | "rod" | undefined; start: number; end: number };
      const runs: Run[] = [];
      for (let i = 0; i < N; i++) {
        const sig = sigByPeriod.get(kolumner[i].period);
        const last = runs[runs.length - 1];
        if (last && last.sig === sig) last.end = i;
        else runs.push({ sig, start: i, end: i });
      }
      for (const run of runs) {
        const x = xAt(run.start);
        const w = Math.max(1, xAt(run.end + 1) - x);
        lane.append("rect").attr("x", x).attr("y", laneY).attr("width", w).attr("height", laneH)
          .attr("fill", signalColor(run.sig));
        if ((run.sig === "gul" || run.sig === "rod") && w >= 16) {
          appendGlyph(lane, x + w / 2, laneCy, run.sig);
        }
      }

      // ── Namn-hit (förklaring + klick) ──
      root.append("rect")
        .attr("x", 0).attr("y", rowY).attr("width", leftW - 2).attr("height", rowH)
        .attr("fill", "transparent").style("cursor", onCellClick ? "pointer" : "help")
        .attr("tabindex", 0).attr("role", "button")
        .attr("aria-label", `${kpi.namn}. ${kortBeskrivning(kpi) || "Visa i graf"}`)
        .on("mouseenter", (ev: MouseEvent) => {
          const r = (ev.currentTarget as SVGRectElement).getBoundingClientRect();
          setHover({ kind: "name", kpi, x: r.left + 20, yTop: r.top, yBot: r.bottom });
        })
        .on("mouseleave", () => setHover(null))
        .on("click", () => onCellClick?.(kpi))
        .on("keydown", (ev: KeyboardEvent) => { if (ev.key === "Enter" || ev.key === " ") { ev.preventDefault(); onCellClick?.(kpi); } });

      // ── Statustagg → hover förklarar hur status bedöms ──
      const tagG = root.append("g").style("cursor", "help");
      tagG.append("rect").attr("x", tagX).attr("y", laneCy - tagH / 2)
        .attr("width", tagW).attr("height", tagH).attr("rx", tagH / 2).attr("fill", statusBg);
      tagG.append("text").attr("x", tagX + tagW / 2).attr("y", laneCy + 3.3)
        .attr("text-anchor", "middle").attr("fill", statusColor)
        .attr("font-family", FONT).attr("font-size", `${tagFont}px`).attr("font-weight", 600)
        .text(statusLabel);
      tagG.append("rect").attr("x", tagX - 3).attr("y", laneCy - tagH / 2 - 3)
        .attr("width", tagW + 6).attr("height", tagH + 6).attr("fill", "transparent")
        .attr("tabindex", 0).attr("role", "img")
        .attr("aria-label", `Status ${statusLabel}. Förklaring av hur status bedöms.`)
        .on("mouseenter", (ev: MouseEvent) => {
          const r = (ev.currentTarget as SVGRectElement).getBoundingClientRect();
          setHover({ kind: "status", kpi, x: r.left + r.width / 2, yTop: r.top, yBot: r.bottom });
        })
        .on("mouseleave", () => setHover(null));

      // ── Hover-overlay över lanen → exakt period under muspekaren ──
      // referens_serie (samma period föregående år) finns t.ex. i dagvyn och
      // är index-linjerad med tidsserien.
      const refSerie = kpi.referens_serie && kpi.referens_serie.length === serie.length
        ? kpi.referens_serie : undefined;
      root.append("rect")
        .attr("x", x0).attr("y", rowY).attr("width", timelineW).attr("height", rowH)
        .attr("fill", "transparent").style("cursor", onCellClick ? "pointer" : "crosshair")
        .on("mousemove", (ev: MouseEvent) => {
          const [mx] = d3.pointer(ev);
          const idx = Math.max(0, Math.min(N - 1, Math.floor(((mx - x0) / timelineW) * N)));
          const cx = center(idx);
          marker.attr("x1", cx).attr("x2", cx).attr("y1", laneY - 3).attr("y2", laneY + laneH + 3).attr("opacity", 0.55);
          const { period, etikett } = kolumner[idx];
          const point = serie.find((p) => p.period === period);
          // Föreg. år: index-linjerad referensserie (dagvy) eller ~1 år bak i serien.
          const prevYear = refSerie
            ? (refSerie[idx]?.varde ?? null)
            : prevYearValue(serie, period, effVy);
          const rect = (ev.currentTarget as SVGRectElement).getBoundingClientRect();
          setHover({
            kind: "cell", kpi, serie, refSerie, point, etikett, prevYear,
            x: ev.clientX, yTop: rect.top, yBot: rect.bottom,
          });
        })
        .on("mouseleave", () => { marker.attr("opacity", 0); setHover(null); })
        .on("click", () => onCellClick?.(kpi));
    }

    // Nollställ hovern när grafen ritas om (cleanup → ej synkron setState i kroppen).
    return () => setHover(null);
  }, [sektioner, vy, visaDagar, width, onCellClick]);

  return (
    <div ref={outerRef} style={{ width: "100%" }}>
      <div ref={svgRef} style={{ width: "100%" }} />
      {hover?.kind === "cell" && <CellCard hover={hover} />}
      {hover?.kind === "name" && <NameCard hover={hover} />}
      {hover?.kind === "status" && <StatusCard hover={hover} />}
    </div>
  );
}

// ── Cell-ruta: värde + förväntat + föreg. år + status + MiniTrend ──
function CellCard({ hover }: { hover: Extract<Hover, { kind: "cell" }> }) {
  const { kpi, serie, refSerie, point, etikett, prevYear, x, yTop, yBot } = hover;
  const dec = kpi.enhet === "procent" ? 1 : 0;
  const suffix = fmtSuffix(kpi.enhet);
  const accent = SIGNAL_COLORS[kpi.status] || "#00664D";
  const sig = point?.signal;
  const TW = 252;

  const below = yTop < 230;
  const left = Math.max(TW / 2 + 8, Math.min(window.innerWidth - TW / 2 - 8, x));

  let yoy: { text: string; color: string } | null = null;
  if (point && prevYear != null) {
    const diff = point.varde - prevYear;
    const good = kpi.inverterad ? diff < 0 : diff > 0;
    const bad = kpi.inverterad ? diff > 0 : diff < 0;
    const arrow = diff > 0 ? "↑" : diff < 0 ? "↓" : "→";
    const unit = kpi.enhet === "procent" ? " pp" : "";
    yoy = {
      color: good ? SIGNAL_COLORS.gron : bad ? SIGNAL_COLORS.rod : "#9a9a96",
      text: `${fmtVarde(prevYear, kpi.enhet, dec)}${suffix}  ${arrow}${fmtVarde(Math.abs(diff), kpi.enhet, dec)}${unit}`,
    };
  }

  return (
    <div style={{
      position: "fixed", left, top: below ? yBot + 10 : yTop - 10,
      transform: below ? "translate(-50%, 0)" : "translate(-50%, -100%)",
      width: TW, zIndex: 9999, pointerEvents: "none",
      background: "#fff", border: "1px solid #e0e0dc", borderTop: `3px solid ${accent}`,
      borderRadius: 8, boxShadow: "0 8px 30px rgba(0,0,0,0.13)", padding: "11px 13px 9px",
      animation: "fadeIn 0.1s ease",
    }}>
      <div style={{ fontFamily: "'Source Serif 4', Georgia, serif", fontSize: 14, fontWeight: 600, color: "#1a1a1a", lineHeight: 1.25 }}>
        {kpi.namn}
      </div>
      <div style={{ fontFamily: FONT, fontSize: 11, color: "#999", marginBottom: 8 }}>{etikett}</div>

      <div style={{ display: "flex", alignItems: "baseline", gap: 8 }}>
        <span style={{ fontFamily: FONT_MONO, fontFeatureSettings: "'tnum'", fontVariantNumeric: "tabular-nums", fontSize: 23, fontWeight: 700, color: "#0a0a0a", letterSpacing: "-0.02em", lineHeight: 1 }}>
          {point ? fmtVarde(point.varde, kpi.enhet, dec) : "–"}
        </span>
        <span style={{ fontFamily: FONT_MONO, fontSize: 12, color: "#aaa", fontWeight: 500 }}>{suffix}</span>
        {sig && (
          <span style={{ marginLeft: "auto", display: "inline-flex", alignItems: "center", gap: 5, fontFamily: FONT, fontSize: 11, fontWeight: 600, color: SIGNAL_COLORS[sig] }}>
            <span style={{ width: 7, height: 7, borderRadius: "50%", background: SIGNAL_COLORS[sig] }} />
            {SIGNAL_LABELS[sig]}
          </span>
        )}
      </div>

      <div style={{ marginTop: 6, fontFamily: FONT, fontSize: 11, lineHeight: 1.5 }}>
        {point?.yhat != null && (
          <div style={{ display: "flex", justifyContent: "space-between", color: "#999" }}>
            <span>förväntat</span>
            <span style={{ fontFamily: FONT_MONO }}>{fmtVarde(point.yhat, kpi.enhet, dec)}{suffix}</span>
          </div>
        )}
        {yoy && (
          <div style={{ display: "flex", justifyContent: "space-between", color: "#999" }}>
            <span>föreg. år</span>
            <span style={{ fontFamily: FONT_MONO, color: yoy.color, fontWeight: 600 }}>{yoy.text}</span>
          </div>
        )}
      </div>

      <div style={{ marginTop: 8, borderTop: "1px solid #f0efeb", paddingTop: 6 }}>
        <MiniTrend serie={serie} refSerie={refSerie} accent={NEUTRAL_LINE} highlightPeriod={point?.period} width={TW - 26} height={92} />
      </div>

      {/* Klick-indikation: raden öppnar en större graf */}
      <div style={{ marginTop: 8, display: "flex", alignItems: "center", gap: 5, fontFamily: FONT, fontSize: 10.5, color: "#aaa", fontWeight: 500 }}>
        <svg width="11" height="11" viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round">
          <path d="M9.5 2.5H13.5V6.5" /><path d="M13.5 2.5L9 7" />
          <path d="M6.5 13.5H2.5V9.5" /><path d="M2.5 13.5L7 9" />
        </svg>
        Klicka för större graf
      </div>
    </div>
  );
}

// ── Namn-ruta: vad indikatorn mäter ──
function NameCard({ hover }: { hover: Extract<Hover, { kind: "name" }> }) {
  const { kpi, x, yTop, yBot } = hover;
  const beskrivning = kortBeskrivning(kpi);
  const TW = 290;
  const below = yTop < 200;
  const left = Math.max(TW / 2 + 8, Math.min(window.innerWidth - TW / 2 - 8, x + TW / 2 - 20));
  const enhetText = kpi.enhet === "procent" ? "Procent" : kpi.enhet === "minuter" ? "Minuter" : "Antal";

  return (
    <div style={{
      position: "fixed", left, top: below ? yBot + 8 : yTop - 8,
      transform: below ? "translate(-50%, 0)" : "translate(-50%, -100%)",
      width: TW, zIndex: 9999, pointerEvents: "none",
      background: "#fff", border: "1px solid #e0e0dc", borderLeft: "3px solid #00664D",
      borderRadius: 8, boxShadow: "0 8px 30px rgba(0,0,0,0.13)", padding: "11px 14px",
      animation: "fadeIn 0.1s ease",
    }}>
      <div style={{ fontFamily: "'Source Serif 4', Georgia, serif", fontSize: 14, fontWeight: 600, color: "#1a1a1a", lineHeight: 1.25, marginBottom: beskrivning ? 6 : 8 }}>
        {kpi.namn}
      </div>
      {beskrivning && (
        <div style={{ fontFamily: FONT, fontSize: 12, lineHeight: 1.55, color: "#555", marginBottom: 8 }}>{beskrivning}</div>
      )}
      <div style={{ display: "flex", gap: 14, fontFamily: FONT, fontSize: 10.5, color: "#999", borderTop: "1px solid #f0efeb", paddingTop: 7 }}>
        <span>Enhet: <strong style={{ color: "#666", fontWeight: 600 }}>{enhetText}</strong></span>
        <span><strong style={{ color: "#666", fontWeight: 600 }}>{kpi.utan_mal ? "Utan målriktning" : kpi.inverterad ? "Lägre är bättre" : "Högre är bättre"}</strong></span>
      </div>
    </div>
  );
}

// ── Status-ruta: hur "i fas / bevaka / avvikelse" bedöms ──
// Två varianter: ranking mot andra regioner (indikatorer med kontext_serier,
// t.ex. SKR-rapporten) respektive statistiskt förväntat intervall (conformal).
function StatusCard({ hover }: { hover: Extract<Hover, { kind: "status" }> }) {
  const { kpi, x, yTop, yBot } = hover;
  const TW = 300;
  const below = yTop < 230;
  const left = Math.max(TW / 2 + 8, Math.min(window.innerWidth - TW / 2 - 8, x));
  const ranking = !!kpi.kontext_serier && kpi.kontext_serier.length > 0;
  const levels: { sig: "gron" | "gul" | "rod"; txt: string }[] = ranking
    ? [
        { sig: "gron", txt: "Topp 3 bland regionerna" },
        { sig: "gul", txt: "Plats 4–7" },
        { sig: "rod", txt: "Plats 8 eller lägre" },
      ]
    : [
        { sig: "gron", txt: "Inom det förväntade intervallet (80 %)" },
        { sig: "gul", txt: "I ytterkanten — mellan 80 och 95 %" },
        { sig: "rod", txt: "Utanför det förväntade (över 95 %)" },
      ];

  return (
    <div style={{
      position: "fixed", left, top: below ? yBot + 8 : yTop - 8,
      transform: below ? "translate(-50%, 0)" : "translate(-50%, -100%)",
      width: TW, zIndex: 9999, pointerEvents: "none",
      background: "#fff", border: "1px solid #e0e0dc", borderTop: `3px solid ${SIGNAL_COLORS[kpi.status] || "#00664D"}`,
      borderRadius: 8, boxShadow: "0 8px 30px rgba(0,0,0,0.13)", padding: "11px 14px",
      animation: "fadeIn 0.1s ease",
    }}>
      <div style={{ fontFamily: "'Source Serif 4', Georgia, serif", fontSize: 14, fontWeight: 600, color: "#1a1a1a", lineHeight: 1.25, marginBottom: 6 }}>
        Så bedöms status
      </div>
      <div style={{ fontFamily: FONT, fontSize: 12, lineHeight: 1.55, color: "#555", marginBottom: 9 }}>
        {ranking
          ? "Senaste årets värde rankas mot övriga regioner (hänsyn tas till om högre eller lägre är bättre). Halland är i fas när regionen ligger bland de tre bästa."
          : "Senaste värdet jämförs mot ett statistiskt förväntat intervall — modellen väger in säsong, veckodag och trend (GLM + conformal prediction)."}
      </div>
      <div style={{ display: "flex", flexDirection: "column", gap: 5 }}>
        {levels.map((l) => {
          const aktiv = l.sig === kpi.status;
          return (
            <div key={l.sig} style={{
              display: "flex", alignItems: "center", gap: 8,
              padding: "3px 6px", borderRadius: 5,
              background: aktiv ? SIGNAL_BG[l.sig] : "transparent",
            }}>
              <span style={{ width: 8, height: 8, borderRadius: "50%", background: SIGNAL_COLORS[l.sig], flexShrink: 0 }} />
              <span style={{ fontFamily: FONT, fontSize: 11, fontWeight: 600, color: SIGNAL_COLORS[l.sig], width: 62, flexShrink: 0 }}>
                {SIGNAL_LABELS[l.sig]}
              </span>
              <span style={{ fontFamily: FONT, fontSize: 11, color: "#666", lineHeight: 1.4 }}>{l.txt}</span>
            </div>
          );
        })}
      </div>
    </div>
  );
}
