-- In-app announcements visible to all users (including anonymous)
create table if not exists public.app_announcements (
    id          uuid primary key default gen_random_uuid(),
    title       text not null,
    message     text not null,
    is_active   boolean not null default true,
    created_at  timestamptz not null default now()
);

-- Allow anyone (anon + authenticated) to read announcements
alter table public.app_announcements enable row level security;

create policy "Anyone can read active announcements"
    on public.app_announcements
    for select
    using (is_active = true);
