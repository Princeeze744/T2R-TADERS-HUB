// T2R Signal Hub - results bot. Telegram calls this address for every message and button press.
//   setWebhook url = https://<site>/api/telegram , secret_token = TELEGRAM_WEBHOOK_SECRET
// Buttons: market group -> period (today, yesterday, week, month, calendar) -> results card. Telegram-only or all signals.
import { dbReady, rest } from '@/lib/supabase-server';

export const dynamic = 'force-dynamic';
export const maxDuration = 20;

const TOKEN = process.env.TELEGRAM_BOT_TOKEN;
const SECRET = process.env.TELEGRAM_WEBHOOK_SECRET;
const SITE = process.env.SITE_URL || 'https://t2r-traders-hub.vercel.app';

// ---------- market groups ----------
const GROUPS = [
  ['all', 'All markets'], ['bc', 'Boom & Crash'], ['dex', 'DEX'], ['vo', 'Vol over'],
  ['vol', 'Volatility'], ['rb', 'Range Break'], ['syn', 'Other synthetics'], ['fx', 'Forex'], ['met', 'Metals'],
];
const GNAME = Object.fromEntries(GROUPS);
function groupOf(m) {
  if (/^(Boom|Crash) \d/.test(m)) return 'bc';
  if (/DEX/.test(m)) return 'dex';
  if (/Vol over/.test(m)) return 'vo';
  if (/Range Break/.test(m)) return 'rb';
  if (/^X(AU|AG|PT|PD)/.test(m)) return 'met';
  if (/^[A-Z]{6}$/.test(m)) return 'fx';
  if (/Volatility|High Frequency/.test(m)) return 'vol';
  return 'syn';
}

// ---------- time (server time = GMT) ----------
const DAY = 86400;
const MON = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const DOW = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
const today0 = () => Math.floor(Date.now() / 1000 / DAY) * DAY;
const ymd = (t) => new Date(t * 1000).toISOString().slice(0, 10).replace(/-/g, '');
const fromYmd = (s) => Date.UTC(+s.slice(0, 4), +s.slice(4, 6) - 1, +s.slice(6, 8)) / 1000;
const dlabel = (t) => { const d = new Date(t * 1000); return `${DOW[d.getUTCDay()]} ${d.getUTCDate()} ${MON[d.getUTCMonth()]}`; };
function period(code) {
  const t = today0();
  const dow = (new Date(t * 1000).getUTCDay() + 6) % 7; // Monday = 0
  const m0 = Date.UTC(new Date(t * 1000).getUTCFullYear(), new Date(t * 1000).getUTCMonth(), 1) / 1000;
  switch (code) {
    case 'today': return [t, t + DAY, 'Today, ' + dlabel(t)];
    case 'yday': return [t - DAY, t, 'Yesterday, ' + dlabel(t - DAY)];
    case 'week': return [t - dow * DAY, t + DAY, 'This week'];
    case 'lweek': return [t - (dow + 7) * DAY, t - dow * DAY, 'Last week'];
    case '7d': return [t - 6 * DAY, t + DAY, 'Last 7 days'];
    case 'month': return [m0, t + DAY, 'This month'];
    case 'all': return [0, t + DAY, 'All time'];
    default:
      if (/^d\d{8}$/.test(code)) { const a = fromYmd(code.slice(1)); return [a, a + DAY, dlabel(a) + ' ' + code.slice(1, 5)]; }
      return [t, t + DAY, 'Today'];
  }
}

// ---------- Telegram helpers ----------
async function tg(method, body) {
  const r = await fetch(`https://api.telegram.org/bot${TOKEN}/${method}`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) });
  return r.json().catch(() => ({}));
}
const esc = (s) => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
const R = (x) => (x >= 0 ? '+' : '−') + Math.abs(x).toFixed(1) + 'R';
const btn = (text, data) => ({ text, callback_data: data });

// state carried in every button: g = group, p = period, s = source (t = Telegram signals, a = all)
const enc = (g, p, s) => `r|${g}|${p}|${s}`;

