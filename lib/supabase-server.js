// Server-only helpers for writing to Supabase with the secret key (never sent to the browser).
const URL_ = process.env.SUPABASE_URL || process.env.NEXT_PUBLIC_SUPABASE_URL;
const KEY = process.env.SUPABASE_SECRET_KEY || process.env.SUPABASE_SERVICE_ROLE_KEY;

export const dbReady = () => !!(URL_ && KEY);

function headers(extra) {
  const h = { apikey: KEY, 'Content-Type': 'application/json', ...extra };
  if (KEY && KEY.startsWith('eyJ')) h.Authorization = 'Bearer ' + KEY; // old-style service_role key
  return h;
}

export async function rest(path, { method = 'GET', body, prefer } = {}) {
  const r = await fetch(URL_ + '/rest/v1/' + path, {
    method,
    headers: headers(prefer ? { Prefer: prefer } : {}),
    body: body ? JSON.stringify(body) : undefined,
    cache: 'no-store',
  });
  const txt = await r.text();
  if (!r.ok) throw new Error(`Supabase ${method} ${path} ${r.status}: ${txt.slice(0, 300)}`);
  return txt ? JSON.parse(txt) : null;
}
