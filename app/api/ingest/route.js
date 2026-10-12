// The EA posts every signal event here.
//   POST /api/ingest   header  x-t2r-key: <T2R_INGEST_KEY>
//   body: one event object, or { "events": [ ... ] }
// Event: { id, kind, at, price?, r?, r_t2r?, r_float?, market, strategy, view, side, stop_class, dir,
//          order_type, entry, stop, tp1, target, rr, family?, note? }
// kind: signal | activated | tp1 | target | stop | breakeven | cancel | update
import { dbReady, rest } from '@/lib/supabase-server';

export const dynamic = 'force-dynamic';

const FIELDS = ['market', 'family', 'strategy', 'view', 'side', 'stop_class', 'dir', 'order_type', 'entry', 'stop', 'tp1', 'target', 'rr', 'note'];
const num = (v) => (v === undefined || v === null || v === '' ? undefined : Number(v));

function rowFor(e) {
  const row = { id: String(e.id) };
  for (const f of FIELDS) if (e[f] !== undefined && e[f] !== null && e[f] !== '') row[f] = ['entry', 'stop', 'tp1', 'target'].includes(f) ? num(e[f]) : String(e[f]);
  const at = num(e.at);
  switch (e.kind) {
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
  const valid = events.filter((e) => e && e.id && e.kind);
  if (!valid.length) return Response.json({ ok: false, error: 'no events' }, { status: 400 });
  try {
    for (const e of valid) {
      await rest('signals?on_conflict=id', { method: 'POST', body: [rowFor(e)], prefer: 'resolution=merge-duplicates,return=minimal' });
      if (e.kind !== 'update') await rest('signal_events', { method: 'POST', body: [{ signal_id: String(e.id), kind: e.kind, at: num(e.at), price: num(e.price), r: num(e.r) }], prefer: 'return=minimal' });
    }
    return Response.json({ ok: true, saved: valid.length });
  } catch (err) {
    return Response.json({ ok: false, error: String(err.message || err) }, { status: 500 });
  }
}

export async function GET() {
  return Response.json({ ok: true, ready: dbReady() && !!process.env.T2R_INGEST_KEY, hint: 'POST events here with header x-t2r-key' });
}
