// T2R Signal Hub - results bot. Telegram calls this address for every message and button press.
//   setWebhook url = https://<site>/api/telegram , secret_token = TELEGRAM_WEBHOOK_SECRET
// Members: /start -> free trial -> signals by direct message -> subscribe (Paystack). Admin: /grant /revoke /members /setup
// Buttons: market group -> period (today, yesterday, week, month, calendar) -> results card. Telegram-only or all signals.
import { dbReady, rest } from '@/lib/supabase-server';
import { GROUPS, GNAME, groupOf, ADMIN, PRODUCT, TRIAL_DAYS, PLAN_DAYS, payOn, priceTxt, payLink, member, touch, hasAccess, daysLeft, setMember, extend, dateTxt, ubtn } from '@/lib/bot';

export const dynamic = 'force-dynamic';
export const maxDuration = 30;

const TOKEN = process.env.TELEGRAM_BOT_TOKEN;
const SECRET = process.env.TELEGRAM_WEBHOOK_SECRET;
const SITE = process.env.SITE_URL || 'https://t2r-traders-hub.vercel.app';

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
    case '30d': return [t - 29 * DAY, t + DAY, 'Last 30 days'];
    case 'month': return [m0, t + DAY, 'This month'];
    case 'lmonth': { const d = new Date(t * 1000); return [Date.UTC(d.getUTCFullYear(), d.getUTCMonth() - 1, 1) / 1000, m0, 'Last month']; }
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

// state carried in every button: sc = scope (a market group key, or @Market for one asset),
// d = direction (a = buys + sells, b = buys only, s = sells only), p = period
const DIRS = { a: 'Buys + sells', b: 'Buys only', s: 'Sells only' };
const dOk = (x) => (DIRS[x] ? x : 'a');
const enc = (sc, d, p) => `r|${sc}|${d}|${p}`;
const fits = (s) => Buffer.byteLength(s) <= 64;
const scName = (sc) => (sc.startsWith('@') ? sc.slice(1) : GNAME[sc] || 'All markets');
const scGroup = (sc) => (sc.startsWith('@') ? groupOf(sc.slice(1)) : sc);
const calBtn = (sc, d) => btn('📅 Pick a day', `c|${sc}|${d}|${ymd(today0()).slice(0, 6)}`);

// mode r: results for the group · mode a: pick an asset inside the group
function groupKeyboard(d, p, mode = 'r') {
  const list = GROUPS.filter(([k]) => mode === 'r' || k !== 'all');
  const rows = [];
  for (let i = 0; i < list.length; i += 3) rows.push(list.slice(i, i + 3).map(([k, n]) => btn(n, mode === 'r' ? enc(k, d, p) : `a|${k}|${d}|${p}`)));
  rows.push(mode === 'r' ? [btn('🔎 Pick one asset instead', `ag|${d}|${p}`)] : [btn('‹ Back to market groups', `g|${d}|${p}`)]);
  return rows;
}
async function assetKeyboard(g, d, p) {
  const since = today0() - 60 * DAY;
  const seen = new Set();
  for (let off = 0; off < 20000; off += 1000) {
    const r = (await rest(`signals?select=market&t_signal=gte.${since}&limit=1000&offset=${off}`)) || [];
    r.forEach((x) => { if (groupOf(x.market) === g) seen.add(x.market); });
    if (r.length < 1000) break;
  }
  const list = [...seen].sort((x, y) => x.localeCompare(y, 'en', { numeric: true })).filter((m) => fits(enc('@' + m, d, 'd20261231')));
  const rows = [];
  for (let i = 0; i < list.length; i += 2) rows.push(list.slice(i, i + 2).map((m) => btn(m, enc('@' + m, d, p))));
  if (!rows.length) rows.push([btn('No signals in this group yet', 'noop')]);
  rows.push([btn('‹ Other groups', `ag|${d}|${p}`), btn(`📊 All of ${GNAME[g]}`, enc(g, d, p))]);
  return rows;
}
function periodKeyboard(sc, d) {
  return [
    [btn('Today', enc(sc, d, 'today')), btn('Yesterday', enc(sc, d, 'yday')), btn('Last 7 days', enc(sc, d, '7d'))],
    [btn('This week', enc(sc, d, 'week')), btn('Last week', enc(sc, d, 'lweek')), btn('Last 30 days', enc(sc, d, '30d'))],
    [btn('This month', enc(sc, d, 'month')), btn('Last month', enc(sc, d, 'lmonth')), btn('All time', enc(sc, d, 'all'))],
    [calBtn(sc, d)],
  ];
}
function calendar(sc, d, ym) {
  const y = +ym.slice(0, 4), m = +ym.slice(4, 6) - 1;
  const first = Date.UTC(y, m, 1) / 1000;
  const days = new Date(Date.UTC(y, m + 1, 0)).getUTCDate();
  const lead = (new Date(first * 1000).getUTCDay() + 6) % 7;
  const rows = [[btn(`${MON[m]} ${y}`, 'noop')], ['Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa', 'Su'].map((x) => btn(x, 'noop'))];
  let row = Array.from({ length: lead }, () => btn(' ', 'noop'));
  const t0 = today0();
  for (let k = 1; k <= days; k++) {
    const t = first + (k - 1) * DAY;
    row.push(t > t0 ? btn('·', 'noop') : btn(String(k), enc(sc, d, 'd' + ymd(t))));
    if (row.length === 7) { rows.push(row); row = []; }
  }
  if (row.length) { while (row.length < 7) row.push(btn(' ', 'noop')); rows.push(row); }
  const prev = new Date(Date.UTC(y, m - 1, 1)).toISOString().slice(0, 7).replace('-', '');
  const next = new Date(Date.UTC(y, m + 1, 1)).toISOString().slice(0, 7).replace('-', '');
  rows.push([btn('‹ Prev', `c|${sc}|${d}|${prev}`), btn('Back', enc(sc, d, 'today')), btn('Next ›', `c|${sc}|${d}|${next}`)]);
  return rows;
}

