-- Compliance module restructure: real license/permit/certificate
-- tracking with actual expiry dates and optional file attachments,
-- replacing the old purely-illustrative checklist as the source of
-- truth for "what's actually expiring." Run AFTER schema_procurement.sql
-- (reuses my_org_id() and the 'org-documents' storage bucket/policies
-- already created by schema_expansion.sql — run that one first too).

create table if not exists compliance_items (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references organizations(id) on delete cascade,
  name text not null,
  category text not null default 'License',
  issuing_authority text,
  reference_number text,
  issue_date date,
  expiry_date date,
  responsible_person text,
  file_path text,   -- path inside the 'org-documents' bucket, nullable
  file_name text,
  notes text,
  created_by uuid references auth.users(id),
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

alter table compliance_items enable row level security;
drop policy if exists "ci: org read" on compliance_items;
create policy "ci: org read" on compliance_items for select using (org_id = my_org_id());
drop policy if exists "ci: org write" on compliance_items;
create policy "ci: org write" on compliance_items for insert with check (org_id = my_org_id());
drop policy if exists "ci: org update" on compliance_items;
create policy "ci: org update" on compliance_items for update using (org_id = my_org_id());
drop policy if exists "ci: org delete" on compliance_items;
create policy "ci: org delete" on compliance_items for delete using (org_id = my_org_id());