function groupKeyboard(p, s) {
  const rows = [];
  for (let i = 0; i < GROUPS.length; i += 3) rows.push(GROUPS.slice(i, i + 3).map(([k, n]) => btn(n, enc(k, p, s))));
  return rows;
}
function periodKeyboard(g, s) {
  return [
    [btn('Today', enc(g, 'today', s)), btn('Yesterday', enc(g, 'yday', s)), btn('Last 7 days', enc(g, '7d', s))],
    [btn('This week', enc(g, 'week', s)), btn('Last week', enc(g, 'lweek', s)), btn('This month', enc(g, 'month', s))],
    [btn('📅 Pick a day', `c|${g}|${s}|${ymd(today0()).slice(0, 6)}`), btn('All time', enc(g, 'all', s))],
  ];
}
function calendar(g, s, ym) {
  const y = +ym.slice(0, 4), m = +ym.slice(4, 6) - 1;
  const first = Date.UTC(y, m, 1) / 1000;
  const days = new Date(Date.UTC(y, m + 1, 0)).getUTCDate();
  const lead = (new Date(first * 1000).getUTCDay() + 6) % 7;
  const rows = [[btn(`${MON[m]} ${y}`, 'noop')], ['Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa', 'Su'].map((d) => btn(d, 'noop'))];
  let row = Array.from({ length: lead }, () => btn(' ', 'noop'));
  const t0 = today0();
  for (let d = 1; d <= days; d++) {
    const t = first + (d - 1) * DAY;
    row.push(t > t0 ? btn('·', 'noop') : btn(String(d), enc(g, 'd' + ymd(t), s)));
    if (row.length === 7) { rows.push(row); row = []; }
  }
  if (row.length) { while (row.length < 7) row.push(btn(' ', 'noop')); rows.push(row); }
  const prev = new Date(Date.UTC(y, m - 1, 1)).toISOString().slice(0, 7).replace('-', '');
  const next = new Date(Date.UTC(y, m + 1, 1)).toISOString().slice(0, 7).replace('-', '');
  rows.push([btn('‹ Prev', `c|${g}|${s}|${prev}`), btn('Back', enc(g, 'today', s)), btn('Next ›', `c|${g}|${s}|${next}`)]);
  return rows;
}

// ---------- the numbers ----------
async function fetchRows(a, b) {
  const cols = 'market,status,r_full,r_t2r,r_float,t_signal,tg';
  const out = [];
  for (let off = 0; off < 20000; off += 1000) {
    let q = `signals?select=${cols}&t_signal=gte.${a}&t_signal=lt.${b}&order=t_signal.asc&limit=1000&offset=${off}`;
    let rows;
    try { rows = await rest(q); } catch (e) {
      // database without the tg column yet: read without it
      q = q.replace(',tg', '');
      rows = await rest(q);
    }
    out.push(...rows);
    if (rows.length < 1000) break;
  }
  return out;
}
async function resultsCard(g, p, s) {
  const [a, b, label] = period(p);
  let rows = (await fetchRows(a, b)).filter((r) => g === 'all' || groupOf(r.market) === g);
  const hasTg = rows.some((r) => r.tg === true);
  if (s === 't') rows = rows.filter((r) => r.tg === true);
  const closed = rows.filter((r) => r.status === 'won' || r.status === 'lost');
  const won = closed.filter((r) => r.status === 'won').length;
  const sum = (L, k) => L.reduce((x, r) => x + (Number(r[k]) || 0), 0);
  const act = rows.filter((r) => r.status === 'active');
  const wait = rows.filter((r) => r.status === 'pending').length;
  const by = {};
  closed.forEach((r) => { const k = r.market; by[k] = by[k] || { n: 0, w: 0, R: 0 }; by[k].n++; if (r.status === 'won') by[k].w++; by[k].R += Number(r.r_full) || 0; });
  const ranked = Object.entries(by).sort((x, y) => y[1].R - x[1].R);
  let t = `📊 <b>Results · ${esc(GNAME[g])}</b>\n<i>${esc(label)} · ${s === 't' ? 'Telegram signals' : 'all signals'} · GMT</i>\n\n`;
  if (!rows.length) {
    t += (s === 't' && !hasTg) ? 'No Telegram-marked signals in this period yet (marking started with EA v1.58). Try <b>All signals</b>.' : 'No signals in this period.';
  } else {
    t += `✅ Won <b>${won}</b>   ❌ Lost <b>${closed.length - won}</b>   ${closed.length ? `🎯 <b>${Math.round((100 * won) / closed.length)}%</b>` : ''}\n`;
    t += `💰 Result <b>${R(sum(closed, 'r_full'))}</b>   ·   T2R rule <b>${R(sum(closed, 'r_t2r'))}</b>\n`;
    t += `⚡ Running <b>${act.length}</b>${act.length ? ` · floating ${R(sum(act, 'r_float'))}` : ''}   ·   ⏳ Waiting ${wait}\n`;
    if (ranked.length) {
      t += `\n<b>Best</b>\n` + ranked.slice(0, 3).map(([k, v]) => `• ${esc(k)}  ${R(v.R)}  (${v.w}/${v.n})`).join('\n');
      const worst = ranked.slice(-3).reverse().filter(([, v]) => v.R < 0);
      if (worst.length) t += `\n<b>Worst</b>\n` + worst.map(([k, v]) => `• ${esc(k)}  ${R(v.R)}  (${v.w}/${v.n})`).join('\n');
    }
  }
  t += `\n\n<a href="${SITE}/desk">Open the live desk</a>`;
  const kb = [
    [btn('Today', enc(g, 'today', s)), btn('Yesterday', enc(g, 'yday', s)), btn('7 days', enc(g, '7d', s)), btn('📅', `c|${g}|${s}|${ymd(today0()).slice(0, 6)}`)],
    [btn(s === 't' ? '✓ Telegram signals' : 'Telegram signals', enc(g, p, 't')), btn(s === 'a' ? '✓ All signals' : 'All signals', enc(g, p, 'a'))],
    [btn('🔀 Market group', `g|${p}|${s}`), btn('🗓 Period', `p|${g}|${s}`)],
  ];
  return { text: t, kb };
}

