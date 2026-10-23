# BulaoJi — Phase 2: One Login, Invite-Only Technicians, Super Admin

Marketing pages: `/`, `/about`, `/contact`. One **shared** email/password login at `/login`.

Registration:
- `/signup` — **Customer signup only**. Customers do not require admin approval.
- `/reg.tec?token=<ADMIN_GENERATED_TOKEN>` — **Technician registration only** via a single-use, admin-issued, 7-day link.
- Technician enters a pending state (`/tech/pending`) until Super Admin approves.
- Admin accounts **cannot self-register**. Roles are verified server-side.

Super Admin: `/admin/dashboard`, `/admin/users`, `/admin/technicians`, `/admin/customers`, `/admin/technician-links`, `/admin/audit`. Other admin navigation items are currently labeled as development placeholders, not simulated live data. Dashboard metrics show real profiles and technician rows after Supabase setup; booking and payment modules are not implemented in this phase.

## Installation
```bash
npm install
cp .env.example .env
npm run dev
```
Add your own public credentials in `.env`:
```dotenv
VITE_SUPABASE_URL=https://YOUR-PROJECT.supabase.co
VITE_SUPABASE_ANON_KEY=YOUR-PUBLISHABLE-OR-ANON-KEY
```
Do **not** commit `.env`. Never put a Supabase service-role key in frontend code or Vite environment variables.

## Supabase setup (required)
1. Create your Supabase project.
2. Run `supabase/migrations/20261023_auth_and_approvals.sql` in **SQL Editor** once. It creates profiles, pending technician records, invitation records, RLS and secure admin RPCs. Ensure `pgcrypto` is available in the `extensions` schema.
3. Supabase Dashboard > Authentication > Providers > Email: **disable Confirm email** if you want customers and technicians to sign in immediately without email verification. This is an admin-controlled Supabase setting, not a frontend toggle. Use CAPTCHA, rate limits and anti-abuse measures because unverified addresses increase signup abuse risk.
4. Register the initial owner using **Customer Signup**. Then in the SQL Editor, as project owner, promote that specific user to admin:
   ```sql
   update public.profiles
      set role = 'admin'
    where id = (select id from auth.users where email = 'YOUR-OWNER-EMAIL@example.com');
   ```
   Replace the email carefully and execute only once, after initial signup. Keep admin credentials private.
5. Log in at `/login`. The role guard routes you to the correct dashboard using the **profiles** table, not a client-side role selector.
6. Open `/admin/technician-links` and click **Create Invite**. Copy the link immediately (only a SHA-256 hash is stored server-side). Send it to your technician.
7. The technician signs up with that link and sees pending status. Open `/admin/technicians`, then Approve or Reject. Login goes to `/tech` only after approval.

## Security
- `profiles.role` cannot be set to admin by user metadata or by signup form.
- Technician invitation token is validated atomically in the database signup trigger.
- Invitation can be used only once and expires automatically.
- RLS prevents unauthorized users from reading others' profiles and administrator tables.
- Admin approval, blocking and invitation creation use authenticated security-definer RPCs with `is_admin()` checks and audit logging.
- No service-role secret in frontend.
- Disable email verification **only** in Supabase configuration; frontend cannot enforce or turn off the provider's email confirmation.

## What still needs building
Customer bookings and offers, technician live jobs, GPS, payment capture, multi-job approvals, complete reports, web push, and production E2E testing. Existing pages honestly display placeholders for these features; they are not ready for commercial launch.

## Quality status
GitHub code is uploaded, but a production build, SQL migration run against your Supabase project and real multi-user end-to-end testing have **not** been verified in this session.
