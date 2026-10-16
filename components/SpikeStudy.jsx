'use client';
import { useEffect, useMemo, useState } from 'react';
import Link from 'next/link';
import { motion } from 'framer-motion';
import { Reveal, Seg, Counter, ease } from './ui';
import { useData } from './DataProvider';
import { IcArrow } from './Icons';

const MON = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const sR = (x, d = 0) => (x >= 0 ? '+' : '−') + Math.abs(x).toFixed(d) + 'R';
const pct = (x) => Math.round(x * 100) + '%';
const cls = (x) => (x > 0 ? 'g' : x < 0 ? 'r' : 'n');

// ---------- running total, with vs against the spike ----------
function Curve({ eq }) {
  const W = 1000, H = 300, P = 28;
  const pts = (k) => eq[k] || [];
  const all = [...pts('with'), ...pts('against')];
  if (!all.length) return null;
  const days = [...new Set(all.map((p) => p[0]))].sort();
  const ix = Object.fromEntries(days.map((d, i) => [d, i]));
  const vals = all.map((p) => p[1]);
  const lo = Math.min(0, ...vals), hi = Math.max(0, ...vals);
  const x = (d) => P + (ix[d] / Math.max(1, days.length - 1)) * (W - 2 * P);
  const y = (v) => H - P - ((v - lo) / (hi - lo || 1)) * (H - 2 * P);
  const path = (k) => pts(k).map((p, i) => (i ? 'L' : 'M') + x(p[0]).toFixed(1) + ',' + y(p[1]).toFixed(1)).join('');
  const months = days.filter((d, i) => i === 0 || d.slice(5, 7) !== days[i - 1].slice(5, 7));
  return (
    <svg viewBox={`0 0 ${W} ${H}`} className="ss-curve" role="img" aria-label="Running total of R, with the spike and against the spike">
      <defs>
        <linearGradient id="ssg" x1="0" x2="0" y1="0" y2="1"><stop offset="0" stopColor="var(--win)" stopOpacity=".28" /><stop offset="1" stopColor="var(--win)" stopOpacity="0" /></linearGradient>
      </defs>
      <line x1={P} x2={W - P} y1={y(0)} y2={y(0)} stroke="rgba(255,255,255,.12)" strokeDasharray="4 6" />
      {months.map((d) => (
        <g key={d}>
          <line x1={x(d)} x2={x(d)} y1={P} y2={H - P} stroke="rgba(255,255,255,.04)" />
          <text x={x(d) + 4} y={H - 8} fill="var(--dim)" fontSize="13" fontFamily="var(--mono)">{MON[+d.slice(5, 7) - 1]}</text>
        </g>
      ))}
      <motion.path d={path('with') + `L${x(pts('with').at(-1)[0])},${y(lo)}L${x(pts('with')[0][0])},${y(lo)}Z`} fill="url(#ssg)" initial={{ opacity: 0 }} whileInView={{ opacity: 1 }} viewport={{ once: true }} transition={{ duration: 1.2, delay: 0.6 }} />
      <motion.path d={path('against')} fill="none" stroke="var(--loss)" strokeWidth="2" strokeOpacity=".85" initial={{ pathLength: 0 }} whileInView={{ pathLength: 1 }} viewport={{ once: true }} transition={{ duration: 1.8, ease }} />
      <motion.path d={path('with')} fill="none" stroke="var(--win)" strokeWidth="2.6" initial={{ pathLength: 0 }} whileInView={{ pathLength: 1 }} viewport={{ once: true }} transition={{ duration: 1.8, ease }} />
      <text x={W - P} y={Math.max(18, y(pts('with').at(-1)[1]) - 14)} textAnchor="end" fill="var(--win)" fontSize="15" fontFamily="var(--mono)">With the spike {sR(pts('with').at(-1)[1])}</text>
      <text x={W - P - 60} y={Math.min(H - 34, y(pts('against').at(-1)[1]) - 12)} textAnchor="end" fill="var(--loss)" fontSize="15" fontFamily="var(--mono)">Against {sR(pts('against').at(-1)[1])}</text>
    </svg>
  );
}

