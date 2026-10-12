'use client';
import { useEffect, useRef, useState } from 'react';
import { f2, fmtPrice, hhmm, dayLabel, dayKey } from '@/lib/util';

const C = { win: '#36d399', loss: '#ff6b6b', gold: '#f3dca4', open: '#7ea6ff', mute: '#9aa2b2', grid: 'rgba(255,255,255,0.045)' };
function monoFont() {
  try { const v = getComputedStyle(document.documentElement).getPropertyValue('--font-geist-mono').trim(); if (v) return v + ', ui-monospace, monospace'; } catch (e) { /* server */ }
  return 'ui-monospace, monospace';
}
const baseOpts = (h) => ({
  autoSize: true,
  height: h,
  layout: { background: { type: 'solid', color: 'transparent' }, textColor: C.mute, fontFamily: monoFont(), fontSize: 11, attributionLogo: false },
  grid: { vertLines: { color: C.grid }, horzLines: { color: C.grid } },
  rightPriceScale: { borderVisible: false },
  timeScale: { borderVisible: false, timeVisible: true, secondsVisible: false },
  crosshair: { mode: 0, vertLine: { color: 'rgba(243,220,164,.35)', labelBackgroundColor: '#2a2418' }, horzLine: { color: 'rgba(243,220,164,.35)', labelBackgroundColor: '#2a2418' } },
});

// ---------- running total of R (equity curve) ----------
export function EquityChart({ trades, height = 260 }) {
  const box = useRef(null);
  useEffect(() => {
    let chart, dead = false;
    const closed = trades.filter((t) => t.res !== 'open' && (t.tout || t.tin));
    const agg = new Map();
    closed.forEach((t) => { const k = t.tout || t.tin; agg.set(k, (agg.get(k) || 0) + t.R); });
    const keys = [...agg.keys()].sort((a, b) => a - b);
    let s = 0;
    const pts = keys.map((k) => { s += agg.get(k); return { time: k, value: Math.round(s * 100) / 100 }; });
    import('lightweight-charts').then(({ createChart, BaselineSeries }) => {
      if (dead || !box.current) return;
      chart = createChart(box.current, { ...baseOpts(height), handleScroll: false, handleScale: false, rightPriceScale: { borderVisible: false, scaleMargins: { top: 0.12, bottom: 0.08 } } });
      const ser = chart.addSeries(BaselineSeries, {
        baseValue: { type: 'price', price: 0 },
        topLineColor: C.win, topFillColor1: 'rgba(54,211,153,0.28)', topFillColor2: 'rgba(54,211,153,0.02)',
        bottomLineColor: C.loss, bottomFillColor1: 'rgba(255,107,107,0.02)', bottomFillColor2: 'rgba(255,107,107,0.25)',
        lineWidth: 2, priceFormat: { type: 'custom', formatter: (v) => (v >= 0 ? '+' : '') + v.toFixed(1) + 'R', minMove: 0.01 },
        priceLineVisible: false,
      });
      ser.setData(pts);
      chart.timeScale().fitContent();
    });
    return () => { dead = true; if (chart) chart.remove(); };
  }, [trades, height]);
  if (trades.filter((t) => t.res !== 'open').length < 2) return <div className="empty" style={{ height }}><b>Not enough closed trades</b>Widen the dates or filters to draw the curve.</div>;
  return <div className="chart-box" style={{ height }}><div className="lw" ref={box} /></div>;
}

// ---------- candles for one market, loaded on demand ----------
let idxP = null;
const barCache = new Map();
function barsIndex() {
  if (!idxP) idxP = fetch('/data/bars/index.json').then((r) => (r.ok ? r.json() : {})).catch(() => ({}));
  return idxP;
}
async function loadBars(market) {
  const idx = await barsIndex();
  const m = idx[market];
  if (!m) return null;
  if (!barCache.has(m.f)) {
    barCache.set(m.f, fetch('/data/bars/' + m.f + '.json').then((r) => (r.ok ? r.json() : null)).then((b) => {
      if (!b) return null;
      const out = new Array(b.t.length);
      let t = b.t0;
      for (let i = 0; i < b.t.length; i++) { t += b.t[i] * 60; out[i] = { time: t, open: b.o[i], high: b.h[i], low: b.l[i], close: b.c[i] }; }
      return { d: b.d, bars: out };
    }).catch(() => null));
  }
  return barCache.get(m.f);
}
function idxAt(bars, t) { // last bar starting at or before t
  let lo = 0, hi = bars.length - 1, r = 0;
  while (lo <= hi) { const mid = (lo + hi) >> 1; if (bars[mid].time <= t) { r = mid; lo = mid + 1; } else hi = mid - 1; }
  return r;
}

