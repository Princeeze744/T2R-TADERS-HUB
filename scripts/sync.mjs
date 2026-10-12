// T2R Lab - data sync
// Reads the files the EA and the bar-export script write in MQL5\Files\T2R_Lab
// and turns them into the website data in public/data.
//
//   node scripts/sync.mjs                      (finds your MT5 folder by itself on Windows)
//   node scripts/sync.mjs "C:\path\to\MQL5\Files\T2R_Lab"
//
// Writes:
//   public/data/trades.json        every trade: replay + live demo (closed and open)
//   public/data/bars/index.json    which markets have candles
//   public/data/bars/<market>.json 15-minute candles for each market
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const OUT = path.join(ROOT, 'public', 'data');

const STRATS = ['Trap Zones', 'Trap + Gap', 'Untouched Ground', 'Rejection Stacks', 'Self-taught Zones', 'Self-taught 4H+1D', 'FVG Confluence', 'Flip Levels', 'Stretch Bands'];
const V0 = ['All traps', 'All traps', 'All zones', 'Bounce', 'All levels', 'All levels', 'All gaps', 'All flips', 'All bands'];
const V1 = ['At a stack', 'With a gap', '', 'Sweep', 'Model picks', 'Model picks', '2+ timeframes', '', ''];
const SC = ['Tight', 'Medium', 'Wide'];
const SD = ['Both', 'Buys', 'Sells'];
const SM = [0.2, 0.5, 1, 2];
const LV = [0.5, 1, 2, 3];

// ---------- find the T2R_Lab folder ----------
function findLab() {
  if (process.argv[2]) return process.argv[2];
  const base = path.join(process.env.APPDATA || path.join(os.homedir(), 'AppData', 'Roaming'), 'MetaQuotes', 'Terminal');
  let best = null, bestT = 0;
  if (fs.existsSync(base)) {
    for (const d of fs.readdirSync(base)) {
      const p = path.join(base, d, 'MQL5', 'Files', 'T2R_Lab');
      if (!fs.existsSync(p)) continue;
      const t = fs.statSync(p).mtimeMs;
      if (t > bestT) { bestT = t; best = p; }
    }
  }
  return best;
}

// ---------- reading helpers ----------
function readText(file) {
  const b = fs.readFileSync(file);
  if (b[0] === 0xff && b[1] === 0xfe) return b.slice(2).toString('utf16le');
  if (b[0] === 0xef && b[1] === 0xbb && b[2] === 0xbf) return b.slice(3).toString('utf8');
  return b.toString('utf8');
}
function lines(file) { return readText(file).split(/\r?\n/).filter((l) => l.trim() !== ''); }
function csv(file, sep) {
  const L = lines(file);
  const head = L[0].split(sep).map((h) => h.trim());
  return L.slice(1).map((l) => { const p = l.split(sep); const o = {}; head.forEach((h, i) => { o[h] = (p[i] ?? '').trim(); }); return o; });
}
// "2026.10.07 17:00" (MT5 server time) -> seconds
function ts(s) {
  if (!s) return 0;
  const m = s.match(/(\d{4})\.(\d{2})\.(\d{2})\s+(\d{2}):(\d{2})(?::(\d{2}))?/);
  if (!m) return 0;
  return Date.UTC(+m[1], +m[2] - 1, +m[3], +m[4], +m[5], +(m[6] || 0)) / 1000;
}
const px = (v) => { const x = Number(v); return Number.isFinite(x) ? Number(x.toPrecision(10)) : 0; };
function ratioOf(rr) { const m = String(rr).match(/1:([\d.]+)/); return m ? +m[1] : 2; }
function rrText(r) { return '1:' + (Math.round(r * 100) / 100); }
function hash(s) { let h = 5381; for (let i = 0; i < s.length; i++) h = ((h * 33) ^ s.charCodeAt(i)) >>> 0; return h.toString(36); }
function filesLike(dir, re) {
  return fs.readdirSync(dir).filter((f) => re.test(f)).map((f) => path.join(dir, f))
    .sort((a, b) => fs.statSync(a).mtimeMs - fs.statSync(b).mtimeMs);
}
export function slug(s) { return s.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, ''); }

