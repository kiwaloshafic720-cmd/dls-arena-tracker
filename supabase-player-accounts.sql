-- Add player accounts, join codes, team branding, and logo uploads.
-- This migration does not rewrite or delete leagues.state, so all
-- existing scores, matches, and derived standings remain exactly as stored.

alter table public.leagues add column if not exists join_code text;

create or replace function public.make_league_join_code()
returns text
language plpgsql
volatile
set search_path = pg_catalog, public
as $$
declare
  candidate text;
begin
  loop
    candidate := upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 12));
    exit when not exists (select 1 from public.leagues where join_code = candidate);
  end loop;
  return candidate;
end;
$$;

update public.leagues set join_code = public.make_league_join_code() where join_code is null;
alter table public.leagues alter column join_code set default public.make_league_join_code();
alter table public.leagues alter column join_code set not null;
create unique index if not exists leagues_join_code_unique on public.leagues(join_code);

create or replace function public.set_league_join_code()
returns trigger
language plpgsql
set search_path = pg_catalog, public
as $$
begin
  if new.join_code is null or length(trim(new.join_code)) = 0 then
    new.join_code := public.make_league_join_code();
  else
    new.join_code := upper(trim(new.join_code));
  end if;
  return new;
end;
$$;

drop trigger if exists leagues_set_join_code on public.leagues;
create trigger leagues_set_join_code before insert or update of join_code on public.leagues
for each row execute function public.set_league_join_code();

create table if not exists public.platform_owners (
  user_id uuid primary key
);
alter table public.platform_owners enable row level security;
revoke all on public.platform_owners from anon, authenticated;

-- The configured platform owner ID already exists in online-config.js.
insert into public.platform_owners(user_id)
values ('aefd5d45-3fa8-4d4a-b9d0-acf4ccad301d'::uuid)
on conflict do nothing;

create or replace function public.is_platform_owner()
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select exists (select 1 from public.platform_owners where user_id = auth.uid());
$$;

create or replace function public.is_league_admin(p_league_id uuid)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select public.is_platform_owner() or exists (
    select 1 from public.leagues l
    where l.id = p_league_id and l.owner_id = auth.uid()
  );
$$;

drop policy if exists "Platform owner can read all leagues" on public.leagues;
create policy "Platform owner can read all leagues" on public.leagues
  for select to authenticated using (public.is_platform_owner());
drop policy if exists "Platform owner can update all leagues" on public.leagues;
create policy "Platform owner can update all leagues" on public.leagues
  for update to authenticated using (public.is_platform_owner())
  with check (public.is_platform_owner());
drop policy if exists "Platform owner can delete all leagues" on public.leagues;
create policy "Platform owner can delete all leagues" on public.leagues
  for delete to authenticated using (public.is_platform_owner());

