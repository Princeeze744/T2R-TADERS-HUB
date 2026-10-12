'use client';
import { useState } from 'react';
import { AnimatePresence, motion } from 'framer-motion';
import { Reveal, ease } from './ui';

const FAQ = [
  ['What is R?', 'R is the amount risked on one trade. Risk $10 and 1R is $10. A loss costs 1R; a 1:3 win pays 3R. +0.30R a trade means the average trade made 30% of what was risked. Change the risk box at the top and every dollar figure on the site follows.'],
  ['What are the three stages?', 'The history is cut into three equal periods. Stage 1 is where a strategy learns or its settings are chosen. Stages 2 and 3 are periods it never saw, with completely new trades. Only the lesson carries forward, never the trades. A setup that only wins in stage 1 is thrown out.'],
  ['Risk to reward and break-even', '1:2 means a win pays twice the loss, so winning 33 times in 100 breaks even. 1:1 needs 50, 1:3 needs 25, 1:6 needs 14, 1:15 needs 6. A low win rate can still make money when the wins are big enough.'],
  ['Stop class: Tight, Medium, Wide', "Tight uses the zone's own height as 1R. Medium makes 1R at least one normal 15-minute candle range, Wide at least three. Wider stops make the spread a smaller share of the risk."],
  ['Pass and Stronghold', 'Pass: the standard setup (risk 1 to make 2) made money in all three stages. Stronghold: the best stop and target, chosen in stage 1, confirmed in stage 2 and still profitable in the stage 3 exam.'],
  ['TP1 and the T2R rule', 'Every signal has a first target at 1:1. At +1R a member banks half and moves the stop to entry. From then on the trade cannot lose: the worst case is +0.5R, the best is half of the full target plus 0.5R.'],
  ['Replay versus live demo', 'Replay means the EA went back over past days and took every signal the followed setups would have given, candle by candle. Live demo means trades taken in real time on a demo account, with real fills. The journal marks every trade with its source.'],
  ['Why we test live on demo', 'Thousands of combinations were tested, so some look good by luck. Every winner is now followed live with real prices. Only setups that keep winning there go to members.'],
  ['Spike markets', 'On Boom, Crash, Jump and Range Break, price can jump past a stop, so a real loss can be bigger than 1R. The backtest fills stops at the stop price; the live demo records the real fill.'],
  ['How much to risk', '1% of the account or less per trade. Many setups lose more trades than they win and make it back on fewer, bigger winners, so losing runs are normal.'],
  ['What time zone are the times in?', 'MT5 server time, which is GMT. Lagos is one hour ahead, so a trade at 14:00 on the site happened at 15:00 Lagos time.'],
];

const NOW = [
  ['MT5 runs the lab', 'The T2R Lab EA runs the backtest, follows the watchlist on the demo account and writes everything to the folder MQL5\\Files\\T2R_Lab.', 'Running on the laptop'],
  ['Candles are saved', <>The script <code>T2R_BarExport</code> saves the 15-minute candles of every market. The website draws every trade on these exact candles, so the chart you see is the same price feed the EA traded.</>, 'One click in MT5'],
  ['Sync the data', <>One command, <code>npm run sync</code>, turns those files into website data: every trade, every candle.</>, 'One command'],
  ['Publish', <><code>git push</code> sends it to GitHub, and Vercel puts the new version live in about a minute.</>, 'Automatic'],
];
const NEXT = [
  ['VPS', 'MT5 moves to a server that never sleeps, so the lab runs 24/7 without the laptop.'],
  ['Live database', 'The EA sends every event (signal, activated, +1R, target, stop, cancel) to a database the moment it happens. The site and the bot read from it, so no more manual sync.'],
  ['Telegram bot', 'Signals reach the admin first with Approve and Skip buttons. Approved ones go to the channel, followed by live updates. Members can ask /today, /open, /week, /month, /market and /strategy.'],
  ['Matching indicator', 'An MT5 indicator built from the very same zone code the EA uses. It draws the zones only, clean, with no entry, stop or target clutter. Put it on any chart and the zones line up with the trades on this site. Same code, same candles, same zones.'],
];

export default function Method() {
  const [open, setOpen] = useState(0);
  return (
    <div className="wrap">
      <div className="page-head">
        <Reveal><span className="eyebrow">How it works</span></Reveal>
        <Reveal delay={0.05}><h1 className="h-sec">The method, <em>in plain words.</em></h1></Reveal>
        <Reveal delay={0.1}><p className="lead">How the numbers are made, how the data reaches this site, and what comes next. Everything on the site comes from one source: the T2R Lab EA in MT5.</p></Reveal>
      </div>

      <div className="grid g2" style={{ alignItems: 'start' }}>
        <div>
          <Reveal><h2 className="serif" style={{ fontSize: 30, marginBottom: 14 }}>How data reaches this site today</h2></Reveal>
          <div className="flow">
            {NOW.map(([h, p, tag], i) => (
              <Reveal key={h} delay={i * 0.06}>
                <div className="card flow-i"><span className="n">{i + 1}</span><div><h4>{h}</h4><p>{p}</p><span className="badge soft tag">{tag}</span></div></div>
              </Reveal>
            ))}
          </div>
        </div>
        <div>
          <Reveal><h2 className="serif" style={{ fontSize: 30, marginBottom: 14 }}>What comes next</h2></Reveal>
          <div className="flow">
            {NEXT.map(([h, p], i) => (
              <Reveal key={h} delay={i * 0.06}>
                <div className="card flow-i"><span className="n" style={{ color: 'var(--mute)' }}>{String.fromCharCode(65 + i)}</span><div><h4>{h}</h4><p>{p}</p></div></div>
              </Reveal>
            ))}
          </div>
        </div>
      </div>

      <div className="sec" style={{ paddingTop: 64 }}>
        <Reveal><h2 className="h-sec" style={{ marginBottom: 18 }}>Questions, <em>answered.</em></h2></Reveal>
        <div className="faq">
          {FAQ.map(([q, a], i) => (
            <div className="faq-i" key={q}>
              <button type="button" className="faq-q" aria-expanded={open === i} onClick={() => setOpen(open === i ? -1 : i)}>
                <span>{q}</span><span className="pl">+</span>
              </button>
              <AnimatePresence initial={false}>
                {open === i && (
                  <motion.div className="faq-a" initial={{ height: 0, opacity: 0 }} animate={{ height: 'auto', opacity: 1 }} exit={{ height: 0, opacity: 0 }} transition={{ duration: 0.3, ease }}>
                    <p>{a}</p>
                  </motion.div>
                )}
              </AnimatePresence>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}
