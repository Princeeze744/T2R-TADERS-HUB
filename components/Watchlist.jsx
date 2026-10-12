'use client';
import { useMemo, useState } from 'react';
import { useData } from './DataProvider';
import StoryDrawer from './StoryDrawer';
import { PickList, bestPerMarket } from './Overview';
import { Reveal, Select, Seg } from './ui';
import { FAMS, STRATS, SYN, SM, LV, SMN, LVN } from '@/lib/constants';
import { f2, f1, cl, pc, summarise, rrTxt, strengthOf, nf } from '@/lib/util';

export default function Watchlist() {
  const { data } = useData();
  const [fam, setFam] = useState('');
  const [st, setSt] = useState('');
  const [str, setStr] = useState('All');
  const [q, setQ] = useState('');
  const [story, setStory] = useState(null);
  const syn = useMemo(() => bestPerMarket(data.WATCH, (w) => SYN[w.fam]).slice(0, 5), [data]);
  const fx = useMemo(() => bestPerMarket(data.WATCH, (w) => w.fam === 'Forex' || w.fam === 'Metals').slice(0, 5), [data]);
  const rows = useMemo(() => data.WATCH.map((w) => {
    const rp = summarise(data.TRADES.filter((t) => t.a === w.a && t.s === w.s && t.v === w.v && t.sd === w.sd && t.c === w.c));
    return { ...w, ratio: LV[w.lv] / SM[w.si], strength: strengthOf(w), rp };
  }), [data]);
  const counts = useMemo(() => {
    const c = { Strong: 0, Promising: 0, Watch: 0 };
    rows.forEach((r) => { c[r.strength]++; });
    return c;
  }, [rows]);
  const list = rows.filter((w) => (!fam || w.fam === fam) && (!st || w.s === st) && (str === 'All' || w.strength === str) && (!q || w.a.toLowerCase().includes(q.toLowerCase())))
    .sort((a, b) => (a.strength === b.strength ? b.z - a.z : ['Strong', 'Promising', 'Watch'].indexOf(a.strength) - ['Strong', 'Promising', 'Watch'].indexOf(b.strength)));
  const open = (w) => setStory({ a: w.a, s: w.s, v: w.v, sd: w.sd, c: w.c, st: w.st, ratio: w.ratio, mix: `stop ${SMN[w.si]}, target ${LVN[w.lv]}`, t1: w.b1 });

  return (
    <div className="wrap">
      <div className="page-head">
        <Reveal><span className="eyebrow">Watchlist</span></Reveal>
        <Reveal delay={0.05}><h1 className="h-sec">{data.WATCH.length} setups, <em>followed live.</em></h1></Reveal>
        <Reveal delay={0.1}><p className="lead">Every setup that passed the exam, now running on the live demo. Strong means it made money in both unseen periods on at least 100 trades each. Promising made money on fewer trades.</p></Reveal>
      </div>

      <div className="grid g2">
        <Reveal><div className="between" style={{ marginBottom: 10 }}><h3 className="serif" style={{ fontSize: 26 }}>Today’s top 5 synthetics</h3></div><PickList list={syn} trades={data.TRADES} /></Reveal>
        <Reveal delay={0.08}><div className="between" style={{ marginBottom: 10 }}><h3 className="serif" style={{ fontSize: 26 }}>Today’s top 5 forex and metals</h3></div><PickList list={fx} trades={data.TRADES} /></Reveal>
      </div>

      <div className="sticky-bar" style={{ marginTop: 34 }}>
        <div className="toolbar">
          <Seg id="str" value={str} onChange={setStr} options={[{ value: 'All', label: `All ${rows.length}` }, { value: 'Strong', label: `Strong ${counts.Strong}` }, { value: 'Promising', label: `Promising ${counts.Promising}` }, { value: 'Watch', label: `Watch ${counts.Watch}` }]} />
          <Select label="Family" value={fam} onChange={setFam} options={FAMS.map((f) => ({ value: f, label: f }))} allLabel="All families" />
          <Select label="Strategy" value={st} onChange={setSt} options={STRATS.map((s) => ({ value: s, label: s }))} allLabel="All strategies" />
          <input className="field-btn" style={{ width: 200, outline: 0 }} placeholder="Search a market" value={q} onChange={(e) => setQ(e.target.value)} />
          <span className="note" style={{ marginLeft: 'auto' }}>{nf(list.length)} setups · click one for its full story</span>
        </div>
      </div>

      <div className="card tbl-wrap" style={{ marginTop: 10 }}>
        <table className="tbl">
          <thead><tr><th className="l">Market</th><th className="l">Strategy</th><th className="l">Side · stop</th><th>R:R</th><th>Stage 2</th><th>Stage 3</th><th>Won unseen</th><th className="l">Strength</th><th>In the journal</th></tr></thead>
          <tbody>
            {list.map((w) => {
              const un = w.st[1][0] + w.st[2][0], uw = w.st[1][1] + w.st[2][1];
              return (
                <tr key={w.i} className="click" onClick={() => open(w)}>
                  <td className="l b">{w.a}<small>{w.fam}</small></td>
                  <td className="l">{w.s}<small>{w.v}</small></td>
                  <td className="l">{w.sd}<small>{w.c}</small></td>
                  <td className="num">{rrTxt(w.ratio)}</td>
                  <td className={'num ' + cl(w.st[1][2])}>{f2(w.st[1][2])}R<small>{w.st[1][0]} trades</small></td>
                  <td className={'num ' + cl(w.st[2][2])}>{f2(w.st[2][2])}R<small>{w.st[2][0]} trades</small></td>
                  <td className="num">{pc(uw, un)}<small>needs {Math.round(100 / (1 + w.ratio))}%</small></td>
                  <td className="l"><span className={'badge ' + (w.strength === 'Strong' ? 'gold' : w.strength === 'Promising' ? 'open' : 'soft')}>{w.strength}</span></td>
                  <td className={'num ' + cl(w.rp.R)}>{w.rp.n ? f1(w.rp.R) + 'R' : '–'}<small>{w.rp.n} trades</small></td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>
      <StoryDrawer story={story} onClose={() => setStory(null)} />
    </div>
  );
}