// ---------- trades ----------
// one trade = [id, src, tSignal, tIn, tOut, asset, strategy, view, side, stopClass, dir, entry, stop, target, rr, result, R, hit1to1]
function buildTrades(lab) {
  const T = new Map();
  const put = (t) => { T.set(t[0], t); };

  // 1) replay files (the EA's look back at past days): newest file wins on duplicates
  const rep = filesLike(lab, /replay.*\.csv$/i);
  for (const f of rep) {
    for (const x of csv(f, ',')) {
      if (!x.asset) continue;
      const tin = ts(x.time_in);
      const id = 'r' + hash([x.asset, x.strategy, x.view, x.side, x.stop_class, x.direction, tin, x.entry].join('|'));
      const res = x.result === 'won' || x.result === 'lost' ? x.result : 'open';
      put([id, 'r', tin, tin, ts(x.time_out), x.asset, x.strategy, x.view, x.side, x.stop_class, x.direction,
        px(x.entry), px(x.stop), px(x.target), x.risk_to_reward, res, res === 'open' && !x.R ? null : px(x.R), null]);
    }
  }
  console.log(`  replay files: ${rep.length ? rep.map((f) => path.basename(f)).join(', ') : 'none'}`);

  // 2) live demo, closed trades
  const fw = filesLike(lab, /forward.*\.csv$/i);
  let nf = 0;
  for (const f of fw) {
    for (const x of csv(f, ',')) {
      if (!x.asset) continue;
      const e = px(x.entry), ex = px(x.exit), R = px(x.R), ratio = ratioOf(x.risk_to_reward);
      const unit = R !== 0 ? Math.abs(ex - e) / Math.abs(R) : 0;
      const buy = x.direction === 'buy';
      const sl = unit ? px(buy ? e - unit : e + unit) : 0;
      const tp = unit ? px(buy ? e + unit * ratio : e - unit * ratio) : 0;
      const tin = ts(x.time_in);
      const id = 'l' + hash([x.watch_id, x.asset, x.direction, tin, x.entry].join('|'));
      put([id, 'l', ts(x.time_signal), tin, ts(x.time_out), x.asset, x.strategy, x.view, x.side, x.stop_class, x.direction,
        e, sl, tp, x.risk_to_reward, R > 0 ? 'won' : 'lost', R, x.reached_1to1 === 'yes' ? 1 : 0, ex]);
      nf++;
    }
  }
  console.log(`  live demo closed trades: ${nf}`);

  // 3) live demo, trades running now (open.csv state 1) - needs watchlist.csv to name them
  const wf = filesLike(lab, /watchlist.*\.csv$/i).pop();
  const of = filesLike(lab, /open.*\.csv$/i).pop();
  let no = 0;
  if (wf && of) {
    const W = lines(wf).slice(1).map((l) => l.split(';'));
    for (const l of lines(of)) {
      const p = l.split(';');
      if (p.length < 12 || p[2] !== '1') continue;
      const w = W[+p[0]];
      if (!w) continue;
      const si = +w[1], vm = +w[2];
      const view = vm === 0 ? V0[si] : vm === 1 ? V1[si] : 'Learned picks';
      const ratio = LV[+w[6]] / SM[+w[5]];
      const dir = p[1] === '0' ? 'buy' : 'sell';
      const tin = +p[10] || +p[9];
      const id = 'l' + hash([p[0], w[0], dir, tin, p[3]].join('|'));
      if (T.has(id)) continue;
      put([id, 'l', +p[9], tin, 0, w[0], STRATS[si], view, SD[+w[3]], SC[+w[4]], dir,
        px(p[3]), px(p[4]), px(p[5]), rrText(ratio), 'open', null, p[8] === '1' ? 1 : 0]);
      no++;
    }
  }
  console.log(`  live demo open trades: ${no}`);

  const all = [...T.values()].sort((a, b) => a[3] - b[3]);
  return all;
}

// ---------- candles ----------
function buildBars(lab) {
  const dir = path.join(lab, 'bars');
  const outDir = path.join(OUT, 'bars');
  const idxFile = path.join(dir, '_index.csv');
  if (!fs.existsSync(idxFile)) { console.log('  candles: none yet (run T2R_BarExport in MT5 first)'); return null; }
  fs.mkdirSync(outDir, { recursive: true });
  const index = {};
  for (const x of csv(idxFile, ';')) {
    const src = path.join(dir, x.file);
    if (!fs.existsSync(src)) continue;
    const L = lines(src).slice(1);
    const t = [], o = [], h = [], lo = [], c = [];
    let t0 = 0, prev = 0;
    for (const l of L) {
      const p = l.split(';');
      const tt = +p[0];
      if (!t0) { t0 = tt; prev = tt; }
      t.push((tt - prev) / 60); prev = tt;
      o.push(+p[1]); h.push(+p[2]); lo.push(+p[3]); c.push(+p[4]);
    }
    if (!t.length) continue;
    const sl = slug(x.symbol);
    fs.writeFileSync(path.join(outDir, sl + '.json'), JSON.stringify({ s: x.symbol, d: +x.digits, t0, t, o, h, l: lo, c }));
    index[x.symbol] = { f: sl, n: t.length, a: t0, b: prev };
  }
  fs.writeFileSync(path.join(outDir, 'index.json'), JSON.stringify(index));
  console.log(`  candles: ${Object.keys(index).length} markets`);
  return index;
}

// ---------- run ----------
const lab = findLab();
if (!lab || !fs.existsSync(lab)) {
  console.error('Could not find the T2R_Lab folder. Run:  node scripts/sync.mjs "C:\\...\\MQL5\\Files\\T2R_Lab"');
  process.exit(1);
}
console.log('T2R sync from: ' + lab);
fs.mkdirSync(OUT, { recursive: true });
const trades = buildTrades(lab);
const bars = buildBars(lab);
const first = trades.length ? trades[0][3] : 0, last = trades.length ? trades[trades.length - 1][3] : 0;
fs.writeFileSync(path.join(OUT, 'trades.json'), JSON.stringify({ gen: Math.floor(Date.now() / 1000), from: first, to: last, trades }));
console.log(`DONE  ${trades.length} trades from ${new Date(first * 1000).toISOString().slice(0, 10)} to ${new Date(last * 1000).toISOString().slice(0, 10)}${bars ? ', candles for ' + Object.keys(bars).length + ' markets' : ''}`);
