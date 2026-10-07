-- Arena League Hub: owner-isolated leagues with public, direct share links.
-- This creates a new collection/table; the legacy tournament_state row is not changed.

create table if not exists public.leagues (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  name text not null check (char_length(name) between 2 and 60),
  game text not null check (char_length(game) between 2 and 40),
  share_code text not null unique,
  state jsonb not null default '{"players":[],"matches":[]}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.leagues enable row level security;
revoke all on public.leagues from anon, authenticated;
grant select, insert, update, delete on public.leagues to authenticated;

drop policy if exists "Owners can read their leagues" on public.leagues;
create policy "Owners can read their leagues" on public.leagues
  for select to authenticated using (auth.uid() = owner_id);

drop policy if exists "Owners can create leagues" on public.leagues;
create policy "Owners can create leagues" on public.leagues
  for insert to authenticated with check (auth.uid() = owner_id);

drop policy if exists "Owners can update their leagues" on public.leagues;
create policy "Owners can update their leagues" on public.leagues
  for update to authenticated using (auth.uid() = owner_id)
  with check (auth.uid() = owner_id);

drop policy if exists "Owners can delete their leagues" on public.leagues;
create policy "Owners can delete their leagues" on public.leagues
  for delete to authenticated using (auth.uid() = owner_id);

-- A public link can fetch exactly one league by its high-entropy share code.
-- Anonymous users cannot list the leagues table or read rows directly.
create or replace function public.get_league_by_share_code(p_share_code text)
returns table (
  id uuid,
  name text,
  game text,
  share_code text,
  state jsonb,
  updated_at timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  select l.id, l.name, l.game, l.share_code, l.state, l.updated_at
  from public.leagues as l
  where l.share_code = p_share_code
  limit 1;
$$;

revoke all on function public.get_league_by_share_code(text) from public;
grant execute on function public.get_league_by_share_code(text) to anon, authenticated;
