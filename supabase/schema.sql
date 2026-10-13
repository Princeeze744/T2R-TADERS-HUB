-- T2R Lab · Signal Desk database
-- Paste this whole file into Supabase → SQL Editor → New query → Run. Safe to run more than once.

-- one row per signal, updated as it moves: pending → active → won / lost / cancelled
create table if not exists public.signals (
  id          text primary key,              -- set by the EA, unique per signal
  market      text,
  family      text,
  strategy    text,
  view        text,
  side        text,
  stop_class  text,
  dir         text check (dir in ('buy','sell')),
  order_type  text default 'limit',          -- limit = pending order at the zone, market = enter now
  entry       double precision,
  stop        double precision,
  tp1         double precision,
  target      double precision,
  rr          text,
  status      text not null default 'pending', -- pending | active | won | lost | cancelled
  hit_tp1     boolean not null default false,
  t_signal    bigint,                          -- MT5 server time, seconds
  t_fill      bigint,
  t_tp1       bigint,
  t_close     bigint,
  exit_price  double precision,
  r_full      double precision,                -- result if held to the full target or stop
  r_t2r       double precision,                -- result with the T2R rule (half off at 1:1, stop to entry)
  r_float     double precision,                -- live floating R while active
  note        text,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create index if not exists signals_t_signal_idx on public.signals (t_signal desc);
create index if not exists signals_status_idx on public.signals (status);

-- every lifecycle step, for the timeline
create table if not exists public.signal_events (
  id         bigserial primary key,
  signal_id  text not null references public.signals(id) on delete cascade,
  kind       text not null,                    -- signal | activated | tp1 | target | stop | breakeven | cancel | update
  at         bigint,
  price      double precision,
  r          double precision,
  created_at timestamptz not null default now()
);
create index if not exists signal_events_sig_idx on public.signal_events (signal_id, at);

create or replace function public.touch_updated_at() returns trigger language plpgsql as $$
begin new.updated_at = now(); return new; end $$;
drop trigger if exists signals_touch on public.signals;
create trigger signals_touch before update on public.signals for each row execute function public.touch_updated_at();

-- everyone may READ (the desk is public); only the website server (secret key) may WRITE
alter table public.signals enable row level security;
alter table public.signal_events enable row level security;
drop policy if exists "public read signals" on public.signals;
create policy "public read signals" on public.signals for select to anon, authenticated using (true);
drop policy if exists "public read events" on public.signal_events;
create policy "public read events" on public.signal_events for select to anon, authenticated using (true);

-- live push to the website
do $$ begin
  begin alter publication supabase_realtime add table public.signals; exception when duplicate_object then null; end;
  begin alter publication supabase_realtime add table public.signal_events; exception when duplicate_object then null; end;
end $$;

-- ===== v2.5: lot sizes, demo-account trading, account snapshots (safe to run again) =====
alter table public.signals add column if not exists risk_per_lot double precision;  -- money lost on 1.0 lot at the stop
alter table public.signals add column if not exists vol_min double precision;
alter table public.signals add column if not exists vol_step double precision;
alter table public.signals add column if not exists lots double precision;          -- lots used on the lab's demo account
alter table public.signals add column if not exists ccy text;

create table if not exists public.account_snapshots (
  id         bigserial primary key,
  at         bigint,
  balance    double precision,
  equity     double precision,
  profit     double precision,
  positions  int,
  orders     int,
  ccy        text,
  demo       boolean,
  risk_pct   double precision,
  created_at timestamptz not null default now()
);
create index if not exists account_snapshots_at_idx on public.account_snapshots (at desc);
alter table public.account_snapshots enable row level security;
drop policy if exists "public read account" on public.account_snapshots;
create policy "public read account" on public.account_snapshots for select to anon, authenticated using (true);
do $$ begin
  begin alter publication supabase_realtime add table public.account_snapshots; exception when duplicate_object then null; end;
end $$;
-- Run once in Supabase > SQL Editor: marks which signals were posted to Telegram
alter table public.signals add column if not exists tg boolean not null default false;
create index if not exists signals_tg_idx on public.signals (tg);
-- and keep the lab's demo account private
drop policy if exists "public read account" on public.account_snapshots;
