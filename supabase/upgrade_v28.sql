-- T2R Spike members: private signals by direct message, free trial, paid access (run once in Supabase > SQL Editor)
create table if not exists public.members (
  tg_id          bigint primary key,
  username       text,
  first_name     text,
  created_at     timestamptz not null default now(),
  last_seen      timestamptz,
  trial_used     boolean not null default false,
  access_until   timestamptz,
  balance        numeric,
  email          text,
  blocked        boolean not null default false,
  reminded_at    timestamptz,
  ended_notified boolean not null default false,
  note           text
);
create index if not exists members_access_idx on public.members (access_until);

-- one row per signal sent to members (stops a signal ever going out twice)
create table if not exists public.broadcasts (
  signal_id text primary key,
  at        timestamptz not null default now(),
  sent      int not null default 0
);

-- every message a member received, so updates reply under the right card
create table if not exists public.deliveries (
  signal_id  text   not null,
  tg_id      bigint not null,
  kind       text   not null,
  message_id bigint,
  at         timestamptz not null default now(),
  primary key (signal_id, tg_id, kind)
);

create table if not exists public.payments (
  reference   text primary key,
  tg_id       bigint,
  amount_kobo bigint,
  currency    text,
  days        int,
  at          timestamptz not null default now(),
  raw         jsonb
);

-- private: only the website (secret key) reads or writes these. No public policies on purpose.
alter table public.members    enable row level security;
alter table public.broadcasts enable row level security;
alter table public.deliveries enable row level security;
alter table public.payments   enable row level security;
