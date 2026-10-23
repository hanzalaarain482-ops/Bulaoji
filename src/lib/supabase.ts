import {createClient} from '@supabase/supabase-js';
const url=import.meta.env.VITE_SUPABASE_URL as string|undefined;
const key=import.meta.env.VITE_SUPABASE_ANON_KEY as string|undefined;
export const supabase=url&&key?createClient(url,key,{auth:{autoRefreshToken:true,persistSession:true,detectSessionInUrl:true}}):null;
export type Profile={id:string;role:'customer'|'technician'|'admin';full_name:string;email:string|null;phone:string|null;is_active:boolean};
export type TechnicianStatus='pending'|'approved'|'rejected';
export function resolveHome(profile:Profile){return profile.role==='admin'?'/admin':profile.role==='technician'?'/tech':'/app'}