create table if not exists public.league_memberships (
  league_id uuid not null references public.leagues(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  player_id text not null,
  role text not null default 'player' check (role = 'player'),
  approved boolean not null default false,
  created_at timestamptz not null default now(),
  primary key (league_id, user_id),
  unique (league_id, player_id)
);
alter table public.league_memberships enable row level security;
revoke all on public.league_memberships from anon, authenticated;
grant select, insert, update, delete on public.league_memberships to authenticated;

drop policy if exists "Users can read their league membership" on public.league_memberships;
create policy "Users can read their league membership" on public.league_memberships
  for select to authenticated using (auth.uid() = user_id or public.is_league_admin(league_id));
drop policy if exists "League admins can manage memberships" on public.league_memberships;
create policy "League admins can manage memberships" on public.league_memberships
  for all to authenticated using (public.is_league_admin(league_id))
  with check (public.is_league_admin(league_id));

create or replace function public.is_approved_team_owner(p_league_id uuid, p_player_id text)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select exists (
    select 1 from public.league_memberships m
    join public.leagues l on l.id = m.league_id
    where m.league_id = p_league_id and m.player_id = p_player_id
      and m.user_id = auth.uid() and m.approved
      and exists (
        select 1 from jsonb_array_elements(coalesce(l.state->'players','[]'::jsonb)) as p(value)
        where p.value->>'id' = p_player_id
      )
  );
$$;

create table if not exists public.team_branding (
  league_id uuid not null references public.leagues(id) on delete cascade,
  player_id text not null,
  builtin_badge text,
  logo_path text,
  updated_at timestamptz not null default now(),
  primary key (league_id, player_id),
  check (builtin_badge is null or builtin_badge in ('shield','crown','flame','lightning','star','eagle','lion','ball'))
);
alter table public.team_branding enable row level security;
revoke all on public.team_branding from anon, authenticated;
grant select, insert, update on public.team_branding to anon, authenticated;

drop policy if exists "Anyone can view team branding" on public.team_branding;
create policy "Anyone can view team branding" on public.team_branding
  for select to anon, authenticated using (true);
drop policy if exists "Authorized team owners can set branding" on public.team_branding;
create policy "Authorized team owners can set branding" on public.team_branding
  for insert to authenticated with check (
    public.is_league_admin(league_id) or public.is_approved_team_owner(league_id, player_id)
  );
drop policy if exists "Authorized team owners can update branding" on public.team_branding;
create policy "Authorized team owners can update branding" on public.team_branding
  for update to authenticated using (
    public.is_league_admin(league_id) or public.is_approved_team_owner(league_id, player_id)
  ) with check (
    public.is_league_admin(league_id) or public.is_approved_team_owner(league_id, player_id)
  );

insert into storage.buckets(id, name, public, file_size_limit, allowed_mime_types)
values ('dls-team-logos', 'dls-team-logos', true, 2097152, array['image/png','image/jpeg','image/webp'])
on conflict (id) do nothing;

drop policy if exists "Public can view team logos" on storage.objects;
create policy "Public can view team logos" on storage.objects
  for select to anon, authenticated using (bucket_id = 'dls-team-logos');
drop policy if exists "Team owners and admins can upload logos" on storage.objects;
create policy "Team owners and admins can upload logos" on storage.objects
  for insert to authenticated with check (
    bucket_id = 'dls-team-logos' and array_length(string_to_array(name, '/'), 1) = 3
    and (
      public.is_league_admin(split_part(name, '/', 1)::uuid)
      or public.is_approved_team_owner(split_part(name, '/', 1)::uuid, split_part(name, '/', 2))
    )
  );
drop policy if exists "Team owners and admins can update logos" on storage.objects;
create policy "Team owners and admins can update logos" on storage.objects
  for update to authenticated using (
    bucket_id = 'dls-team-logos' and (
      public.is_league_admin(split_part(name, '/', 1)::uuid)
      or public.is_approved_team_owner(split_part(name, '/', 1)::uuid, split_part(name, '/', 2))
    )
  ) with check (
    bucket_id = 'dls-team-logos' and (
      public.is_league_admin(split_part(name, '/', 1)::uuid)
      or public.is_approved_team_owner(split_part(name, '/', 1)::uuid, split_part(name, '/', 2))
    )
  );
drop policy if exists "Team owners and admins can delete logos" on storage.objects;
create policy "Team owners and admins can delete logos" on storage.objects
  for delete to authenticated using (
    bucket_id = 'dls-team-logos' and (
      public.is_league_admin(split_part(name, '/', 1)::uuid)
      or exists (
        select 1 from public.league_memberships m
        where m.league_id = split_part(name, '/', 1)::uuid
          and m.player_id = split_part(name, '/', 2) and m.user_id = auth.uid() and m.approved
      )
    )
  );

create or replace function public.get_league_join_details(p_join_code text)
returns table (id uuid, name text, game text, share_code text, players jsonb)
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select l.id, l.name, l.game, l.share_code,
    coalesce((
      select jsonb_agg(p.value) from jsonb_array_elements(coalesce(l.state->'players','[]'::jsonb)) as p(value)
      where not exists (
        select 1 from public.league_memberships m
        where m.league_id = l.id and m.player_id = p.value->>'id'
      )
    ), '[]'::jsonb)
  from public.leagues l
  where l.join_code = upper(trim(p_join_code))
    and auth.uid() is not null
  limit 1;
$$;

create or replace function public.join_league(p_join_code text, p_player_id text)
returns table (share_code text, league_name text)
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  target public.leagues%rowtype;
begin
  if auth.uid() is null then raise exception 'Sign in to join a league'; end if;
  select * into target from public.leagues
    where join_code = upper(trim(p_join_code)) limit 1;
  if target.id is null then raise exception 'That league code is not valid'; end if;
  if not exists (
    select 1 from jsonb_array_elements(coalesce(target.state->'players','[]'::jsonb)) as p(value)
    where p.value->>'id' = p_player_id
  ) then raise exception 'Choose a player from this league roster'; end if;
  insert into public.league_memberships(league_id,user_id,player_id)
    values(target.id,auth.uid(),p_player_id);
  return query select target.share_code,target.name;
end;
$$;

create or replace function public.get_my_player_leagues()
returns table (id uuid, name text, game text, share_code text, player_id text, player_name text, approved boolean)
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select l.id,l.name,l.game,l.share_code,m.player_id,p.value->>'name',m.approved
  from public.league_memberships m
  join public.leagues l on l.id=m.league_id
  cross join lateral jsonb_array_elements(coalesce(l.state->'players','[]'::jsonb)) as p(value)
  where m.user_id=auth.uid() and p.value->>'id'=m.player_id
  order by l.created_at desc;
$$;

revoke all on function public.get_league_join_details(text) from public;
revoke all on function public.join_league(text,text) from public;
revoke all on function public.get_my_player_leagues() from public;
grant execute on function public.get_league_join_details(text) to authenticated;
grant execute on function public.join_league(text,text) to authenticated;
grant execute on function public.get_my_player_leagues() to authenticated;


