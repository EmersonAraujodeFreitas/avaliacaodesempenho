-- =====================================================================
-- Avaliação de Desempenho · Inovação Casa
-- Banco de dados no Supabase. Cole tudo no SQL Editor e clique em Run.
-- Pode rodar de novo sem problema: o script não apaga dados.
-- =====================================================================

-- 1) Perfis dos usuários (um por conta de login)
create table if not exists public.perfis (
  id uuid primary key references auth.users(id) on delete cascade,
  nome text not null default '',
  email text,
  cargo text not null default 'Assistente'
    check (cargo in ('Gerente','Coordenador','Supervisor','Analista','Assistente')),
  criado_em timestamptz not null default now()
);

-- 2) Avaliações de desempenho
create table if not exists public.avaliacoes (
  id text primary key,
  owner uuid not null default auth.uid() references public.perfis(id) on delete cascade,
  consultor text not null default '',
  data text not null default '',
  nota numeric,
  registro jsonb not null,
  atualizado_em timestamptz not null default now()
);

-- 3) Resultados da dinâmica (um por participante)
create table if not exists public.dinamica_participantes (
  id text primary key,
  owner uuid not null default auth.uid() references public.perfis(id) on delete cascade,
  nome text not null default '',
  equipe text not null default '',
  data text not null default '',
  registro jsonb not null,
  criado_em timestamptz not null default now()
);

-- 4) Partidas da dinâmica por equipes
create table if not exists public.dinamica_equipes (
  id text primary key,
  owner uuid not null default auth.uid() references public.perfis(id) on delete cascade,
  data text not null default '',
  registro jsonb not null,
  criado_em timestamptz not null default now()
);

create index if not exists avaliacoes_owner_idx on public.avaliacoes(owner);
create index if not exists dinp_owner_idx on public.dinamica_participantes(owner);
create index if not exists dine_owner_idx on public.dinamica_equipes(owner);

-- Quem é gerente ou coordenador (vê tudo)
create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.perfis
                 where id = auth.uid() and cargo in ('Gerente','Coordenador'));
$$;

-- Toda conta nova ganha um perfil. A primeira conta criada vira Gerente.
create or replace function public.novo_usuario() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.perfis (id, nome, email, cargo)
  values (new.id,
          coalesce(new.raw_user_meta_data->>'nome', ''),
          new.email,
          case when exists (select 1 from public.perfis) then 'Assistente' else 'Gerente' end)
  on conflict (id) do nothing;
  return new;
end $$;
drop trigger if exists ao_criar_usuario on auth.users;
create trigger ao_criar_usuario after insert on auth.users
  for each row execute function public.novo_usuario();

-- Só gerente ou coordenador muda cargo, e ninguém muda o próprio cargo
create or replace function public.protege_cargo() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.cargo is distinct from old.cargo then
    if not public.is_admin() then
      raise exception 'Somente gerente ou coordenador pode alterar cargos';
    end if;
    if new.id = auth.uid() then
      raise exception 'Você não pode alterar o próprio cargo';
    end if;
  end if;
  new.id := old.id;
  return new;
end $$;
drop trigger if exists protege_cargo on public.perfis;
create trigger protege_cargo before update on public.perfis
  for each row execute function public.protege_cargo();

-- Segurança por linha: cada um vê o que lançou; gerente e coordenador veem tudo
alter table public.perfis enable row level security;
alter table public.avaliacoes enable row level security;
alter table public.dinamica_participantes enable row level security;
alter table public.dinamica_equipes enable row level security;

drop policy if exists perfis_ler on public.perfis;
create policy perfis_ler on public.perfis for select to authenticated
  using (id = auth.uid() or public.is_admin());
drop policy if exists perfis_editar on public.perfis;
create policy perfis_editar on public.perfis for update to authenticated
  using (id = auth.uid() or public.is_admin())
  with check (id = auth.uid() or public.is_admin());

do $$
declare t text;
begin
  foreach t in array array['avaliacoes','dinamica_participantes','dinamica_equipes'] loop
    execute format('drop policy if exists %1$s_ler on public.%1$s', t);
    execute format('create policy %1$s_ler on public.%1$s for select to authenticated using (owner = auth.uid() or public.is_admin())', t);
    execute format('drop policy if exists %1$s_criar on public.%1$s', t);
    execute format('create policy %1$s_criar on public.%1$s for insert to authenticated with check (owner = auth.uid())', t);
    execute format('drop policy if exists %1$s_editar on public.%1$s', t);
    execute format('create policy %1$s_editar on public.%1$s for update to authenticated using (owner = auth.uid() or public.is_admin()) with check (owner = auth.uid() or public.is_admin())', t);
    execute format('drop policy if exists %1$s_excluir on public.%1$s', t);
    execute format('create policy %1$s_excluir on public.%1$s for delete to authenticated using (owner = auth.uid() or public.is_admin())', t);
  end loop;
end $$;

-- Mantém a data de atualização das avaliações
create or replace function public.toca_atualizado() returns trigger language plpgsql as $$
begin new.atualizado_em := now(); return new; end $$;
drop trigger if exists toca_atualizado on public.avaliacoes;
create trigger toca_atualizado before update on public.avaliacoes
  for each row execute function public.toca_atualizado();