// ---------- the numbers ----------
async function fetchRows(a, b, market) {
  const out = [];
  for (let off = 0; off < 20000; off += 1000) {
    const q = `signals?select=market,dir,status,r_full,r_t2r,r_float,t_signal&t_signal=gte.${a}&t_signal=lt.${b}` +
      (market ? `&market=eq.${encodeURIComponent(market)}` : '') + `&order=t_signal.asc&limit=1000&offset=${off}`;
    const rows = (await rest(q)) || [];
    out.push(...rows);
    if (rows.length < 1000) break;
  }
  return out;
}
const tally = (L) => {
  const closed = L.filter((r) => r.status === 'won' || r.status === 'lost');
  const won = closed.filter((r) => r.status === 'won').length;
  const sum = (k) => closed.reduce((x, r) => x + (Number(r[k]) || 0), 0);
  return { n: closed.length, won, lost: closed.length - won, R: sum('r_full'), T: sum('r_t2r') };
};
async function resultsCard(sc, d, p) {
  const [a, b, label] = period(p);
  const mk = sc.startsWith('@') ? sc.slice(1) : null;
  const all = (await fetchRows(a, b, mk)).filter((r) => mk || sc === 'all' || groupOf(r.market) === sc);
  const rows = d === 'b' ? all.filter((r) => r.dir === 'buy') : d === 's' ? all.filter((r) => r.dir === 'sell') : all;
  const t0 = tally(rows);
  const act = rows.filter((r) => r.status === 'active');
  const wait = rows.filter((r) => r.status === 'pending').length;
  let t = `📊 <b>Results · ${esc(scName(sc))}</b>\n<i>${esc(label)} · ${DIRS[d]} · GMT</i>\n\n`;
  if (!rows.length) t += 'No signals in this period.';
  else {
    t += `✅ Won <b>${t0.won}</b>   ❌ Lost <b>${t0.lost}</b>${t0.n ? `   🎯 <b>${Math.round((100 * t0.won) / t0.n)}%</b>` : ''}\n`;
    t += `💰 Full target <b>${R(t0.R)}</b>   ·   T2R rule <b>${R(t0.T)}</b>\n`;
    t += `⚡ Running <b>${act.length}</b>${act.length ? ` · floating ${R(act.reduce((x, r) => x + (Number(r.r_float) || 0), 0))}` : ''}   ·   ⏳ Waiting ${wait}\n`;
    if (d === 'a') {
      const bu = tally(all.filter((r) => r.dir === 'buy')), se = tally(all.filter((r) => r.dir === 'sell'));
      t += `\n🟢 Buys   ${bu.won}/${bu.n} won · <b>${R(bu.R)}</b>\n🔴 Sells   ${se.won}/${se.n} won · <b>${R(se.R)}</b>\n`;
    }
    if (!mk) {
      const by = {};
      rows.filter((r) => r.status === 'won' || r.status === 'lost').forEach((r) => {
        const k = r.market; by[k] = by[k] || { n: 0, w: 0, R: 0 }; by[k].n++; if (r.status === 'won') by[k].w++; by[k].R += Number(r.r_full) || 0;
      });
      const ranked = Object.entries(by).sort((x, y) => y[1].R - x[1].R);
      const best = ranked.slice(0, 3).filter(([, v]) => v.R > 0);
      const worst = ranked.slice(-3).reverse().filter(([, v]) => v.R < 0);
      if (best.length) t += `\n<b>Best</b>\n` + best.map(([k, v]) => `• ${esc(k)}  ${R(v.R)}  (${v.w}/${v.n})`).join('\n');
      if (worst.length) t += `\n<b>Worst</b>\n` + worst.map(([k, v]) => `• ${esc(k)}  ${R(v.R)}  (${v.w}/${v.n})`).join('\n');
    }
  }
  t += `\n\n<i>R = risk. At 1% risk per trade, +1R = +1% on your account.</i>\n<a href="${SITE}/desk">Open the live desk</a>`;
  const dl = (k, txt) => btn((d === k ? '✓ ' : '') + txt, enc(sc, k, p));
  const kb = [
    [dl('a', '⇅ Both'), dl('b', '🟢 Buys'), dl('s', '🔴 Sells')],
    [btn('Today', enc(sc, d, 'today')), btn('Yesterday', enc(sc, d, 'yday')), btn('7 days', enc(sc, d, '7d')), btn('30 days', enc(sc, d, '30d'))],
    [btn('This week', enc(sc, d, 'week')), btn('This month', enc(sc, d, 'month')), btn('📅 Day', `c|${sc}|${d}|${ymd(today0()).slice(0, 6)}`), btn('More…', `p|${sc}|${d}`)],
    [btn('🔎 Pick an asset', sc === 'all' ? `ag|${d}|${p}` : `a|${scGroup(sc)}|${d}|${p}`), btn('🔀 Market group', `g|${d}|${p}`)],
  ];
  return { text: t, kb };
}

