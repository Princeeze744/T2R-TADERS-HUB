export const SM = [0.2, 0.5, 1, 2];
export const LV = [0.5, 1, 2, 3];
export const SMN = ['0.2x', '0.5x', '1x', '2x'];
export const LVN = ['0.5x', '1x', '2x', '3x'];
export const FAMS = ['Catching Spikes', 'Volatility', 'Forex', 'Metals', 'Other synthetics'];
export const SYN = { 'Catching Spikes': 1, Volatility: 1, 'Other synthetics': 1 };
// one place that decides which shelf a market sits on (the same rule everywhere on the site)
export function familyOf(m) {
  const a = String(m || '');
  if (/^(Boom|Crash) \d|Vol over|Volatility (Boom|Crash)|\bDEX\b|Trek|Crash Boom Flip/.test(a)) return 'Catching Spikes';
  if (/^X(AU|AG|PT|PD)|GOLD|SILVER/i.test(a)) return 'Metals';
  if (/^[A-Z]{6}$/.test(a)) return 'Forex';
  if (/^Volatility \d|High Frequency Vol|VolSwitch/.test(a)) return 'Volatility';
  return 'Other synthetics';
}
// the spike shelf, split further
export function spikeGroupOf(m) {
  const a = String(m || '');
  if (/^(Boom|Crash) \d/.test(a)) return 'Boom & Crash';
  if (/\bDEX\b/.test(a)) return 'DEX';
  if (/Vol over|Volatility (Boom|Crash)/.test(a)) return 'Vol over';
  if (/Trek/.test(a)) return 'Trek';
  if (/Crash Boom Flip/.test(a)) return 'Crash Boom Flip';
  return '';
}
export const FAM_SHORT = { 'Catching Spikes': '⚡ Spikes', Volatility: 'Volatility', Forex: 'Forex', Metals: 'Gold & Silver', 'Other synthetics': 'Other' };

export const STRATS = ['Trap Zones', 'Trap + Gap', 'Untouched Ground', 'Rejection Stacks', 'Self-taught Zones', 'Self-taught 4H+1D', 'FVG Confluence', 'Flip Levels', 'Stretch Bands'];

export const FAM_TXT = {
  'Catching Spikes': 'Boom & Crash, DEX, Vol over, Trek and Crash Boom Flip: quiet drifts, then a sudden spike.',
  Volatility: 'Volatility 10 to 300, the 1-second versions, High Frequency and VolSwitch.',
  Forex: 'Currency pairs: majors, minors and exotics.',
  Metals: 'Gold, silver, platinum and palladium.',
  'Other synthetics': 'Step, Range Break, Jump, Drift Switch, Skew Step and the other Deriv indices.',
};

