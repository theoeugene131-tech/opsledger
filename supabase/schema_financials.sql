-- Financials module: proper double-entry bookkeeping. Chart of
-- accounts + journal entries/lines, with an atomic posting function
-- that rejects any entry where debits don't equal credits — that
-- balance check happens in the database, not just in the browser, so
-- it can't be bypassed by a buggy or malicious client.
-- Run AFTER schema_procurement.sql (reuses my_org_id()).

create table if not exists accounts (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references organizations(id) on delete cascade,
  code text not null,
  name text not null,
  type text not null check (type in ('asset','liability','equity','revenue','expense')),
  subtype text not null,
  is_active boolean not null default true,
  created_at timestamptz default now(),
  unique (org_id, code)
);

create table if not exists journal_entries (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references organizations(id) on delete cascade,
  entry_date date not null default current_date,
  memo text,
  reference text,
  created_by uuid references auth.users(id),
  created_at timestamptz default now()
);

create table if not exists journal_lines (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references organizations(id) on delete cascade,
  entry_id uuid not null references journal_entries(id) on delete cascade,
  account_id uuid not null references accounts(id),
  debit numeric(14,2) not null default 0,
  credit numeric(14,2) not null default 0,
  line_memo text,
  created_at timestamptz default now(),
  check (debit >= 0 and credit >= 0),
  check (not (debit > 0 and credit > 0)) -- a single line can't be both
);

alter table accounts enable row level security;
alter table journal_entries enable row level security;
alter table journal_lines enable row level security;

drop policy if exists "accounts: org read" on accounts;
create policy "accounts: org read" on accounts for select using (org_id = my_org_id());
drop policy if exists "accounts: org write" on accounts;
create policy "accounts: org write" on accounts for insert with check (org_id = my_org_id());
drop policy if exists "accounts: org update" on accounts;
create policy "accounts: org update" on accounts for update using (org_id = my_org_id());

drop policy if exists "je: org read" on journal_entries;
create policy "je: org read" on journal_entries for select using (org_id = my_org_id());
drop policy if exists "jl: org read" on journal_lines;
create policy "jl: org read" on journal_lines for select using (org_id = my_org_id());
-- No direct insert policy on journal_entries/journal_lines for the
-- authenticated role — all posting goes through post_journal_entry()
-- below, so the balance check can never be skipped by calling
-- sb.from('journal_lines').insert(...) directly from the browser.

-- Atomic, balance-enforced posting. p_lines is a JSON array like:
-- [{"account_id":"...","debit":1000,"credit":0}, {"account_id":"...","debit":0,"credit":1000}]
create or replace function post_journal_entry(
  p_org_id uuid, p_entry_date date, p_memo text, p_reference text, p_lines jsonb
)
returns uuid
language plpgsql security invoker
as $$
declare
  v_entry_id uuid;
  v_total_debit numeric(14,2) := 0;
  v_total_credit numeric(14,2) := 0;
  v_line jsonb;
begin
  if p_org_id <> my_org_id() then
    raise exception 'not authorized for this organization';
  end if;
  if jsonb_array_length(p_lines) < 2 then
    raise exception 'a journal entry needs at least two lines';
  end if;

  select coalesce(sum((l->>'debit')::numeric),0), coalesce(sum((l->>'credit')::numeric),0)
    into v_total_debit, v_total_credit
    from jsonb_array_elements(p_lines) l;

  if v_total_debit <> v_total_credit then
    raise exception 'entry does not balance: debits % vs credits %', v_total_debit, v_total_credit;
  end if;
  if v_total_debit = 0 then
    raise exception 'entry has no amounts';
  end if;

  insert into journal_entries (org_id, entry_date, memo, reference, created_by)
    values (p_org_id, p_entry_date, p_memo, p_reference, auth.uid())
    returning id into v_entry_id;

  for v_line in select * from jsonb_array_elements(p_lines) loop
    insert into journal_lines (org_id, entry_id, account_id, debit, credit, line_memo)
      values (p_org_id, v_entry_id, (v_line->>'account_id')::uuid,
              coalesce((v_line->>'debit')::numeric,0), coalesce((v_line->>'credit')::numeric,0),
              v_line->>'line_memo');
  end loop;

  return v_entry_id;
end;
$$;

grant execute on function post_journal_entry(uuid, date, text, text, jsonb) to authenticated;

-- Seed a standard small-business chart of accounts the moment an org
-- is created, so there's something to post against immediately.
create or replace function seed_default_accounts()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  insert into accounts (org_id, code, name, type, subtype) values
    (new.id,'1000','Cash and Bank','asset','current_asset'),
    (new.id,'1100','Accounts Receivable','asset','current_asset'),
    (new.id,'1200','Inventory','asset','current_asset'),
    (new.id,'1500','Fixed Assets','asset','fixed_asset'),
    (new.id,'1590','Accumulated Depreciation','asset','contra_asset'),
    (new.id,'2000','Accounts Payable','liability','current_liability'),
    (new.id,'2100','Accrued Expenses','liability','current_liability'),
    (new.id,'2500','Loans Payable','liability','long_term_liability'),
    (new.id,'3000','Owner''s Capital','equity','equity'),
    (new.id,'3900','Retained Earnings','equity','equity'),
    (new.id,'4000','Sales Revenue','revenue','revenue'),
    (new.id,'4900','Other Income','revenue','revenue'),
    (new.id,'5000','Cost of Goods Sold','expense','cogs'),
    (new.id,'6000','Salaries and Wages','expense','operating_expense'),
    (new.id,'6100','Rent','expense','operating_expense'),
    (new.id,'6200','Utilities','expense','operating_expense'),
    (new.id,'6300','Marketing','expense','operating_expense'),
    (new.id,'6400','Professional Fees','expense','operating_expense'),
    (new.id,'6900','Other Operating Expenses','expense','operating_expense')
  on conflict (org_id, code) do nothing;
  return new;
end;
$$;

drop trigger if exists on_org_created_seed_accounts on organizations;
create trigger on_org_created_seed_accounts
after insert on organizations
for each row execute function seed_default_accounts();
