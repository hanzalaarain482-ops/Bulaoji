-- Phase 3 marketplace dashboard. Run AFTER both authentication migrations.
create table if not exists public.bj_categories(
 id uuid primary key default gen_random_uuid(), name text unique not null, icon text,
 active boolean not null default true, created_at timestamptz default now()
);
create table if not exists public.bj_services(
 id uuid primary key default gen_random_uuid(), category_id uuid not null references public.bj_categories(id),
 name text not null, base_price int not null check(base_price between 100 and 100000),
 created_at timestamptz default now(), unique(category_id,name)
);
create table if not exists public.bj_bookings(
 id uuid primary key default gen_random_uuid(),
 customer_id uuid not null references public.profiles(id),
 technician_id uuid references public.technician_profiles(id),
 category_id uuid not null references public.bj_categories(id),
 service_id uuid not null references public.bj_services(id),
 description text not null check(length(description) between 10 and 500),
 address_text text not null check(length(address_text)>3),
 offered_price int not null check(offered_price between 100 and 100000),
 final_price int check(final_price between 100 and 100000),
 urgency text not null default 'normal' check(urgency in ('normal','emergency')),
 status text not null default 'searching' check(status in ('searching','offers_received','confirmed','on_the_way','arrived','in_progress','completed','cancelled')),
 created_at timestamptz not null default now(), started_at timestamptz,completed_at timestamptz
);
create table if not exists public.bj_offers(
 id uuid primary key default gen_random_uuid(),booking_id uuid not null references public.bj_bookings(id) on delete cascade,
 technician_id uuid not null references public.technician_profiles(id),price int not null check(price between 100 and 100000),
 offer_type text not null check(offer_type in ('accept','counter')), status text not null default 'pending' check(status in ('pending','accepted','rejected','expired')),
 created_at timestamptz not null default now(),unique(booking_id,technician_id)
);
create table if not exists public.bj_reviews(
 id uuid primary key default gen_random_uuid(),booking_id uuid unique not null references public.bj_bookings(id),
 customer_id uuid not null references public.profiles(id), technician_id uuid not null references public.technician_profiles(id),
 rating int not null check(rating between 1 and 5), comment text, created_at timestamptz not null default now()
);
create index if not exists bj_bookings_customer on public.bj_bookings(customer_id,created_at desc);
create index if not exists bj_bookings_tech on public.bj_bookings(technician_id,status);
create index if not exists bj_bookings_status_category on public.bj_bookings(status,category_id);
create index if not exists bj_offers_booking on public.bj_offers(booking_id);
alter table public.bj_categories enable row level security;
alter table public.bj_services enable row level security;
alter table public.bj_bookings enable row level security;
alter table public.bj_offers enable row level security;
alter table public.bj_reviews enable row level security;
drop policy if exists bj_categories_read on public.bj_categories;
create policy bj_categories_read on public.bj_categories for select to authenticated using(active or public.is_admin());
drop policy if exists bj_services_read on public.bj_services;
create policy bj_services_read on public.bj_services for select to authenticated using(true);
drop policy if exists bj_bookings_read on public.bj_bookings;
create policy bj_bookings_read on public.bj_bookings for select to authenticated using(
 customer_id=auth.uid() or technician_id=auth.uid() or public.is_admin() or
 (status in ('searching','offers_received') and exists(
 select 1 from public.technician_profiles t where t.id=auth.uid() and t.approval_status='approved'
 and exists(select 1 from public.technician_applications a where a.technician_id=auth.uid()
 and exists(select 1 from public.bj_categories c where c.id=bj_bookings.category_id and c.name=any(a.service_names)))
 )));
drop policy if exists bj_bookings_customer_insert on public.bj_bookings;
create policy bj_bookings_customer_insert on public.bj_bookings for insert to authenticated
with check(customer_id=auth.uid() and technician_id is null and status='searching' and
exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='customer' and p.is_active));
drop policy if exists bj_offers_read on public.bj_offers;
create policy bj_offers_read on public.bj_offers for select to authenticated using(
 technician_id=auth.uid() or public.is_admin() or
 exists(select 1 from public.bj_bookings b where b.id=booking_id and b.customer_id=auth.uid()));
drop policy if exists bj_reviews_read on public.bj_reviews;
create policy bj_reviews_read on public.bj_reviews for select to authenticated using(
 customer_id=auth.uid() or technician_id=auth.uid() or public.is_admin());
drop policy if exists bj_reviews_insert on public.bj_reviews;
create policy bj_reviews_insert on public.bj_reviews for insert to authenticated with check(
 customer_id=auth.uid() and exists(select 1 from public.bj_bookings b
 where b.id=booking_id and b.customer_id=auth.uid() and b.technician_id=technician_id and b.status='completed'));
revoke insert,update,delete on public.bj_categories,public.bj_services,public.bj_bookings,public.bj_offers,public.bj_reviews from anon,authenticated;
grant select on public.bj_categories,public.bj_services,public.bj_bookings,public.bj_offers,public.bj_reviews to authenticated;
grant insert on public.bj_bookings,public.bj_reviews to authenticated;

