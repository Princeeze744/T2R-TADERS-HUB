// T2R Spike - the members side of the bot: who has access, the premium signal card, sending to every member,
// and the updates that reply under each card. Server only (uses the secret key and the bot token).
import { rest } from '@/lib/supabase-server';

export const TOKEN = process.env.TELEGRAM_BOT_TOKEN;
export const SITE = process.env.SITE_URL || 'https://t2r-traders-hub.vercel.app';
export const ADMIN = String(process.env.TELEGRAM_ADMIN_ID || '7921661093');
export const PRODUCT = process.env.PRODUCT_NAME || 'T2R Spike Signals';
export const BOT_USER = process.env.BOT_USERNAME || 'T2RsignalHubbot';
export const TRIAL_DAYS = Number(process.env.TRIAL_DAYS || 3);
export const PLAN_DAYS = Number(process.env.PLAN_DAYS || 14);
export const PRICE_NGN = Number(process.env.PLAN_PRICE_NGN || 0);   // 0 = payments not switched on yet
export const PAYSTACK = process.env.PAYSTACK_SECRET_KEY || '';
export const payOn = () => !!(PAYSTACK && PRICE_NGN > 0);

// ---------- Telegram ----------
export async function tg(method, body) {
  const r = await fetch(`https://api.telegram.org/bot${TOKEN}/${method}`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) });
  return r.json().catch(() => ({}));
}
export const esc = (s) => String(s ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
export const Rtxt = (x) => (x >= 0 ? '+' : '−') + Math.abs(Number(x) || 0).toFixed(1) + 'R';
export const btn = (text, data) => ({ text, callback_data: data });
export const ubtn = (text, url) => ({ text, url });
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const nowIso = () => new Date().toISOString();
const MON = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
export const dateTxt = (iso) => { const d = new Date(iso); return `${d.getUTCDate()} ${MON[d.getUTCMonth()]}, ${String(d.getUTCHours()).padStart(2, '0')}:${String(d.getUTCMinutes()).padStart(2, '0')} GMT`; };

// ---------- market groups (shared with the results bot and the daily report) ----------
export const GROUPS = [
  ['all', 'All markets'], ['bc', 'Boom & Crash'], ['dex', 'DEX'], ['vo', 'Vol over'],
  ['vol', 'Volatility'], ['rb', 'Range Break'], ['syn', 'Other synthetics'], ['fx', 'Forex'], ['met', 'Metals'],
];
export const GNAME = Object.fromEntries(GROUPS);
export function groupOf(m) {
  if (/^(Boom|Crash) \d/.test(m)) return 'bc';
  if (/DEX/.test(m)) return 'dex';
  if (/Vol over/.test(m)) return 'vo';
  if (/Range Break/.test(m)) return 'rb';
  if (/^X(AU|AG|PT|PD)/.test(m) || /GOLD|SILVER/i.test(m)) return 'met';
  if (/^[A-Z]{6}$/.test(m)) return 'fx';
  if (/Volatility|High Frequency/.test(m)) return 'vol';
  return 'syn';
}

// ---------- which signals members get ----------
// Every market except forex and metals (gold, silver ...), buys AND sells, so every side is tracked.
// PREMIUM_MARKETS (Vercel variable, optional): exact market names, comma separated, to narrow the list.
const ONLY = (process.env.PREMIUM_MARKETS || '').split(',').map((s) => s.trim().toLowerCase()).filter(Boolean);
export function premiumOk(market) {
  const m = String(market || '');
  if (!m) return false;
  if (ONLY.length) return ONLY.includes(m.toLowerCase());
  const g = groupOf(m);
  return g !== 'fx' && g !== 'met';
}
// MEMBER_FEED (Vercel variable, optional): 'best' (default) = only the proven setups, 'all' = every premium signal.
// Proven: the Drift Breakout, and Boom & Crash Self-taught Zones model picks with the spike at the wide stop.
const FEED = (process.env.MEMBER_FEED || 'best').toLowerCase();
export const isDrift = (row) => String(row?.strategy || '') === 'T2R Drift Breakout';
export function isBest(row) {
  if (isDrift(row)) return true;
  return groupOf(String(row?.market || '')) === 'bc' && /^Self-taught Zones/.test(String(row?.strategy || '')) &&
    /Model picks/.test(String(row?.view || '')) && row?.stop_class === 'Wide' && spikeSide(row.market, row.dir) === 'with';
}
export const memberFeed = (row) => FEED === 'all' || isBest(row);
// which way the market spikes: Boom and "Vol over Boom" up, Crash and "Vol over Crash" down
export function spikeSide(market, dir) {
  const m = String(market || '');
  const up = /Boom/.test(m), down = /Crash/.test(m);
  if (!up && !down) return null;
  return (up && dir === 'buy') || (down && dir === 'sell') ? 'with' : 'against';
}

// ---------- members ----------
export async function member(id) {
  const r = await rest(`members?tg_id=eq.${id}&select=*`);
  return r?.[0] || null;
}
export async function touch(from) {
  const row = { tg_id: from.id, username: from.username || null, first_name: from.first_name || null, last_seen: nowIso() };
  const r = await rest('members?on_conflict=tg_id', { method: 'POST', body: [row], prefer: 'resolution=merge-duplicates,return=representation' });
  return r?.[0] || row;
}
export const hasAccess = (m) => !!(m && !m.blocked && m.access_until && new Date(m.access_until) > new Date());
export const daysLeft = (m) => (hasAccess(m) ? Math.max(0, (new Date(m.access_until) - Date.now()) / 86400000) : 0);
export async function setMember(id, patch) {
  await rest(`members?tg_id=eq.${id}`, { method: 'PATCH', body: patch, prefer: 'return=minimal' });
}
// adds days on top of what is left (so renewing early never loses days)
export async function extend(id, days) {
  const m = await member(id);
  const base = hasAccess(m) ? new Date(m.access_until).getTime() : Date.now();
  const until = new Date(base + days * 86400000).toISOString();
  await setMember(id, { access_until: until, ended_notified: false, reminded_at: null, blocked: false });
  return until;
}
export async function activeMembers() {
  return (await rest(`members?select=tg_id,balance&blocked=eq.false&access_until=gt.${nowIso()}&limit=10000`)) || [];
}

// ---------- the premium card ----------
const px = (x) => { const n = Number(x); return Number.isFinite(n) ? String(+n.toPrecision(10)) : '-'; };
function ratioOf(row) {
  const m = /1:(\d+(?:\.\d+)?)/.exec(String(row.rr || ''));
  if (m) return Number(m[1]);
  const risk = Math.abs(row.entry - row.stop);
  return risk > 0 ? Math.abs(row.target - row.entry) / risk : 0;
}
export function lotLine(row, balance) {
  const rpl = Number(row.risk_per_lot), step = Number(row.vol_step) || 0.01, min = Number(row.vol_min) || step;
  if (!balance) return `📦 Send your balance, e.g. <code>500</code>, and every card shows your exact lot size.\n`;
  if (!(rpl > 0)) return '';
  const ccy = row.ccy || 'USD';
  const lot = (pct) => Math.floor((balance * pct / 100) / rpl / step + 1e-9) * step;
  const f = (v) => v.toFixed(Math.max(0, -Math.floor(Math.log10(step) + 1e-9)));
  const l1 = lot(0.5), l05 = lot(0.25);
  if (l05 < min) {
    const riskPct = (min * rpl / balance) * 100;
    return `📦 Your lot (${ccy} ${balance}): the smallest lot ${f(min)} risks <b>${riskPct.toFixed(1)}%</b>. Skip it or size up your account.\n`;
  }
  return `📦 Your lot (${ccy} ${balance}):  0.25% → <b>${f(l05)}</b>   ·   0.5% → <b>${f(l1)}</b>\n`;
}
export function cardText(row, balance) {
  const buy = row.dir === 'buy';
  const now = row.order_type === 'market' || row.status === 'active';
  const ratio = ratioOf(row);
  let t = `${buy ? '🟢' : '🔴'} <b>${buy ? 'BUY' : 'SELL'} ${now ? 'NOW' : String(row.order_type || 'limit').toUpperCase()}</b>  ·  <b>${esc(row.market)}</b>\n`;
  const dr = isDrift(row);
  t += dr ? `<i>${esc(row.view || 'Session')} range just broke. Enter at market now.</i>\n\n` : now ? '<i>Price is in the zone. Enter at market now.</i>\n\n' : '<i>Place this pending order now. It only fills if price comes back to the zone.</i>\n\n';
  t += `📍 Entry    <code>${px(row.entry)}</code>\n`;
  t += `🛑 Stop     <code>${px(row.stop)}</code>   −1R\n`;
  if (ratio > 1 && row.tp1) t += `💰 TP1      <code>${px(row.tp1)}</code>   +1R → bank half, stop to entry\n`;
  t += `🎯 Target   <code>${px(row.target)}</code>   +${+ratio.toFixed(1)}R\n\n`;
  t += `⚖️ Risk : reward  <b>1:${+ratio.toFixed(1)}</b>\n`;
  t += lotLine(row, balance);
  const sp = spikeSide(row.market, row.dir);
  t += dr ? '🌊 <b>Drift Breakout</b>: rides the walk between spikes. Out after 8 hours if neither stop nor target.\n\n'
    : sp === 'with' ? '⚡ <b>With the spike</b>, the side we teach.\n\n'
    : sp === 'against' ? '↩️ <b>Against the spike.</b> A spike can jump the stop, so keep the risk small.\n\n'
    : '🧠 Zone setup from our live-tested system.\n\n';
  t += `<blockquote>Risk 0.25% of your account (0.5% at most). Losing runs are normal. Not financial advice.${now ? '' : ' We post CANCEL if the zone breaks first.'}</blockquote>\n`;
  const ts = Number(row.t_signal) ? new Date(Number(row.t_signal) * 1000) : new Date();
  t += `⏱ ${String(ts.getUTCHours()).padStart(2, '0')}:${String(ts.getUTCMinutes()).padStart(2, '0')} GMT`;
  return t;
}
function lifeText(kind, row) {
  const full = Number(row.r_full), t2r = Number(row.r_t2r);
  switch (kind) {
    case 'activated': return `▶️ <b>Filled</b>. The trade is live from <code>${px(row.entry)}</code>.`;
    case 'tp1': return `💰 <b>+1R reached.</b> Bank half now and move your stop to entry. The rest runs risk-free to target.`;
    case 'target': return `🎯 <b>Target hit</b>  ·  <b>${Rtxt(full)}</b>${Number.isFinite(t2r) && Math.abs(t2r - full) > 0.01 ? `  (T2R rule ${Rtxt(t2r)})` : ''} 🔥`;
    case 'closed': return `⏱ <b>Time's up, closed at market</b>  ·  <b>${Rtxt(full)}</b>${full > 0 ? ' ✅' : ''}`;
    case 'cancel': return `❌ <b>Cancelled.</b> The zone broke before price came back. Delete the pending order.`;
    default: // stop / breakeven
      if (row.hit_tp1) return `🛡 <b>Closed at entry</b> after banking half at +1R  ·  <b>${Rtxt(Number.isFinite(t2r) ? t2r : 0.5)}</b>`;
      return `🛑 <b>Stopped</b>  ·  <b>−1R</b>. Part of the plan. On to the next one.`;
  }
}

// ---------- sending ----------
async function sendTo(id, payload) {
  const r = await tg('sendMessage', { chat_id: id, parse_mode: 'HTML', disable_web_page_preview: true, ...payload });
  if (!r.ok && (r.error_code === 403 || /blocked|deactivated|not found/i.test(r.description || ''))) await setMember(id, { blocked: true }).catch(() => {});
  if (!r.ok && r.error_code === 429) { await sleep(((r.parameters?.retry_after) || 2) * 1000); return sendTo(id, payload); }
  return r;
}
async function claim(table, conflict, row) {
  const r = await rest(`${table}?on_conflict=${conflict}`, { method: 'POST', body: [row], prefer: 'resolution=ignore-duplicates,return=representation' });
  return Array.isArray(r) && r.length > 0;
}
async function signalRow(id) {
  const r = await rest(`signals?id=eq.${encodeURIComponent(id)}&select=*`);
  return r?.[0] || null;
}

// A brand-new Telegram signal in a premium market: one card to every member with access
export async function broadcastSignal(id) {
  const row = await signalRow(id);
  if (!row || !['pending', 'active'].includes(row.status) || !premiumOk(row.market) || !memberFeed(row)) return 0;
  if (Number(row.t_signal) && Date.now() / 1000 - Number(row.t_signal) > 20 * 60) return 0; // never send stale signals
  // two setups on the same zone = one card (same market, same side, entries within 0.35 of the stop distance)
  const risk = Math.abs(Number(row.entry) - Number(row.stop));
  const near = (await rest(`signals?select=id,entry&market=eq.${encodeURIComponent(row.market)}&dir=eq.${row.dir}&t_signal=gte.${Number(row.t_signal) - 3600}&id=neq.${encodeURIComponent(id)}&status=in.(pending,active)`)) || [];
  const twins = near.filter((x) => Math.abs(Number(x.entry) - Number(row.entry)) <= 0.35 * risk).map((x) => encodeURIComponent(x.id));
  if (twins.length) {
    const hit = await rest(`broadcasts?select=signal_id&signal_id=in.(${twins.join(',')})`);
    if (hit?.length) return 0;
  }
  if (!(await claim('broadcasts', 'signal_id', { signal_id: id }))) return 0;            // already sent
  const list = await activeMembers();
  let n = 0;
  for (const m of list) {
    const r = await sendTo(m.tg_id, { text: cardText(row, Number(m.balance) || 0) });
    if (r.ok) {
      n++;
      await rest('deliveries?on_conflict=signal_id,tg_id,kind', { method: 'POST', body: [{ signal_id: id, tg_id: m.tg_id, kind: 'card', message_id: r.result.message_id }], prefer: 'resolution=ignore-duplicates,return=minimal' }).catch(() => {});
    }
    await sleep(40); // Telegram allows about 30 messages a second
  }
  await rest(`broadcasts?signal_id=eq.${encodeURIComponent(id)}`, { method: 'PATCH', body: { sent: n }, prefer: 'return=minimal' }).catch(() => {});
  return n;
}

// An update on a signal members received: a reply under each member's card
export async function broadcastLife(id, kind) {
  const b = await rest(`broadcasts?signal_id=eq.${encodeURIComponent(id)}&select=signal_id`);
  if (!b?.length) return 0;
  const row = await signalRow(id);
  if (!row) return 0;
  if (kind === 'activated' && row.order_type === 'market') return 0;
  const slot = ['target', 'stop', 'breakeven', 'closed'].includes(kind) ? 'close' : kind; // one closing message only
  const cards = (await rest(`deliveries?signal_id=eq.${encodeURIComponent(id)}&kind=eq.card&select=tg_id,message_id`)) || [];
  let n = 0;
  for (const c of cards) {
    if (!(await claim('deliveries', 'signal_id,tg_id,kind', { signal_id: id, tg_id: c.tg_id, kind: slot }))) continue;
    const r = await sendTo(c.tg_id, { text: lifeText(kind, row), reply_to_message_id: c.message_id, allow_sending_without_reply: true });
    if (r.ok) n++;
    await sleep(40);
  }
  return n;
}

// Called by /api/ingest after the database is updated. Every new signal (not forex or metals) goes to members.
const LIFE = ['activated', 'tp1', 'target', 'stop', 'breakeven', 'closed', 'cancel'];
export async function fanout(events) {
  if (!TOKEN) return;
  const fresh = new Set();
  const life = [];
  for (const e of events) {
    if (e.market && !premiumOk(e.market)) continue;
    if (e.kind === 'signal') fresh.add(String(e.id));
    if (LIFE.includes(e.kind)) life.push([String(e.id), e.kind]);
  }
  for (const id of fresh) await broadcastSignal(id).catch(() => {});
  for (const [id, kind] of life) await broadcastLife(id, kind).catch(() => {});
}

// ---------- payments (Paystack) ----------
export async function payLink(m) {
  const reference = `t2r_${m.tg_id}_${Date.now()}`;
  const r = await fetch('https://api.paystack.co/transaction/initialize', {
    method: 'POST',
    headers: { Authorization: `Bearer ${PAYSTACK}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({
      email: m.email, amount: Math.round(PRICE_NGN * 100), currency: 'NGN', reference,
      callback_url: `https://t.me/${BOT_USER}`,
      metadata: { tg_id: String(m.tg_id), days: PLAN_DAYS, custom_fields: [{ display_name: 'Telegram', variable_name: 'telegram', value: m.username ? '@' + m.username : String(m.tg_id) }] },
    }),
  });
  const j = await r.json().catch(() => ({}));
  return j?.data?.authorization_url || null;
}
export const priceTxt = () => `₦${PRICE_NGN.toLocaleString('en-NG')} / ${PLAN_DAYS} days`;