// ---------- members ----------
const SUPPORT = process.env.SUPPORT_URL || '';
const say = (chat, text, kb) => tg('sendMessage', { chat_id: chat, parse_mode: 'HTML', text, disable_web_page_preview: true, ...(kb ? { reply_markup: { inline_keyboard: kb } } : {}) });
const toAdmin = (text) => tg('sendMessage', { chat_id: ADMIN, parse_mode: 'HTML', text, disable_web_page_preview: true }).catch(() => {});
const who = (m) => `${esc(m.first_name || 'Member')}${m.username ? ' @' + esc(m.username) : ''} (<code>${m.tg_id}</code>)`;
const resultsBtn = btn('📊 Live results', enc('all', 'a', '7d'));
// the menu that stays at the bottom of the chat, so nobody has to type a /command
const MENU = { keyboard: [[{ text: '📊 Results' }, { text: '🔎 Results by asset' }], [{ text: '👤 My account' }, { text: 'ℹ️ How it works' }]], resize_keyboard: true, is_persistent: true };
const showMenu = (chat) => tg('sendMessage', { chat_id: chat, parse_mode: 'HTML', text: '👇 <b>Your menu is at the bottom of this chat.</b> Tap <b>📊 Results</b> any time to check any market, buys or sells, by day, week or month.', reply_markup: MENU });

