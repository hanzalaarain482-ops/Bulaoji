import React from 'react';
import { createRoot } from 'react-dom/client';
import { BrowserRouter, Navigate, Route, Routes, Link } from 'react-router-dom';
import PublicPage from './PublicPages';
function ComingSoon(){return <main style={{minHeight:'100vh',background:'#0d1439',color:'white',display:'grid',placeItems:'center',textAlign:'center',padding:24,fontFamily:'Inter,Arial,sans-serif'}}><section><h1>BulaoJi</h1><p>Customer, Technician and Admin dashboards are being developed.</p><Link to="/" style={{color:'#ffcf82'}}>Back to Home</Link></section></main>}
createRoot(document.getElementById('root')!).render(<React.StrictMode><BrowserRouter><Routes>
<Route path="/" element={<PublicPage page="home"/>}/>
<Route path="/about" element={<PublicPage page="about"/>}/>
<Route path="/contact" element={<PublicPage page="contact"/>}/>
<Route path="/login" element={<PublicPage page="login"/>}/>
<Route path="/signup" element={<PublicPage page="signup"/>}/>
<Route path="/app/*" element={<ComingSoon/>}/>
<Route path="/tech/*" element={<ComingSoon/>}/>
<Route path="/admin/*" element={<ComingSoon/>}/>
<Route path="*" element={<Navigate to="/" replace/>}/>
</Routes></BrowserRouter></React.StrictMode>);
