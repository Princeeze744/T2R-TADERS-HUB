'use client';
import Link from 'next/link';
import { useMemo } from 'react';
import { motion } from 'framer-motion';
import { useData } from './DataProvider';
import { EquityChart } from './Charts';
import { Reveal, Counter, Ring, ease } from './ui';
import { IcArrow, IcFlask, IcShield, IcRadio, IcSend } from './Icons';
import { FAMS, FAM_TXT, STRATS, INFO, SYN, SM, LV } from '@/lib/constants';
import { summarise, f1, f2, cl, pc, nf, money, shortDate, dayKey, rrTxt, strengthOf } from '@/lib/util';

export function bestPerMarket(WATCH, filter) {
  const by = {};
  WATCH.forEach((w) => {
    if (!filter(w)) return;
    const strong = strengthOf(w) === 'Strong';
    const k = (strong ? 1000 : 0) + w.z;
    if (!by[w.a] || k > by[w.a].k) by[w.a] = { w, k };
  });
  return Object.values(by).sort((x, y) => y.k - x.k).map((x) => x.w);
}

export function PickList({ list, trades }) {
  return (
    <div className="card" style={{ overflow: 'hidden' }}>
      {list.map((w, i) => {
        const ratio = LV[w.lv] / SM[w.si];
        const un = w.st[1][0] + w.st[2][0], uw = w.st[1][1] + w.st[2][1];
        const rp = summarise(trades.filter((t) => t.a === w.a && t.s === w.s && t.v === w.v && t.sd === w.sd && t.c === w.c));
        return (
          <Link key={w.i} href={'/journal?mk=' + encodeURIComponent(w.a)} className="pick">
            <span className="rk">{i + 1}</span>
            <span><span className="nm">{w.a}</span><br /><span className="sub">{w.s} · {w.sd} · {rrTxt(ratio)} · {pc(uw, un)} won on unseen history</span></span>
            <span className="rt"><b className={cl(rp.R)}>{rp.n ? f1(rp.R) + 'R' : '–'}</b><span>{rp.n ? rp.n + ' trades in the data' : 'no trade yet'}</span></span>
          </Link>
        );
      })}
    </div>
  );
}

