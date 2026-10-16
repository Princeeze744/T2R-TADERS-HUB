'use client';
import { useEffect, useState } from 'react';
import Link from 'next/link';
import { AnimatePresence, motion } from 'framer-motion';
import { useData, wkey } from './DataProvider';
import { TradeChart } from './Charts';
import Diagram from './Diagram';
import { IcX, IcLeft, IcRight, IcLink, IcCopy, IcCheck } from './Icons';
import { INFO, VIEWTXT, SM, LV } from '@/lib/constants';
import { f2, cl, money, fmtPrice, dateTime, duration, pc, rrTxt } from '@/lib/util';
import { ease } from './ui';

function signalText(t) {
  const unit = Math.abs(t.e - t.sl);
  const tp1 = t.dir === 'buy' ? t.e + unit : t.e - unit;
  const D = t.dir.toUpperCase();
  return `${t.dir === 'buy' ? '🟢' : '🔴'} ${D} — ${t.a}\n\nEntry   ${fmtPrice(t.e, t.e)}\nStop    ${fmtPrice(t.sl, t.e)}\n${t.ratio > 1.05 ? `TP1     ${fmtPrice(tp1, t.e)}  (1:1, bank half, stop to entry)\n` : ''}Target  ${fmtPrice(t.tp, t.e)}  (${t.rr})\n\nWhy: ${t.s} · ${t.v}\nRisk 1% of the account or less.\n— T2R Signal Hub`;
}

export default function TradeDrawer({ trade, list, onClose, onNav }) {
  const { data, risk } = useData();
  const [copied, setCopied] = useState('');
  const i = trade ? list.findIndex((x) => x.id === trade.id) : -1;
  const prev = i > 0 ? list[i - 1] : null, next = i >= 0 && i < list.length - 1 ? list[i + 1] : null;

  useEffect(() => {
    if (!trade) return;
    const onKey = (e) => {
      if (e.key === 'Escape') onClose();
      if (e.key === 'ArrowLeft' && prev) onNav(prev.id);
      if (e.key === 'ArrowRight' && next) onNav(next.id);
    };
    window.addEventListener('keydown', onKey);
    document.body.style.overflow = 'hidden';
    return () => { window.removeEventListener('keydown', onKey); document.body.style.overflow = ''; };
  }, [trade, prev, next, onClose, onNav]);

  const copy = (txt, what) => {
    navigator.clipboard?.writeText(txt).then(() => { setCopied(what); setTimeout(() => setCopied(''), 1600); }).catch(() => {});
  };

  return (
    <AnimatePresence>
      {trade && (
        <>
          <motion.div key="scrim" className="scrim" initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }} onClick={onClose} />
          <motion.aside key="drawer" className="drawer" initial={{ x: '100%' }} animate={{ x: 0 }} exit={{ x: '100%' }} transition={{ duration: 0.45, ease }} role="dialog" aria-label="Trade details">
            <div className="drawer-h">
              <span className={'badge ' + (trade.src === 'l' ? 'live' : 'soft')}>{trade.src === 'l' ? <><span className="dot" />Live demo</> : trade.src === 'b' ? 'Backtest' : 'Replay'}</span>
              <span className="dim" style={{ fontSize: 13 }}>{i + 1} of {list.length}</span>
              <div className="x">
                <button type="button" className="iconbtn" disabled={!prev} onClick={() => prev && onNav(prev.id)} aria-label="Previous trade"><IcLeft s={16} /></button>
                <button type="button" className="iconbtn" disabled={!next} onClick={() => next && onNav(next.id)} aria-label="Next trade"><IcRight s={16} /></button>
                <button type="button" className="iconbtn" onClick={() => copy(window.location.href, 'link')} aria-label="Copy link to this trade">{copied === 'link' ? <IcCheck s={16} /> : <IcLink s={16} />}</button>
                <button type="button" className="iconbtn" onClick={onClose} aria-label="Close"><IcX s={16} /></button>
              </div>
            </div>
            <div className="drawer-b">
              <motion.div key={trade.id} initial={{ opacity: 0, y: 10 }} animate={{ opacity: 1, y: 0 }} transition={{ duration: 0.35, ease }}>
                <Body t={trade} data={data} risk={risk} copy={copy} copied={copied} />
              </motion.div>
            </div>
          </motion.aside>
        </>
      )}
    </AnimatePresence>
  );
}

