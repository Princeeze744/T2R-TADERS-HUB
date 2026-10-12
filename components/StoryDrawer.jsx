'use client';
import { useEffect } from 'react';
import Link from 'next/link';
import { AnimatePresence, motion } from 'framer-motion';
import { useData } from './DataProvider';
import Diagram from './Diagram';
import { IcX, IcArrow } from './Icons';
import { INFO, VIEWTXT } from '@/lib/constants';
import { f2, f1, cl, pc, money, summarise, dateTime } from '@/lib/util';
import { ease } from './ui';

// story = {a,s,v,sd,c,st,ratio,mix,t1}
export default function StoryDrawer({ story, onClose }) {
  useEffect(() => {
    if (!story) return;
    const onKey = (e) => { if (e.key === 'Escape') onClose(); };
    window.addEventListener('keydown', onKey);
    document.body.style.overflow = 'hidden';
    return () => { window.removeEventListener('keydown', onKey); document.body.style.overflow = ''; };
  }, [story, onClose]);
  return (
    <AnimatePresence>
      {story && (
        <>
          <motion.div className="scrim" initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }} onClick={onClose} />
          <motion.aside className="drawer" style={{ width: 'min(880px,100vw)' }} initial={{ x: '100%' }} animate={{ x: 0 }} exit={{ x: '100%' }} transition={{ duration: 0.45, ease }} role="dialog" aria-label="Setup story">
            <div className="drawer-h"><span className="badge soft">Setup story</span><div className="x"><button type="button" className="iconbtn" onClick={onClose} aria-label="Close"><IcX s={16} /></button></div></div>
            <div className="drawer-b"><Story s={story} /></div>
          </motion.aside>
        </>
      )}
    </AnimatePresence>
  );
}

function stageDates(m) {
  if (!m) return ['', '', '', ''];
  const t0 = new Date(m.from.replace(/\./g, '-')).getTime(), t3 = new Date(m.to.replace(/\./g, '-')).getTime();
  const d = (t) => new Date(t).toISOString().slice(0, 10);
  return [d(t0), d(t0 + (t3 - t0) / 3), d(t0 + (2 * (t3 - t0)) / 3), d(t3)];
}

