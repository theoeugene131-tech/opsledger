-- Procurement module: purchase approvals, inventory tracking, vendor
-- payment reconciliation. Run in Supabase SQL Editor. Additive only —
-- doesn't touch your existing profiles/documents tables.
--
-- Why "organizations" at all: real purchase approval requires TWO
-- people — a requester and a different approver. A single-user account
-- can't produce a real approval trail (self-approval isn't approval),
-- so this adds a lightweight multi-person model: an org owner invites
-- teammates by email; when that email signs up, they're auto-linked as
-- a member. No email-sending service required — you just share your
-- signup link with the email addresses you invite.

create table if not exists organizations (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  owner_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz default now()
);

create table if not exists org_members (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references organizations(id) on delete cascade,
  email text not null,
  user_id uuid references auth.users(id) on delete set null,
  role text not null default 'requester' check (role in ('owner','approver','requester')),
  invited_at timestamptz default now(),
  unique (org_id, email)
);

-- Helper functions (SECURITY DEFINER so they can be used inside RLS
-- policies on org_members itself without infinite-recursion issues).
create or replace function my_org_id()
returns uuid
language sql stable security definer set search_path = public
as $$
  select org_id from org_members where user_id = auth.uid() limit 1;
$$;

create or replace function is_org_approver(check_org_id uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from org_members
    where org_id = check_org_id and user_id = auth.uid() and role in ('owner','approver')
  );
$$;

create or replace function is_org_owner(check_org_id uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from org_members
    where org_id = check_org_id and user_id = auth.uid() and role = 'owner'
  );
$$;

-- Auto-add the creator as 'owner' the moment they create an org.
create or replace function create_org_owner_membership()
returns trigger
language plpgsql security definer set search_path = public
as $$
declare
  owner_email text;
begin
  select email into owner_email from profiles where id = new.owner_id;
  insert into org_members (org_id, email, user_id, role)
  values (new.id, coalesce(owner_email, new.owner_id::text), new.owner_id, 'owner')
  on conflict (org_id, email) do nothing;
  return new;
end;
$$;

drop trigger if exists on_org_created_add_owner on organizations;
create trigger on_org_created_add_owner
after insert on organizations
for each row execute function create_org_owner_membership();

-- Auto-link an invited member's user_id once they actually sign up
-- (relies on your existing `profiles` table getting a row per signup).
create or replace function link_org_member()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  update org_members set user_id = new.id
  where lower(email) = lower(new.email) and user_id is null;
  return new;
end;
$$;

drop trigger if exists on_profile_created_link_org on profiles;
create trigger on_profile_created_link_org
after insert on profiles
for each row execute function link_org_member();

alter table organizations enable row level security;
alter table org_members enable row level security;

drop policy if exists "org: member read" on organizations;
create policy "org: member read" on organizations
  for select using (id = my_org_id());
drop policy if exists "org: anyone can create" on organizations;
create policy "org: anyone can create" on organizations
  for insert with check (owner_id = auth.uid());

drop policy if exists "org_members: same org read" on org_members;
create policy "org_members: same org read" on org_members
  for select using (org_id = my_org_id());
drop policy if exists "org_members: owner invites" on org_members;
create policy "org_members: owner invites" on org_members
  for insert with check (is_org_owner(org_id));
drop policy if exists "org_members: owner updates roles" on org_members;
create policy "org_members: owner updates roles" on org_members
  for update using (is_org_owner(org_id));
drop policy if exists "org_members: owner removes" on org_members;
create policy "org_members: owner removes" on org_members
  for delete using (is_org_owner(org_id));

-- ===================== PURCHASE APPROVALS =====================
create table if not exists purchase_requests (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references organizations(id) on delete cascade,
  requested_by uuid not null references auth.users(id),
  title text not null,
  vendor_name text,
  amount numeric(14,2) not null,
  currency text not null default 'NGN',
  category text,
  notes text,
  status text not null default 'pending' check (status in ('pending','approved','rejected')),
  approver_id uuid references auth.users(id),
  decision_note text,
  decided_at timestamptz,
  created_at timestamptz default now()
);

alter table purchase_requests enable row level security;

