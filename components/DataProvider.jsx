'use client';
import { createContext, useContext, useEffect, useMemo, useState } from 'react';
import { AnimatePresence, motion } from 'framer-motion';
import { toTrades, dayKey, ratioOf } from '@/lib/util';
import { sb, fetchAll, rowToTrade } from '@/lib/supabase-client';

const Ctx = createContext(null);
export const useData = () => useContext(Ctx);

let cache = null;
function load() {
  if (!cache) {
    cache = Promise.all([
      fetch('/data/lab.json').then((r) => r.json()),
      fetch('/data/trades.json').then((r) => (r.ok ? r.json() : { trades: [] })).catch(() => ({ trades: [] })),
    ]);
  }
  return cache;
}

export const wkey = (a, s, v, sd, c) => a + '|' + s + '|' + v + '|' + sd + '|' + c;

export default function DataProvider({ children }) {
  const [raw, setRaw] = useState(null);
  const [err, setErr] = useState(null);
  const [risk, setRiskState] = useState(10);
  const [liveRows, setLiveRows] = useState([]);

  useEffect(() => {
    load().then(setRaw).catch((e) => setErr(String(e)));
    if (sb()) fetchAll('signals', (q) => q.in('status', ['active', 'won', 'lost']).order('t_signal', { ascending: true })).then(setLiveRows).catch(() => {});
    try { const r = parseFloat(localStorage.getItem('t2r_risk')); if (r > 0) setRiskState(r); } catch (e) { /* storage off */ }
  }, []);

  const setRisk = (v) => {
    setRiskState(v);
    try { localStorage.setItem('t2r_risk', String(v)); } catch (e) { /* storage off */ }
  };

  const data = useMemo(() => {
    if (!raw) return null;
    const [lab, tr] = raw;
    const MK = {};
    lab.markets.forEach((m) => { MK[m[0]] = { name: m[0], fam: m[1], bars: m[2], from: m[3], to: m[4], status: m[5] }; });
    const famOf = (a) => (MK[a] ? MK[a].fam : /^[A-Z]{6}$/.test(a) ? (/^X(AU|AG|PT|PD)/.test(a) ? 'Metals' : 'Forex') : 'Synthetics');
    const ROWS = lab.rows.map((r, i) => ({ i, a: r[0], s: r[1], v: r[2], sd: r[3], c: r[4], st: r[5], best: r[6], pass: r[7], strong: r[8], fam: famOf(r[0]) }));
    const WATCH = lab.watch.map((w, i) => ({ i, a: w[0], s: w[1], v: w[2], sd: w[3], c: w[4], si: w[5], lv: w[6], st: w[7], b1: w[8], pw: w[9], z: w[10], house: w[11], fam: famOf(w[0]) }));
    const WSET = {};
    WATCH.forEach((w) => { WSET[wkey(w.a, w.s, w.v, w.sd, w.c)] = w; });
    const TRADES = toTrades(tr.trades || [], famOf).concat(liveRows.map((r) => rowToTrade(r, famOf, dayKey, ratioOf))).sort((a, b) => a.tin - b.tin);
    const TBYID = {};
    TRADES.forEach((t) => { TBYID[t.id] = t; });
    return { MK, famOf, ROWS, WATCH, WSET, TRADES, TBYID, meta: lab.meta, tmeta: { gen: tr.gen, from: tr.from, to: tr.to } };
  }, [raw, liveRows]);

  return (
    <Ctx.Provider value={{ data, risk, setRisk }}>
      <AnimatePresence>
        {!data && (
          <motion.div className="loader" initial={{ opacity: 1 }} exit={{ opacity: 0, transition: { duration: 0.5 } }}>
            <div className="in">
              <div className="brand"><span className="mark loader-mark mark">T</span></div>
              <div className="track"><i /></div>
              <span>{err ? 'Could not load the lab data. Refresh the page.' : 'Loading 1.4 million test trades'}</span>
            </div>
          </motion.div>
        )}
      </AnimatePresence>
      {data ? children : null}
    </Ctx.Provider>
  );
}
