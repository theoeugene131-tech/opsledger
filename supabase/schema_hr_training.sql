-- HR & Training module: employee roster, leave approvals, training
-- courses, and a certification/training-record expiry tracker.
-- Run AFTER schema_procurement.sql (reuses organizations, org_members,
-- my_org_id(), is_org_approver()) and AFTER schema_expansion.sql
-- (reuses the 'org-documents' storage bucket/policies for certificate
-- file attachments, same as schema_compliance.sql does).

create table if not exists employees (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references organizations(id) on delete cascade,
  full_name text not null,
  job_title text,
  department text,
  employment_type text default 'Full-time',
  start_date date,
  end_date date,
  manager text,
  email text,
  phone text,
  status text not null default 'active' check (status in ('active','on_leave','exited')),
  notes text,
  created_by uuid references auth.users(id),
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

create table if not exists leave_requests (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references organizations(id) on delete cascade,
  employee_id uuid references employees(id) on delete set null,
  leave_type text not null default 'Annual',
  start_date date not null,
  end_date date not null,
  status text not null default 'pending' check (status in ('pending','approved','rejected')),
  notes text,
  requested_by uuid not null references auth.users(id),
  decided_by uuid references auth.users(id),
  created_at timestamptz default now()
);

create table if not exists training_courses (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references organizations(id) on delete cascade,
  title text not null,
  category text default 'Onboarding',
  description text,
  duration_hours numeric,
  created_by uuid references auth.users(id),
  created_at timestamptz default now()
);

create table if not exists training_records (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references organizations(id) on delete cascade,
  employee_id uuid references employees(id) on delete set null,
  employee_name text,          -- denormalized snapshot, survives employee deletion
  item_name text not null,     -- course title or certification name
  category text not null default 'Course' check (category in ('Course','Certification')),
  provider text,
  completion_date date,
  expiry_date date,            -- null for one-off training with no renewal
  file_path text,
  file_name text,
  notes text,
  created_by uuid references auth.users(id),
  created_at timestamptz default now()
);

alter table employees enable row level security;
alter table leave_requests enable row level security;
alter table training_courses enable row level security;
alter table training_records enable row level security;

drop policy if exists "emp: org read" on employees;
create policy "emp: org read" on employees for select using (org_id = my_org_id());
drop policy if exists "emp: org write" on employees;
create policy "emp: org write" on employees for insert with check (org_id = my_org_id());
drop policy if exists "emp: org update" on employees;
create policy "emp: org update" on employees for update using (org_id = my_org_id());
drop policy if exists "emp: org delete" on employees;
create policy "emp: org delete" on employees for delete using (org_id = my_org_id());

drop policy if exists "lv: org read" on leave_requests;
create policy "lv: org read" on leave_requests for select using (org_id = my_org_id());
drop policy if exists "lv: org write" on leave_requests;
create policy "lv: org write" on leave_requests for insert with check (org_id = my_org_id() and requested_by = auth.uid());
drop policy if exists "lv: org update" on leave_requests;
create policy "lv: org update" on leave_requests for update using (org_id = my_org_id() and is_org_approver(org_id));

drop policy if exists "tc: org read" on training_courses;
create policy "tc: org read" on training_courses for select using (org_id = my_org_id());
drop policy if exists "tc: org write" on training_courses;
create policy "tc: org write" on training_courses for insert with check (org_id = my_org_id());
drop policy if exists "tc: org delete" on training_courses;
create policy "tc: org delete" on training_courses for delete using (org_id = my_org_id());

drop policy if exists "tr: org read" on training_records;
create policy "tr: org read" on training_records for select using (org_id = my_org_id());
drop policy if exists "tr: org write" on training_records;
create policy "tr: org write" on training_records for insert with check (org_id = my_org_id());
drop policy if exists "tr: org update" on training_records;
create policy "tr: org update" on training_records for update using (org_id = my_org_id());
drop policy if exists "tr: org delete" on training_records;
create policy "tr: org delete" on training_records for delete using (org_id = my_org_id());
