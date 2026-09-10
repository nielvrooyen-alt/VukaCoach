-- ============================================================
-- VukaCoach backend schema — run once in Supabase SQL Editor
-- Project: fxrpvssnlgvxykvnntil
--
-- Design:
--   - Ghost auth: each device holds a random UUID (the "owner token"),
--     no signup, no passwords. The token is the only key to the data.
--   - Tables are NOT writable by the anon role directly. All client
--     access goes through SECURITY DEFINER rpc functions that take the
--     token as an argument. This avoids trusting client-supplied
--     identity and sidesteps CORS/header issues.
--   - n8n (server side) uses the service_role key and can write
--     directly (RLS is bypassed for service_role).
-- ============================================================

-- ---------- Tables ----------

create table if not exists public.profiles (
  owner_token text primary key,
  profile     jsonb not null default '{}'::jsonb,
  language    text  not null default 'en',
  created_at  timestamptz not null default now(),
  last_open   timestamptz not null default now()
);

create table if not exists public.chats (
  id          bigserial primary key,
  owner_token text not null references public.profiles(owner_token) on delete cascade,
  role        text not null check (role in ('user', 'coach')),
  text        text not null,
  created_at  timestamptz not null default now()
);
create index if not exists chats_owner_idx on public.chats (owner_token, created_at);

create table if not exists public.memory_entries (
  id          bigserial primary key,
  owner_token text not null references public.profiles(owner_token) on delete cascade,
  entry       text not null,
  source      text not null default 'ai' check (source in ('seed', 'ai', 'weight_log', 'system')),
  active      boolean not null default true,
  created_at  timestamptz not null default now(),
  unique (owner_token, entry)
);
create index if not exists memory_owner_idx on public.memory_entries (owner_token, active);

create table if not exists public.days (
  owner_token text not null references public.profiles(owner_token) on delete cascade,
  day         date not null,
  checkin     text,
  water       int  not null default 0,
  plan_hit    boolean not null default false,
  primary key (owner_token, day)
);

create table if not exists public.weights (
  id          bigserial primary key,
  owner_token text not null references public.profiles(owner_token) on delete cascade,
  day         date not null,
  kg          numeric(5,1) not null,
  unique (owner_token, day)
);

create table if not exists public.device_tokens (
  owner_token text primary key references public.profiles(owner_token) on delete cascade,
  token       text,
  platform    text default 'web',
  updated_at  timestamptz not null default now()
);

create table if not exists public.events (
  id          bigserial primary key,
  owner_token text not null references public.profiles(owner_token) on delete cascade,
  name        text not null,
  created_at  timestamptz not null default now()
);
create index if not exists events_owner_name_idx on public.events (owner_token, name, created_at);

-- ---------- Row Level Security ----------
-- Enabled everywhere; no policies granted to anon/anon-authenticated,
-- so the tables are only reachable via the rpc functions below
-- (SECURITY DEFINER) or via the service_role key (n8n).

alter table public.profiles       enable row level security;
alter table public.chats          enable row level security;
alter table public.memory_entries enable row level security;
alter table public.days           enable row level security;
alter table public.weights        enable row level security;
alter table public.device_tokens  enable row level security;
alter table public.events         enable row level security;

-- ---------- Helper ----------

create or replace function public._vc_touch(p_token text)
returns void language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (owner_token, last_open)
  values (p_token, now())
  on conflict (owner_token) do update set last_open = now();
end $$;

-- ---------- RPC functions (called by the PWA via PostgREST) ----------

-- Boot: register/update profile + log an open event. Called on every app open.
create or replace function public.vc_boot(
  p_token text, p_profile jsonb, p_lang text default null
) returns void
language plpgsql security definer set search_path = public as $$
begin
  if p_token is null or length(p_token) < 8 then
    raise exception 'invalid token';
  end if;
  insert into public.profiles (owner_token, profile, language, last_open)
  values (p_token, coalesce(p_profile, '{}'::jsonb), coalesce(p_lang, 'en'), now())
  on conflict (owner_token) do update
    set profile   = coalesce(p_profile, public.profiles.profile),
        language  = coalesce(p_lang, public.profiles.language),
        last_open = now();
  insert into public.events (owner_token, name) values (p_token, 'open');
end $$;

-- Seed memory (written once at onboarding finish).
create or replace function public.vc_seed_memory(p_token text, p_entries text[])
returns void
language sql security definer set search_path = public as $$
  insert into public.memory_entries (owner_token, entry, source)
  select p_token, e, 'seed' from unnest(p_entries) as e
  on conflict (owner_token, entry) do nothing;
$$;

-- Insert one chat message. ts is supplied by the client so ordering
-- matches what the user sees locally.
create or replace function public.vc_chat_insert(
  p_token text, p_role text, p_text text, p_ts timestamptz default now()
) returns void
language sql security definer set search_path = public as $$
  insert into public.chats (owner_token, role, text, created_at)
  values (p_token, p_role, p_text, coalesce(p_ts, now()));
