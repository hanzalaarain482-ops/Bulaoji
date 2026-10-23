import React from 'react';
import {createRoot} from 'react-dom/client';
import {BrowserRouter,Routes,Route,Navigate} from 'react-router-dom';
import PublicPage from './PublicPages';
import AuthPage from './AuthPage';
import AdminDashboard,{TechnicianPending} from './AdminDashboard';
import {CustomerDashboard,TechnicianDashboard} from './Marketplace';
import RoleGuard from './app/RoleGuard';
import {CustomerApp,TechnicianApp} from './MarketplaceApps';
const protect=(role:'customer'|'technician'|'admin',component:React.ReactNode,allowPending=false)=><RoleGuard role={role} allowPending={allowPending}>{component}</RoleGuard>;
createRoot(document.getElementById('root')!).render(<React.StrictMode><BrowserRouter><Routes>
<Route path="/" element={<PublicPage page="home"/>}/>
<Route path="/about" element={<PublicPage page="about"/>}/>
<Route path="/contact" element={<PublicPage page="contact"/>}/>
<Route path="/login" element={<AuthPage mode="login"/>}/>
<Route path="/signup" element={<AuthPage mode="signup"/>}/>
<Route path="/reg.tec" element={<AuthPage mode="technician"/>}/>
<Route path="/app/*" element={protect('customer',<CustomerApp/>)}/>
<Route path="/tech/pending" element={protect('technician',<TechnicianPending/>,true)}/>
<Route path="/tech/*" element={protect('technician',<TechnicianApp/>)}/>
<Route path="/admin/*" element={protect('admin',<AdminDashboard/>)}/>
<Route path="*" element={<Navigate to="/" replace/>}/>
</Routes></BrowserRouter></React.StrictMode>);