export function TradeChart({ t, height = 440 }) {
  const box = useRef(null);
  const ov = useRef(null);
  const [state, setState] = useState('loading'); // loading | ok | none
  useEffect(() => {
    let chart, raf, dead = false;
    setState('loading');
    (async () => {
      const [lw, B] = await Promise.all([import('lightweight-charts'), loadBars(t.a)]);
      if (dead) return;
      if (!B || !B.bars.length || t.tin < B.bars[0].time || t.tin > B.bars[B.bars.length - 1].time + 900) { setState('none'); return; }
      setState('ok');
      const bars = B.bars;
      const iA = idxAt(bars, t.tin);
      const iB = t.tout ? idxAt(bars, t.tout) : bars.length - 1;
      const s0 = Math.max(0, iA - 160), s1 = Math.min(bars.length - 1, iB + 80);
      const data = bars.slice(s0, s1 + 1);
      const a = iA - s0, b = iB - s0;
      const prec = B.d ?? 2;
      chart = lw.createChart(box.current, baseOpts(height));
      const ser = chart.addSeries(lw.CandlestickSeries, {
        upColor: C.win, downColor: C.loss, borderVisible: false, wickUpColor: C.win, wickDownColor: C.loss,
        priceFormat: { type: 'price', precision: prec, minMove: Math.pow(10, -prec) }, priceLineVisible: false, lastValueVisible: false,
      });
      ser.setData(data);
      const unit = Math.abs(t.e - t.sl);
      const buy = t.dir === 'buy';
      const tp1 = buy ? t.e + unit : t.e - unit;
      const line = (price, color, title, style) => ser.createPriceLine({ price, color, lineWidth: 1, lineStyle: style, axisLabelVisible: true, title });
      line(t.e, C.gold, 'Entry', 0);
      line(t.sl, C.loss, 'Stop', 2);
      line(t.tp, C.win, 'Target ' + t.rr, 2);
      if (t.ratio > 1.05) line(tp1, 'rgba(54,211,153,.55)', 'TP1 1:1', 1);
      const mk = [{ time: data[a].time, position: buy ? 'belowBar' : 'aboveBar', shape: buy ? 'arrowUp' : 'arrowDown', color: C.gold, text: (buy ? 'BUY ' : 'SELL ') + hhmm(t.tin) }];
      if (t.tout) mk.push({ time: data[b].time, position: t.res === 'won' ? (buy ? 'aboveBar' : 'belowBar') : (buy ? 'belowBar' : 'aboveBar'), shape: 'circle', color: t.res === 'won' ? C.win : C.loss, text: (t.res === 'won' ? 'Target ' : 'Stop ') + f2(t.R) + 'R' });
      lw.createSeriesMarkers(ser, mk.sort((x, y) => x.time - y.time));
      chart.timeScale().setVisibleLogicalRange({ from: Math.max(0, a - 70), to: Math.min(data.length - 1, b + 30) + 4 });

      // risk / reward boxes drawn on top of the chart
      const g = ov.current;
      const rk = g.querySelector('.rk'), rw = g.querySelector('.rw');
      const draw = () => {
        const ts = chart.timeScale();
        const x1 = ts.logicalToCoordinate(a), x2 = ts.logicalToCoordinate(Math.max(b, a + 1));
        const yE = ser.priceToCoordinate(t.e), yS = ser.priceToCoordinate(t.sl), yT = ser.priceToCoordinate(t.tp);
        if (x1 == null || x2 == null || yE == null || yS == null || yT == null) { raf = requestAnimationFrame(draw); return; }
        const W = Math.max(2, x2 - x1);
        rk.setAttribute('x', x1); rk.setAttribute('width', W); rk.setAttribute('y', Math.min(yE, yS)); rk.setAttribute('height', Math.abs(yS - yE));
        rw.setAttribute('x', x1); rw.setAttribute('width', W); rw.setAttribute('y', Math.min(yE, yT)); rw.setAttribute('height', Math.abs(yT - yE));
        raf = requestAnimationFrame(draw);
      };
      raf = requestAnimationFrame(draw);
    })();
    return () => { dead = true; cancelAnimationFrame(raf); if (chart) chart.remove(); };
  }, [t, height]);

  if (state === 'none') return <TradeSchematic t={t} height={height} />;
  return (
    <div className="chart-box" style={{ height }}>
      {state === 'loading' && <div className="skel" style={{ position: 'absolute', inset: 12 }} />}
      <svg className="overlay" ref={ov} width="100%" height="100%" style={{ zIndex: 1 }}>
        <rect className="rk" fill="rgba(255,107,107,.13)" stroke="rgba(255,107,107,.35)" />
        <rect className="rw" fill="rgba(54,211,153,.11)" stroke="rgba(54,211,153,.35)" />
      </svg>
      <div className="lw" ref={box} style={{ zIndex: 2 }} />
    </div>
  );
}

