// Paystack calls this when a payment succeeds. Set it in Paystack > Settings > API Keys & Webhooks:
//   Webhook URL = https://t2r-traders-hub.vercel.app/api/paystack
import crypto from 'node:crypto';
import { rest } from '@/lib/supabase-server';
import { PAYSTACK, PRICE_NGN, PLAN_DAYS, ADMIN, extend, member, tg, esc, dateTxt } from '@/lib/bot';

export const dynamic = 'force-dynamic';
export const maxDuration = 30;

export async function POST(req) {
  if (!PAYSTACK) return Response.json({ ok: false }, { status: 503 });
  const raw = await req.text();
  const sig = crypto.createHmac('sha512', PAYSTACK).update(raw).digest('hex');
  if (sig !== req.headers.get('x-paystack-signature')) return Response.json({ ok: false }, { status: 401 });
  const ev = JSON.parse(raw);
  if (ev.event !== 'charge.success') return Response.json({ ok: true });
  const d = ev.data || {};
  const id = Number(d.metadata?.tg_id);
  const days = Number(d.metadata?.days) || PLAN_DAYS;
  if (!id || d.status !== 'success') return Response.json({ ok: true });
  // the same payment never counts twice
  const ins = await rest('payments?on_conflict=reference', { method: 'POST', body: [{ reference: d.reference, tg_id: id, amount_kobo: d.amount, currency: d.currency, days, raw: d }], prefer: 'resolution=ignore-duplicates,return=representation' });
  if (!ins?.length) return Response.json({ ok: true, duplicate: true });
  if (d.currency !== 'NGN' || Number(d.amount) < Math.round(PRICE_NGN * 100)) {
    await tg('sendMessage', { chat_id: ADMIN, parse_mode: 'HTML', text: `⚠️ Payment ${esc(d.reference)} was ${d.currency} ${d.amount / 100}, less than the plan. No access added.` });
    return Response.json({ ok: true });
  }
  const until = await extend(id, days);
  const m = await member(id);
  await rest(`members?tg_id=eq.${id}`, { method: 'PATCH', body: { note: 'paid' }, prefer: 'return=minimal' }).catch(() => {});
  await tg('sendMessage', { chat_id: id, parse_mode: 'HTML', text: `✅ <b>Payment received. Thank you!</b>\nYour access runs until <b>${dateTxt(until)}</b>. Signals keep arriving here automatically.` });
  await tg('sendMessage', { chat_id: ADMIN, parse_mode: 'HTML', text: `💰 Paid ₦${(d.amount / 100).toLocaleString('en-NG')}: ${esc(m?.first_name || '')}${m?.username ? ' @' + esc(m.username) : ''} (<code>${id}</code>) · until ${dateTxt(until)}` });
  return Response.json({ ok: true });
}
