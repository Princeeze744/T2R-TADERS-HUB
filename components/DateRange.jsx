'use client';
import { useEffect, useMemo, useState } from 'react';
import { AnimatePresence, motion } from 'framer-motion';
import { useDismiss, popAnim } from './ui';
import { IcCal, IcChevron, IcLeft, IcRight } from './Icons';
import { MONTHS, dayKey, keyToTs, addDays, weekStart, shortDate, f1 } from '@/lib/util';

export function presets(todayKey, min, max) {
  const t = todayKey;
  const ws = weekStart(t);
  const m0 = t.slice(0, 8) + '01';
  const pm = new Date(keyToTs(m0) * 1000); pm.setUTCMonth(pm.getUTCMonth() - 1);
  const pm0 = dayKey(pm.getTime() / 1000);
  return [
    { k: 'today', label: 'Today', from: t, to: t },
    { k: 'yday', label: 'Yesterday', from: addDays(t, -1), to: addDays(t, -1) },
    { k: 'week', label: 'This week', from: ws, to: t },
    { k: 'lweek', label: 'Last week', from: addDays(ws, -7), to: addDays(ws, -1) },
    { k: '7d', label: 'Last 7 days', from: addDays(t, -6), to: t },
    { k: '30d', label: 'Last 30 days', from: addDays(t, -29), to: t },
    { k: 'month', label: 'This month', from: m0, to: t },
    { k: 'lmonth', label: 'Last month', from: pm0, to: addDays(m0, -1) },
    { k: 'all', label: 'All data', from: min, to: max },
  ];
}

export default function DateRange({ from, to, onChange, min, max, todayKey, dayStats }) {
  const [open, setOpen] = useState(false);
  const ref = useDismiss(open, setOpen);
  const [view, setView] = useState(() => (to || max).slice(0, 7));
  const [anchor, setAnchor] = useState(null);
  const [hover, setHover] = useState(null);
  const P = useMemo(() => presets(todayKey, min, max), [todayKey, min, max]);
  const active = P.find((p) => p.from === from && p.to === to);
  useEffect(() => { if (open) { setView((to || max).slice(0, 7)); setAnchor(null); } }, [open, to, max]);

  const y = +view.slice(0, 4), m = +view.slice(5, 7) - 1;
  const first = Date.UTC(y, m, 1) / 1000;
  const lead = (new Date(first * 1000).getUTCDay() + 6) % 7;
  const days = new Date(Date.UTC(y, m + 1, 0)).getUTCDate();
  const cells = [];
  for (let i = 0; i < lead; i++) cells.push(null);
  for (let d = 1; d <= days; d++) cells.push(dayKey(first + (d - 1) * 86400));
  const shift = (n) => { const d = new Date(Date.UTC(y, m + n, 1)); setView(d.toISOString().slice(0, 7)); };

  let a = from, b = to;
  if (anchor) { const h = hover || anchor; a = anchor < h ? anchor : h; b = anchor < h ? h : anchor; }
  const click = (k) => {
    if (!anchor) { setAnchor(k); return; }
    const lo = anchor < k ? anchor : k, hi = anchor < k ? k : anchor;
    setAnchor(null); onChange(lo, hi); setOpen(false);
  };
  const maxAbs = Math.max(1, ...[...dayStats.values()].map((s) => Math.abs(s.R)));
  const label = active ? active.label : from === to ? shortDate(from) + ' ' + from.slice(0, 4) : shortDate(from) + ' – ' + shortDate(to) + ' ' + to.slice(0, 4);
  const sub = from === to ? '' : shortDate(from) + ' – ' + shortDate(to);

  return (
    <div className="field" ref={ref}>
      <button type="button" className="field-btn set" onClick={() => setOpen((o) => !o)} aria-expanded={open} style={{ maxWidth: 340 }}>
        <IcCal s={16} /><span className="v">{label}</span>{active && sub && <span className="k">{sub}</span>}<IcChevron s={15} />
      </button>
      <AnimatePresence>
        {open && (
          <motion.div className="pop" {...popAnim} style={{ padding: 0, maxWidth: 'none' }}>
            <div className="dr-pop">
              <div className="dr-presets">
                {P.map((p) => (
                  <button type="button" key={p.k} className={active && active.k === p.k ? 'on' : ''} onClick={() => { onChange(p.from, p.to); setOpen(false); }}>{p.label}</button>
                ))}
              </div>
              <div className="cal">
                <div className="cal-head">
                  <button type="button" onClick={() => shift(-1)} aria-label="Previous month"><IcLeft s={16} /></button>
                  <b>{MONTHS[m]} {y}</b>
                  <button type="button" onClick={() => shift(1)} aria-label="Next month"><IcRight s={16} /></button>
                </div>
                <div className="cal-grid">
                  {['Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa', 'Su'].map((d) => <div key={d} className="dow">{d}</div>)}
                  {cells.map((k, i) => {
                    if (!k) return <div key={'e' + i} />;
                    const s = dayStats.get(k);
                    const inr = k >= a && k <= b;
                    const edge = k === a || k === b;
                    const heat = s ? Math.min(1, Math.abs(s.R) / maxAbs) : 0;
                    const bg = s && !inr ? (s.R >= 0 ? `rgba(54,211,153,${0.06 + heat * 0.28})` : `rgba(255,107,107,${0.06 + heat * 0.28})`) : undefined;
                    return (
                      <button type="button" key={k} className={'day' + (s ? ' has' : '') + (inr ? ' inr' : '') + (edge ? ' edge' : '') + (k === todayKey ? ' today' : '')}
                        style={{ background: edge ? undefined : bg }} disabled={k > todayKey}
                        onClick={() => click(k)} onMouseEnter={() => setHover(k)} title={s ? `${s.n} trades, ${f1(s.R)}R` : 'No trades'}>
                        <span>{+k.slice(8)}</span>
                        {s && <span className={'dr ' + (s.R >= 0 ? 'g' : 'r')}>{f1(s.R)}</span>}
                      </button>
                    );
                  })}
                </div>
                <div className="cal-foot">
                  <span>{anchor ? 'Now pick the end day' : 'Pick a start day, then an end day'}</span>
                  <span className="dimmer">Data from {shortDate(min)} to {shortDate(max)}</span>
                </div>
              </div>
            </div>
          </motion.div>
        )}
      </AnimatePresence>
    </div>
  );
}
