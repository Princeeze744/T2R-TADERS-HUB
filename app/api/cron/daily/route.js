// Runs once a day (vercel.json): the daily report to members, and reminders before access ends.
import { rest } from '@/lib/supabase-server';
import { groupOf, GNAME, tg, esc, Rtxt, btn, ADMIN, PRODUCT, premiumOk, activeMembers, hasAccess, dateTxt, payOn, priceTxt } from '@/lib/bot';

export const dynamic = 'force-dynamic';
export const maxDuration = 60;
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const send = (id, text, kb) => tg('sendMessage', { chat_id: id, parse_mode: 'HTML', text, disable_web_page_preview: true, ...(kb ? { reply_markup: { inline_keyboard: kb } } : {}) });

async function report() {
  const t0 = Math.floor(Date.now() / 86400000) * 86400;
  const a = t0 - 86400;
  const sent = (await rest(`broadcasts?select=signal_id&at=gte.${new Date(a * 1000).toISOString()}&limit=5000`)) || [];
  const ids = new Set(sent.map((r) => r.signal_id));
  const rows = ((await rest(`signals?select=id,market,dir,status,r_full,r_t2r,hit_tp1,t_signal&t_signal=gte.${a}&t_signal=lt.${t0}&limit=5000`)) || [])
    .filter((r) => ids.has(r.id) && premiumOk(r.market));
  const closed = rows.filter((r) => r.status === 'won' || r.status === 'lost');
  const won = closed.filter((r) => r.status === 'won').length;
  const sum = (k) => closed.reduce((x, r) => x + (Number(r[k]) || 0), 0);
  const d = new Date(a * 1000);
  let t = `📊 <b>${esc(PRODUCT)} · daily report</b>\n<i>${d.toUTCString().slice(0, 11)} · signals sent to members · GMT</i>\n\n`;
  if (!rows.length) return t + 'No signals were sent yesterday.';
  t += `✅ Won <b>${won}</b>   ❌ Lost <b>${closed.length - won}</b>${closed.length ? `   🎯 <b>${Math.round((100 * won) / closed.length)}%</b>` : ''}\n`;
  t += `💰 T2R rule (half off at +1R) <b>${Rtxt(sum('r_t2r'))}</b>   ·   Full target <b>${Rtxt(sum('r_full'))}</b>\n`;
  const open = rows.length - closed.length - rows.filter((r) => r.status === 'cancelled').length;
  if (open > 0) t += `⚡ Still running or waiting: ${open}\n`;
  const gs = {};
  closed.forEach((r) => { const g = groupOf(r.market); gs[g] = gs[g] || { n: 0, w: 0, R: 0 }; gs[g].n++; if (r.status === 'won') gs[g].w++; gs[g].R += Number(r.r_t2r) || 0; });
  const gl = Object.entries(gs).sort((x, y) => y[1].R - x[1].R);
  if (gl.length) t += `\n<b>By market (T2R rule)</b>\n` + gl.map(([g, v]) => `• ${esc(GNAME[g])}  ${v.w}/${v.n} won · ${Rtxt(v.R)}`).join('\n') + '\n';
  const top = closed.filter((r) => r.status === 'won').sort((x, y) => y.r_full - x.r_full).slice(0, 3);
  if (top.length) t += `\n<b>Best</b>\n` + top.map((r) => `• ${esc(r.market)} ${r.dir === 'buy' ? 'BUY' : 'SELL'}  ${Rtxt(r.r_full)}`).join('\n');
  t += `\n\nAt 1% risk, 1R = 1% of your account. Every trade is on the public record: /results`;
  return t;
}

export async function GET(req) {
  if (!process.env.CRON_SECRET || req.headers.get('authorization') !== `Bearer ${process.env.CRON_SECRET}`) return Response.json({ ok: false }, { status: 401 });
  const text = await report();
  const list = await activeMembers();
  for (const m of list) { await send(m.tg_id, text); await sleep(40); }
  await send(ADMIN, text + `\n\n<i>(sent to ${list.length} members)</i>`);

  // reminders: 2 days before the end, and once when access ends
  const all = (await rest('members?select=*&blocked=eq.false&access_until=not.is.null&limit=10000')) || [];
  const now = Date.now();
  const kb = [[btn(payOn() ? `💳 Renew · ${priceTxt()}` : '💳 Renew', 'sub')]];
  let rem = 0, ended = 0;
  for (const m of all) {
    const left = new Date(m.access_until).getTime() - now;
    if (hasAccess(m) && left < 2 * 86400000 && !m.reminded_at) {
      await send(m.tg_id, `⏳ Your access ends <b>${dateTxt(m.access_until)}</b>. Renew now and the new days are added on top.`, kb);
      await rest(`members?tg_id=eq.${m.tg_id}`, { method: 'PATCH', body: { reminded_at: new Date().toISOString() }, prefer: 'return=minimal' });
      rem++;
    } else if (!hasAccess(m) && !m.ended_notified) {
      await send(m.tg_id, `🔒 Your access has ended, so signals have stopped. Renew any time to switch them back on.`, kb);
      await rest(`members?tg_id=eq.${m.tg_id}`, { method: 'PATCH', body: { ended_notified: true }, prefer: 'return=minimal' });
      ended++;
    }
    await sleep(40);
  }
  return Response.json({ ok: true, members: list.length, reminded: rem, ended });
}
