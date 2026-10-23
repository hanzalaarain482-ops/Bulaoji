-- Run after marketplace migration. Strict technician online toggle.
create or replace function public.bj_set_technician_online(p_online boolean)
returns void language plpgsql security definer set search_path='' as $$
begin
 if not exists(select 1 from public.profiles p join public.technician_profiles t on t.id=p.id
 where p.id=auth.uid() and p.is_active and t.approval_status='approved') then
  raise exception 'Only approved active technicians may go online';
 end if;
 update public.technician_profiles set is_online=p_online where id=auth.uid();
end $$;
revoke all on function public.bj_set_technician_online(boolean) from public;
grant execute on function public.bj_set_technician_online(boolean) to authenticated;
