// ---------- formatting ----------
export const nf = (n) => Number(n).toLocaleString('en-US');
export const f2 = (x) => (x >= 0 ? '+' : '−') + Math.abs(x).toFixed(2);
export const f1 = (x) => (x >= 0 ? '+' : '−') + Math.abs(x).toFixed(1);
export const cl = (x) => (x > 0.005 ? 'g' : x < -0.005 ? 'r' : 'n');
export const pc = (w, n) => (n > 0 ? Math.round((100 * w) / n) + '%' : '–');
export const rrTxt = (ratio) => '1:' + Math.round(ratio * 100) / 100;
export function money(R, risk) {
  const v = Math.round(R * risk);
  return (v >= 0 ? '+' : '−') + '$' + Math.abs(v).toLocaleString('en-US');
}
export function fmtPrice(p, ref) {
  if (p == null || !isFinite(p)) return '–';
  const a = Math.abs(ref || p);
  const d = a >= 10000 ? 2 : a >= 1000 ? 2 : a >= 100 ? 3 : a >= 10 ? 4 : 5;
  return Number(p).toLocaleString('en-US', { minimumFractionDigits: d, maximumFractionDigits: d });
}
export function ratioOf(rr) {
  const m = String(rr || '').match(/1:([\d.]+)/);
  return m ? +m[1] : 2;
}

// ---------- time (all times are MT5 server time = GMT) ----------
const DN = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
const MN = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
export const MONTHS = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
export const dayKey = (t) => new Date(t * 1000).toISOString().slice(0, 10);
export const keyToTs = (k) => Date.UTC(+k.slice(0, 4), +k.slice(5, 7) - 1, +k.slice(8, 10)) / 1000;
export function hhmm(t) {
  if (!t) return '–';
  const d = new Date(t * 1000);
  return String(d.getUTCHours()).padStart(2, '0') + ':' + String(d.getUTCMinutes()).padStart(2, '0');
}
export function dayLabel(k, long) {
  const d = new Date(keyToTs(k) * 1000);
  return long ? `${DN[d.getUTCDay()]} ${d.getUTCDate()} ${MONTHS[d.getUTCMonth()]} ${d.getUTCFullYear()}` : `${DN[d.getUTCDay()]} ${d.getUTCDate()} ${MN[d.getUTCMonth()]}`;
}
export function shortDate(k) {
  const d = new Date(keyToTs(k) * 1000);
  return `${d.getUTCDate()} ${MN[d.getUTCMonth()]}`;
}
export function dateTime(t) {
  if (!t) return '–';
  return `${dayLabel(dayKey(t))}, ${hhmm(t)}`;
}
export function duration(a, b) {
  if (!a || !b || b < a) return '–';
  const m = Math.round((b - a) / 60);
  if (m < 60) return m + ' min';
  const h = Math.floor(m / 60), r = m % 60;
  if (h < 48) return h + 'h' + (r ? ' ' + r + 'm' : '');
  return Math.round(h / 24) + ' days';
}
// Monday of the week (ISO weeks)
export function weekStart(k) {
  const t = keyToTs(k);
  const dow = (new Date(t * 1000).getUTCDay() + 6) % 7;
  return dayKey(t - dow * 86400);
}
export const addDays = (k, n) => dayKey(keyToTs(k) + n * 86400);

// ---------- trades ----------
export function toTrades(raw, famOf) {
  return raw.map((x) => {
    const ratio = ratioOf(x[14]);
    return {
      id: x[0], src: x[1], tsig: x[2], tin: x[3], tout: x[4], a: x[5], s: x[6], v: x[7], sd: x[8], c: x[9], dir: x[10],
      e: x[11], sl: x[12], tp: x[13], rr: x[14], ratio, res: x[15], R: x[16], h1: x[17], ex: x[18],
      fam: famOf(x[5]), day: dayKey(x[3]),
    };
  });
}
export function summarise(list) {
  const o = { n: list.length, w: 0, l: 0, o: 0, R: 0, gw: 0, gl: 0, best: null, worst: null, streak: 0 };
  let cur = 0;
  const closed = list.filter((t) => t.res !== 'open').sort((a, b) => (a.tout || a.tin) - (b.tout || b.tin));
  for (const t of list) { if (t.res === 'open') o.o++; }
  for (const t of closed) {
    if (t.res === 'won') { o.w++; cur = 0; } else { o.l++; cur++; o.streak = Math.max(o.streak, cur); }
    o.R += t.R;
    if (t.R > 0) o.gw += t.R; else o.gl -= t.R;
    if (!o.best || t.R > o.best.R) o.best = t;
    if (!o.worst || t.R < o.worst.R) o.worst = t;
  }
  o.closed = o.w + o.l;
  o.wr = o.closed ? o.w / o.closed : 0;
  o.avg = o.closed ? o.R / o.closed : 0;
  o.pf = o.gl > 0 ? o.gw / o.gl : o.gw > 0 ? Infinity : 0;
  return o;
}
// the Telegram plan: at most `k` signals per market per day, first come first served
export function capPerDay(list, k = 2) {
  const seen = new Map();
  return list.slice().sort((a, b) => a.tin - b.tin).filter((t) => {
    const key = t.a + '|' + t.day;
    const n = seen.get(key) || 0;
    if (n >= k) return false;
    seen.set(key, n + 1);
    return true;
  });
}
export function groupBy(list, fn) {
  const m = new Map();
  for (const x of list) { const k = fn(x); if (!m.has(k)) m.set(k, []); m.get(k).push(x); }
  return m;
}
export function strengthOf(w) {
  const n = Math.min(w.st[1][0], w.st[2][0]);
  const e = Math.min(w.st[1][2], w.st[2][2]);
  if (n >= 100 && e >= 0.05) return 'Strong';
  if (e > 0) return 'Promising';
  return 'Watch';
}