function Body({ t, data, risk, copy, copied }) {
  const unit = Math.abs(t.e - t.sl);
  const tp1 = t.dir === 'buy' ? t.e + unit : t.e - unit;
  const I = INFO[t.s] || {};
  const w = data.WSET[wkey(t.a, t.s, t.v, t.sd, t.c)];
  const resCls = t.res === 'won' ? 'g' : t.res === 'lost' ? 'r' : 'o';
  const events = [];
  if (t.src === 'l' && t.tsig && t.tsig !== t.tin) events.push({ c: '', b: 'Signal sent', s: dateTime(t.tsig), p: `${t.dir === 'buy' ? 'Buy' : 'Sell'} order placed at ${fmtPrice(t.e, t.e)}, waiting for price.` });
  events.push({ c: '', b: t.src === 'l' ? 'Activated: in the trade' : 'Price reached the zone: in the trade', s: dateTime(t.tin), p: `${t.dir === 'buy' ? 'Bought' : 'Sold'} at ${fmtPrice(t.e, t.e)}. Risk ${fmtPrice(unit, t.e)} in price = 1R.` });
  if (t.h1) events.push({ c: 'g', b: 'Reached +1R (1:1)', s: '', p: 'A member following the T2R rule banks half here and moves the stop to entry.' });
  if (t.res === 'won') events.push({ c: 'g', b: 'Target hit', s: dateTime(t.tout), p: `Closed ${f2(t.R)}R after ${duration(t.tin, t.tout)}.` });
  else if (t.res === 'lost') events.push({ c: 'r', b: 'Stopped out', s: dateTime(t.tout), p: `Closed ${f2(t.R)}R after ${duration(t.tin, t.tout)}.` });
  else events.push({ c: 'o', b: 'Still running', s: '', p: 'No target or stop yet when this data was saved.' });
  const un = w ? w.st[1][0] + w.st[2][0] : 0, uw = w ? w.st[1][1] + w.st[2][1] : 0;

  return (
    <>
      <div className="dt-title">
        <h2>{t.a}</h2>
        <span className={'badge ' + t.dir}>{t.dir.toUpperCase()}</span>
        <span className={'badge ' + t.res}>{t.res === 'open' ? 'OPEN' : t.res.toUpperCase()}</span>
        {t.res !== 'open' && <span className={'mono ' + cl(t.R)} style={{ fontSize: 22, fontWeight: 600 }}>{f2(t.R)}R</span>}
        {t.res !== 'open' && <span className={'mono ' + cl(t.R)} style={{ fontSize: 15 }}>{money(t.R, risk)}</span>}
      </div>
      <div className="dt-sub">{t.s} · {t.v} · {t.sd} · {t.c} stop class · risk to reward {t.rr} · {data.famOf(t.a)}</div>

      <div className="card dt-chart">
        <div className="bar">
          <div className="legend">
            <span><i style={{ background: '#f3dca4' }} />Entry</span>
            <span><i style={{ background: 'rgba(255,107,107,.6)' }} />Risk (to stop)</span>
            <span><i style={{ background: 'rgba(54,211,153,.6)' }} />Reward (to target)</span>
          </div>
          <span className="note">15-minute candles · MT5 server time (GMT) · scroll or pinch to zoom</span>
        </div>
        <TradeChart t={t} height={440} />
        <div className="levels">
          <div><span>Entry</span><b style={{ color: 'var(--gold2)' }}>{fmtPrice(t.e, t.e)}</b></div>
          <div><span>Stop</span><b className="r">{fmtPrice(t.sl, t.e)}</b></div>
          <div><span>TP1 · 1:1</span><b className="g" style={{ opacity: 0.8 }}>{t.ratio > 1.05 ? fmtPrice(tp1, t.e) : '–'}</b></div>
          <div><span>Target · {t.rr}</span><b className="g">{fmtPrice(t.tp, t.e)}</b></div>
          <div><span>1R in price</span><b>{fmtPrice(unit, t.e)}</b></div>
        </div>
      </div>

      <div className="grid g2" style={{ marginTop: 16 }}>
        <div className="card pad">
          <div className="eyebrow">What happened</div>
          <ul className="tl" style={{ marginTop: 16 }}>
            {events.map((e, k) => <li key={k} className={e.c}><b>{e.b}</b>{e.s && <span>{e.s}</span>}<p>{e.p}</p></li>)}
          </ul>
        </div>
        <div className="card pad">
          <div className="eyebrow">The result</div>
          <div style={{ marginTop: 14, display: 'flex', alignItems: 'baseline', gap: 12 }}>
            <span className={'serif ' + resCls} style={{ fontSize: 56, lineHeight: 1 }}>{t.res === 'open' ? 'Open' : f2(t.R) + 'R'}</span>
            {t.res !== 'open' && <span className={'mono ' + cl(t.R)}>{money(t.R, risk)} at ${risk} risk</span>}
          </div>
          <p className="dim" style={{ fontSize: 14, marginBottom: 0 }}>
            {t.res === 'won' && `Price travelled from entry to the full target (${t.rr}). Every $1 risked made $${t.ratio}, minus the spread.`}
            {t.res === 'lost' && 'Price reached the stop first. The loss is 1R plus the spread (and more on a spike that jumps the stop).'}
            {t.res === 'open' && 'This trade had not finished when the data was saved. It will show its result after the next update.'}
          </p>
          <div className="hr" />
          <div className="between" style={{ fontSize: 13.5 }}><span className="dim">Time in the trade</span><span className="mono">{duration(t.tin, t.tout)}</span></div>
          {t.rT2R != null && t.res !== 'open' && <div className="between" style={{ fontSize: 13.5, marginTop: 8 }}><span className="dim">With the T2R rule (half off at 1:1)</span><span className={'mono ' + cl(t.rT2R)}>{f2(t.rT2R)}R</span></div>}
          <div className="between" style={{ fontSize: 13.5, marginTop: 8 }}><span className="dim">Break-even win rate at {t.rr}</span><span className="mono">{Math.round(100 / (1 + t.ratio))}%</span></div>
          {w && <div className="between" style={{ fontSize: 13.5, marginTop: 8 }}><span className="dim">This setup on unseen history</span><span className="mono">{pc(uw, un)} won · {un} trades</span></div>}
        </div>
      </div>

      <div className="card pad" style={{ marginTop: 16 }}>
        <div className="between">
          <div className="eyebrow">Why this trade: {t.s}</div>
          <Link className="chip" href={'/strategies?s=' + encodeURIComponent(t.s)}>Learn the strategy</Link>
        </div>
        <div className="grid g2" style={{ marginTop: 14, alignItems: 'center' }}>
          <div>
            <p style={{ marginTop: 0 }}>{I.one}{VIEWTXT[t.v] ? ' This setup takes ' + VIEWTXT[t.v] : ''}</p>
            <div className="rules" style={{ gridTemplateColumns: '1fr' }}>
              <div><span className="eyebrow" style={{ fontSize: 11 }}>Entry</span><p style={{ margin: '4px 0 0', fontSize: 14 }}>{I.entry}</p></div>
              <div><span className="eyebrow" style={{ fontSize: 11 }}>Stop</span><p style={{ margin: '4px 0 0', fontSize: 14 }}>{I.stop}</p></div>
              <div><span className="eyebrow" style={{ fontSize: 11 }}>Target</span><p style={{ margin: '4px 0 0', fontSize: 14 }}>{I.target}</p></div>
            </div>
          </div>
          <div className="diagram"><Diagram s={t.s} /></div>
        </div>
        {w && (
          <div className="stage-bars" style={{ marginTop: 16 }}>
            {['Stage 1 · learning', 'Stage 2 · unseen', 'Stage 3 · exam'].map((nm, k) => (
              <div key={k} className="card stage"><span>{nm}</span><b className={cl(w.st[k][2])}>{f2(w.st[k][2])}R</b><small>{pc(w.st[k][1], w.st[k][0])} won · {w.st[k][0]} trades · {rrTxt(LV[w.lv] / SM[w.si])}</small></div>
            ))}
          </div>
        )}
      </div>

      <div className="card pad" style={{ marginTop: 16 }}>
        <div className="between">
          <div className="eyebrow">As a Telegram signal</div>
          <button type="button" className="chip" onClick={() => copy(signalText(t), 'sig')}>{copied === 'sig' ? <><IcCheck s={14} />Copied</> : <><IcCopy s={14} />Copy</>}</button>
        </div>
        <pre className="signal" style={{ marginTop: 14 }}>{signalText(t)}</pre>
      </div>
    </>
  );
}
