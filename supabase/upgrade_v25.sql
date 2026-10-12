-- Run this once in Supabase > SQL Editor (it is the v2.5 part of schema.sql)
alter table public.signals add column if not exists risk_per_lot double precision;
alter table public.signals add column if not exists vol_min double precision;
alter table public.signals add column if not exists vol_step double precision;
alter table public.signals add column if not exists lots double precision;
alter table public.signals add column if not exists ccy text;
create table if not exists public.account_snapshots (
  id bigserial primary key, at bigint, balance double precision, equity double precision, profit double precision,
  positions int, orders int, ccy text, demo boolean, risk_pct double precision, created_at timestamptz not null default now()
);
create index if not exists account_snapshots_at_idx on public.account_snapshots (at desc);
alter table public.account_snapshots enable row level security;
drop policy if exists "public read account" on public.account_snapshots;
create policy "public read account" on public.account_snapshots for select to anon, authenticated using (true);
do $$ begin
  begin alter publication supabase_realtime add table public.account_snapshots; exception when duplicate_object then null; end;
end $$;
