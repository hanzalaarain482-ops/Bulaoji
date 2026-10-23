-- BulaoJi Phase 2: unified auth, role-based access, technician invitations and admin approval.
-- Execute in Supabase SQL editor before using login/signup. Requires Supabase Auth.
create schema if not exists extensions;
create extension if not exists pgcrypto with schema extensions;

do $$ begin
 create type public.bj_role as enum('customer','technician','admin');
exception when duplicate_object then null; end $$;
do $$ begin
 create type public.bj_approval as enum('pending','approved','rejected');
exception when duplicate_object then null; end $$;

create table if not exists public.profiles (
 id uuid primary key references auth.users(id) on delete cascade,
 role public.bj_role not null default 'customer',
 full_name text not null default '',
 email text,
 phone text,
 city text not null default 'Karachi',
 avatar_url text,
 is_active boolean not null default true,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create index if not exists profiles_role_idx on public.profiles(role);

create table if not exists public.technician_profiles (
 id uuid primary key references public.profiles(id) on delete cascade,
 approval_status public.bj_approval not null default 'pending',
 bio text,
 cnic text,
 experience_years int not null default 0,
 is_online boolean not null default false,
 categories uuid[] not null default '{}',
 rating_avg numeric(3,2) not null default 0,
 rating_count int not null default 0,
 wallet_balance numeric(12,2) not null default 0,
 multi_job_enabled boolean not null default false,
 max_active_jobs int not null default 1,
 created_at timestamptz not null default now(),
 approved_at timestamptz,
 approved_by uuid references public.profiles(id)
);
create index if not exists technician_approval_idx on public.technician_profiles(approval_status);

-- The plaintext invitation code is not persisted; only SHA-256 hash.
create table if not exists public.technician_invitations (
 id uuid primary key default gen_random_uuid(),
 token_hash text not null unique,
 created_by uuid not null references public.profiles(id),
 expires_at timestamptz not null default now()+interval '7 days',
 used_by uuid unique references public.profiles(id),
 used_at timestamptz,
 created_at timestamptz not null default now()
);
create index if not exists technician_invites_created_idx on public.technician_invitations(created_at desc);

create table if not exists public.admin_audit_logs (
 id uuid primary key default gen_random_uuid(),
 admin_id uuid not null references public.profiles(id),
 action text not null,
 target_id uuid,
 data jsonb not null default '{}'::jsonb,
 created_at timestamptz not null default now()
);

create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.profiles where id=auth.uid() and role='admin' and is_active);
$$;

-- Auth metadata is NEVER allowed to select an admin role. Tech signup requires an admin-issued invitation.
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path='' as $$
declare
 requested_role text := coalesce(new.raw_user_meta_data->>'role','customer');
 invite_hash text;
 invite_id uuid;
begin
 if requested_role not in ('customer','technician') then
   raise exception 'Self-registration is permitted for customers and invited technicians only';
 end if;
 if requested_role='technician' then
   if length(coalesce(new.raw_user_meta_data->>'invite_token',''))<20 then raise exception 'Technician invite link required'; end if;
   invite_hash := encode(extensions.digest(new.raw_user_meta_data->>'invite_token','sha256'),'hex');
   select id into invite_id from public.technician_invitations
     where token_hash=invite_hash and expires_at>now() and used_by is null for update;
   if invite_id is null then raise exception 'Technician invitation is invalid or expired'; end if;
 end if;
 insert into public.profiles(id,role,full_name,email,phone)
 values(new.id,requested_role::public.bj_role,left(coalesce(new.raw_user_meta_data->>'full_name',''),120),new.email,left(coalesce(new.raw_user_meta_data->>'phone',''),30));
 if requested_role='technician' then
   insert into public.technician_profiles(id) values(new.id);
   update public.technician_invitations set used_by=new.id,used_at=now() where id=invite_id;
 end if;
 return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users for each row execute function public.handle_new_user();

