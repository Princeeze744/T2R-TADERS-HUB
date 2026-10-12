// The EA posts every signal event here.
//   POST /api/ingest   header  x-t2r-key: <T2R_INGEST_KEY>
//   body: one event object, or { "events": [ ... ] }
// Event: { id, kind, at, price?, r?, r_t2r?, r_float?, market, strategy, view, side, stop_class, dir,
//          order_type, entry, stop, tp1, target, rr, family?, note? }
// kind: signal | activated | tp1 | target | stop | breakeven | cancel | update | sync
import { dbReady, rest } from '@/lib/supabase-server';

export const dynamic = 'force-dynamic';
export const maxDuration = 30;

const FIELDS = ['market', 'family', 'strategy', 'view', 'side', 'stop_class', 'dir', 'order_type', 'entry', 'stop', 'tp1', 'target', 'rr', 'note', 'risk_per_lot', 'vol_min', 'vol_step', 'lots', 'ccy'];
const NUMS = ['entry', 'stop', 'tp1', 'target', 'risk_per_lot', 'vol_min', 'vol_step', 'lots'];
const num = (v) => (v === undefined || v === null || v === '' ? undefined : Number(v));

function rowFor(e) {
  const row = { id: String(e.id) };
  for (const f of FIELDS) if (e[f] !== undefined && e[f] !== null && e[f] !== '') row[f] = NUMS.includes(f) ? num(e[f]) : String(e[f]);
  const at = num(e.at);
  if (num(e.t_signal) !== undefined) row.t_signal = num(e.t_signal);
  if (num(e.t_fill) !== undefined) row.t_fill = num(e.t_fill);
  switch (e.kind) {
    case 'sync': // the EA restarted: restate an order already on its book
      if (['pending', 'active'].includes(e.status)) row.status = e.status;
      row.hit_tp1 = e.hit_tp1 === true;
      break;
    case 'signal':
      row.t_signal = at;
      if (row.order_type === 'market') { row.status = 'active'; row.t_fill = at; } else row.status = 'pending';
      break;
    case 'activated': row.status = 'active'; row.t_fill = at; break;
    case 'tp1': row.hit_tp1 = true; row.t_tp1 = at; break;
    case 'target': row.status = 'won'; row.t_close = at; row.exit_price = num(e.price); break;
    case 'stop': row.status = 'lost'; row.t_close = at; row.exit_price = num(e.price); break;
    case 'breakeven': row.status = 'won'; row.t_close = at; row.exit_price = num(e.price); break;
    case 'cancel': row.status = 'cancelled'; row.t_close = at; break;
    default: break; // update: only fields / floating R
  }
  if (num(e.r) !== undefined) row.r_full = num(e.r);
  if (num(e.r_t2r) !== undefined) row.r_t2r = num(e.r_t2r);
  if (num(e.r_float) !== undefined) row.r_float = num(e.r_float);
  if (['target', 'stop', 'breakeven', 'cancel'].includes(e.kind)) row.r_float = null;
  return row;
}

export async function POST(req) {
  const key = req.headers.get('x-t2r-key') || new URL(req.url).searchParams.get('key');
  if (!process.env.T2R_INGEST_KEY || key !== process.env.T2R_INGEST_KEY) return Response.json({ ok: false, error: 'bad key' }, { status: 401 });
  if (!dbReady()) return Response.json({ ok: false, error: 'database not configured' }, { status: 503 });
  let body;
  try { body = await req.json(); } catch { return Response.json({ ok: false, error: 'bad json' }, { status: 400 }); }
  const events = Array.isArray(body?.events) ? body.events : [body];
  const all = events.filter((e) => e && e.id && e.kind);
  if (!all.length) return Response.json({ ok: false, error: 'no events' }, { status: 400 });
  const accts = all.filter((e) => e.kind === 'account');
  const valid = all.filter((e) => e.kind !== 'account');
  try {
    if (accts.length) {
      // the account table may not exist yet (upgrade_v25.sql not run): never let that block the signals
      await rest('account_snapshots', { method: 'POST', prefer: 'return=minimal', body: accts.map((a) => ({
        at: num(a.at) ?? null, balance: num(a.balance) ?? null, equity: num(a.equity) ?? null, profit: num(a.profit) ?? null,
        positions: num(a.positions) ?? null, orders: num(a.orders) ?? null, ccy: a.ccy ? String(a.ccy) : null, demo: a.demo === true, risk_pct: num(a.risk_pct) ?? null,
      })) }).catch(() => {});
    }
    if (!valid.length) return Response.json({ ok: true, saved: all.length });
    // several events for one signal in a batch become one row (later events win), in the order they happened
    const merged = new Map();
    for (const e of valid) { const r = rowFor(e); merged.set(r.id, { ...(merged.get(r.id) || {}), ...r }); }
    // the database wants rows with the same columns in one call
    const groups = new Map();
    for (const r of merged.values()) { const k = Object.keys(r).sort().join(','); if (!groups.has(k)) groups.set(k, []); groups.get(k).push(r); }
    const NEW = ['risk_per_lot', 'vol_min', 'vol_step', 'lots', 'ccy'];
    for (const rows of groups.values()) {
      try {
        await rest('signals?on_conflict=id', { method: 'POST', body: rows, prefer: 'resolution=merge-duplicates,return=minimal' });
      } catch (err) {
        // database not upgraded yet: save the signal without the new lot-size columns
        if (!/column/i.test(String(err.message))) throw err;
        const slim = rows.map((r) => { const o = { ...r }; NEW.forEach((k) => delete o[k]); return o; });
        await rest('signals?on_conflict=id', { method: 'POST', body: slim, prefer: 'resolution=merge-duplicates,return=minimal' });
      }
    }
    const ev = valid.filter((e) => e.kind !== 'update' && e.kind !== 'sync')
      .map((e) => ({ signal_id: String(e.id), kind: e.kind, at: num(e.at) ?? null, price: num(e.price) ?? null, r: num(e.r) ?? null }));
    if (ev.length) await rest('signal_events', { method: 'POST', body: ev, prefer: 'return=minimal' });
    return Response.json({ ok: true, saved: all.length });
  } catch (err) {
    return Response.json({ ok: false, error: String(err.message || err) }, { status: 500 });
  }
}

export async function GET() {
  return Response.json({ ok: true, ready: dbReady() && !!process.env.T2R_INGEST_KEY, hint: 'POST events here with header x-t2r-key' });
}