function welcome(m) {
  const name = m.first_name ? `, ${esc(m.first_name)}` : '';
  if (hasAccess(m)) {
    const d = daysLeft(m);
    return {
      text: `✅ <b>You're in${name}.</b>\nSignals arrive in this chat automatically.\n\nAccess until <b>${dateTxt(m.access_until)}</b> (${d >= 1 ? Math.floor(d) + ' days' : 'less than a day'} left).` +
        (m.balance ? `\nLot sizes are worked out for a balance of <b>${m.balance}</b>.` : `\n\n📦 Send your account balance, e.g. <code>500</code>, and every card will show your exact lot size.`),
      kb: [[btn('📦 Set my balance', 'bal'), resultsBtn], [btn('ℹ️ How it works', 'how'), btn('💳 Extend', 'sub')]],
    };
  }
  let t = `👋 <b>Welcome${name}, to ${esc(PRODUCT)}</b>\n\nBoom & Crash signals from the only two setups that passed our 3-million-trade test: ⚡ <b>zones with the spike</b> and 🌊 the <b>Drift Breakout</b>. They come straight to this chat:\n` +
    `• entry, stop, take-profit and target on every card\n• your exact lot size for your balance\n• an update under each signal: target, stop or time's up\n\n` +
    `📊 Every result is public, wins and losses. Tap <b>Live results</b> and judge for yourself.\n\n`;
  if (!m.trial_used) {
    t += `🎁 Start with a <b>${TRIAL_DAYS}-day free trial</b>. No card needed.`;
    return { text: t, kb: [[btn(`🎁 Start my ${TRIAL_DAYS}-day free trial`, 'trial')], [resultsBtn, btn('ℹ️ How it works', 'how')]] };
  }
  t += `Your access has ended. ${payOn() ? `Continue for <b>${priceTxt()}</b>.` : 'Tap Subscribe and we will set you up.'}`;
  return { text: t, kb: [[btn('💳 Subscribe', 'sub')], [resultsBtn, btn('ℹ️ How it works', 'how')]] };
}
const HOW = `ℹ️ <b>How it works</b>\n\n1️⃣ A card arrives: BUY or SELL, entry, stop, TP1 and target.\n2️⃣ Place it with your lot size. Send your balance once and we work it out for you.\n` +
  `3️⃣ At +1R we tell you: bank half and move the stop to entry. From there the trade can't lose.\n4️⃣ Filled, target, stop or cancel: we reply under the card every time.\n\n` +
  `⚡ On Boom and Crash we teach catching the spike: <b>buys on Boom, sells on Crash</b>. Every card says if it is with or against the spike. Both sides are sent and tracked, so you can see which side pays.\n\n` +
  `📊 Tap <b>📊 Results</b> at the bottom: any market, buys only or sells only, any day, week or month.\n\nRisk 1% of your account or less per trade.`;

async function startTrial(chat, m) {
  if (hasAccess(m)) { const w = welcome(m); return say(chat, w.text, w.kb); }
  if (m.trial_used) return say(chat, 'Your free trial has already been used.', [[btn('💳 Subscribe', 'sub')], [resultsBtn]]);
  const until = await extend(m.tg_id, TRIAL_DAYS);
  await setMember(m.tg_id, { trial_used: true });
  await say(chat, `🎉 <b>Your free trial is on!</b>\nFor the next ${TRIAL_DAYS} days every spike signal comes straight here. Access until <b>${dateTxt(until)}</b>.\n\n` +
    `📦 One thing first: send your account balance as a number, e.g. <code>500</code>, so each card shows your exact lot size.`, [[btn('ℹ️ How it works', 'how'), resultsBtn]]);
  await showMenu(chat);
  await toAdmin(`🆕 Trial started: ${who(m)}`);
}

async function subscribe(chat, m) {
  if (!payOn()) {
    await say(chat, `💳 <b>Subscriptions open very soon.</b>\nWe have your name. We'll message you here to set you up.`, SUPPORT ? [[ubtn('💬 Message us', SUPPORT)]] : undefined);
    return toAdmin(`💳 Wants to subscribe: ${who(m)}\nGive access: <code>/grant ${m.tg_id} ${PLAN_DAYS}</code>`);
  }
  if (!m.email) return say(chat, '📧 Send your email address for your Paystack receipt, then tap Subscribe again (or it continues automatically).');
  const url = await payLink(m);
  if (!url) { await toAdmin(`⚠️ Paystack link failed for ${who(m)}`); return say(chat, 'The payment page could not open just now. Please try again in a minute.'); }
  return say(chat, `💳 <b>${esc(PRODUCT)}</b> · <b>${priceTxt()}</b>\nPay securely with Paystack: card, bank transfer or USSD. Your access is added automatically the moment payment lands.` +
    (hasAccess(m) ? '\n\nYour days left are kept. The new days are added on top.' : ''), [[ubtn(`💳 Pay ${priceTxt()}`, url)]]);
}