-- Create a random invite securely; only its SHA is stored.
create or replace function public.issue_technician_invite(p_days int default 7)
returns text language plpgsql security definer set search_path='' as $$
declare token text;
begin
 if not public.is_admin() then raise exception 'Admin access required'; end if;
 if p_days not between 1 and 30 then raise exception 'Expiry must be between 1 and 30 days'; end if;
 token := encode(extensions.gen_random_bytes(24),'hex');
 insert into public.technician_invitations(token_hash,created_by,expires_at)
 values(encode(extensions.digest(token,'sha256'),'hex'),auth.uid(),now()+make_interval(days=>p_days));
 insert into public.admin_audit_logs(admin_id,action,data) values(auth.uid(),'invite.created',jsonb_build_object('expires_in_days',p_days));
 return token;
end $$;

create or replace function public.validate_technician_invite(p_token text)
returns boolean language sql stable security definer set search_path='' as $$
 select length(coalesce(p_token,''))>=20 and exists (
   select 1 from public.technician_invitations
   where token_hash=encode(extensions.digest(p_token,'sha256'),'hex')
   and expires_at>now() and used_by is null
 );
$$;

-- All staff/admin writes pass through trusted functions.
create or replace function public.admin_review_technician(p_tech uuid,p_approve boolean,p_reason text default '')
returns void language plpgsql security definer set search_path='' as $$
begin
 if not public.is_admin() then raise exception 'Admin access required'; end if;
 if not p_approve and length(btrim(coalesce(p_reason,'')))<3 then raise exception 'Please provide a rejection reason'; end if;
 update public.technician_profiles set
 approval_status=case when p_approve then 'approved'::public.bj_approval else 'rejected'::public.bj_approval end,
 approved_by=auth.uid(),approved_at=now(),is_online=false
 where id=p_tech and approval_status='pending';
 if not found then raise exception 'Technician is not pending'; end if;
 insert into public.admin_audit_logs(admin_id,action,target_id,data)
 values(auth.uid(),case when p_approve then 'technician.approved' else 'technician.rejected' end,p_tech,jsonb_build_object('reason',coalesce(p_reason,'')));
end $$;

create or replace function public.admin_set_account_active(p_user uuid,p_active boolean)
returns void language plpgsql security definer set search_path='' as $$
begin
 if not public.is_admin() then raise exception 'Admin access required'; end if;
 if p_user=auth.uid() then raise exception 'Cannot change your own account'; end if;
 update public.profiles set is_active=p_active,updated_at=now()
 where id=p_user and role <> 'admin';
 if not found then raise exception 'Account not found or administrator protected'; end if;
 insert into public.admin_audit_logs(admin_id,action,target_id,data)
 values(auth.uid(),'account.active_changed',p_user,jsonb_build_object('active',p_active));
end $$;

-- RLS on every new table. No direct technician status writes from clients.
alter table public.profiles enable row level security;
alter table public.technician_profiles enable row level security;
alter table public.technician_invitations enable row level security;
alter table public.admin_audit_logs enable row level security;
drop policy if exists profiles_read on public.profiles;
create policy profiles_read on public.profiles for select to authenticated using(id=auth.uid() or public.is_admin());
drop policy if exists profiles_update_self on public.profiles;
-- No updates directly yet: avoid self-privilege escalation.
drop policy if exists tech_read on public.technician_profiles;
create policy tech_read on public.technician_profiles for select to authenticated using(id=auth.uid() or public.is_admin());
drop policy if exists invites_admin_read on public.technician_invitations;
create policy invites_admin_read on public.technician_invitations for select to authenticated using(public.is_admin());
drop policy if exists audit_admin_read on public.admin_audit_logs;
create policy audit_admin_read on public.admin_audit_logs for select to authenticated using(public.is_admin());

revoke all on public.profiles, public.technician_profiles, public.technician_invitations, public.admin_audit_logs from anon;
grant select on public.profiles, public.technician_profiles, public.technician_invitations, public.admin_audit_logs to authenticated;
revoke all on function public.issue_technician_invite(int),public.admin_review_technician(uuid,boolean,text),public.admin_set_account_active(uuid,boolean),public.validate_technician_invite(text) from public;
grant execute on function public.issue_technician_invite(int),public.admin_review_technician(uuid,boolean,text),public.admin_set_account_active(uuid,boolean) to authenticated;
grant execute on function public.validate_technician_invite(text) to anon,authenticated;

-- BOOTSTRAP: signup once as a customer, then use SQL Editor as project owner:
-- update public.profiles set role='admin' where id='<your-auth-user-uuid>';
-- Never put a service_role secret in VITE_* variables or in your GitHub repository.
