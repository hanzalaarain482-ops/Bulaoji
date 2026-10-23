# BulaoJi — Website

Responsive React 18 + TypeScript + Vite marketing website with Home, About, Contact, Login, Signup.

## Local setup

```sh
npm install
cp .env.example .env
npm run dev
```

Enter your Supabase URL and public anon key in `.env`. Signup and login use Supabase Auth, but require a trusted profile-creation trigger, row-level security, and backend authorization before production use. Admin, Technician and Customer dashboard routes are placeholders (not secure or functional). Contact opens an email client rather than submitting to a database.