async function adminCmd(chat, txt) {
  const [cmd, a1, a2] = txt.split(/\s+/);
  const find = async (x) => {
    if (!x) return null;
    if (/^\d+$/.test(x)) return member(x);
    const r = await rest(`members?username=ilike.${encodeURIComponent(x.replace(/^@/, ''))}&select=*`);
    return r?.[0] || null;
  };
  if (cmd === '/grant') {
    const m = await find(a1);
    if (!m) return say(chat, 'Member not found. They must press Start in the bot first. Use: <code>/grant 12345 14</code> or <code>/grant @name 14</code>');
    const days = Number(a2 || PLAN_DAYS);
    const until = await extend(m.tg_id, days);
    await say(m.tg_id, `✅ <b>Access added: ${days} days.</b>\nSignals arrive here automatically until <b>${dateTxt(until)}</b>.`).catch(() => {});
    return say(chat, `✅ ${who(m)} now has access until ${dateTxt(until)}`);
  }
  if (cmd === '/revoke') {
    const m = await find(a1);
    if (!m) return say(chat, 'Member not found.');
    await setMember(m.tg_id, { access_until: new Date().toISOString() });
    return say(chat, `⛔ Access removed: ${who(m)}`);
  }
  if (cmd === '/members') {
    const all = (await rest('members?select=*&order=access_until.desc.nullslast&limit=2000')) || [];
    const act = all.filter(hasAccess);
    let t = `👥 <b>Members</b>\nStarted the bot: <b>${all.length}</b>\nWith access now: <b>${act.length}</b>\nBlocked the bot: ${all.filter((m) => m.blocked).length}\n\n`;
    t += act.slice(0, 30).map((m) => `• ${who(m)} · ${daysLeft(m).toFixed(1)}d`).join('\n') || 'Nobody has access yet.';
    return say(chat, t);
  }
  if (cmd === '/setup') {
    const r = await tg('setMyCommands', { commands: [
      { command: 'start', description: 'Home: your access and the free trial' },
      { command: 'results', description: 'Results: any market, buys or sells, any date' },
      { command: 'asset', description: 'Results for one asset' },
      { command: 'status', description: 'Your access and days left' },
      { command: 'balance', description: 'Set your balance for lot sizes' },
      { command: 'subscribe', description: 'Subscribe or extend' },
      { command: 'help', description: 'How it works' },
    ] });
    return say(chat, `Menu updated: ${r.ok}\nAdmin: /members · /grant id days · /revoke id`);
  }
  return null;
}

