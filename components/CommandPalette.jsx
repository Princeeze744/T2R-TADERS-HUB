'use client';
import { useEffect, useMemo, useRef, useState } from 'react';
import { useRouter } from 'next/navigation';
import { AnimatePresence, motion } from 'framer-motion';
import { useData } from './DataProvider';
import { PAGES } from './Nav';
import { STRATS } from '@/lib/constants';
import { ease } from './ui';

export default function CommandPalette() {
  const [open, setOpen] = useState(false);
  const [q, setQ] = useState('');
  const [act, setAct] = useState(0);
  const router = useRouter();
  const { data } = useData() || {};
  const listRef = useRef(null);

  useEffect(() => {
    const onKey = (e) => {
      if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === 'k') { e.preventDefault(); setOpen((o) => !o); }
      else if (e.key === '/' && !/input|textarea|select/i.test(document.activeElement?.tagName || '')) { e.preventDefault(); setOpen(true); }
      else if (e.key === 'Escape') setOpen(false);
    };
    const onOpen = () => setOpen(true);
    window.addEventListener('keydown', onKey);
    window.addEventListener('t2r-search', onOpen);
    return () => { window.removeEventListener('keydown', onKey); window.removeEventListener('t2r-search', onOpen); };
  }, []);
  useEffect(() => { if (!open) { setQ(''); setAct(0); } }, [open]);

  const items = useMemo(() => {
    if (!data) return [];
    const s = q.trim().toLowerCase();
    const out = [];
    const mk = Object.keys(data.MK).sort();
    const tradeCount = {};
    data.TRADES.forEach((t) => { tradeCount[t.a] = (tradeCount[t.a] || 0) + 1; });
    PAGES.forEach((p) => { if (!s || p.label.toLowerCase().includes(s)) out.push({ k: 'Pages', label: p.label, go: p.href }); });
    STRATS.forEach((st) => { if (!s || st.toLowerCase().includes(s)) out.push({ k: 'Strategies', label: st, hint: 'learn it', go: '/strategies?s=' + encodeURIComponent(st), alt: '/journal?st=' + encodeURIComponent(st) }); });
    mk.forEach((m) => {
      if (!s || m.toLowerCase().includes(s) || data.MK[m].fam.toLowerCase().includes(s))
        out.push({ k: 'Markets', label: m, hint: data.MK[m].fam + (tradeCount[m] ? ' · ' + tradeCount[m] + (tradeCount[m] === 1 ? ' trade' : ' trades') : ''), go: '/journal?mk=' + encodeURIComponent(m), alt: '/explorer?mk=' + encodeURIComponent(m) });
    });
    return out.slice(0, s ? 60 : 30);
  }, [data, q]);

  const go = (it, alt) => { setOpen(false); router.push(alt && it.alt ? it.alt : it.go); };
  const onKey = (e) => {
    if (e.key === 'ArrowDown') { e.preventDefault(); setAct((a) => Math.min(items.length - 1, a + 1)); }
    if (e.key === 'ArrowUp') { e.preventDefault(); setAct((a) => Math.max(0, a - 1)); }
    if (e.key === 'Enter' && items[act]) { e.preventDefault(); go(items[act], e.shiftKey); }
  };
  useEffect(() => {
    const el = listRef.current?.querySelector('.act');
    if (el) el.scrollIntoView({ block: 'nearest' });
  }, [act]);

  let last = null;
  return (
    <AnimatePresence>
      {open && (
        <motion.div className="cmdk-scrim" initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }} onMouseDown={(e) => { if (e.target === e.currentTarget) setOpen(false); }}>
          <motion.div className="cmdk" initial={{ opacity: 0, y: -14, scale: 0.98 }} animate={{ opacity: 1, y: 0, scale: 1 }} exit={{ opacity: 0, y: -10, scale: 0.98 }} transition={{ duration: 0.22, ease }} role="dialog" aria-label="Search">
            <input autoFocus placeholder="Search a market, strategy or page…" value={q} onChange={(e) => { setQ(e.target.value); setAct(0); }} onKeyDown={onKey} />
            <div className="list" ref={listRef}>
              {items.map((it, i) => {
                const g = it.k !== last ? it.k : null; last = it.k;
                return (
                  <div key={it.k + it.label}>
                    {g && <div className="opt-group">{g}</div>}
                    <div className={'opt' + (i === act ? ' act' : '')} onMouseEnter={() => setAct(i)}>
                      <button type="button" style={{ flex: 1, textAlign: 'left' }} onClick={() => go(it)}>
                        {it.label} {it.hint && <small style={{ marginLeft: 8 }}>{it.hint}</small>}
                      </button>
                      {it.alt && (
                        <span className="acts">
                          <button type="button" className="chip" style={{ height: 26 }} onClick={() => go(it)}>{it.k === 'Markets' ? 'Trades' : 'Learn'}</button>
                          <button type="button" className="chip" style={{ height: 26 }} onClick={() => go(it, true)}>{it.k === 'Markets' ? 'Backtest' : 'Trades'}</button>
                        </span>
                      )}
                    </div>
                  </div>
                );
              })}
              {!items.length && <div className="empty"><b>No match</b>Try a market name like “Boom 1000” or “XAUUSD”.</div>}
            </div>
            <div className="hint"><span><span className="kbd">↑↓</span> move</span><span><span className="kbd">Enter</span> open</span><span><span className="kbd">Shift+Enter</span> second option</span><span><span className="kbd">Esc</span> close</span></div>
          </motion.div>
        </motion.div>
      )}
    </AnimatePresence>
  );
}
