'use client';
import { useEffect, useMemo, useState } from 'react';
import Link from 'next/link';
import { useSearchParams } from 'next/navigation';
import { AnimatePresence, motion } from 'framer-motion';
import { useData } from './DataProvider';
import Diagram from './Diagram';
import { Reveal, ease } from './ui';
import { IcPlay, IcArrow } from './Icons';
import { STRATS, INFO } from '@/lib/constants';
import { summarise, f1, cl, pc } from '@/lib/util';

const STEPS = [
  { t: 'The zone forms', k: 'find' },
  { t: 'Price returns: entry', k: 'entry' },
  { t: 'Where the stop goes', k: 'stop' },
  { t: 'Targets and outcome', k: 'target' },
];

export default function Strategies() {
  const { data } = useData();
  const sp = useSearchParams();
  const [s, setS] = useState(sp.get('s') && INFO[sp.get('s')] ? sp.get('s') : STRATS[0]);
  const [step, setStep] = useState(4);
  const [playing, setPlaying] = useState(false);
  useEffect(() => { const q = sp.get('s'); if (q && INFO[q]) setS(q); }, [sp]);
  useEffect(() => { setStep(4); setPlaying(false); }, [s]);
  useEffect(() => {
    if (!playing) return;
    if (step >= 4) { setPlaying(false); return; }
    const id = setTimeout(() => setStep((x) => x + 1), 1700);
    return () => clearTimeout(id);
  }, [playing, step]);

  const stats = useMemo(() => {
    const o = {};
    STRATS.forEach((x) => {
      o[x] = {
        mk: new Set(data.ROWS.filter((r) => r.s === x && (r.pass || r.strong)).map((r) => r.a)).size,
        fol: data.WATCH.filter((w) => w.s === x).length,
        ...summarise(data.TRADES.filter((t) => t.s === x)),
      };
    });
    return o;
  }, [data]);
  const I = INFO[s], S = stats[s];
  const stepText = [I.find, I.entry, I.stop, I.target];

  return (
    <div className="wrap">
      <div className="page-head">
        <Reveal><span className="eyebrow">The nine strategies</span></Reveal>
        <Reveal delay={0.05}><h1 className="h-sec">How each strategy <em>finds a trade.</em></h1></Reveal>
        <Reveal delay={0.1}><p className="lead">Every strategy draws a zone, waits for price to come back to it, and trades with a fixed stop and target. Press play to walk through it one step at a time, the way you would teach it.</p></Reveal>
      </div>
      <div className="strat-layout">
        <div className="card strat-nav">
          {STRATS.map((x) => (
            <button type="button" key={x} className={x === s ? 'on' : ''} onClick={() => setS(x)}>
              {x === s && <motion.span layoutId="stratpill" className="pill" transition={{ type: 'spring', bounce: 0.18, duration: 0.45 }} />}
              {x}<small>{stats[x].mk} markets passed · {stats[x].fol} live</small>
            </button>
          ))}
        </div>
        <AnimatePresence mode="wait">
          <motion.div key={s} initial={{ opacity: 0, y: 12 }} animate={{ opacity: 1, y: 0 }} exit={{ opacity: 0, y: -8 }} transition={{ duration: 0.35, ease }}>
            <div className="card pad">
              <div className="between">
                <h2 className="serif" style={{ fontSize: 'clamp(32px,4vw,46px)', lineHeight: 1.05 }}>{s}</h2>
                <div className="row">
                  <Link className="chip" href={'/journal?st=' + encodeURIComponent(s)}>Its trades</Link>
                  <Link className="chip" href={'/explorer?st=' + encodeURIComponent(s) + '&pass=1'}>Markets it passed</Link>
                </div>
              </div>
              <p style={{ fontSize: 16.5, color: '#d5d9e2', maxWidth: 780 }}>{I.one}</p>
              <div className="between" style={{ marginTop: 18 }}>
                <div className="steps">
                  {STEPS.map((x, i) => (
                    <button type="button" key={x.t} className={step === i + 1 ? 'on' : ''} onClick={() => { setPlaying(false); setStep(i + 1); }}><i>{i + 1}</i>{x.t}</button>
                  ))}
                </div>
                <button type="button" className="btn primary sm" onClick={() => { setStep(1); setPlaying(true); }}><IcPlay s={14} />{playing ? 'Playing…' : 'Play the lesson'}</button>
              </div>
              <div className="card diagram" style={{ marginTop: 14, padding: 14, background: 'rgba(0,0,0,.25)' }}>
                <Diagram key={s + step} s={s} step={step} />
              </div>
              <AnimatePresence mode="wait">
                <motion.div key={step} className="callout" style={{ marginTop: 14 }} initial={{ opacity: 0, y: 6 }} animate={{ opacity: 1, y: 0 }} exit={{ opacity: 0 }} transition={{ duration: 0.25 }}>
                  <b>Step {step} · {STEPS[step - 1].t}. </b>{stepText[step - 1]}
                </motion.div>
              </AnimatePresence>
            </div>
            <div className="rules" style={{ marginTop: 14 }}>
              {[['Finds the zone', I.find], ['Entry', I.entry], ['Stop', I.stop], ['Target', I.target]].map(([k, v]) => (
                <div key={k} className="card rule"><span>{k}</span><p>{v}</p></div>
              ))}
            </div>
            <div className="grid g3" style={{ marginTop: 14 }}>
              <div className="card kpi"><div className="l">Markets where it passed</div><div className="v">{S.mk}</div><div className="s">of {Object.keys(data.MK).length} tested</div></div>
              <div className="card kpi"><div className="l">Setups followed live</div><div className="v">{S.fol}</div><div className="s">on the demo watchlist</div></div>
              <div className="card kpi"><div className="l">Trades in the journal</div><div className={'v ' + cl(S.R)}>{S.n ? f1(S.R) + 'R' : '–'}</div><div className="s">{S.n} trades · {pc(S.w, S.closed)} won</div></div>
            </div>
            <p className="note" style={{ marginTop: 14 }}>The charts are drawn examples of each pattern, not real trades. To see real ones, open <Link href={'/journal?st=' + encodeURIComponent(s)} style={{ color: 'var(--gold2)' }}>its trades <IcArrow s={12} /></Link>.</p>
          </motion.div>
        </AnimatePresence>
      </div>
    </div>
  );
}