// ---------- entry point ----------
export async function POST(req) {
  if (!TOKEN) return Response.json({ ok: false, error: 'TELEGRAM_BOT_TOKEN missing' }, { status: 503 });
  if (SECRET && req.headers.get('x-telegram-bot-api-secret-token') !== SECRET) return Response.json({ ok: false }, { status: 401 });
  const u = await req.json().catch(() => ({}));
  try {
    if (u.message) {
      const chat = u.message.chat.id;
      const txt = String(u.message.text || '').trim().toLowerCase();
      if (!dbReady()) { await tg('sendMessage', { chat_id: chat, text: 'Results are not connected yet.' }); return Response.json({ ok: true }); }
      if (/^\/(start|results|menu)/.test(txt) || txt === 'results') {
        await tg('sendMessage', { chat_id: chat, parse_mode: 'HTML', text: '📊 <b>T2R Lab results</b>\nPick a market group:', reply_markup: { inline_keyboard: groupKeyboard('today', 'a') } });
      } else if (/^\/today/.test(txt)) {
        const c = await resultsCard('all', 'today', 'a');
        await tg('sendMessage', { chat_id: chat, parse_mode: 'HTML', text: c.text, disable_web_page_preview: true, reply_markup: { inline_keyboard: c.kb } });
      } else if (/^\/(boom|crash|bc)/.test(txt)) {
        const c = await resultsCard('bc', 'today', 'a');
        await tg('sendMessage', { chat_id: chat, parse_mode: 'HTML', text: c.text, disable_web_page_preview: true, reply_markup: { inline_keyboard: c.kb } });
      }
      return Response.json({ ok: true });
    }
    if (u.callback_query) {
      const q = u.callback_query;
      const chat = q.message.chat.id, mid = q.message.message_id;
      const [k, ...p] = String(q.data || '').split('|');
      await tg('answerCallbackQuery', { callback_query_id: q.id });
      if (k === 'noop') return Response.json({ ok: true });
      const edit = (text, kb) => tg('editMessageText', { chat_id: chat, message_id: mid, parse_mode: 'HTML', text, disable_web_page_preview: true, reply_markup: { inline_keyboard: kb } });
      if (k === 'r') { const c = await resultsCard(p[0], p[1], p[2]); await edit(c.text, c.kb); }
      if (k === 'g') await edit('📊 <b>Pick a market group</b>', groupKeyboard(p[0], p[1]));
      if (k === 'p') await edit(`🗓 <b>Pick a period</b> · ${esc(GNAME[p[0]])}`, periodKeyboard(p[0], p[1]));
      if (k === 'c') await edit(`📅 <b>Pick a day</b> · ${esc(GNAME[p[0]])}`, calendar(p[0], p[1], p[2]));
      return Response.json({ ok: true });
    }
  } catch (e) {
    return Response.json({ ok: true, note: String(e.message || e) });
  }
  return Response.json({ ok: true });
}

export async function GET() {
  return Response.json({ ok: true, bot: !!TOKEN, secret: !!SECRET, db: dbReady() });
}