export const INFO = {
  'Trap Zones': {
    one: 'A failed breakout. Traders who chased a strong breakout get trapped when the very next candle wipes the move out. Their entry area becomes a zone to trade against them.',
    find: 'On the 1-hour, 4-hour, daily or weekly chart: a candle closes beyond the previous high (or low) with a strong body, then the next candle closes back past where it started.',
    entry: 'A limit order at the edge of the zone, waiting for price to come back to it.',
    stop: 'Beyond the far side of the zone. The zone height sets the size of 1R.',
    target: 'A multiple of the zone height in the opposite direction to the breakout.',
  },
  'Trap + Gap': {
    one: 'A trap zone that also has a fair value gap inside it, so two separate reasons point to the same price.',
    find: 'A trap zone as above, plus a three-candle price gap of the same direction that formed inside it.',
    entry: 'A limit order at the edge of the trap zone.', stop: 'Beyond the far side of the zone.', target: 'A multiple of the zone height.',
  },
  'Untouched Ground': {
    one: 'A strip of price the market rushed through once and never revisited, sitting between two busy areas. When price finally comes back, it tends to react there.',
    find: "The last 150 candles are sliced into thin price bands and each band's visits are counted. A run of almost-empty bands between two heavily traded areas is the zone.",
    entry: 'When price returns to the edge of the untouched strip.', stop: 'Beyond the far side of the strip (or a minimum size).', target: 'A multiple of the strip height.',
  },
  'Rejection Stacks': {
    one: 'A price where the market has been pushed back several separate times. Bounce trades the next push back. Sweep trades the turn just after price pokes past it to take out the stops resting there.',
    find: 'Long wicks (at least a third of the candle) whose tips line up at almost the same price, at least two separate times, and not yet broken.',
    entry: 'Bounce: a limit at the stack. Sweep: a limit just beyond it.', stop: 'Beyond the zone.', target: 'A multiple of the zone height.',
  },
  'Self-taught Zones': {
    one: 'Every recent swing high and low is a candidate. The computer studied stage 1 to learn which ones tended to work, and scores each new one.',
    find: 'Swing highs and lows on the higher timeframes. Each is scored on where it sits in the range, the size of its wick, its age, how fast price approaches, time of day and trend.',
    entry: 'At the level when price returns. Model picks only takes levels scoring 0.30 or more.', stop: 'Beyond the level.', target: 'A multiple of the zone height.',
  },
  'Self-taught 4H+1D': {
    one: 'The same self-taught model, using only swing highs and lows from the 4-hour and daily charts: the bigger levels.',
    find: 'Swing highs and lows on the 4-hour and daily charts, scored by the model.',
    entry: 'At the level when price returns.', stop: 'Beyond the level.', target: 'A multiple of the zone height.',
  },
  'FVG Confluence': {
    one: 'Fair value gaps: three candles where the market moved so fast it left a gap that was never traded both ways. When gaps on different timeframes overlap, they merge into one stronger zone.',
    find: "The third candle's low is above the first candle's high (a buy gap), or the mirror for a sell gap. Gaps from the 1-hour, 4-hour, daily and weekly charts are overlaid.",
    entry: 'A limit order at the edge of the gap.', stop: 'Beyond the far side of the gap.', target: 'A multiple of the gap height.',
  },
  'Flip Levels': {
    one: 'Going with a break instead of fading it. A swing high that price closes above with a strong candle turns from ceiling into floor. The first return to it is a buy. The mirror gives sells.',
    find: 'A swing high (or low) is broken by a candle closing beyond it with a strong body.',
    entry: 'A limit order at the broken level, waiting for the first return.', stop: 'Below the level (for buys).', target: 'A multiple of the zone height, in the direction of the break.',
  },
  'Stretch Bands': {
    one: 'No chart pattern, only distance. When price is stretched far above its recent average it is a sell zone; far below is a buy zone.',
    find: 'The average of the last 20 candles, and a band 2.5 normal candle ranges above and below it.',
    entry: 'When price reaches the band.', stop: 'Beyond the band.', target: 'Back towards the average, as a multiple of the zone height.',
  },
};

export const VIEWTXT = {
  'Learned picks': 'only the setups the learning step liked after studying stage 1.',
  'Model picks': 'only the levels the model scored highly.',
  'At a stack': 'only traps that sit at a rejection stack.',
  'With a gap': 'only traps with a price gap inside.',
  '2+ timeframes': 'only gaps where two or more timeframes overlap.',
  Bounce: 'the bounce version.',
  Sweep: 'the sweep version.',
};

