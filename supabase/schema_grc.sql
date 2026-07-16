-- Governance & Reports module: tasks (remediation tracking) and the
-- evidence log (proof, not just policy). Run AFTER schema_procurement.sql
-- (reuses organizations, my_org_id()) and AFTER schema_expansion.sql
-- (reuses the 'org-documents' storage bucket for evidence file uploads).

create table if not exists tasks (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references organizations(id) on delete cascade,
  title text not null,
  description text,
  assigned_to text,
  due_date date,
  status text not null default 'open' check (status in ('open','in_progress','done')),
  source_module text default 'Manual',   -- Manual / Audit Finding / Risk Mitigation / Compliance / Other
  source_id uuid,                         -- optional link back to the record that spawned this task
  created_by uuid references auth.users(id),
  created_at timestamptz default now()
);

create table if not exists evidence_log (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references organizations(id) on delete cascade,
  title text not null,
  category text not null default 'Other',
  notes text,
  file_path text,
  file_name text,
  created_by uuid references auth.users(id),
  created_at timestamptz default now()
);

alter table tasks enable row level security;
alter table evidence_log enable row level security;

drop policy if exists "tasks: org read" on tasks;
create policy "tasks: org read" on tasks for select using (org_id = my_org_id());
drop policy if exists "tasks: org write" on tasks;
create policy "tasks: org write" on tasks for insert with check (org_id = my_org_id());
drop policy if exists "tasks: org update" on tasks;
create policy "tasks: org update" on tasks for update using (org_id = my_org_id());
drop policy if exists "tasks: org delete" on tasks;
create policy "tasks: org delete" on tasks for delete using (org_id = my_org_id());

drop policy if exists "ev: org read" on evidence_log;
create policy "ev: org read" on evidence_log for select using (org_id = my_org_id());
drop policy if exists "ev: org write" on evidence_log;
create policy "ev: org write" on evidence_log for insert with check (org_id = my_org_id());
drop policy if exists "ev: org delete" on evidence_log;
create policy "ev: org delete" on evidence_log for delete using (org_id = my_org_id());
