-- ============================================================================
-- 304 : classement entre amis (donne du jour + parties gagnées).
-- Tables préfixées g304_ (projet Supabase partagé). Aucune lecture directe :
-- RLS activé sans politique, tout passe par des fonctions security definer.
-- Identité : id + secret tirés au hasard par l'appli et gardés sur l'appareil
-- (pas de compte, pas d'e-mail). Les prénoms ne sont montrés qu'aux amis
-- ajoutés par code ; le classement général du jour n'affiche que des rangs.
-- ============================================================================

create table if not exists g304_joueurs (
  id uuid primary key default gen_random_uuid(),
  secret uuid not null default gen_random_uuid(),
  code_ami text not null unique,
  pseudo text not null default '',
  avatar int not null default 0,
  gagnees int not null default 0,
  jouees int not null default 0,
  cree_le timestamptz not null default now(),
  vu_le timestamptz not null default now()
);

create table if not exists g304_amis (
  joueur uuid not null references g304_joueurs(id) on delete cascade,
  ami uuid not null references g304_joueurs(id) on delete cascade,
  primary key (joueur, ami)
);

create table if not exists g304_jour (
  joueur uuid not null references g304_joueurs(id) on delete cascade,
  jour date not null,
  delta int not null,
  points int not null,
  primary key (joueur, jour)
);
create index if not exists g304_jour_jour on g304_jour (jour);

alter table g304_joueurs enable row level security;
alter table g304_amis enable row level security;
alter table g304_jour enable row level security;
revoke all on g304_joueurs, g304_amis, g304_jour from anon, authenticated;

-- prénom nettoyé : une ligne, caractères invisibles / bidi retirés (ZWJ gardé), 24 car.
create or replace function g304_nom(p text) returns text
language sql immutable set search_path = public as $$
  select left(btrim(regexp_replace(
    regexp_replace(coalesce(p, ''), '[\u0001-\u001f\u007f\u200b\u200c\u200e\u200f\u202a-\u202e\u2066-\u2069\ufeff]', '', 'g'),
    '\s+', ' ', 'g')), 24)
$$;

create or replace function g304_moi(p_joueur uuid, p_secret uuid) returns g304_joueurs
language plpgsql security definer set search_path = public as $$
declare v g304_joueurs%rowtype;
begin
  select * into v from g304_joueurs where id = p_joueur and secret = p_secret;
  if not found then raise exception 'g304:inconnu'; end if;
  update g304_joueurs set vu_le = now() where id = p_joueur;
  return v;
end $$;

-- nouveau joueur : renvoie id, secret, code ami (6 caractères sans 0/O/1/I)
create or replace function g304_inscrire(p_pseudo text, p_avatar int)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_code text;
  v g304_joueurs%rowtype;
  a text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
begin
  loop
    v_code := '';
    for i in 1..6 loop
      v_code := v_code || substr(a, 1 + floor(random() * length(a))::int, 1);
    end loop;
    exit when not exists (select 1 from g304_joueurs where code_ami = v_code);
  end loop;
  insert into g304_joueurs (code_ami, pseudo, avatar)
  values (v_code, g304_nom(p_pseudo), greatest(0, least(11, coalesce(p_avatar, 0))))
  returning * into v;
  return jsonb_build_object('id', v.id, 'secret', v.secret, 'code', v.code_ami);
end $$;

-- prénom, avatar et compteurs de parties solo (déclarés par l'appli)
create or replace function g304_profil(p_joueur uuid, p_secret uuid, p_pseudo text,
  p_avatar int, p_gagnees int, p_jouees int)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform g304_moi(p_joueur, p_secret);
  update g304_joueurs set
    pseudo = g304_nom(p_pseudo),
    avatar = greatest(0, least(11, coalesce(p_avatar, 0))),
    jouees = greatest(0, least(1000000, coalesce(p_jouees, 0))),
    gagnees = greatest(0, least(greatest(0, least(1000000, coalesce(p_jouees, 0))), coalesce(p_gagnees, 0)))
  where id = p_joueur;
end $$;

-- score officiel de la donne du jour (1er envoi seulement ; jour = veille,
-- aujourd'hui ou lendemain en UTC, pour les fuseaux et minuit)
create or replace function g304_score_jour(p_joueur uuid, p_secret uuid, p_jour date,
  p_delta int, p_points int)
returns void language plpgsql security definer set search_path = public as $$
declare d date := (now() at time zone 'utc')::date;
begin
  perform g304_moi(p_joueur, p_secret);
  if p_jour is null or p_jour < d - 1 or p_jour > d + 1 then raise exception 'g304:jour'; end if;
  if p_delta is null or p_delta < -7 or p_delta > 5 then raise exception 'g304:score'; end if;
  if p_points is null or p_points < 0 or p_points > 304 then raise exception 'g304:score'; end if;
  insert into g304_jour (joueur, jour, delta, points) values (p_joueur, p_jour, p_delta, p_points)
  on conflict do nothing;
end $$;

create or replace function g304_ajouter_ami(p_joueur uuid, p_secret uuid, p_code text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v g304_joueurs%rowtype;
begin
  perform g304_moi(p_joueur, p_secret);
  select * into v from g304_joueurs where code_ami = upper(btrim(coalesce(p_code, '')));
  if not found then raise exception 'g304:code'; end if;
  if v.id = p_joueur then raise exception 'g304:soi'; end if;
  if (select count(*) from g304_amis where joueur = p_joueur) >= 50 then
    raise exception 'g304:trop';
  end if;
  insert into g304_amis (joueur, ami) values (p_joueur, v.id), (v.id, p_joueur)
  on conflict do nothing;
  return jsonb_build_object('id', v.id, 'pseudo', v.pseudo);
end $$;

create or replace function g304_retirer_ami(p_joueur uuid, p_secret uuid, p_ami uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform g304_moi(p_joueur, p_secret);
  delete from g304_amis where (joueur = p_joueur and ami = p_ami) or (joueur = p_ami and ami = p_joueur);
end $$;

-- classement : moi + amis (prénom, avatar, parties, score du jour), et mon rang
-- parmi tous les joueurs du jour (sans aucun nom)
create or replace function g304_classement(p_joueur uuid, p_secret uuid, p_jour date)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v g304_joueurs%rowtype;
  r jsonb;
  mine g304_jour%rowtype;
  total int;
  rang int;
begin
  v := g304_moi(p_joueur, p_secret);
  select coalesce(jsonb_agg(jsonb_build_object(
      'id', j.id, 'pseudo', j.pseudo, 'avatar', j.avatar, 'moi', j.id = p_joueur,
      'gagnees', j.gagnees, 'jouees', j.jouees,
      'delta', s.delta, 'points', s.points)), '[]'::jsonb)
    into r
    from g304_joueurs j
    left join g304_jour s on s.joueur = j.id and s.jour = p_jour
    where j.id = p_joueur or j.id in (select ami from g304_amis where joueur = p_joueur);
  select count(*) into total from g304_jour where jour = p_jour;
  select * into mine from g304_jour where joueur = p_joueur and jour = p_jour;
  if found then
    select 1 + count(*) into rang from g304_jour
      where jour = p_jour and (delta > mine.delta or (delta = mine.delta and points > mine.points));
  end if;
  return jsonb_build_object('code', v.code_ami, 'joueurs', r, 'total', total, 'rang', rang);
end $$;

revoke all on function g304_nom(text), g304_moi(uuid, uuid) from public, anon, authenticated;
grant execute on function g304_inscrire(text, int), g304_profil(uuid, uuid, text, int, int, int),
  g304_score_jour(uuid, uuid, date, int, int), g304_ajouter_ami(uuid, uuid, text),
  g304_retirer_ami(uuid, uuid, uuid), g304_classement(uuid, uuid, date) to anon, authenticated;
