-- Push notification device tokens
create table if not exists public.device_tokens (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references auth.users(id) on delete cascade,
    token text not null,
    platform text not null default 'ios',
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

-- One token per device per user
create unique index if not exists device_tokens_token_idx on public.device_tokens(token);

-- Fast lookup by user
create index if not exists device_tokens_user_id_idx on public.device_tokens(user_id);

-- RLS
alter table public.device_tokens enable row level security;

create policy "Users can manage their own tokens"
    on public.device_tokens
    for all
    using (auth.uid() = user_id)
    with check (auth.uid() = user_id);

-- Service role can read all tokens (for send-push edge function)
create policy "Service role can read all tokens"
    on public.device_tokens
    for select
    using (auth.role() = 'service_role');
