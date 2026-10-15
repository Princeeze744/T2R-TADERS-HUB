-- Retire every old forex and metals zone signal (they showed no edge). Run once in Supabase > SQL Editor.
delete from public.signal_events where signal_id in (
  select id from public.signals where market ~ '^[A-Z]{6}$' or market ~ '^X(AU|AG|PT|PD)'
);
delete from public.deliveries where signal_id in (
  select id from public.signals where market ~ '^[A-Z]{6}$' or market ~ '^X(AU|AG|PT|PD)'
);
delete from public.signals where market ~ '^[A-Z]{6}$' or market ~ '^X(AU|AG|PT|PD)';
select count(*) as signals_left from public.signals;