export default function Overview() {
  const { data, risk } = useData();
  const rep = useMemo(() => data.TRADES.filter((t) => t.src === 'r'), [data]);
  const S = useMemo(() => summarise(rep), [rep]);
  const live = useMemo(() => summarise(data.TRADES.filter((t) => t.src === 'l')), [data]);
  const followedMk = useMemo(() => new Set(data.WATCH.map((w) => w.a)).size, [data]);
  const from = rep.length ? dayKey(Math.min(...rep.map((t) => t.tin))) : '', to = rep.length ? dayKey(Math.max(...rep.map((t) => t.tin))) : '';
  const syn = useMemo(() => bestPerMarket(data.WATCH, (w) => SYN[w.fam]).slice(0, 5), [data]);
  const fx = useMemo(() => bestPerMarket(data.WATCH, (w) => w.fam === 'Forex' || w.fam === 'Metals').slice(0, 5), [data]);
  const fams = useMemo(() => FAMS.map((f) => {
    const mk = Object.values(data.MK).filter((m) => m.fam === f).length;
    const passed = new Set(data.ROWS.filter((r) => r.fam === f && (r.pass || r.strong)).map((r) => r.a)).size;
    const fol = new Set(data.WATCH.filter((w) => w.fam === f).map((w) => w.a)).size;
    return { f, mk, passed, fol, ...summarise(data.TRADES.filter((t) => t.fam === f)) };
  }), [data]);
  const stratStats = useMemo(() => STRATS.map((s) => ({ s, ...summarise(rep.filter((t) => t.s === s)), follow: data.WATCH.filter((w) => w.s === s).length })), [rep, data]);

  const steps = [
    { Ic: IcFlask, t: 'Backtest everything', p: `Nine strategies replayed on every 15-minute candle of ${Object.keys(data.MK).length} markets, close to two years each. ${nf(data.meta.trades)} test trades, after spread.` },
    { Ic: IcShield, t: 'Pass a three-stage exam', p: 'History is cut in three. Stage 1 teaches, stages 2 and 3 are unseen. A setup must make money on history it never saw.' },
    { Ic: IcRadio, t: 'Prove it live on demo', p: `${data.WATCH.length} winning setups on ${followedMk} markets are followed live with real prices and real fills, around the clock.` },
    { Ic: IcSend, t: 'Approved signals only', p: 'Each signal reaches the admin first. Approved ones go to the channel with entry, stop, TP1 and target, then live updates.' },
  ];

  return (
    <>
      <section className="hero">
        <div className="wrap">
          <div className="hero-grid">
            <div>
              <Reveal><span className="eyebrow">Trade2Retire Academy · T2R Lab</span></Reveal>
              <Reveal delay={0.06}><h1 className="h-display" style={{ marginTop: 22 }}>Nine strategies.<br />{Object.keys(data.MK).length} markets.<br /><em>Every trade counted.</em></h1></Reveal>
              <Reveal delay={0.14}><p className="lead">A computer tested our zone strategies on Deriv synthetics, forex and metals, trade by trade, and only kept what held up on history it had never seen. Pick any day and see every trade on the chart.</p></Reveal>
              <Reveal delay={0.2}>
                <div className="hero-cta">
                  <Link href="/journal" className="btn primary">Open the trade journal <IcArrow s={16} /></Link>
                  <Link href="/method" className="btn ghost">How it works</Link>
                </div>
              </Reveal>
            </div>
            <Reveal delay={0.18}>
              <div className="card hero-card">
                <div className="top"><span className="eyebrow">{from ? `${shortDate(from)} – ${shortDate(to)}, replayed` : 'Replay'}</span><Ring value={S.wr} /></div>
                <div className="between" style={{ alignItems: 'baseline' }}>
                  <span className={'big ' + cl(S.R)}><Counter value={S.R} format={(v) => (v >= 0 ? '+' : '−') + Math.abs(Math.round(v)) + 'R'} /></span>
                  <span className="mono dim" style={{ fontSize: 13 }}>{money(S.R, risk)} at ${risk}</span>
                </div>
                <p className="dim" style={{ margin: '6px 0 4px', fontSize: 13.5 }}>{nf(S.n)} signals · {S.w} won · {S.l} lost · {pc(S.w, S.closed)} win rate</p>
                <EquityChart trades={rep} height={170} />
                <Link href="/journal" className="chip" style={{ marginTop: 6 }}>See every trade <IcArrow s={14} /></Link>
              </div>
            </Reveal>
          </div>
          <div className="stat-row">
            {[
              [data.meta.trades, 'test trades taken'],
              [Object.keys(data.MK).length, 'markets tested'],
              [data.WATCH.length, `setups followed live, on ${followedMk} markets`],
              [STRATS.length, 'strategies'],
            ].map(([v, l], i) => (
              <Reveal key={l} delay={0.05 * i}><div><b><Counter value={v} /></b><span>{l}</span></div></Reveal>
            ))}
          </div>
        </div>
      </section>

      <section className="sec">
        <div className="wrap">
          <div className="sec-head">
            <div><Reveal><span className="eyebrow">The process</span></Reveal><Reveal delay={0.05}><h2 className="h-sec" style={{ marginTop: 12 }}>From an idea to a signal, <em>in four gates.</em></h2></Reveal></div>
            <Reveal><Link href="/method" className="btn ghost sm">Read the method</Link></Reveal>
          </div>
          <div className="pipe">
            {steps.map((s, i) => (
              <Reveal key={s.t} delay={i * 0.07}>
                <div className="card hover" style={{ height: '100%', padding: '22px 20px' }}>
                  <div className="ico"><s.Ic s={20} /></div>
                  <span className="no" style={{ fontFamily: 'var(--mono)', fontSize: 12, color: 'var(--gold)' }}>STEP 0{i + 1}</span>
                  <h3 className="serif" style={{ fontSize: 26, margin: '8px 0 8px', lineHeight: 1.1 }}>{s.t}</h3>
                  <p className="dim" style={{ margin: 0, fontSize: 14 }}>{s.p}</p>
                </div>
              </Reveal>
            ))}
          </div>
        </div>
      </section>

      <section className="sec">
        <div className="wrap">
          <div className="sec-head">
            <div><Reveal><span className="eyebrow">Daily focus</span></Reveal><Reveal delay={0.05}><h2 className="h-sec" style={{ marginTop: 12 }}>The <em>strongest</em> markets right now.</h2></Reveal>
              <Reveal delay={0.1}><p>One best setup per market, ranked by how well it did on history it never saw. Live demo results will reshape this list as they come in.</p></Reveal></div>
            <Reveal><Link href="/watchlist" className="btn ghost sm">All {data.WATCH.length} setups</Link></Reveal>
          </div>
          <div className="grid g2">
            <Reveal><div className="between" style={{ marginBottom: 10 }}><h3 className="serif" style={{ fontSize: 26 }}>Top 5 synthetics</h3><span className="note">Deriv indices</span></div><PickList list={syn} trades={data.TRADES} /></Reveal>
            <Reveal delay={0.08}><div className="between" style={{ marginBottom: 10 }}><h3 className="serif" style={{ fontSize: 26 }}>Top 5 forex and metals</h3><span className="note">pairs and gold, silver</span></div><PickList list={fx} trades={data.TRADES} /></Reveal>
          </div>
        </div>
      </section>

      <section className="sec">
        <div className="wrap">
          <div className="sec-head">
            <div><Reveal><span className="eyebrow">Families</span></Reveal><Reveal delay={0.05}><h2 className="h-sec" style={{ marginTop: 12 }}>Five families, <em>one standard.</em></h2></Reveal></div>
          </div>
          <div className="grid g5">
            {fams.map((f, i) => (
              <Reveal key={f.f} delay={i * 0.05}>
                <Link href={'/journal?fam=' + encodeURIComponent(f.f)} className="card hover fam" style={{ height: '100%' }}>
                  <h3>{f.f}</h3>
                  <p className="dim" style={{ margin: 0, fontSize: 13 }}>{FAM_TXT[f.f]}</p>
                  <div className="meta"><span><b>{f.mk}</b> tested</span><span><b>{f.passed}</b> passed</span><span><b>{f.fol}</b> live</span></div>
                  <div className="foot"><span className={'R ' + cl(f.R)}>{f1(f.R)}R</span><span className="note">{f.n} trades in the data</span></div>
                </Link>
              </Reveal>
            ))}
          </div>
        </div>
      </section>

      <section className="sec">
        <div className="wrap">
          <div className="sec-head">
            <div><Reveal><span className="eyebrow">The strategies</span></Reveal><Reveal delay={0.05}><h2 className="h-sec" style={{ marginTop: 12 }}>Every one explained, <em>step by step.</em></h2></Reveal>
              <Reveal delay={0.1}><p>How each strategy finds its zone and where it puts the entry, the stop and the target. Made for teaching.</p></Reveal></div>
            <Reveal><Link href="/strategies" className="btn ghost sm">Open the strategies</Link></Reveal>
          </div>
          <div className="grid g3">
            {stratStats.map((s, i) => (
              <Reveal key={s.s} delay={(i % 3) * 0.06}>
                <Link href={'/strategies?s=' + encodeURIComponent(s.s)} className="card hover pad" style={{ display: 'block', height: '100%' }}>
                  <div className="between"><h3 className="serif" style={{ fontSize: 24 }}>{s.s}</h3><span className={'mono ' + cl(s.R)}>{s.n ? f1(s.R) + 'R' : '–'}</span></div>
                  <p className="dim" style={{ fontSize: 13.5, margin: '8px 0 12px', display: '-webkit-box', WebkitLineClamp: 3, WebkitBoxOrient: 'vertical', overflow: 'hidden' }}>{INFO[s.s].one}</p>
                  <span className="note">{s.follow} setups followed · {s.n} trades · {pc(s.w, s.closed)} won</span>
                </Link>
              </Reveal>
            ))}
          </div>
        </div>
      </section>

      <section className="sec">
        <div className="wrap">
          <Reveal>
            <div className="card" style={{ padding: 'clamp(28px,5vw,56px)', overflow: 'hidden' }}>
              <motion.div aria-hidden="true" style={{ position: 'absolute', inset: -2, background: 'radial-gradient(600px 300px at 85% 0%, rgba(216,178,106,.16), transparent 70%)', pointerEvents: 'none' }} animate={{ opacity: [0.6, 1, 0.6] }} transition={{ duration: 6, repeat: Infinity, ease: 'easeInOut' }} />
              <span className="eyebrow">Live demo</span>
              <h2 className="h-sec" style={{ marginTop: 12, maxWidth: 760 }}>The real test is <em>happening now.</em></h2>
              <p className="lead" style={{ marginTop: 14 }}>Backtests can be lucky. So every setup is followed live on a demo account with real prices. {live.n ? `${live.n} live trades recorded so far: ${live.w} won, ${live.l} lost, ${live.o} still running.` : ''} Only setups that keep winning there reach members.</p>
              <div className="hero-cta"><Link href="/journal?src=l" className="btn primary">See the live demo trades <IcArrow s={16} /></Link></div>
            </div>
          </Reveal>
        </div>
      </section>
    </>
  );
}
