import React,{useEffect,useState} from 'react';
import {Link,useNavigate,useSearchParams} from 'react-router-dom';
import {Mail,LockKeyhole,Eye,EyeOff,ArrowRight,UserRound,MapPin,ShieldCheck,Wrench,LoaderCircle,Phone,CheckCircle,AlertCircle} from 'lucide-react';
import {supabase,resolveHome} from './lib/supabase';
import type {Profile} from './lib/supabase';
import './public.css';
import './dashboard.css';
type Mode='login'|'signup'|'technician';
export default function AuthPage({mode}:{mode:Mode}){
 const navigate=useNavigate();const [params]=useSearchParams();
 const token=params.get('token')||'';
 const [validInvite,setValidInvite]=useState<boolean|null>(mode==='technician'?null:true);
 const [name,setName]=useState(''),[email,setEmail]=useState(''),[phone,setPhone]=useState(''),[password,setPassword]=useState(''),[show,setShow]=useState(false),[busy,setBusy]=useState(false),[message,setMessage]=useState(''),[error,setError]=useState('');
 useEffect(()=>{if(mode!=='technician')return;if(!supabase||!token){setValidInvite(false);return}let alive=true;void supabase.rpc('validate_technician_invite',{p_token:token}).then(({data,error})=>{if(alive)setValidInvite(!error&&data===true)});return()=>{alive=false}},[mode,token]);
 async function submit(event:React.FormEvent){event.preventDefault();setError('');setMessage('');if(!supabase){setError('Supabase is not configured. Add public URL and anon key in your .env file.');return}if(mode==='technician'&&!validInvite){setError('Technician invitation is invalid or expired. Ask the administrator for a new link.');return}if(password.length<8){setError('Use a password with at least 8 characters.');return}if(mode!=='login'&&name.trim().length<2){setError('Enter your full name.');return}
 setBusy(true);
 try{
  if(mode==='login'){
   const {data,error:authError}=await supabase.auth.signInWithPassword({email,password});if(authError)throw authError;
   if(!data.user)throw new Error('Could not sign in.');
   const {data:profile,error:profileError}=await supabase.from('profiles').select('id,role,full_name,email,phone,is_active').eq('id',data.user.id).single();
   if(profileError||!profile){await supabase.auth.signOut();throw new Error('Account profile was not found. Contact an administrator.')}
   if(!profile.is_active){await supabase.auth.signOut();throw new Error('Your account is blocked. Contact support.')}
   if(profile.role==='technician'){
    const {data:technician,error:techError}=await supabase.from('technician_profiles').select('approval_status').eq('id',data.user.id).single();
    if(techError||!technician)throw new Error('Technician record is missing.');
    navigate(technician.approval_status==='approved'?'/tech':'/tech/pending',{replace:true});
   }else navigate(resolveHome(profile as Profile),{replace:true});
  }else{
   const role=mode==='technician'?'technician':'customer';
   const metadata=role==='technician'?{role,invite_token:token,full_name:name.trim(),phone}:{role,full_name:name.trim(),phone};
   const {data,error:signError}=await supabase.auth.signUp({email,password,options:{data:metadata}});
   if(signError)throw signError;
   if(data.session){navigate(role==='technician'?'/tech/pending':'/app',{replace:true})}
   else setMessage('Account submitted. If email confirmation is enabled in Supabase, confirm your email first. Technician accounts also need admin approval.');
  }
 }catch(e){setError(e instanceof Error?e.message:'Something went wrong')}finally{setBusy(false)}
 }
 const title=mode==='login'?'Welcome back!':mode==='technician'?'Technician Registration':'Create Customer Account';
 return <div className="bj-auth-layout bj-public"><div className="bj-auth-left"><Link to="/" className="bj-logo"><span className="bj-logo-icon"><MapPin/></span><span><strong>Bulao<span>Ji</span></strong><small>Apni Price Lagao, Ustaad Bulao!</small></span></Link><div className="bj-auth-copy"><span className="bj-eyebrow">KARACHI • HOME & VEHICLE SERVICES</span><h1>Apni Price Lagao.<br/><span>Ustaad Bulao!</span></h1><p>One login for Customers, Technicians and Super Admin. Customers can register freely. Technicians register only through an admin-issued invitation link.</p><div className="bj-auth-points"><span><ShieldCheck/> Verified Professionals</span><span><Wrench/> Jobs & Earnings</span><span><CheckCircle/> Transparent Service</span></div></div><p className="bj-auth-foot">BulaoJi • Pakistan</p></div><div className="bj-auth-right"><Link to="/" className="bj-backhome">← Back to Home</Link><form className="bj-auth-card" onSubmit={submit}><div className="bj-auth-symbol">{mode==='technician'?<Wrench/>:mode==='login'?<LockKeyhole/>:<UserRound/>}</div><h2>{title}</h2><p>{mode==='login'?'Sign in with your registered email and password.':mode==='technician'?'A valid invitation link from your administrator is required.':'Sign up to find technicians and post jobs at your own price.'}</p>{mode==='technician'&&<div role="status" className={'bj-invite-status '+(validInvite?'good':'')}>{validInvite===null?'Checking invitation...':validInvite?'✓ Invitation verified':'Invitation unavailable or expired'}</div>}
{mode!=='login'&&<><label htmlFor="auth-name">Full Name</label><div className="bj-input-wrap"><UserRound size={18}/><input id="auth-name" required minLength={2} maxLength={120} autoComplete="name" value={name} onChange={e=>setName(e.target.value)} placeholder="Your full name"/></div><label htmlFor="auth-phone">Phone Number</label><div className="bj-input-wrap"><Phone size={18}/><input id="auth-phone" required type="tel" minLength={10} autoComplete="tel" value={phone} onChange={e=>setPhone(e.target.value)} placeholder="03XX XXXXXXX"/></div></>}
{mode==='technician'&&<p className="bj-form-note">Your registration will remain pending until Super Admin approves it. Identity documents will be collected through a secure verification process.</p>}
<label htmlFor="auth-email">Email Address</label><div className="bj-input-wrap"><Mail size={18}/><input id="auth-email" type="email" required autoComplete="email" placeholder="you@example.com" value={email} onChange={e=>setEmail(e.target.value)}/></div>
<label htmlFor="auth-password">Password</label><div className="bj-input-wrap"><LockKeyhole size={18}/><input id="auth-password" type={show?'text':'password'} required minLength={8} autoComplete={mode==='login'?'current-password':'new-password'} placeholder="Minimum 8 characters" value={password} onChange={e=>setPassword(e.target.value)}/><button type="button" onClick={()=>setShow(!show)} aria-label={show?'Hide password':'Show password'}>{show?<EyeOff size={18}/>:<Eye size={18}/>}</button></div>
{error&&<div className="bj-form-error" role="alert"><AlertCircle size={16}/> {error}</div>}
{message&&<div className="bj-form-success" role="status">{message}</div>}
<button type="submit" className="bj-button bj-button-dark bj-submit" disabled={busy||(mode==='technician'&&!validInvite)}>{busy?<LoaderCircle className="bj-spin"/>:mode==='login'?'Login':mode==='technician'?'Submit for Admin Approval':'Create Customer Account'} <ArrowRight size={19}/></button>
<div className="bj-auth-switch">{mode==='login'?<>New customer? <Link to="/signup">Create an account</Link></>:<>Already registered? <Link to="/login">Login here</Link></>}</div>
{mode==='login'&&<p className="bj-form-note" style={{textAlign:'center'}}>Technicians: use the private /reg.tec invitation link sent by your admin to register.</p>}
</form></div></div>
}
