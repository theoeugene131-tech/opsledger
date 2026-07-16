-- Expansion module: Asset Management, Risk Management, Internal Audits,
-- deeper Vendor Management, and Document Management (file uploads).
-- Run in Supabase SQL Editor AFTER schema_procurement.sql (this reuses
-- my_org_id(), is_org_owner(), is_org_approver() from that file).

-- ===================== ASSETS =====================
create table if not exists assets (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references organizations(id) on delete cascade,
  name text not null,
  asset_tag text,
  category text,
  assigned_to text,
  location text,
  purchase_date date,
  purchase_value numeric(14,2),
  condition text not null default 'good' check (condition in ('good','fair','poor','retired')),
  last_serviced date,
  next_service_due date,
  notes text,
  created_by uuid references auth.users(id),
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

alter table assets enable row level security;
drop policy if exists "assets: org read" on assets;
create policy "assets: org read" on assets for select using (org_id = my_org_id());
drop policy if exists "assets: org write" on assets;
create policy "assets: org write" on assets for insert with check (org_id = my_org_id());
drop policy if exists "assets: org update" on assets;
create policy "assets: org update" on assets for update using (org_id = my_org_id());

-- ===================== RISK REGISTER =====================
create table if not exists risks (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references organizations(id) on delete cascade,
  title text not null,
  description text,
  category text,
  likelihood int not null default 3 check (likelihood between 1 and 5),
  impact int not null default 3 check (impact between 1 and 5),
  mitigation text,
  owner_name text,
  status text not null default 'open' check (status in ('open','mitigating','closed')),
  review_date date,
  created_by uuid references auth.users(id),
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

alter table risks enable row level security;
drop policy if exists "risks: org read" on risks;
create policy "risks: org read" on risks for select using (org_id = my_org_id());
drop policy if exists "risks: org write" on risks;
create policy "risks: org write" on risks for insert with check (org_id = my_org_id());
drop policy if exists "risks: org update" on risks;
create policy "risks: org update" on risks for update using (org_id = my_org_id());

-- ===================== INTERNAL AUDITS =====================
create table if not exists audits (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references organizations(id) on delete cascade,
  title text not null,
  scope text,
  auditor_name text,
  status text not null default 'planned' check (status in ('planned','in_progress','completed')),
  start_date date,
  end_date date,
  summary text,
  created_by uuid references auth.users(id),
  created_at timestamptz default now()
);

create table if not exists audit_findings (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references organizations(id) on delete cascade,
  audit_id uuid not null references audits(id) on delete cascade,
  finding text not null,
  severity text not null default 'medium' check (severity in ('low','medium','high','critical')),
  corrective_action text,
  owner_name text,
  due_date date,
  status text not null default 'open' check (status in ('open','resolved')),
  created_by uuid references auth.users(id),
  created_at timestamptz default now()
);

alter table audits enable row level security;
alter table audit_findings enable row level security;
drop policy if exists "audits: org read" on audits;
create policy "audits: org read" on audits for select using (org_id = my_org_id());
drop policy if exists "audits: org write" on audits;
create policy "audits: org write" on audits for insert with check (org_id = my_org_id());
drop policy if exists "audits: org update" on audits;
create policy "audits: org update" on audits for update using (org_id = my_org_id());

drop policy if exists "findings: org read" on audit_findings;
create policy "findings: org read" on audit_findings for select using (org_id = my_org_id());
drop policy if exists "findings: org write" on audit_findings;
create policy "findings: org write" on audit_findings for insert with check (org_id = my_org_id());
drop policy if exists "findings: org update" on audit_findings;
create policy "findings: org update" on audit_findings for update using (org_id = my_org_id());

-- ===================== VENDOR MANAGEMENT (DEEPER) =====================
-- Adds columns to the `vendors` table created in schema_procurement.sql.
alter table vendors add column if not exists category text;
alter table vendors add column if not exists status text not null default 'active' check (status in ('active','inactive'));
alter table vendors add column if not exists contract_start date;
alter table vendors add column if not exists contract_end date;
alter table vendors add column if not exists performance_rating int check (performance_rating between 1 and 5);

-- ===================== DOCUMENT MANAGEMENT (FILE UPLOADS) =====================
create table if not exists org_documents (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references organizations(id) on delete cascade,
  file_name text not null,
  file_path text not null, -- path inside the 'org-documents' storage bucket
  category text,
  notes text,
  uploaded_by uuid references auth.users(id),
  uploaded_at timestamptz default now()
);

alter table org_documents enable row level security;
drop policy if exists "orgdocs: org read" on org_documents;
create policy "orgdocs: org read" on org_documents for select using (org_id = my_org_id());
drop policy if exists "orgdocs: org write" on org_documents;
create policy "orgdocs: org write" on org_documents for insert with check (org_id = my_org_id());
drop policy if exists "orgdocs: org delete" on org_documents;
create policy "orgdocs: org delete" on org_documents for delete using (org_id = my_org_id());

-- Storage bucket for the actual files. Private (public=false) — access
-- only via signed URLs generated for org members, not a public link.
insert into storage.buckets (id, name, public)
values ('org-documents', 'org-documents', false)
on conflict (id) do nothing;

-- Storage RLS: files are stored at path `{org_id}/{filename}`. These
-- policies check the first path segment against the caller's org.
drop policy if exists "org-documents: org read" on storage.objects;
create policy "org-documents: org read" on storage.objects
  for select using (bucket_id = 'org-documents' and (storage.foldername(name))[1] = my_org_id()::text);

drop policy if exists "org-documents: org upload" on storage.objects;
create policy "org-documents: org upload" on storage.objects
  for insert with check (bucket_id = 'org-documents' and (storage.foldername(name))[1] = my_org_id()::text);

drop policy if exists "org-documents: org delete" on storage.objects;
create policy "org-documents: org delete" on storage.objects
  for delete using (bucket_id = 'org-documents' and (storage.foldername(name))[1] = my_org_id()::text);