// ---------- entry point ----------
export async function POST(req) {
  if (!TOKEN) return Response.json({ ok: false, error: 'TELEGRAM_BOT_TOKEN missing' }, { status: 503 });
  if (SECRET && req.headers.get('x-telegram-bot-api-secret-token') !== SECRET) return Response.json({ ok: false }, { status: 401 });
  const u = await req.json().catch(() => ({}));
  try {
    if (u.message) {
      const chat = u.message.chat.id;
      const raw = String(u.message.text || '').trim();
      const txt = raw.toLowerCase();
      if (!dbReady()) { await tg('sendMessage', { chat_id: chat, text: 'The service is not connected yet.' }); return Response.json({ ok: true }); }
      const sendCard = async (sc, d, p) => { const c = await resultsCard(sc, d, p); await tg('sendMessage', { chat_id: chat, parse_mode: 'HTML', text: c.text, disable_web_page_preview: true, reply_markup: { inline_keyboard: c.kb } }); };
      if (/^\/(results|menu)/.test(txt) || /^📊 results$/.test(txt) || txt === 'results') { await sendCard('all', 'a', 'today'); return Response.json({ ok: true }); }
      if (/results by asset/.test(txt) || /^\/asset/.test(txt)) {
        await tg('sendMessage', { chat_id: chat, parse_mode: 'HTML', text: '🔎 <b>Results by asset</b>\nPick the market group first:', reply_markup: { inline_keyboard: groupKeyboard('a', '7d', 'a') } });
        return Response.json({ ok: true });
      }
      if (/^\/today/.test(txt)) { await sendCard('all', 'a', 'today'); return Response.json({ ok: true }); }
      if (/^\/(boom|crash|bc)/.test(txt)) { await sendCard('bc', 'a', 'today'); return Response.json({ ok: true }); }
      if (u.message.chat.type !== 'private' || !u.message.from) return Response.json({ ok: true });

      // members (needs upgrade_v28.sql; before that, /start falls back to the results menu)
      let m;
      try { m = await touch(u.message.from); } catch {
        await sendCard('all', 'a', 'today');
        return Response.json({ ok: true });
      }
      const isNew = m.created_at && Date.now() - new Date(m.created_at).getTime() < 20000;
      if (String(chat) === ADMIN && /^\/(grant|revoke|members|setup)\b/.test(txt)) { await adminCmd(chat, raw); return Response.json({ ok: true }); }

      const num = /^(?:\/balance\s*)?\$?\s*([\d,]+(?:\.\d+)?)\s*(?:usd|\$)?$/i.exec(raw);
      const mail = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.exec(raw);
      if (/^\/start/.test(txt)) {
        const w = welcome(m);
        await say(chat, w.text, w.kb);
        await showMenu(chat);
        if (isNew) await toAdmin(`👋 New in the bot: ${who(m)}`);
      } else if (/^\/status/.test(txt) || /my account/.test(txt)) {
        const w = welcome(m);
        await say(chat, w.text, w.kb);
      } else if (/^\/(subscribe|renew|pay)/.test(txt)) {
        await subscribe(chat, m);
      } else if (/^\/help/.test(txt) || /how it works/.test(txt)) {
        await say(chat, HOW, [[resultsBtn]]);
      } else if (/^\/balance\s*$/.test(txt)) {
        await say(chat, '📦 Send your account balance as a number, e.g. <code>500</code>.');
      } else if (num) {
        const bal = Number(num[1].replace(/,/g, ''));
        if (bal > 0 && bal <= 100000000) {
          await setMember(m.tg_id, { balance: bal });
          await say(chat, `📦 Saved. Every card now shows your lot size for a balance of <b>${bal}</b>.\nChange it any time: just send a new number.`);
        }
      } else if (mail) {
        await setMember(m.tg_id, { email: raw });
        await say(chat, '📧 Email saved.');
        await subscribe(chat, { ...m, email: raw });
      } else {
        const w = welcome(m);
        await say(chat, w.text, w.kb);
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
      if (k === 'r') {
        // buttons from older cards were r|group|period|source
        const [sc, d, per] = DIRS[p[1]] ? [p[0], p[1], p[2]] : [p[0], 'a', p[1]];
        const c = await resultsCard(sc, d, per);
        // results opened from a member message: send a new card instead of replacing the welcome
        if (q.message.text && !q.message.text.startsWith('📊')) await tg('sendMessage', { chat_id: chat, parse_mode: 'HTML', text: c.text, disable_web_page_preview: true, reply_markup: { inline_keyboard: c.kb } });
        else await edit(c.text, c.kb);
      }
      if (k === 'g') { const [d, per] = DIRS[p[0]] ? [p[0], p[1]] : ['a', p[0]]; await edit('📊 <b>Pick a market group</b>', groupKeyboard(d, per)); }
      if (k === 'ag') await edit('🔎 <b>Results by asset</b>\nPick the market group first:', groupKeyboard(dOk(p[0]), p[1], 'a'));
      if (k === 'a') await edit(`🔎 <b>${esc(GNAME[p[0]] || '')}</b> · pick an asset`, await assetKeyboard(p[0], dOk(p[1]), p[2]));
      if (k === 'p') await edit(`🗓 <b>Pick a period</b> · ${esc(scName(p[0]))}`, periodKeyboard(p[0], dOk(p[1])));
      if (k === 'c') await edit(`📅 <b>Pick a day</b> · ${esc(scName(p[0]))}`, calendar(p[0], dOk(p[1]), p[2]));
      if (['trial', 'sub', 'how', 'bal'].includes(k) && q.from) {
        const m = await touch(q.from);
        if (k === 'trial') await startTrial(chat, m);
        if (k === 'sub') await subscribe(chat, m);
        if (k === 'how') await say(chat, HOW, [[resultsBtn]]);
        if (k === 'bal') await say(chat, '📦 Send your account balance as a number, e.g. <code>500</code>.');
      }
      return Response.json({ ok: true });
    }
  } catch (e) {
    return Response.json({ ok: true, note: String(e.message || e) });
  }
  return Response.json({ ok: true });
}

export async function GET() {
  let members = false;
  try { await rest('members?select=tg_id&limit=1'); members = true; } catch {}
  return Response.json({ ok: true, bot: !!TOKEN, secret: !!SECRET, db: dbReady(), members, payments: payOn(), cron: !!process.env.CRON_SECRET });
}
