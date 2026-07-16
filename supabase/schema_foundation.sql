-- FOUNDATION SCHEMA — run this FIRST in a brand-new Supabase project,
-- before schema_procurement.sql / schema_expansion.sql /
-- schema_financials.sql / schema_compliance.sql.
--
-- These two tables (profiles, documents) were never in a SQL file —
-- they were built directly in the original Procwise Supabase project's
-- dashboard. Reconstructed here from how the app code actually uses
-- them, so a fresh Supabase project for OpsLedger has everything it
-- needs from a clean start.

create table if not exists profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text,
  plan text not null default 'free',
  docs_used integer not null default 0,
  created_at timestamptz default now()
);

create table if not exists documents (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  title text,
  content text,
  doc_type text default 'SOP',
  created_at timestamptz default now()
);

alter table profiles enable row level security;
alter table documents enable row level security;

drop policy if exists "profiles: owner read" on profiles;
create policy "profiles: owner read" on profiles for select using (auth.uid() = id);
drop policy if exists "profiles: owner insert" on profiles;
create policy "profiles: owner insert" on profiles for insert with check (auth.uid() = id);
drop policy if exists "profiles: owner update" on profiles;
create policy "profiles: owner update" on profiles for update using (auth.uid() = id);

drop policy if exists "documents: owner read" on documents;
create policy "documents: owner read" on documents for select using (auth.uid() = user_id);
drop policy if exists "documents: owner insert" on documents;
create policy "documents: owner insert" on documents for insert with check (auth.uid() = user_id);
drop policy if exists "documents: owner delete" on documents;
create policy "documents: owner delete" on documents for delete using (auth.uid() = user_id);

-- NOTE, carried over from the original app and still true here: the
-- `profiles.plan` and `docs_used` columns exist but the current
-- frontend code doesn't reliably enforce limits through them — actual
-- usage counting happens in localStorage, and there are hardcoded
-- license-key strings in the client-side JS that grant free Pro access
-- to anyone who reads the page source. This schema doesn't fix that;
-- it's the same open issue flagged earlier, now present in OpsLedger's
-- copy of the code too since it was carried over unchanged.
