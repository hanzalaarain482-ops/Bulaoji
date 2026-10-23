-- Run after 20261023_auth_and_approvals.sql.
-- Registration applications are inserted only from the trusted auth.users signup trigger.
create table if not exists public.technician_applications (
 technician_id uuid primary key references public.technician_profiles(id) on delete cascade,
 city text not null default 'Karachi',
 area text not null,
 address_text text not null,
 service_names text[] not null default '{}',
 experience_years integer not null default 0 check (experience_years between 0 and 70),
 availability text not null default 'Full time',
 bio text not null,
 created_at timestamptz not null default now()
);
alter table public.technician_applications enable row level security;
drop policy if exists technician_applications_read on public.technician_applications;
create policy technician_applications_read on public.technician_applications for select to authenticated
using(technician_id=auth.uid() or public.is_admin());
revoke all on public.technician_applications from anon,authenticated;
grant select on public.technician_applications to authenticated;

create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path='' as $$
declare
 requested_role text := coalesce(new.raw_user_meta_data->>'role','customer');
 invite_hash text;
 invite_id uuid;
 service_names text[];
 experience integer;
begin
 if requested_role not in ('customer','technician') then
   raise exception 'Self-registration is permitted for customers and invited technicians only';
 end if;
 if requested_role='technician' then
   if length(coalesce(new.raw_user_meta_data->>'invite_token',''))<20 then raise exception 'Technician invite link required'; end if;
   invite_hash := encode(extensions.digest(new.raw_user_meta_data->>'invite_token','sha256'),'hex');
   select id into invite_id from public.technician_invitations
     where token_hash=invite_hash and expires_at>now() and used_by is null for update;
   if invite_id is null then raise exception 'Technician invitation invalid, expired or used'; end if;
   select coalesce(array_agg(value),'{}'::text[]) into service_names
     from jsonb_array_elements_text(
       case when jsonb_typeof(new.raw_user_meta_data->'categories')='array'
       then new.raw_user_meta_data->'categories' else '[]'::jsonb end
     ) as services(value);
   if cardinality(service_names)<1 or cardinality(service_names)>11 or
      exists(select 1 from unnest(service_names) as category(name)
      where category.name <> all(array['Car Services','Bike Services','Electrician','Plumber','Painter','Carpenter','AC Service','Cleaning','Locksmith','Appliance Repair','Computer Repair']))
   then raise exception 'Valid technician service categories required'; end if;
   if length(trim(coalesce(new.raw_user_meta_data->>'bio',''))) not between 20 and 1200
      or length(trim(coalesce(new.raw_user_meta_data->>'address','')))<10
      or length(trim(coalesce(new.raw_user_meta_data->>'area','')))<2
   then raise exception 'Technician profile details incomplete'; end if;
   experience := least(70,greatest(0,coalesce(nullif(new.raw_user_meta_data->>'experience_years','')::integer,0)));
 end if;
 insert into public.profiles(id,role,full_name,email,phone,city)
 values(new.id,requested_role::public.bj_role,left(coalesce(new.raw_user_meta_data->>'full_name',''),120),
 new.email,left(coalesce(new.raw_user_meta_data->>'phone',''),30),left(coalesce(new.raw_user_meta_data->>'city','Karachi'),100));
 if requested_role='technician' then
   insert into public.technician_profiles(id,bio,experience_years)
   values(new.id,trim(new.raw_user_meta_data->>'bio'),experience);
   insert into public.technician_applications(technician_id,city,area,address_text,service_names,experience_years,availability,bio)
   values(new.id,left(coalesce(new.raw_user_meta_data->>'city','Karachi'),100),
   left(new.raw_user_meta_data->>'area',100),left(new.raw_user_meta_data->>'address',400),
   service_names,experience,left(coalesce(new.raw_user_meta_data->>'availability','Full time'),80),
   left(new.raw_user_meta_data->>'bio',1200));
   update public.technician_invitations set used_by=new.id,used_at=now() where id=invite_id;
 end if;
 return new;
end $$;

-- Update any technician approved from admin dashboard: their profile stays pending until RPC action.
-- Client-supplied metadata never determines admin access.
