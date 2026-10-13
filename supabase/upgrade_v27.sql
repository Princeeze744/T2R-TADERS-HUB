-- Run once in Supabase > SQL Editor: marks which signals were posted to Telegram
alter table public.signals add column if not exists tg boolean not null default false;
create index if not exists signals_tg_idx on public.signals (tg);
-- and keep the lab's demo account private
drop policy if exists "public read account" on public.account_snapshots;
