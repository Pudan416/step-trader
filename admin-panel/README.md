# DOOM CTRL — Admin Panel

Internal admin UI for inspecting **global stats** and drilling down **per user**.

## What it shows
- Dashboard:
  - total users
  - total shields
  - energy ledger totals (sum of `energy_ledger.delta`)
- Users:
  - list of users from `public.users`
  - user detail: profile, shields, and energy ledger breakdown

## Config
Set environment variables (locally via `.env.local`, in CI via secrets):

- `SUPABASE_URL`
- `SUPABASE_SERVICE_ROLE_KEY` *(server-only; never expose to the browser)*
- `ADMIN_PASSWORD` *(simple password gate for this panel)*

## Run

```bash
cd admin-panel
npm run dev
```

Open `http://localhost:3000`.
