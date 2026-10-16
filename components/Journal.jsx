'use client';
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { useRouter, useSearchParams, usePathname } from 'next/navigation';
import { motion } from 'framer-motion';
import { useData } from './DataProvider';
import DateRange from './DateRange';
import TradeDrawer from './TradeDrawer';
import { EquityChart } from './Charts';
import { Select, Seg, Toggle, Ring, Reveal, ease } from './ui';
import { FAMS, STRATS, STRATS_LIVE, FAM_SHORT, spikeGroupOf, SETUPS, SETUP, setupOf } from '@/lib/constants';
const SPIKE_GROUPS = ['Boom & Crash', 'DEX', 'Vol over', 'Trek', 'Crash Boom Flip'];
import { summarise, capPerDay, groupBy, f2, f1, cl, money, pc, nf, dayKey, dayLabel, hhmm, fmtPrice, weekStart, addDays, shortDate } from '@/lib/util';

const STEP = 120;

export default function Journal() {
  const { data, risk } = useData();
  const sp = useSearchParams();
  const router = useRouter();
  const pathname = usePathname();
  const all = data.TRADES;

  const todayKey = dayKey(Date.now() / 1000);
  const minK = all.length ? all[0].day : todayKey;
  const maxK = todayKey > (all.length ? all[all.length - 1].day : todayKey) ? todayKey : all[all.length - 1].day;

  const q = {
    from: sp.get('from') || minK, to: sp.get('to') || maxK,
    set: sp.get('set') || '', fam: sp.get('fam') || '', sg: sp.get('sg') || '', mk: sp.get('mk') || '', st: sp.get('st') || '',
    res: sp.get('res') || 'all', dir: sp.get('dir') || '', src: sp.get('src') || '',
    cap: sp.get('cap') === '1', sort: sp.get('sort') || 'new', t: sp.get('t') || '',
  };
  const set = useCallback((patch) => {
    const p = new URLSearchParams(sp.toString());
    Object.entries(patch).forEach(([k, v]) => { if (v === '' || v == null || v === false || (k === 'res' && v === 'all') || (k === 'sort' && v === 'new')) p.delete(k); else p.set(k, v === true ? '1' : v); });
    if (p.get('from') === minK && p.get('to') === maxK) { p.delete('from'); p.delete('to'); }
    const s = p.toString();
    router.replace(pathname + (s ? '?' + s : ''), { scroll: false });
  }, [sp, router, pathname, minK, maxK]);

  // everything except the date range (for the calendar heat)
  const base = useMemo(() => {
    let L = all.filter((t) => (!q.set || setupOf(t) === q.set) && (!q.fam || t.fam === q.fam) && (!q.sg || spikeGroupOf(t.a) === q.sg) && (!q.mk || t.a === q.mk) && (!q.st || t.s === q.st) && (!q.dir || t.dir === q.dir) && (!q.src || t.src === q.src));
    if (q.cap) L = capPerDay(L, 2);
    return L;
  }, [all, q.set, q.fam, q.sg, q.mk, q.st, q.dir, q.src, q.cap]);
  const dayStats = useMemo(() => {
    const m = new Map();
    base.forEach((t) => { const s = m.get(t.day) || { n: 0, R: 0 }; s.n++; if (t.res !== 'open') s.R += t.R; m.set(t.day, s); });
    return m;
  }, [base]);
  const inRange = useMemo(() => base.filter((t) => t.day >= q.from && t.day <= q.to), [base, q.from, q.to]);
  const list = useMemo(() => {
    const L = inRange.filter((t) => q.res === 'all' || t.res === q.res);
    const f = { new: (a, b) => b.tin - a.tin, old: (a, b) => a.tin - b.tin, best: (a, b) => (b.R ?? -99) - (a.R ?? -99), worst: (a, b) => (a.R ?? 99) - (b.R ?? 99) }[q.sort];
    return L.sort(f);
  }, [inRange, q.res, q.sort]);
  const S = useMemo(() => summarise(inRange), [inRange]);

  const [shown, setShown] = useState(STEP);
  useEffect(() => setShown(STEP), [list]);
  const more = useRef(null);
  useEffect(() => {
    const el = more.current;
    if (!el) return;
    const io = new IntersectionObserver((e) => { if (e[0].isIntersecting) setShown((s) => s + STEP); }, { rootMargin: '600px' });
    io.observe(el);
    return () => io.disconnect();
  }, [list, shown]);

  const days = useMemo(() => {
    const g = groupBy(inRange, (t) => t.day);
    const out = [];
    for (let k = q.from; k <= q.to; k = addDays(k, 1)) { if (g.has(k)) out.push([k, summarise(g.get(k))]); if (out.length > 120) break; }
    return out;
  }, [inRange, q.from, q.to]);
  const weeks = useMemo(() => [...groupBy(inRange, (t) => weekStart(t.day)).entries()].sort((a, b) => (a[0] < b[0] ? 1 : -1)).map(([k, L]) => [k, summarise(L)]), [inRange]);
  const byMarket = useMemo(() => [...groupBy(inRange, (t) => t.a).entries()].map(([k, L]) => ({ k, ...summarise(L) })).sort((a, b) => b.R - a.R), [inRange]);
  const byStrat = useMemo(() => [...groupBy(inRange, (t) => t.s).entries()].map(([k, L]) => ({ k, ...summarise(L) })).sort((a, b) => b.R - a.R), [inRange]);

  const marketOpts = useMemo(() => {
    const cnt = {};
    all.forEach((t) => { cnt[t.a] = (cnt[t.a] || 0) + 1; });
    return Object.keys(cnt).filter((a) => !q.fam || data.famOf(a) === q.fam).sort().map((a) => ({ value: a, label: a, hint: cnt[a] + ' trades', group: data.famOf(a) }))
      .sort((x, y) => FAMS.indexOf(x.group) - FAMS.indexOf(y.group) || (x.label < y.label ? -1 : 1));
  }, [all, q.fam, data]);

  const trade = q.t ? data.TBYID[q.t] : null;
  const anyFilter = q.set || q.fam || q.sg || q.mk || q.st || q.dir || q.src || q.cap || q.res !== 'all';
  const maxDay = Math.max(1, ...days.map((d) => Math.abs(d[1].R)));
  const maxMk = Math.max(1, ...byMarket.map((m) => Math.abs(m.R)));
  const visible = list.slice(0, shown);
  const groups = q.sort === 'new' || q.sort === 'old' ? [...groupBy(visible, (t) => t.day).entries()] : [['', visible]];
  const range = q.from === q.to ? dayLabel(q.from, true) : `${dayLabel(q.from)} to ${dayLabel(q.to)} ${q.to.slice(0, 4)}`;

  return (
    <div className="wrap">
      <div className="page-head">
        <Reveal><span className="eyebrow">Trade journal</span></Reveal>
        <Reveal delay={0.05}><h1 className="h-sec">Every trade, <em>day by day.</em></h1></Reveal>
        <Reveal delay={0.1}><p className="lead">Pick any dates and see every trade the followed setups took: where it entered, where the stop and target sat, and how it ended. Click a trade to watch it on the chart.</p></Reveal>
      </div>

      <div className="shelves">
        <Seg id="jset" value={q.set} onChange={(v) => set({ set: v })} options={[{ value: '', label: 'All setups' }, ...SETUPS.map((x) => ({ value: x.k, label: x.e + ' ' + x.t }))]} />
        <Seg id="jfam" value={q.fam} onChange={(v) => set({ fam: v, sg: '', mk: v && q.mk && data.famOf(q.mk) !== v ? '' : q.mk })} options={[{ value: '', label: 'All markets' }, ...FAMS.map((f) => ({ value: f, label: FAM_SHORT[f] }))]} />
        {q.fam === 'Catching Spikes' && (
          <Seg id="jsg" value={q.sg} onChange={(v) => set({ sg: v, mk: '' })} options={[{ value: '', label: 'All spikes' }, ...SPIKE_GROUPS.map((g) => ({ value: g, label: g }))]} />
        )}
      </div>
      <div className="sticky-bar">
        <div className="toolbar">
          <DateRange from={q.from} to={q.to} min={minK} max={maxK} todayKey={todayKey} dayStats={dayStats} onChange={(from, to) => set({ from, to })} />
          <Select label="Family" value={q.fam} onChange={(v) => set({ fam: v, mk: v && q.mk && data.famOf(q.mk) !== v ? '' : q.mk })} options={FAMS.map((f) => ({ value: f, label: f }))} allLabel="All families" />
          <Select label="Market" value={q.mk} onChange={(v) => set({ mk: v })} options={marketOpts} allLabel="All markets" searchable />
          <Select label="Strategy" value={q.st} onChange={(v) => set({ st: v })} options={[...STRATS_LIVE, ...STRATS].map((s) => ({ value: s, label: s }))} allLabel="All strategies" />
          <Select label="Order" value={q.dir} onChange={(v) => set({ dir: v })} options={[{ value: 'buy', label: 'Buys' }, { value: 'sell', label: 'Sells' }]} allLabel="Buys and sells" />
          <Select label="Source" value={q.src} onChange={(v) => set({ src: v })} options={[{ value: 'r', label: 'Replay of past days' }, { value: 'l', label: 'Live demo' }]} allLabel="Replay + live demo" right />
          <Toggle checked={q.cap} onChange={(v) => set({ cap: v })}>Telegram plan: max 2 a market a day</Toggle>
          {anyFilter && <button type="button" className="chip" onClick={() => set({ set: '', fam: '', sg: '', mk: '', st: '', dir: '', src: '', cap: false, res: 'all' })}>Clear filters</button>}
        </div>
      </div>

      <div className="between" style={{ margin: '18px 0 14px' }}>
        <h2 className="serif" style={{ fontSize: 28 }}>{range}</h2>
        <span className="dim" style={{ fontSize: 13 }}>{q.set ? SETUP[q.set].e + ' ' + SETUP[q.set].t + ' · ' : ''}{q.mk || q.sg || q.fam || 'All markets'}{q.st ? ' · ' + q.st : ''}</span>
      </div>

      <div className="kpis">
        <Kpi l="Trades" v={nf(S.n)} s={`${S.closed} closed · ${S.o} open`} />
        <Kpi l="Win rate" v={pc(S.w, S.closed)} s={`${S.w} won · ${S.l} lost`} ring={S.wr} />
        <Kpi l="Net result" v={f1(S.R) + 'R'} c={cl(S.R)} s={money(S.R, risk) + ' at $' + risk + ' a trade'} />
        <Kpi l="Average trade" v={f2(S.avg) + 'R'} c={cl(S.avg)} s="after spread" />
        <Kpi l="Profit factor" v={S.pf === Infinity ? '∞' : S.pf.toFixed(2)} c={S.pf >= 1 ? 'g' : S.closed ? 'r' : ''} s="won R ÷ lost R" />
        <Kpi l="Longest losing run" v={S.streak} s="losses in a row" />
      </div>

      <div className="grid" style={{ gridTemplateColumns: 'minmax(0,1fr)', marginTop: 16 }}>
        <div className="card">
          <div className="between" style={{ padding: '16px 18px 0' }}>
            <div><div className="eyebrow">Running total</div><p className="dim" style={{ margin: '6px 0 0', fontSize: 13.5 }}>Closed trades added up in R, in the order they closed.</p></div>
            <span className={'serif ' + cl(S.R)} style={{ fontSize: 34 }}>{f1(S.R)}R</span>
          </div>
          <div style={{ padding: '6px 6px 8px' }}><EquityChart trades={inRange} height={250} /></div>
        </div>
      </div>

      {days.length > 1 && (
        <div className="card pad" style={{ marginTop: 16 }}>
          <div className="between" style={{ marginBottom: 14 }}>
            <div className="eyebrow">Day by day</div><span className="note">Click a day to open it</span>
          </div>
          <div className="days">
            {days.map(([k, s]) => {
              const h = Math.max(2, (Math.abs(s.R) / maxDay) * 36);
              return (
                <button type="button" key={k} className="dayb" onClick={() => set({ from: k, to: k })}>
                  <span className="d">{dayLabel(k)}</span>
                  <div className="bar">
                    <motion.span className={s.R < 0 ? 'neg' : 'pos'} style={{ height: h }} initial={{ scaleY: 0 }} animate={{ scaleY: 1 }} transition={{ duration: 0.6, ease }} />
                  </div>
                  <span className={'R ' + cl(s.R)}>{f1(s.R)}R</span>
                  <span className="w">{s.n} trades · {pc(s.w, s.closed)}</span>
                </button>
              );
            })}
          </div>
        </div>
      )}

      <div className="grid g2" style={{ marginTop: 16 }}>
        <div className="card">
          <div className="between" style={{ padding: '16px 18px 6px' }}><div className="eyebrow">Week by week</div><span className="note">Mon to Sun · click a week</span></div>
          <div className="tbl-wrap">
            <table className="tbl">
              <thead><tr><th className="l">Week</th><th>Trades</th><th>Won</th><th>Lost</th><th>Win rate</th><th>Result</th></tr></thead>
              <tbody>
                {weeks.map(([k, s]) => (
                  <tr key={k} className="click" onClick={() => set({ from: k, to: addDays(k, 6) > maxK ? maxK : addDays(k, 6) })}>
                    <td className="l b">{shortDate(k)} – {shortDate(addDays(k, 6))}</td><td className="num">{s.n}</td><td className="num">{s.w}</td><td className="num">{s.l}</td><td className="num">{pc(s.w, s.closed)}</td>
                    <td className={'num ' + cl(s.R)}>{f1(s.R)}R<small>{money(s.R, risk)}</small></td>
                  </tr>
                ))}
                {!weeks.length && <tr><td className="l dim" colSpan={6}>No trades in these dates.</td></tr>}
              </tbody>
            </table>
          </div>
        </div>
        <div className="card">
          <div className="between" style={{ padding: '16px 18px 6px' }}><div className="eyebrow">By strategy</div><span className="note">click to filter</span></div>
          <div className="tbl-wrap">
            <table className="tbl">
              <thead><tr><th className="l">Strategy</th><th>Trades</th><th>Win rate</th><th>Result</th></tr></thead>
              <tbody>
                {byStrat.map((s) => (
                  <tr key={s.k} className="click" onClick={() => set({ st: q.st === s.k ? '' : s.k })}>
                    <td className="l b">{s.k}</td><td className="num">{s.n}</td><td className="num">{pc(s.w, s.closed)}</td><td className={'num ' + cl(s.R)}>{f1(s.R)}R</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      </div>

      {byMarket.length > 1 && (
        <div className="card pad" style={{ marginTop: 16 }}>
          <div className="between" style={{ marginBottom: 12 }}><div className="eyebrow">Markets in this period</div><span className="note">{byMarket.length} markets · best first · click to filter</span></div>
          <div className="grid" style={{ gridTemplateColumns: 'repeat(auto-fill,minmax(250px,1fr))', gap: 8 }}>
            {byMarket.slice(0, 24).map((m) => (
              <button type="button" key={m.k} className="opt" style={{ display: 'grid', gridTemplateColumns: '1fr auto', gap: 6, padding: '10px 12px', border: '1px solid var(--line)' }} onClick={() => set({ mk: m.k })}>
                <span style={{ overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap', fontWeight: 600 }}>{m.k}</span>
                <span className={'mono ' + cl(m.R)}>{f1(m.R)}R</span>
                <span className="prog" style={{ gridColumn: '1 / -1' }}><i style={{ width: (Math.abs(m.R) / maxMk) * 100 + '%', background: m.R >= 0 ? 'var(--win)' : 'var(--loss)' }} /></span>
                <small className="dimmer">{m.n} trades · {pc(m.w, m.closed)} won</small>
              </button>
            ))}
          </div>
        </div>
      )}

      <div className="sec" style={{ paddingTop: 40 }}>
        <div className="between">
          <div><h2 className="h-sec" style={{ fontSize: 'clamp(28px,3.4vw,40px)' }}>The trades</h2><p className="dim" style={{ margin: '6px 0 0' }}>{nf(list.length)} trades · click one to see it on the chart</p></div>
          <div className="row">
            <Seg id="res" value={q.res} onChange={(v) => set({ res: v })} options={[{ value: 'all', label: 'All' }, { value: 'won', label: 'Won' }, { value: 'lost', label: 'Lost' }, { value: 'open', label: 'Open' }]} />
            <Select label="Sort" value={q.sort === 'new' ? '' : q.sort} onChange={(v) => set({ sort: v || 'new' })} options={[{ value: 'old', label: 'Oldest first' }, { value: 'best', label: 'Best result' }, { value: 'worst', label: 'Worst result' }]} allLabel="Newest first" right />
          </div>
        </div>

        {!list.length && <div className="card empty" style={{ marginTop: 20 }}><b>No trades here</b>Try other dates, or clear the filters.</div>}

        {groups.map(([k, L]) => {
          const ds = k ? summarise(inRange.filter((t) => t.day === k)) : null;
          return (
            <div className="tday" key={k || 'all'}>
              {k && (
                <div className="tday-h">
                  <b>{dayLabel(k, true)}</b>
                  <div className="m"><span>{ds.n} trades</span><span>{ds.w} won · {ds.l} lost</span><span className={'mono ' + cl(ds.R)} style={{ fontSize: 14 }}>{f1(ds.R)}R</span></div>
                </div>
              )}
              <div className="trow trow-h"><span>Time</span><span>Market</span><span>Strategy</span><span>Order</span><span style={{ textAlign: 'right' }}>Entry</span><span style={{ textAlign: 'right' }}>Stop</span><span style={{ textAlign: 'right' }}>Target</span><span style={{ textAlign: 'right' }}>R:R</span><span>Result</span><span style={{ textAlign: 'right' }}>R</span></div>
              {L.map((t) => <Row key={t.id} t={t} onOpen={() => set({ t: t.id })} showDay={!k} />)}
            </div>
          );
        })}
        {shown < list.length && <div ref={more} style={{ padding: 30, textAlign: 'center' }}><button type="button" className="btn ghost sm" onClick={() => setShown((s) => s + STEP)}>Show more ({nf(list.length - shown)} left)</button></div>}
      </div>

      <TradeDrawer trade={trade} list={list} onClose={() => set({ t: '' })} onNav={(id) => set({ t: id })} />
    </div>
  );
}

function Kpi({ l, v, s, c = '', ring }) {
  return (
    <div className="card kpi">
      <div className="l"><span>{l}</span>{ring != null && <Ring value={ring} size={30} />}</div>
      <div className={'v ' + c}>{v}</div>
      <div className="s">{s}</div>
    </div>
  );
}

function Row({ t, onOpen, showDay }) {
  return (
    <motion.button type="button" className="trow" onClick={onOpen} initial={{ opacity: 0 }} animate={{ opacity: 1 }} transition={{ duration: 0.25 }}>
      <span className="t">{showDay ? dayLabel(t.day).slice(4) + ' ' : ''}{hhmm(t.tin)}</span>
      <span className="mk">{t.a}<small>{SETUP[setupOf(t)].e} {SETUP[setupOf(t)].t} · {t.fam}{t.src === 'l' ? ' · live demo' : ''}</small></span>
      <span className="st">{t.s}<small>{t.v} · {t.c}</small></span>
      <span><span className={'badge ' + t.dir}>{t.dir.toUpperCase()}</span></span>
      <span className="p">{fmtPrice(t.e, t.e)}</span>
      <span className="p r">{fmtPrice(t.sl, t.e)}</span>
      <span className="p g">{fmtPrice(t.tp, t.e)}</span>
      <span className="p rr">{t.rr}</span>
      <span><span className={'badge ' + t.res}>{t.res === 'open' ? 'OPEN' : t.res.toUpperCase()}</span></span>
      <span className={'Rv ' + (t.res === 'open' ? 'o' : cl(t.R))}>{t.res === 'open' ? '…' : f2(t.R)}</span>
    </motion.button>
  );
}
