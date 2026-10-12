'use client';
import { useEffect, useMemo, useState } from 'react';
import Link from 'next/link';
import { useSearchParams } from 'next/navigation';
import { useData, wkey } from './DataProvider';
import StoryDrawer from './StoryDrawer';
import { Reveal, Select, Toggle } from './ui';
import { FAMS, STRATS, INFO, SM, LV, SMN, LVN } from '@/lib/constants';
import { f2, f1, cl, pc, nf, summarise, rrTxt } from '@/lib/util';

const minU = (st) => Math.min(st[1][2], st[2][2]);
const score = (r) => minU(r.st) + (r.pass ? 5 : 0) + (r.strong ? 1 : 0) - (Math.min(r.st[1][0], r.st[2][0]) < 40 ? 3 : 0);

function Cell({ t }) {
  if (!t || !t[0]) return <td className="num dimmer">–</td>;
  return <td className={'num ' + cl(t[2])}>{f2(t[2])}R<small>{pc(t[1], t[0])} of {t[0]}</small></td>;
}

export default function Explorer() {
  const { data } = useData();
  const sp = useSearchParams();
  const [fam, setFam] = useState('');
  const [mk, setMk] = useState(sp.get('mk') || '');
  const [st, setSt] = useState(sp.get('st') || '');
  const [sd, setSd] = useState('');
  const [c, setC] = useState('');
  const [po, setPo] = useState(sp.get('pass') === '1' || !!sp.get('st'));
  const [shown, setShown] = useState(150);
  const [story, setStory] = useState(null);
  useEffect(() => { setMk(sp.get('mk') || ''); if (sp.get('st')) setSt(sp.get('st')); }, [sp]);

  const list = useMemo(() => data.ROWS.filter((r) => (!fam || r.fam === fam) && (!mk || r.a === mk) && (!st || r.s === st) && (!sd || r.sd === sd) && (!c || r.c === c) && (!po || r.pass || r.strong)).sort((x, y) => score(y) - score(x)), [data, fam, mk, st, sd, c, po]);
  useEffect(() => setShown(150), [list]);
  const mkOpts = Object.keys(data.MK).filter((a) => !fam || data.MK[a].fam === fam).sort().map((a) => ({ value: a, label: a, group: data.MK[a].fam })).sort((x, y) => FAMS.indexOf(x.group) - FAMS.indexOf(y.group) || (x.label < y.label ? -1 : 1));

  const open = (r) => {
    if (r.best && !r.pass) { const b = r.best; setStory({ a: r.a, s: r.s, v: r.v, sd: r.sd, c: r.c, st: b[2], ratio: LV[b[1]] / SM[b[0]], mix: `stop ${SMN[b[0]]}, target ${LVN[b[1]]}` }); }
    else setStory({ a: r.a, s: r.s, v: r.v, sd: r.sd, c: r.c, st: r.st, ratio: 2, mix: 'stop 1x, target 2x (the standard setup)' });
  };

  let head = null;
  if (mk) {
    const m = data.MK[mk];
    const nP = data.ROWS.filter((r) => r.a === mk && (r.pass || r.strong)).length, nW = data.WATCH.filter((w) => w.a === mk).length;
    const rp = summarise(data.TRADES.filter((t) => t.a === mk));
    head = (
      <div className="card pad" style={{ marginTop: 6 }}>
        <div className="between">
          <div><span className="eyebrow">{m?.fam}</span><h2 className="serif" style={{ fontSize: 36, marginTop: 6 }}>{mk}</h2><p className="dim" style={{ margin: '4px 0 0', fontSize: 13.5 }}>{m ? `${nf(m.bars)} fifteen-minute candles tested, ${m.from} to ${m.to}${m.status === 'short' ? ' (all the history the broker has)' : ''}` : ''}</p></div>
          <div className="row" style={{ gap: 24 }}>
            <div><b className="serif" style={{ fontSize: 34 }}>{nP}</b><div className="note">setups passed</div></div>
            <div><b className="serif" style={{ fontSize: 34 }}>{nW}</b><div className="note">followed live</div></div>
            <div><b className={'serif ' + cl(rp.R)} style={{ fontSize: 34 }}>{rp.n ? f1(rp.R) + 'R' : '–'}</b><div className="note">{rp.n} trades in the journal</div></div>
            <Link href={'/journal?mk=' + encodeURIComponent(mk)} className="btn ghost sm">See its trades</Link>
          </div>
        </div>
      </div>
    );
  } else if (st) {
    const mks = new Set(list.filter((r) => r.pass || r.strong).map((r) => r.a)).size;
    head = <div className="card pad" style={{ marginTop: 6 }}><span className="eyebrow">Strategy</span><h2 className="serif" style={{ fontSize: 36, marginTop: 6 }}>{st}</h2><p className="dim" style={{ margin: '6px 0 0' }}>{INFO[st].one} Passed on <b style={{ color: 'var(--text)' }}>{mks}</b> markets.</p></div>;
  }

  return (
    <div className="wrap">
      <div className="page-head">
        <Reveal><span className="eyebrow">Backtest explorer</span></Reveal>
        <Reveal delay={0.05}><h1 className="h-sec">Every strategy on <em>every market.</em></h1></Reveal>
        <Reveal delay={0.1}><p className="lead">{nf(data.ROWS.length)} combinations. Stage cells show the average result per trade with the standard setup (risk 1 to make 2), the win rate and the number of trades. Stages 2 and 3 are history the strategy never saw.</p></Reveal>
      </div>
      <div className="sticky-bar">
        <div className="toolbar">
          <Select label="Family" value={fam} onChange={(v) => { setFam(v); if (v && mk && data.MK[mk]?.fam !== v) setMk(''); }} options={FAMS.map((f) => ({ value: f, label: f }))} allLabel="All families" />
          <Select label="Market" value={mk} onChange={setMk} options={mkOpts} allLabel="All markets" searchable />
          <Select label="Strategy" value={st} onChange={setSt} options={STRATS.map((s) => ({ value: s, label: s }))} allLabel="All strategies" />
          <Select label="Side" value={sd} onChange={setSd} options={['Both', 'Buys', 'Sells'].map((s) => ({ value: s, label: s }))} allLabel="All sides" />
          <Select label="Stop class" value={c} onChange={setC} options={['Tight', 'Medium', 'Wide'].map((s) => ({ value: s, label: s }))} allLabel="All" />
          <Toggle checked={po} onChange={setPo}>Passed only</Toggle>
          <span className="note" style={{ marginLeft: 'auto' }}>{nf(list.length)} results</span>
        </div>
      </div>
      {head}
      <div className="card tbl-wrap" style={{ marginTop: 12 }}>
        <table className="tbl">
          <thead><tr><th className="l">Market</th><th className="l">Strategy</th><th className="l">Side · stop</th><th>Stage 1</th><th>Stage 2</th><th>Stage 3</th><th className="l">Verdict</th><th className="l">Best stop and target</th></tr></thead>
          <tbody>
            {list.slice(0, shown).map((r) => {
              const fol = data.WSET[wkey(r.a, r.s, r.v, r.sd, r.c)];
              const b = r.best;
              return (
                <tr key={r.i} className="click" onClick={() => open(r)}>
                  <td className="l b">{r.a}<small>{r.fam}</small></td>
                  <td className="l">{r.s}<small>{r.v}</small></td>
                  <td className="l">{r.sd}<small>{r.c}</small></td>
                  <Cell t={r.st[0]} /><Cell t={r.st[1]} /><Cell t={r.st[2]} />
                  <td className="l"><span className="row" style={{ gap: 4 }}>{r.pass ? <span className="badge won">PASS</span> : r.strong ? <span className="badge gold">STRONGHOLD</span> : <span className="badge soft">NO</span>}{fol && <span className="badge live">LIVE</span>}</span></td>
                  <td className="l">{b ? <>{rrTxt(LV[b[1]] / SM[b[0]])}<small>exam <span className={cl(b[2][2][2])}>{f2(b[2][2][2])}R</span> · {pc(b[2][2][1], b[2][2][0])} of {b[2][2][0]}</small></> : <span className="dimmer">none passed</span>}</td>
                </tr>
              );
            })}
            {!list.length && <tr><td className="l dim" colSpan={8}>Nothing matches these filters.</td></tr>}
          </tbody>
        </table>
      </div>
      {shown < list.length && <div style={{ textAlign: 'center', padding: 24 }}><button type="button" className="btn ghost sm" onClick={() => setShown((s) => s + 300)}>Show more ({nf(list.length - shown)} left)</button></div>}
      <StoryDrawer story={story} onClose={() => setStory(null)} />
    </div>
  );
}
