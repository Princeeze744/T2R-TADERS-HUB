-- Make the lab's demo account private: the website can no longer read it (the EA can still save it)
drop policy if exists "public read account" on public.account_snapshots;
