import React,{useEffect,useState} from 'react';
import {Navigate,useLocation} from 'react-router-dom';
import {supabase,resolveHome} from '../lib/supabase';
import type {Profile} from '../lib/supabase';
type Props={role:'customer'|'technician'|'admin';children:React.ReactNode;allowPending?:boolean};
export default function RoleGuard({role,children,allowPending=false}:Props){
 const path=useLocation().pathname;
 const [loading,setLoading]=useState(true);
 const [profile,setProfile]=useState<Profile|null>(null);
 const [approved,setApproved]=useState<boolean|null>(null);
 const [status,setStatus]=useState<'ok'|'missing'|'blocked'|'error'>('ok');
 useEffect(()=>{let mounted=true;const check=async()=>{
 if(!supabase){if(mounted){setStatus('error');setLoading(false)}return}
 const {data:{user},error}=await supabase.auth.getUser();
 if(!mounted)return;
 if(error||!user){setStatus('missing');setLoading(false);return}
 const p=await supabase.from('profiles').select('id,role,full_name,email,phone,is_active').eq('id',user.id).maybeSingle();
 if(!mounted)return;
 if(p.error||!p.data){setStatus('missing');setLoading(false);return}
 if(!p.data.is_active){await supabase.auth.signOut();if(mounted){setStatus('blocked');setLoading(false)}return}
 setProfile(p.data as Profile);
 if(p.data.role==='technician'){
  const t=await supabase.from('technician_profiles').select('approval_status').eq('id',user.id).maybeSingle();
  if(mounted)setApproved(t.data?.approval_status==='approved');
 }
 if(mounted){setStatus('ok');setLoading(false)}
 };void check();const {data:listener}=supabase?.auth.onAuthStateChange(()=>{void check()})??{data:null};return()=>{mounted=false;listener?.subscription.unsubscribe()}},[path]);
 if(loading)return <main className="dash-loading"><span>Checking your account…</span></main>;
 if(status==='error')return <main className="dash-loading">Supabase configuration required.</main>;
 if(status==='blocked')return <main className="dash-loading">Your account is blocked. <a href="/login">Login</a></main>;
 if(!profile||status==='missing')return <Navigate to="/login" replace/>;
 if(profile.role!==role)return <Navigate to={resolveHome(profile)} replace/>;
 if(role==='technician'&&!approved&&!allowPending)return <Navigate to="/tech/pending" replace/>;
 if(role==='technician'&&approved&&allowPending)return <Navigate to="/tech" replace/>;
 return <>{children}</>;
}
