'use client';
import Link from 'next/link';
import { Reveal } from './ui';
import { IcArrow } from './Icons';

const V = { yes: { t: 'Proven edge', c: 'g' }, no: { t: 'No edge', c: 'r' }, watch: { t: 'Watching', c: 'o' } };
const STUDIES = [
  { v: 'yes', k: 'Boom & Crash · zones with the spike', n: '1.83 million test trades · 34 spike markets · Jan – Oct 2026',
    p: 'Self-taught Zones (model picks), wide stop, traded only in the direction of the spike: buy Boom, sell Crash. Picked on January – June, proven on July – October.',
    s: [['With the spike, 1:3', '+268R', 'g'], ['Against the spike', '−95R', 'r'], ['Unseen months (Jul – Oct)', '+61R vs −203R', 'g']],
    link: ['/spikes', 'See the full spike study'] },
  { v: 'yes', k: 'Boom & Crash · Drift Breakout', n: '5,507 trades · 20 markets · 07:00 and 13:30 GMT · Jan – Oct 2026',
    p: 'The first 15-minute candle of the session; trade the break only with the drift (sell Boom, buy Crash), stop half the candle, target 5R. Charged for spikes that jump the stop. Picked on January – June, proven on July – October.',
    s: [['Per trade', '+0.27R', 'g'], ['Months in profit', '10 of 10', 'g'], ['Breaks with the spike', '−316R (skipped)', 'r']],
    link: ['/spikes#drift', 'See the Drift Breakout'] },
  { v: 'no', k: 'Spike timing · "buy Boom at 9:00"', n: 'Every hour and quarter-hour · 34 spike markets · Jan – Oct 2026',
    p: 'Times that looked great in the first half held up only 44% of the time in the second half, worse than picking times at random (49%). Spikes do not follow the clock.',
    s: [['Random entry, any hold', '≈ 0 after spread', 'n'], ['Buying after a long drift ("it is due")', 'loses', 'r'], ['Entering right after a spike', '≈ 0', 'n']] },
  { v: 'no', k: 'Forex · 51 pairs', n: 'Zones: 1.59 million trades · 10 new strategies: 280,000 settings · Jul 2024 – Oct 2026',
    p: 'Without spread, forex at our zones behaves like a coin flip. With spread, it slowly loses. The best settings of 2024 – 25 all failed in 2026. We also found the 21:00 – 23:00 GMT rollover trap that makes fake sell signals look like winners.',
    s: [['Majors, every setting averaged', '−0.42R / trade', 'r'], ['Same, with zero spread', '−0.05R', 'n'], ['2024 – 25 winners still winning in 2026', '0%', 'r']] },
  { v: 'no', k: 'Volatility indices · 28 markets', n: 'Zones and the 10 new strategies · Jan – Oct 2026',
    p: 'Volatility indices have no one-sided spike for a zone to catch. With the best setting per market, only 8 of 28 stayed positive on unseen months.',
    s: [['Markets still positive on unseen months', '8 of 28', 'r'], ['Total, best setting per market', '−410R', 'r']] },
  { v: 'watch', k: 'Gold trends · stock indices momentum', n: 'Forward test on the demo before any signal is sold',
    p: 'Gold 4-hour breakouts, gold 20-day momentum and stock-index momentum held up in some tests but not all. They earn a place only by building a live record.',
    s: [['Gold 20-day momentum, last 4 weeks', '4 trades · +2.7R', 'g'], ['Gold 4H breakout, last 4 weeks', '−4R (choppy gold)', 'r']] },

];
const LESSONS = [
  ['Trade with the spike.', 'The same zones make money with the spike and lose money against it.'],
  ['Spikes do not follow the clock.', 'No hour, minute or weekday held up on unseen months. The session open matters only as a range to break.'],
  ['"It is due" is the most expensive belief.', 'Buying after a long drift without a spike lost money.'],
  ['Spread decides.', 'Most setups that look good before spread are break-even or worse after it.'],
  ['Prove it on months it never saw.', 'Every result here was picked on one period and checked on another.'],
];

export default function Research() {
  return (
    <div className="wrap">
      <div className="page-head">
        <Reveal><span className="eyebrow">Research · Everything we tested</span></Reveal>
        <Reveal delay={0.05}><h1 className="h-display" style={{ marginTop: 18 }}>We tested everything.<br /><em>We only sell what is proven.</em></h1></Reveal>
        <Reveal delay={0.1}><p className="lead">More than 3 million test trades across Boom &amp; Crash, forex, gold, stock indices, crypto and volatility indices. Most ideas failed, and we show those too. Two edges stood, both on Boom &amp; Crash: zones traded with the spike, and the Drift Breakout.</p></Reveal>
      </div>
      <div className="grid rs-grid">
        {STUDIES.map((x, i) => (
          <Reveal key={x.k} delay={i * 0.04}>
            <div className={'card pad rs-card rs-' + x.v}>
              <div className="between"><span className={'rs-badge ' + V[x.v].c}>{V[x.v].t}</span><span className="note">{x.n}</span></div>
              <h2 className="serif" style={{ fontSize: 30, margin: '12px 0 6px' }}>{x.k}</h2>
              <p className="dim" style={{ margin: 0, fontSize: 14.5 }}>{x.p}</p>
              <div className="rs-stats">{x.s.map(([l, v, c]) => <div key={l}><span>{l}</span><b className={c}>{v}</b></div>)}</div>
              {x.link && <Link href={x.link[0]} className="chip" style={{ marginTop: 14 }}>{x.link[1]} <IcArrow s={14} /></Link>}
            </div>
          </Reveal>
        ))}
      </div>
      <section className="sec-sm">
        <Reveal><div className="card pad">
          <span className="eyebrow">Five lessons from 3 million trades</span>
          <div className="grid rs-lessons">{LESSONS.map(([t, p], i) => <div key={t}><span className="rs-num">0{i + 1}</span><b>{t}</b><p>{p}</p></div>)}</div>
        </div></Reveal>
      </section>
    </div>
  );
}
