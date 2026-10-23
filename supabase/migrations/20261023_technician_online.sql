-- Technician availability toggle; verified technicians only
create or replace function public.bj_set_technician_online(p_online boolean)
returns void language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null then raise exception 'Authentication required'; end if;
 update public.technician_profiles set is_online=p_online
 where id=auth.uid() and approval_status='approved'
 and exists(select 1 from public.profiles p where p.id=auth.uid() and p.is_active);
 if not found then raise exception 'Technician approval required'; end if;
end $$;
revoke all on function public.bj_set_technician_online(boolean) from public;
grant execute on function public.bj_set_technician_online(boolean) to authenticated;
