'use client';
import { createClient } from '@supabase/supabase-js';

const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
const key = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY || process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY;

let client = null;
export function sb() {
  if (!url || !key) return null;
  if (!client) client = createClient(url, key, { auth: { persistSession: false }, realtime: { params: { eventsPerSecond: 5 } } });
  return client;
}

// all rows, paged (Supabase returns at most 1000 per call)
export async function fetchAll(table, build) {
  const c = sb();
  if (!c) return [];
  const out = [];
  for (let from = 0; from < 50000; from += 1000) {
    let q = c.from(table).select('*');
    if (build) q = build(q);
    const { data, error } = await q.range(from, from + 999);
    if (error) throw error;
    out.push(...data);
    if (data.length < 1000) break;
  }
  return out;
}

// a desk row -> the trade shape the journal and the trade drawer use
export function rowToTrade(r, famOf, dayKey, ratioOf) {
  const res = r.status === 'won' ? 'won' : r.status === 'lost' ? 'lost' : 'open';
  const tin = r.t_fill || r.t_signal;
  return {
    id: 's' + r.id, src: 'l', tsig: r.t_signal, tin, tout: r.t_close || 0, a: r.market, s: r.strategy, v: r.view, sd: r.side, c: r.stop_class,
    dir: r.dir, e: r.entry, sl: r.stop, tp: r.target, rr: r.rr, ratio: ratioOf(r.rr), res, R: res === 'open' ? null : r.r_full, h1: r.hit_tp1 ? 1 : 0,
    ex: r.exit_price, rT2R: r.r_t2r, fam: famOf(r.market), day: dayKey(tin), live: true, status: r.status, orderType: r.order_type,
  };
}