$$;

-- Upsert a day row (check-in / water / plan).
create or replace function public.vc_day_upsert(
  p_token text, p_day date, p_checkin text default null,
  p_water int default null, p_plan_hit boolean default null
) returns void
language plpgsql security definer set search_path = public as $$
begin
  insert into public.days as d (owner_token, day, checkin, water, plan_hit)
  values (p_token, p_day, p_checkin, coalesce(p_water, 0), coalesce(p_plan_hit, false))
  on conflict (owner_token, day) do update
    set checkin  = coalesce(p_checkin,  d.checkin),
        water    = coalesce(p_water,    d.water),
        plan_hit = coalesce(p_plan_hit, d.plan_hit);
end $$;

-- Upsert a weight entry (one per day, latest wins — matches app behaviour).
create or replace function public.vc_weight_upsert(p_token text, p_day date, p_kg numeric)
returns void
language sql security definer set search_path = public as $$
  insert into public.weights (owner_token, day, kg) values (p_token, p_day, p_kg)
  on conflict (owner_token, day) do update set kg = excluded.kg;
$$;

-- Generic metric event.
create or replace function public.vc_event(p_token text, p_name text)
returns void
language sql security definer set search_path = public as $$
  insert into public.events (owner_token, name) values (p_token, p_name);
$$;

-- Register a push-notification device token (phase 2, harmless to call now).
create or replace function public.vc_device_register(
  p_token text, p_device_token text, p_platform text default 'web'
) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform public._vc_touch(p_token);
  insert into public.device_tokens (owner_token, token, platform, updated_at)
  values (p_token, p_device_token, p_platform, now())
  on conflict (owner_token) do update
    set token = excluded.token, platform = excluded.platform, updated_at = now();
end $$;

-- Pull: used when a device has no local data (new phone / cleared browser).
-- Returns everything needed to restore the coach's memory.
create or replace function public.vc_pull(p_token text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  result jsonb;
begin
  if not exists (select 1 from public.profiles where owner_token = p_token) then
    return null;
  end if;
  select jsonb_build_object(
    'profile', p.profile,
    'language', p.language,
    'memory', (select coalesce(jsonb_agg(entry order by created_at), '[]'::jsonb)
               from public.memory_entries m
               where m.owner_token = p_token and m.active),
    'chats', (select coalesce(jsonb_agg(jsonb_build_object(
                 'role', c.role, 'text', c.text,
                 'ts', (extract(epoch from c.created_at) * 1000)::bigint)
                 order by c.created_at), '[]'::jsonb)
               from public.chats c where c.owner_token = p_token),
    'weights', (select coalesce(jsonb_agg(jsonb_build_object('d', w.day, 'kg', w.kg)
                 order by w.day), '[]'::jsonb)
               from public.weights w where w.owner_token = p_token),
    'days', (select coalesce(jsonb_object_agg(d.day::text,
                 jsonb_build_object('checkin', d.checkin, 'water', d.water,
                                    'plan_hit', d.plan_hit)), '{}'::jsonb)
             from public.days d where d.owner_token = p_token)
  ) into result
  from public.profiles p where p.owner_token = p_token;
  return result;
end $$;

-- ---------- Grants ----------
-- anon can only execute the functions; tables remain closed.

grant execute on function public.vc_boot(text, jsonb, text)           to anon;
grant execute on function public.vc_seed_memory(text, text[])         to anon;
grant execute on function public.vc_chat_insert(text, text, text, timestamptz) to anon;
grant execute on function public.vc_day_upsert(text, date, text, int, boolean) to anon;
grant execute on function public.vc_weight_upsert(text, date, numeric) to anon;
grant execute on function public.vc_event(text, text)                 to anon;
grant execute on function public.vc_device_register(text, text, text) to anon;
grant execute on function public.vc_pull(text)                        to anon;

-- ---------- Kill-clause metrics views (for you, via SQL editor) ----------

create or replace view public.vc_daily_active as
select date_trunc('day', last_open) as day, count(*) as dau
from public.profiles
where last_open > now() - interval '90 days'
group by 1 order by 1;

create or replace view public.vc_week4_retention as
-- Of users who first opened in a given week, % who opened again 3-4 weeks later
with cohorts as (
  select owner_token, date_trunc('week', created_at) as cohort_week
  from public.profiles
)
select c.cohort_week,
       count(*) as installed,
       count(distinct case when p.last_open >= c.cohort_week + interval '21 days'
                           then c.owner_token end) as active_week4
from cohorts c
join public.profiles p on p.owner_token = c.owner_token
group by 1 order by 1;

-- ---------- Photos bucket (phase 2, create now so it exists) ----------
insert into storage.buckets (id, name, public)
values ('vc-photos', 'vc-photos', false)
on conflict (id) do nothing;