drop policy if exists "pr: org read" on purchase_requests;
create policy "pr: org read" on purchase_requests
  for select using (org_id = my_org_id());
drop policy if exists "pr: org member creates" on purchase_requests;
create policy "pr: org member creates" on purchase_requests
  for insert with check (org_id = my_org_id() and requested_by = auth.uid());
drop policy if exists "pr: approver decides" on purchase_requests;
create policy "pr: approver decides" on purchase_requests
  for update using (org_id = my_org_id() and is_org_approver(org_id));

-- ===================== INVENTORY =====================
create table if not exists inventory_items (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references organizations(id) on delete cascade,
  name text not null,
  sku text,
  category text,
  quantity numeric(14,2) not null default 0,
  unit text default 'units',
  reorder_level numeric(14,2) default 0,
  location text,
  updated_by uuid references auth.users(id),
  updated_at timestamptz default now(),
  created_at timestamptz default now()
);

create table if not exists inventory_movements (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references organizations(id) on delete cascade,
  item_id uuid not null references inventory_items(id) on delete cascade,
  change_qty numeric(14,2) not null, -- positive = stock in, negative = stock out
  reason text,
  moved_by uuid references auth.users(id),
  created_at timestamptz default now()
);

alter table inventory_items enable row level security;
alter table inventory_movements enable row level security;

drop policy if exists "inv: org read" on inventory_items;
create policy "inv: org read" on inventory_items for select using (org_id = my_org_id());
drop policy if exists "inv: org write" on inventory_items;
create policy "inv: org write" on inventory_items for insert with check (org_id = my_org_id());
drop policy if exists "inv: org update" on inventory_items;
create policy "inv: org update" on inventory_items for update using (org_id = my_org_id());

drop policy if exists "mov: org read" on inventory_movements;
create policy "mov: org read" on inventory_movements for select using (org_id = my_org_id());
drop policy if exists "mov: org write" on inventory_movements;
create policy "mov: org write" on inventory_movements for insert with check (org_id = my_org_id());

-- Atomic stock adjustment: logs the movement AND updates the running
-- total in one call, so two people adjusting stock at once can't stomp
-- on each other's numbers.
create or replace function record_inventory_movement(p_item_id uuid, p_change numeric, p_reason text)
returns void
language plpgsql security invoker
as $$
declare
  v_org_id uuid;
begin
  select org_id into v_org_id from inventory_items where id = p_item_id;
  if v_org_id is null or v_org_id <> my_org_id() then
    raise exception 'not authorized';
  end if;
  update inventory_items
    set quantity = quantity + p_change, updated_by = auth.uid(), updated_at = now()
    where id = p_item_id;
  insert into inventory_movements (org_id, item_id, change_qty, reason, moved_by)
    values (v_org_id, p_item_id, p_change, p_reason, auth.uid());
end;
$$;

grant execute on function record_inventory_movement(uuid, numeric, text) to authenticated;

-- ===================== VENDORS & PAYMENTS =====================
create table if not exists vendors (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references organizations(id) on delete cascade,
  name text not null,
  contact_email text,
  note text,
  created_at timestamptz default now()
);

create table if not exists vendor_payments (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references organizations(id) on delete cascade,
  vendor_id uuid not null references vendors(id) on delete cascade,
  amount numeric(14,2) not null,
  currency text not null default 'NGN',
  reference text,
  payment_date date not null default current_date,
  status text not null default 'paid' check (status in ('pending','paid')),
  created_by uuid references auth.users(id),
  created_at timestamptz default now()
);

alter table vendors enable row level security;
alter table vendor_payments enable row level security;

drop policy if exists "vendors: org read" on vendors;
create policy "vendors: org read" on vendors for select using (org_id = my_org_id());
drop policy if exists "vendors: org write" on vendors;
create policy "vendors: org write" on vendors for insert with check (org_id = my_org_id());

drop policy if exists "vp: org read" on vendor_payments;
create policy "vp: org read" on vendor_payments for select using (org_id = my_org_id());
drop policy if exists "vp: org write" on vendor_payments;
create policy "vp: org write" on vendor_payments for insert with check (org_id = my_org_id() and created_by = auth.uid());