// ---------- when the market's candles are not loaded yet: draw the trade plan ----------
export function TradeSchematic({ t, height = 440 }) {
  const W = 900, H = height, pl = 30, pr = 150, pt = 36, pb = 46;
  const buy = t.dir === 'buy';
  const exitP = t.res === 'won' ? t.tp : t.res === 'lost' ? t.sl : t.ex ?? t.e;
  const lv = [t.e, t.sl, t.tp];
  let lo = Math.min(...lv), hi = Math.max(...lv);
  const pad = (hi - lo) * 0.14; lo -= pad; hi += pad;
  const Y = (v) => pt + (H - pt - pb) * (1 - (v - lo) / (hi - lo));
  const xA = pl + 120, xB = W - pr - 40;
  const unit = Math.abs(t.e - t.sl);
  const tp1 = buy ? t.e + unit : t.e - unit;
  const pathCol = t.res === 'won' ? C.win : t.res === 'lost' ? C.loss : C.open;
  const path = `M ${xA} ${Y(t.e)} L ${xB} ${Y(exitP)}`;
  const lab = (y, txt, col, val) => (
    <g>
      <line x1={pl} x2={W - pr + 10} y1={Y(y)} y2={Y(y)} stroke={col} strokeDasharray={txt === 'Entry' ? '' : '5 4'} strokeWidth="1.3" opacity=".9" />
      <text x={W - pr + 18} y={Y(y) - 3} fill={col} fontSize="12" fontFamily="var(--mono)">{txt}</text>
      <text x={W - pr + 18} y={Y(y) + 12} fill="#9aa2b2" fontSize="11.5" fontFamily="var(--mono)">{fmtPrice(val, t.e)}</text>
    </g>
  );
  return (
    <div className="chart-box" style={{ height }}>
      <svg viewBox={`0 0 ${W} ${H}`} width="100%" height="100%" preserveAspectRatio="none" role="img" aria-label="Trade plan">
        <rect x={xA} width={xB - xA} y={Math.min(Y(t.e), Y(t.sl))} height={Math.abs(Y(t.sl) - Y(t.e))} fill="rgba(255,107,107,.13)" stroke="rgba(255,107,107,.3)" />
        <rect x={xA} width={xB - xA} y={Math.min(Y(t.e), Y(t.tp))} height={Math.abs(Y(t.tp) - Y(t.e))} fill="rgba(54,211,153,.10)" stroke="rgba(54,211,153,.3)" />
        {lab(t.tp, 'Target ' + t.rr, C.win, t.tp)}
        {t.ratio > 1.05 && lab(tp1, 'TP1 1:1', 'rgba(54,211,153,.7)', tp1)}
        {lab(t.e, 'Entry', C.gold, t.e)}
        {lab(t.sl, 'Stop', C.loss, t.sl)}
        <path d={path} fill="none" stroke={pathCol} strokeWidth="2" strokeDasharray="2 6" strokeLinecap="round" opacity=".9" />
        <circle cx={xA} cy={Y(t.e)} r="6" fill="#0b0e14" stroke={C.gold} strokeWidth="2.5" />
        {t.res !== 'open' && <circle cx={xB} cy={Y(exitP)} r="6.5" fill={pathCol} />}
        <text x={xA} y={H - 18} fill="#9aa2b2" fontSize="12" textAnchor="middle" fontFamily="var(--mono)">{dayLabel(dayKey(t.tin))} {hhmm(t.tin)}</text>
        {t.tout ? <text x={xB} y={H - 18} fill="#9aa2b2" fontSize="12" textAnchor="middle" fontFamily="var(--mono)">{dayLabel(dayKey(t.tout))} {hhmm(t.tout)}</text> : null}
        <text x={pl} y={22} fill="#5f6779" fontSize="12" fontFamily="var(--sans)">Trade plan view: candles for this market are not loaded yet</text>
      </svg>
    </div>
  );
}