-- Atomic tech offer: lock technician row to serialize against accepted bookings.
create or replace function public.bj_send_offer(p_booking uuid,p_price integer)
returns uuid language plpgsql security definer set search_path='' as $$
declare b public.bj_bookings%rowtype; idout uuid; currentjobs int;maxjobs int;
begin
 perform 1 from public.technician_profiles where id=auth.uid() and approval_status='approved' for update;
 if not found then raise exception 'Not approved'; end if;
 select * into b from public.bj_bookings where id=p_booking and status in ('searching','offers_received') for update;
 if not found then raise exception 'Job not available'; end if;
 if not exists(select 1 from public.technician_applications a join public.bj_categories c on c.name=any(a.service_names)
 where a.technician_id=auth.uid() and c.id=b.category_id) then raise exception 'Category not assigned'; end if;
 select count(*) into currentjobs from public.bj_bookings where technician_id=auth.uid() and status in ('confirmed','on_the_way','arrived','in_progress');
 select case when t.multi_job_enabled then least(t.max_active_jobs,3) else 1 end into maxjobs from public.technician_profiles t where id=auth.uid();
 if currentjobs>=coalesce(maxjobs,1) then raise exception 'You already have an active job'; end if;
 if p_price not between 100 and 100000 then raise exception 'Invalid offer price'; end if;
 insert into public.bj_offers(booking_id,technician_id,price,offer_type) values(p_booking,auth.uid(),p_price,case when p_price=b.offered_price then 'accept' else 'counter' end)
 returning id into idout;
 update public.bj_bookings set status='offers_received' where id=p_booking and status='searching';
 return idout;
end$$;
create or replace function public.bj_accept_offer(p_id uuid)
returns void language plpgsql security definer set search_path='' as $$
declare o public.bj_offers%rowtype; b public.bj_bookings%rowtype;currentjobs int;maxjobs int;
begin
 select * into o from public.bj_offers where id=p_id and status='pending';
 if not found then raise exception 'Offer unavailable'; end if;
 perform 1 from public.technician_profiles where id=o.technician_id for update;
 select * into b from public.bj_bookings where id=o.booking_id for update;
 if not found or b.customer_id<>auth.uid() or b.status not in ('searching','offers_received') then raise exception 'Booking unavailable';end if;
 select count(*) into currentjobs from public.bj_bookings where technician_id=o.technician_id and status in ('confirmed','on_the_way','arrived','in_progress');
 select case when multi_job_enabled then least(max_active_jobs,3) else 1 end into maxjobs from public.technician_profiles where id=o.technician_id;
 if currentjobs>=coalesce(maxjobs,1) then raise exception 'Technician already busy'; end if;
 update public.bj_bookings set technician_id=o.technician_id,final_price=o.price,status='confirmed' where id=b.id;
 update public.bj_offers set status=case when id=p_id then 'accepted' else 'rejected' end where booking_id=b.id and status='pending';
end$$;
create or replace function public.bj_transition_job(p_booking uuid,p_status text)
returns void language plpgsql security definer set search_path='' as $$
declare b public.bj_bookings%rowtype; nextstatus text;
begin
 select * into b from public.bj_bookings where id=p_booking for update;
 if not found then raise exception 'Booking not found';end if;
 nextstatus:=case b.status when 'confirmed' then 'on_the_way' when 'on_the_way' then 'arrived' when 'arrived' then 'in_progress' when 'in_progress' then 'completed' end;
 if p_status='cancelled' and b.customer_id=auth.uid() and b.status in ('searching','offers_received','confirmed') then
  update public.bj_bookings set status='cancelled' where id=b.id;return;
 end if;
 if b.technician_id is distinct from auth.uid() or p_status is distinct from nextstatus then raise exception 'Invalid job status transition';end if;
 update public.bj_bookings set status=p_status,started_at=case when p_status='in_progress' then now() else started_at end,completed_at=case when p_status='completed' then now() else completed_at end where id=b.id;
end$$;
revoke all on function public.bj_send_offer(uuid,integer),public.bj_accept_offer(uuid),public.bj_transition_job(uuid,text) from public;
grant execute on function public.bj_send_offer(uuid,integer),public.bj_accept_offer(uuid),public.bj_transition_job(uuid,text) to authenticated;
insert into public.bj_categories(name) values('Car Services'),('Bike Services'),('Electrician'),('Plumber'),('Painter'),('Carpenter'),('AC Service'),('Cleaning'),('Locksmith'),('Appliance Repair'),('Computer Repair') on conflict(name) do nothing;
insert into public.bj_services(category_id,name,base_price)
select id,case name when 'Car Services' then 'Tyre Puncture' when 'Bike Services' then 'Bike Puncture' when 'Electrician' then 'Wiring Repair' when 'Plumber' then 'Pipe Leakage Fix' when 'AC Service' then 'AC Gas Refill' else name end,
case name when 'Car Services' then 500 when 'AC Service' then 1500 else 800 end
from public.bj_categories on conflict(category_id,name) do nothing;