// ---------- teaching diagrams (drawn examples) ----------
const L = (x, y, t, k) => ({ x, y, t, k });
const TRAPC = [[100, 101.5, 99.6, 101], [101, 102.2, 100.7, 101.8], [101.8, 102.5, 101.2, 102.1], [102.1, 102.6, 101.5, 101.9], [101.9, 104.3, 101.8, 104.1], [104.1, 104.3, 101.0, 101.4], [101.4, 101.8, 100.2, 100.6], [100.6, 101.0, 99.8, 100.2], [100.2, 101.2, 100.0, 101.0], [101, 102.0, 100.8, 101.8], [101.8, 102.7, 101.6, 102.4], [102.4, 102.7, 101.5, 101.7], [101.7, 101.9, 100.4, 100.6], [100.6, 100.9, 99.4, 99.6], [99.6, 99.9, 98.9, 99.1]];
export const PAT = {
  'Trap Zones': { c: TRAPC, boxes: [{ x0: 4, x1: 14, lo: 102.6, hi: 104.1, t: 'Sell trap zone', k: 'z' }], marks: [{ x: 4, y: 104.3, t: 'strong breakout candle', left: true }, { x: 5, y: 101.0, t: 'wiped out next candle', dy: 16 }, { x: 10, y: 102.7, t: 'price returns: sell', dy: -10, left: true }], lines: [L(10, 104.1, 'Stop (1R)', 's'), L(10, 102.6, 'Sell limit', 'e'), L(10, 101.1, 'TP1 1:1', 't'), L(10, 99.6, 'Target 1:2', 't')] },
  'Trap + Gap': { c: TRAPC, boxes: [{ x0: 4, x1: 14, lo: 102.6, hi: 104.1, t: 'Sell trap zone', k: 'z' }, { x0: 4, x1: 14, lo: 103.2, hi: 103.7, t: 'gap inside', k: 'g2' }], marks: [{ x: 4, y: 104.3, t: 'breakout leaves a gap', left: true }, { x: 10, y: 102.7, t: 'price returns: sell', dy: -10, left: true }], lines: [L(10, 104.1, 'Stop (1R)', 's'), L(10, 102.6, 'Sell limit', 'e'), L(10, 101.1, 'TP1 1:1', 't'), L(10, 99.6, 'Target 1:2', 't')] },
  'Untouched Ground': { c: [[100, 100.8, 99.7, 100.4], [100.4, 100.9, 99.9, 100.2], [100.2, 101, 99.8, 100.7], [100.7, 101.1, 100.1, 100.5], [100.5, 101.2, 100.3, 101.0], [101.0, 103.5, 100.9, 103.3], [103.3, 103.9, 102.9, 103.6], [103.6, 104.0, 103.0, 103.2], [103.2, 103.8, 102.9, 103.5], [103.5, 104.1, 103.1, 103.8], [103.8, 104.0, 103.0, 103.1], [103.1, 103.2, 102.6, 102.8], [102.8, 103.9, 102.7, 103.8], [103.8, 104.8, 103.6, 104.6], [104.6, 105.5, 104.3, 105.3], [105.3, 106.2, 105.1, 106.0]], boxes: [{ x0: 0, x1: 4, lo: 99.7, hi: 101.2, t: 'busy', k: 'busy' }, { x0: 6, x1: 10, lo: 102.9, hi: 104.1, t: 'busy', k: 'busy' }, { x0: 5, x1: 15, lo: 101.2, hi: 102.8, t: 'untouched ground', k: 'z' }], marks: [{ x: 5, y: 103.5, t: 'rushed through once', left: true }, { x: 11, y: 102.6, t: 'first return: buy', dy: 16 }], lines: [L(11, 104.4, 'TP1 1:1', 't'), L(11, 106.0, 'Target 1:2', 't'), L(11, 102.8, 'Buy limit', 'e'), L(11, 101.2, 'Stop (1R)', 's')] },
  'Rejection Stacks': { c: [[103, 104.1, 102.8, 103.8], [103.8, 105.0, 103.6, 104.1], [104.1, 104.3, 103.2, 103.4], [103.4, 103.9, 102.9, 103.7], [103.7, 104.95, 103.5, 103.9], [103.9, 104.2, 103.0, 103.2], [103.2, 103.7, 102.6, 103.5], [103.5, 104.3, 103.3, 104.0], [104.0, 105.05, 103.8, 104.2], [104.2, 104.4, 103.1, 103.3], [103.3, 103.8, 103.0, 103.6], [103.6, 104.5, 103.4, 104.4], [104.4, 104.9, 104.3, 104.7], [104.7, 104.9, 103.6, 103.8], [103.8, 104.0, 102.6, 102.8], [102.8, 103.0, 102.1, 102.3]], boxes: [{ x0: 1, x1: 15, lo: 104.75, hi: 105.05, t: 'stack: 3 rejections', k: 'z' }, { x0: 1, x1: 15, lo: 105.25, hi: 105.65, t: 'sweep zone', k: 'g2' }], marks: [{ x: 1, y: 105.0, t: '1', dy: -6 }, { x: 4, y: 104.95, t: '2', dy: -6 }, { x: 8, y: 105.05, t: '3', dy: -6 }, { x: 12, y: 104.9, t: 'bounce: sell', dy: 16, left: true }], lines: [L(12, 105.05, 'Stop (1R)', 's'), L(12, 104.75, 'Sell limit', 'e'), L(12, 104.45, 'TP1 1:1', 't'), L(12, 104.15, 'Target 1:2', 't')] },
  'Self-taught Zones': { c: [[100, 100.9, 99.8, 100.7], [100.7, 101.6, 100.5, 101.4], [101.4, 102.4, 101.2, 102.2], [102.2, 104.0, 102.0, 102.6], [102.6, 102.9, 101.6, 101.8], [101.8, 102.1, 100.9, 101.1], [101.1, 101.6, 100.6, 101.4], [101.4, 102.3, 101.2, 102.1], [102.1, 103.1, 102.0, 102.9], [102.9, 103.8, 102.7, 103.6], [103.6, 103.8, 102.6, 102.8], [102.8, 103.0, 101.7, 101.9], [101.9, 102.1, 100.9, 101.2], [101.2, 101.4, 100.5, 100.7]], boxes: [{ x0: 3, x1: 13, lo: 103.6, hi: 104.0, t: 'swing high level', k: 'z' }], marks: [{ x: 3, y: 104.0, t: 'swing high: long wick', left: true }, { x: 9, y: 103.8, t: 'model score +0.42: picked', dy: -10, left: true }], lines: [L(9, 104.0, 'Stop (1R)', 's'), L(9, 103.6, 'Sell limit', 'e'), L(9, 103.2, 'TP1 1:1', 't'), L(9, 102.8, 'Target 1:2', 't')] },
  'FVG Confluence': { c: [[100, 100.6, 99.6, 100.3], [100.3, 101.0, 100.0, 100.8], [100.8, 103.4, 100.7, 103.2], [103.2, 104.2, 102.0, 103.9], [103.9, 104.6, 103.5, 104.4], [104.4, 104.8, 103.6, 103.8], [103.8, 104.0, 102.9, 103.1], [103.1, 103.3, 102.3, 102.5], [102.5, 102.6, 101.9, 102.2], [102.2, 103.4, 102.0, 103.3], [103.3, 104.4, 103.1, 104.2], [104.2, 105.3, 104.0, 105.1], [105.1, 106.2, 104.9, 106.0]], boxes: [{ x0: 2, x1: 12, lo: 101.0, hi: 102.0, t: '1-hour gap', k: 'z' }, { x0: 2, x1: 12, lo: 101.3, hi: 102.4, t: '4-hour gap overlaps', k: 'g2' }], marks: [{ x: 1, y: 101.0, t: 'candle 1 high', left: true, dy: -6 }, { x: 3, y: 102.0, t: 'candle 3 low', dy: 16 }, { x: 8, y: 101.9, t: 'return to the gap: buy', dy: 18 }], lines: [L(8, 104.0, 'Target 1:2', 't'), L(8, 103.0, 'TP1 1:1', 't'), L(8, 102.0, 'Buy limit', 'e'), L(8, 101.0, 'Stop (1R)', 's')] },
  'Flip Levels': { c: [[100, 101.0, 99.8, 100.8], [100.8, 101.8, 100.6, 101.6], [101.6, 103.0, 101.4, 102.6], [102.6, 102.8, 101.8, 102.0], [102.0, 102.3, 101.3, 101.6], [101.6, 102.4, 101.4, 102.2], [102.2, 104.4, 102.1, 104.2], [104.2, 104.9, 103.9, 104.6], [104.6, 104.8, 103.8, 104.0], [104.0, 104.1, 103.1, 103.3], [103.3, 103.5, 102.85, 103.2], [103.2, 104.3, 103.1, 104.1], [104.1, 105.0, 103.9, 104.8], [104.8, 105.6, 104.6, 105.4]], boxes: [{ x0: 2, x1: 13, lo: 102.7, hi: 103.0, t: 'old ceiling becomes floor', k: 'z' }], marks: [{ x: 2, y: 103.0, t: 'swing high', left: true }, { x: 6, y: 104.4, t: 'strong close above it', left: true }, { x: 10, y: 102.85, t: 'first return: buy', dy: 18 }], lines: [L(10, 104.2, 'Target 1:2', 't'), L(10, 103.6, 'TP1 1:1', 't'), L(10, 103.0, 'Buy limit', 'e'), L(10, 102.4, 'Stop (1R)', 's')] },
  'Stretch Bands': { c: [[100, 100.5, 99.6, 100.3], [100.3, 100.8, 100.0, 100.6], [100.6, 101.0, 100.2, 100.4], [100.4, 100.9, 100.1, 100.8], [100.8, 101.3, 100.5, 101.1], [101.1, 101.5, 100.8, 100.9], [100.9, 101.6, 100.7, 101.5], [101.5, 102.6, 101.4, 102.5], [102.5, 103.7, 102.3, 103.5], [103.5, 104.2, 103.2, 103.6], [103.6, 103.8, 102.7, 102.9], [102.9, 103.1, 102.1, 102.3], [102.3, 102.5, 101.6, 101.8], [101.8, 102.0, 101.3, 101.5]], ma: [100.2, 100.3, 100.4, 100.5, 100.6, 100.7, 100.8, 101.0, 101.2, 101.4, 101.5, 101.6, 101.6, 101.6], band: [102.8, 102.9, 103.0, 103.1, 103.2, 103.3, 103.4, 103.6, 103.8, 104.0, 104.1, 104.2, 104.2, 104.2], boxes: [{ x0: 8, x1: 13, lo: 103.9, hi: 104.5, t: 'stretch zone', k: 'z' }], marks: [{ x: 3, y: 100.5, t: '20-candle average', dy: 20 }, { x: 9, y: 104.2, t: 'price far above average: sell', left: true, dy: -8 }], lines: [L(9, 104.5, 'Stop (1R)', 's'), L(9, 103.9, 'Sell limit', 'e'), L(9, 103.3, 'TP1 1:1', 't'), L(9, 102.7, 'Target 1:2', 't')] },
};
PAT['Self-taught 4H+1D'] = JSON.parse(JSON.stringify(PAT['Self-taught Zones']));
PAT['Self-taught 4H+1D'].boxes[0].t = '4-hour / daily swing level';