function Story({ s }) {
  const { data, risk } = useData();
  const { a, st, ratio } = s;
  const n = st.map((x) => x[0]), w = st.map((x) => x[1]), e = st.map((x) => x[2]);
  const N = n[0] + n[1] + n[2], W = w[0] + w[1] + w[2], un = n[1] + n[2], uw = w[1] + w[2];
  const R = [e[0] * n[0], e[1] * n[1], e[2] * n[2]], RT = R[0] + R[1] + R[2];
  const dt = stageDates(data.MK[a]);
  const nm = ['Stage 1 · learning', 'Stage 2 · first unseen test', 'Stage 3 · final exam'];
  const good = e[1] > 0 && e[2] > 0, strong = good && Math.min(n[1], n[2]) >= 100;
  const wr = N ? W / N : 0;
  const streak = wr > 0 && wr < 1 && N > 1 ? Math.round(Math.log(N) / Math.log(1 / (1 - wr))) : 0;
  const weeks = (new Date(dt[3]) - new Date(dt[0])) / 6048e5, pw = weeks > 0 ? N / weeks : 0;
  const trades = data.TRADES.filter((t) => t.a === a && t.s === s.s && t.v === s.v && t.sd === s.sd && t.c === s.c);
  const rp = summarise(trades);
  const notes = [];
  if (Math.min(n[1], n[2]) < 60) notes.push('Small sample: an unseen stage has fewer than 60 trades.');
  if (ratio >= 6) notes.push('Long-shot payoff: rare, big wins, so results swing.');
  if (/Boom|Crash|Jump|Range Break/.test(a)) notes.push('Spike market: a stop can be jumped, making a real loss bigger than planned.');
  if (data.famOf(a) === 'Forex' && s.sd !== 'Both') notes.push('One direction only on a pair that has trended: part of the record may be the trend itself.');
  if (s.v === 'Learned picks' || s.v === 'Model picks') notes.push('Stage 1 flatters this row, because the model learned from it.');
  notes.push('Thousands of combinations were tested, so some look good by luck. Live demo results decide what reaches real money.');
  return (
    <>
      <span className="eyebrow">{data.famOf(a)}</span>
      <h2 className="serif" style={{ fontSize: 'clamp(32px,4vw,44px)', marginTop: 10, lineHeight: 1.05 }}>{a}</h2>
      <p className="dim" style={{ margin: '6px 0 0' }}>{s.s} · {s.v} · {s.sd} · {s.c} stop class · {s.mix}</p>
      <div className="callout" style={{ marginTop: 18 }}><b>Bottom line: </b>{strong ? 'made money in both unseen periods on a solid number of trades. A serious candidate.' : good ? 'made money in both unseen periods, on a smaller number of trades. Promising, not proven.' : 'did not make money in both unseen periods. Not one to trade as it stands.'}</div>

      <div className="grid g3" style={{ marginTop: 16 }}>
        <div className="card kpi"><div className="l">Risk to reward</div><div className="v">1:{Math.round(ratio * 100) / 100}</div><div className="s">a win pays {Math.round(ratio * 100) / 100}R</div></div>
        <div className="card kpi"><div className="l">Break-even win rate</div><div className="v">{Math.round(100 / (1 + ratio))}%</div><div className="s">win more often than this to profit</div></div>
        <div className="card kpi"><div className="l">Won on unseen history</div><div className={'v ' + (uw / Math.max(1, un) > 1 / (1 + ratio) ? 'g' : 'r')}>{pc(uw, un)}</div><div className="s">{uw} wins in {un} trades</div></div>
      </div>

      <h3 className="serif" style={{ fontSize: 26, margin: '28px 0 12px' }}>What happened in the test</h3>
      <div className="card tbl-wrap">
        <table className="tbl">
          <thead><tr><th className="l">Period</th><th className="l">Dates</th><th>Trades</th><th>Won</th><th>Win rate</th><th>Average</th><th>Total</th><th>At ${risk}</th></tr></thead>
          <tbody>
            {[0, 1, 2].map((i) => (
              <tr key={i}><td className="l">{nm[i]}</td><td className="l dim">{dt[i]} → {dt[i + 1]}</td><td className="num">{n[i]}</td><td className="num">{w[i]}</td><td className="num">{pc(w[i], n[i])}</td><td className={'num ' + cl(e[i])}>{f2(e[i])}R</td><td className={'num ' + cl(R[i])}>{f1(R[i])}R</td><td className={'num ' + cl(R[i])}>{money(R[i], risk)}</td></tr>
            ))}
            <tr className="tot"><td className="l">Whole test</td><td className="l dim">{dt[0]} → {dt[3]}</td><td className="num">{N}</td><td className="num">{W}</td><td className="num">{pc(W, N)}</td><td className={'num ' + cl(RT)}>{N ? f2(RT / N) : '–'}R</td><td className={'num ' + cl(RT)}>{f1(RT)}R</td><td className={'num ' + cl(RT)}>{money(RT, risk)}</td></tr>
          </tbody>
        </table>
      </div>
      <p className="note">After trading costs. Stage 1 is where the setup learned or was chosen, so stages 2 and 3 are the fair test.</p>

      <h3 className="serif" style={{ fontSize: 26, margin: '24px 0 10px' }}>What to expect</h3>
      <ul className="dim" style={{ paddingLeft: 18, margin: 0 }}>
        <li>About <b style={{ color: 'var(--text)' }}>{pw >= 1 ? pw.toFixed(1) + ' signals a week' : (pw * 4.3).toFixed(1) + ' signals a month'}</b>.</li>
        <li>It loses about {Math.round(100 * (1 - wr))} trades in 100. A run of about <b style={{ color: 'var(--text)' }}>{streak} losses in a row</b> is normal for a record like this.</li>
        <li>Risking 1% of the account per trade keeps that run to about {streak}% of the account.</li>
        {s.t1 && s.t1[1] >= 0 && ratio > 1 && <li>Taking profit early: {pc(s.t1[1] + s.t1[2], un)} of unseen trades reached 1:1 before the stop.</li>}
      </ul>

      {trades.length > 0 && (
        <>
          <div className="between" style={{ margin: '28px 0 10px' }}>
            <h3 className="serif" style={{ fontSize: 26 }}>Its trades in the journal</h3>
            <Link className="chip" href={`/journal?mk=${encodeURIComponent(a)}&st=${encodeURIComponent(s.s)}`}>Open in the journal <IcArrow s={14} /></Link>
          </div>
          <p className="dim" style={{ marginTop: 0 }}>{rp.n} trades: {rp.w} won, {rp.l} lost{rp.o ? `, ${rp.o} open` : ''}. Result <b className={cl(rp.R)}>{f1(rp.R)}R</b> ({money(rp.R, risk)}).</p>
          <div className="card tbl-wrap">
            <table className="tbl">
              <thead><tr><th className="l">Entered</th><th className="l">Order</th><th>Entry</th><th>Stop</th><th>Target</th><th className="l">Result</th><th>R</th></tr></thead>
              <tbody>
                {trades.slice().sort((x, y) => y.tin - x.tin).slice(0, 30).map((t) => (
                  <tr key={t.id}><td className="l">{dateTime(t.tin)}</td><td className="l"><span className={'badge ' + t.dir}>{t.dir.toUpperCase()}</span></td><td className="num">{t.e}</td><td className="num">{t.sl}</td><td className="num">{t.tp}</td><td className="l"><span className={'badge ' + t.res}>{t.res.toUpperCase()}</span></td><td className={'num ' + cl(t.R || 0)}>{t.res === 'open' ? '…' : f2(t.R)}</td></tr>
                ))}
              </tbody>
            </table>
          </div>
        </>
      )}

      <h3 className="serif" style={{ fontSize: 26, margin: '28px 0 10px' }}>How {s.s} places the trade</h3>
      <p className="dim" style={{ marginTop: 0 }}>{INFO[s.s]?.one}{VIEWTXT[s.v] ? ' This setup takes ' + VIEWTXT[s.v] : ''}</p>
      <div className="card pad diagram"><Diagram s={s.s} /></div>

      <h3 className="serif" style={{ fontSize: 26, margin: '28px 0 10px' }}>Honest notes</h3>
      <ul className="dim" style={{ paddingLeft: 18, margin: 0 }}>{notes.map((x) => <li key={x} style={{ marginBottom: 6 }}>{x}</li>)}</ul>
    </>
  );
}