function Months({ months }) {
  const mx = Math.max(1, ...months.map((m) => Math.max(Math.abs(m.w), Math.abs(m.a))));
  return (
    <div className="ss-months">
      {months.map((m, i) => (
        <div key={m.m} className="ss-mon">
          <div className="bars">
            {[['w', 'var(--win)'], ['a', 'var(--loss)']].map(([k, c]) => (
              <motion.span key={k} className="bar" title={(k === 'w' ? 'With the spike ' : 'Against ') + sR(m[k], 1)}
                style={{ height: Math.max(3, (Math.abs(m[k]) / mx) * 100) + '%', background: m[k] >= 0 ? c : 'transparent', border: m[k] >= 0 ? 'none' : `1.5px dashed ${c}` }}
                initial={{ scaleY: 0 }} whileInView={{ scaleY: 1 }} viewport={{ once: true }} transition={{ duration: 0.7, delay: i * 0.05, ease }} />
            ))}
          </div>
          <b className={cls(m.w)}>{sR(m.w)}</b>
          <span>{MON[+m.m - 1]}</span>
        </div>
      ))}
    </div>
  );
}

export default function SpikeStudy() {
  const { risk } = useData() || { risk: 10 };
  const [S, setS] = useState(null);
  const [rrSel, setRrSel] = useState(3);
  const [bal, setBal] = useState(1000);
  useEffect(() => { fetch('/data/spike_study.json').then((r) => r.json()).then(setS).catch(() => setS(false)); }, []);
  const row = useMemo(() => S && S.rr.find((r) => r.rr === rrSel), [S, rrSel]);
  if (S === false) return <div className="wrap page-head"><p className="lead">The study could not load. Refresh the page.</p></div>;
  if (!S) return <div className="wrap page-head"><p className="lead dim">Loading the spike study…</p></div>;
  const perTrade = bal * 0.0025;
  const pos = S.markets.filter((m) => m.R > 0 && m.n >= 10).length;

  return (
    <div className="wrap ss">
      <div className="page-head">
        <Reveal><span className="eyebrow">Research · Catching spikes · Jan – Oct 2026</span></Reveal>
        <Reveal delay={0.05}><h1 className="h-display" style={{ marginTop: 18 }}>Catch the spike.<br /><em>Ride the drift.</em></h1></Reveal>
        <Reveal delay={0.1}>
          <p className="lead">We tested {S.tested.toLocaleString('en-US')} trades on {S.markets_tested} markets, every candle from 1 January to {new Date(S.period[1]).getUTCDate()} October 2026, after spread. On Boom &amp; Crash, one rule held all year: <b style={{ color: 'var(--text)' }}>buy Boom, sell Crash</b>. The same setup traded the other way lost money at every target size.</p>
        </Reveal>
      </div>

      <div className="kpis ss-kpis">
        {[
          [<Counter key="a" value={S.tested} />, 'test trades', 'every stop and target size'],
          [<span key="b" className="g">{sR(S.rr.find((r) => r.rr === 3).R)}</span>, 'with the spike, 1:3', `${S.rr.find((r) => r.rr === 3).n.toLocaleString('en-US')} trades on Boom & Crash`],
          [<span key="c" className="r">{sR(S.rr.find((r) => r.rr === 3).against)}</span>, 'against the spike, 1:3', 'the same setup, other side'],
          [<span key="d">{pos}<small className="dim"> / {S.markets.filter((m) => m.n >= 10).length}</small></span>, 'markets in profit', 'with the spike, 1:3'],
        ].map(([v, l, s], i) => (
          <Reveal key={l} delay={i * 0.05}><div className="card kpi"><span className="l">{l}</span><span className="v">{v}</span><span className="s">{s}</span></div></Reveal>
        ))}
      </div>

      <section className="sec-sm">
        <Reveal><div className="card pad">
          <div className="between" style={{ flexWrap: 'wrap', gap: 10 }}>
            <div><span className="eyebrow">Boom &amp; Crash · Self-taught Zones · Wide stop · 1:3</span><h2 className="serif" style={{ fontSize: 34, margin: '8px 0 0' }}>The same zones. Opposite sides.</h2></div>
            <span className="dim" style={{ fontSize: 13 }}>Running total of R, Jan – Oct 2026</span>
          </div>
          <Curve eq={S.equity} />
        </div></Reveal>
      </section>

      <section className="sec-sm">
        <div className="sec-head"><div><Reveal><span className="eyebrow">Pick your target</span></Reveal><Reveal delay={0.05}><h2 className="h-sec" style={{ marginTop: 10 }}>Every target size, <em>side by side.</em></h2></Reveal></div></div>
        <Reveal><div className="card pad">
          <div className="between" style={{ flexWrap: 'wrap', gap: 12, marginBottom: 14 }}>
            <Seg id="ssrr" value={rrSel} onChange={setRrSel} options={S.rr.map((r) => ({ value: r.rr, label: '1:' + r.rr }))} />
            <label className="risk" style={{ height: 36 }}><span className="lbl">Account</span>$<input type="number" min="10" step="10" value={bal} onChange={(e) => { const v = parseFloat(e.target.value); if (v > 0) setBal(v); }} aria-label="Account size" /></label>
          </div>
          {row && (
            <motion.div key={rrSel} initial={{ opacity: 0, y: 6 }} animate={{ opacity: 1, y: 0 }} transition={{ duration: 0.3, ease }} className="ss-rr">
              <div><span>Won</span><b>{pct(row.won)}</b><small>needs {pct(1 / (1 + row.rr))} to break even</small></div>
              <div><span>Total</span><b className={cls(row.R)}>{sR(row.R)}</b><small>≈ ${Math.round(row.R * perTrade).toLocaleString('en-US')} at 0.25% risk</small></div>
              <div><span>Worst dip</span><b className="r">{sR(row.dd)}</b><small>≈ −${Math.round(-row.dd * perTrade).toLocaleString('en-US')}</small></div>
              <div><span>Most losses in a row</span><b>{row.run}</b><small>{row.posM} of {row.months} months in profit</small></div>
              <div><span>Against the spike</span><b className={cls(row.against)}>{sR(row.against)}</b><small>same setup, other side</small></div>
              <div><span>Unseen months (Jul – Oct)</span><b className={cls(row.OOS)}>{sR(row.OOS)}</b><small>against: {sR(row.aOOS)}</small></div>
            </motion.div>
          )}
          <p className="note" style={{ marginTop: 14 }}>Money at 0.25% of a ${bal.toLocaleString('en-US')} account per trade (${perTrade.toFixed(2)}), without compounding. Settings were chosen on January – June and then checked on July – October, months they never saw.</p>
        </div></Reveal>
      </section>

      <section className="sec-sm">
        <div className="sec-head"><div><Reveal><span className="eyebrow">Month by month</span></Reveal><Reveal delay={0.05}><h2 className="h-sec" style={{ marginTop: 10 }}>Not a straight line. <em>Still up.</em></h2></Reveal></div>
          <span className="dim" style={{ fontSize: 13 }}><i className="dot g" /> with the spike &nbsp; <i className="dot r" /> against &nbsp; · dashed = a losing month</span></div>
        <Reveal><div className="card pad"><Months months={S.months} /></div></Reveal>
      </section>

      <section className="sec-sm">
        <div className="sec-head"><div><Reveal><span className="eyebrow">Every Boom &amp; Crash market · 1:3</span></Reveal><Reveal delay={0.05}><h2 className="h-sec" style={{ marginTop: 10 }}>Market by market.</h2></Reveal></div></div>
        <Reveal><div className="card tbl-wrap">
          <table className="tbl">
            <thead><tr><th className="l">Market</th><th>Side</th><th>Trades</th><th>Won</th><th>With the spike</th><th>Against</th></tr></thead>
            <tbody>
              {S.markets.map((m) => (
                <tr key={m.m}>
                  <td className="l b">{m.m}<small>{m.since > '2026-01-15' ? 'data from ' + m.since.slice(5).replace('-', '/') : 'full year'}</small></td>
                  <td><span className={'side ' + m.side}>{m.side === 'buy' ? 'BUY' : 'SELL'}</span></td>
                  <td className="mono">{m.n}</td>
                  <td className="mono">{m.n ? pct(m.won) : '–'}</td>
                  <td className={'mono b ' + cls(m.R)}>{m.n >= 10 ? sR(m.R, 1) : 'too few'}</td>
                  <td className={'mono ' + cls(m.aR)}>{m.aN >= 10 ? sR(m.aR, 1) : '–'}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div></Reveal>
      </section>

      <section className="sec-sm">
        <div className="grid ss-two">
          <Reveal><div className="card pad" style={{ height: '100%' }}>
            <span className="eyebrow">The other spike markets · same setup, 1:3</span>
            <h3 className="serif" style={{ fontSize: 28, margin: '8px 0 14px' }}>The edge lives in Boom &amp; Crash.</h3>
            <div className="tbl-wrap"><table className="tbl">
              <thead><tr><th className="l">Family</th><th>With</th><th>Against</th><th>Jul – Oct</th></tr></thead>
              <tbody>{S.families.map((f) => (
                <tr key={f.f}><td className="l b">{f.f}{f.verdict === 'edge' ? <small className="g">edge</small> : <small>no edge</small>}</td>
                  <td className={'mono ' + cls(f.w)}>{sR(f.w)}</td><td className={'mono ' + cls(f.a)}>{sR(f.a)}</td><td className={'mono ' + cls(f.wO)}>{sR(f.wO)}</td></tr>
              ))}</tbody>
            </table></div>
            <ul className="ss-list">{S.other.map((o) => <li key={o}>{o}</li>)}</ul>
          </div></Reveal>
          <Reveal delay={0.06}><div className="card pad" style={{ height: '100%' }}>
            <span className="eyebrow">Does price react at the zone?</span>
            <h3 className="serif" style={{ fontSize: 28, margin: '8px 0 6px' }}>Three times out of four. <em>But small.</em></h3>
            <p className="dim" style={{ marginTop: 0, fontSize: 13.5 }}>Every Boom &amp; Crash zone entry, all strategies, with the spike: how often price moved this far in profit before the stop.</p>
            <div className="tbl-wrap"><table className="tbl">
              <thead><tr><th className="l">Stop</th><th>+0.5×</th><th>+1×</th><th>+2×</th><th>+3×</th></tr></thead>
              <tbody>{S.reaction[0].rows.map((r) => (
                <tr key={r[0]}><td className="l b">{r[0]} zone</td>{r.slice(1).map((v, i) => <td key={i} className="mono">{pct(v)}</td>)}</tr>
              ))}</tbody>
            </table></div>
            <p className="note" style={{ marginTop: 12 }}>Grabbing a quick +0.5× with a 1× stop wins about 63% of the time, but it needs 67% to pay after spread. The money is in the zones the model picks and in holding for the bigger move.</p>
          </div></Reveal>
        </div>
      </section>


      <section className="sec-sm" id="drift">
        <Reveal><div className="card pad">
          <div className="between"><span className="rs-badge g">Proven edge · new</span><span className="note">5,507 trades · 20 Boom &amp; Crash markets · Jan – Oct 2026</span></div>
          <h2 className="serif" style={{ fontSize: 34, margin: '12px 0 6px' }}>The Drift Breakout. <em>Ride the walk between spikes.</em></h2>
          <p className="dim" style={{ marginTop: 0, fontSize: 14.5 }}>Mark the first 15-minute candle at 07:00 and 13:30 GMT. When price closes outside it, trade the break only if it goes with the drift: <b style={{ color: 'var(--text)' }}>sell Boom, buy Crash</b>. Stop half the candle, target 5R, out after 8 hours. Breaks the other way, with the spike, lost money, so the system skips them.</p>
          <div className="rs-stats">
            {[['Per trade, after spread', '+0.27R', 'g'], ['Total', '+1,473R', 'g'], ['Months in profit', '10 of 10', 'g'], ['Picked Jan – Jun → proven Jul – Oct', '+0.24R → +0.31R', 'g'], ['Breaks with the spike (skipped)', '−316R', 'r'], ['Win rate', '1 in 4', 'n']].map(([l, v, c]) => <div key={l}><span>{l}</span><b className={c}>{v}</b></div>)}
          </div>
          <div className="dr-bars">{[78, 83, 143, 96, 217, 143, 191, 185, 223, 114].map((v, i) => (
            <div key={i}><i style={{ height: (v / 223) * 100 + '%' }} /><span>{['J', 'F', 'M', 'A', 'M', 'J', 'J', 'A', 'S', 'O'][i]}</span><b>+{v}</b></div>
          ))}</div>
          <p className="note" style={{ marginTop: 12 }}>Every result is charged for the spike that jumps a stop (about −5R when it happens). Worst dip −80R and a longest losing run of 18, so it is traded at 0.25% risk: $1,000 → about +$3,680 over the ten months, with a worst dip of about −20%. October is to the 15th. Now live on the demo and on members' Telegram.</p>
        </div></Reveal>
      </section>
      <section className="sec-sm">
        <Reveal><div className="card pad ss-honest">
          <span className="eyebrow">Read this before trading it</span>
          <div className="grid ss-three">
            <div><b>Risk 0.25%, not 1%.</b><p>The worst dip at 1:3 was about −91R. At 1% risk that would empty an account. At 0.25% it is about −23%.</p></div>
            <div><b>Losing runs are normal.</b><p>At 1:3 you win about 3 trades in 10, and once lost 35 in a row. The profit comes from taking every signal, not picking.</p></div>
            <div><b>A backtest, then live proof.</b><p>Boom/Crash 99, 100 and 200 only have data from May. The live record on the Signal Desk is the proof that counts.</p></div>
          </div>
          <div className="hero-cta" style={{ marginTop: 18 }}>
            <Link href="/desk" className="btn primary"><span className="live-dot" />Live Signal Desk <IcArrow s={16} /></Link>
            <Link href="/journal?fam=Catching+Spikes&sg=Boom+%26+Crash" className="btn ghost">Boom &amp; Crash trades</Link>
          </div>
        </div></Reveal>
      </section>
    </div>
  );
}
