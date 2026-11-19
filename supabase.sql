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

-- Login por usuário (versão 2): guarda o nome de usuário de cada conta
alter table public.perfis add column if not exists usuario text;
create unique index if not exists perfis_usuario_idx on public.perfis (lower(usuario));

-- Aprovação de cadastro (versão 3): conta nova fica pendente até o gerente ou coordenador aprovar.
-- Contas que já existiam continuam ativas.
alter table public.perfis add column if not exists status text;
update public.perfis set status = 'ativo' where status is null;
alter table public.perfis alter column status set default 'pendente';
alter table public.perfis alter column status set not null;
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'perfis_status_ck') then
    alter table public.perfis add constraint perfis_status_ck check (status in ('pendente','ativo','bloqueado'));
  end if;
end $$;

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
                 where id = auth.uid() and status = 'ativo' and cargo in ('Gerente','Coordenador'));
$$;

-- Usuário aprovado (pode ver e lançar os próprios dados)
create or replace function public.ativo() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.perfis where id = auth.uid() and status = 'ativo');
$$;

-- Toda conta nova ganha um perfil. A primeira conta criada vira Gerente.
create or replace function public.novo_usuario() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.perfis (id, nome, usuario, email, cargo, status)
  values (new.id,
          coalesce(new.raw_user_meta_data->>'nome', ''),
          coalesce(new.raw_user_meta_data->>'usuario', split_part(new.email, '@', 1)),
          new.email,
          case when exists (select 1 from public.perfis) then 'Assistente' else 'Gerente' end,
          case when exists (select 1 from public.perfis) then 'pendente' else 'ativo' end)
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
  if new.cargo is distinct from old.cargo or new.status is distinct from old.status then
    if not public.is_admin() then
      raise exception 'Somente gerente ou coordenador pode alterar cargo ou acesso';
    end if;
    if new.id = auth.uid() then
      raise exception 'Você não pode alterar o próprio cargo ou acesso';
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
    execute format('create policy %1$s_ler on public.%1$s for select to authenticated using ((public.ativo() and owner = auth.uid()) or public.is_admin())', t);
    execute format('drop policy if exists %1$s_criar on public.%1$s', t);
    execute format('create policy %1$s_criar on public.%1$s for insert to authenticated with check (public.ativo() and owner = auth.uid())', t);
    execute format('drop policy if exists %1$s_editar on public.%1$s', t);
    execute format('create policy %1$s_editar on public.%1$s for update to authenticated using ((public.ativo() and owner = auth.uid()) or public.is_admin()) with check ((public.ativo() and owner = auth.uid()) or public.is_admin())', t);
    execute format('drop policy if exists %1$s_excluir on public.%1$s', t);
    execute format('create policy %1$s_excluir on public.%1$s for delete to authenticated using ((public.ativo() and owner = auth.uid()) or public.is_admin())', t);
  end loop;
end $$;

-- Mantém a data de atualização das avaliações
create or replace function public.toca_atualizado() returns trigger language plpgsql as $$
begin new.atualizado_em := now(); return new; end $$;
drop trigger if exists toca_atualizado on public.avaliacoes;
create trigger toca_atualizado before update on public.avaliacoes
  for each row execute function public.toca_atualizado();

-- Gerente ou coordenador cria uma nova senha para quem esqueceu
create extension if not exists pgcrypto with schema extensions;
create or replace function public.admin_redefinir_senha(alvo uuid, nova text) returns void
language plpgsql security definer set search_path = public, extensions, auth as $$
begin
  if not public.is_admin() then
    raise exception 'Somente gerente ou coordenador pode redefinir senhas';
  end if;
  if alvo = auth.uid() then
    raise exception 'Para trocar a sua própria senha, use o botão Senha no menu';
  end if;
  if length(coalesce(nova, '')) < 6 then
    raise exception 'A senha precisa ter pelo menos 6 caracteres';
  end if;
  update auth.users
     set encrypted_password = extensions.crypt(nova, extensions.gen_salt('bf')),
         updated_at = now()
   where id = alvo;
end $$;
revoke all on function public.admin_redefinir_senha(uuid, text) from public;
grant execute on function public.admin_redefinir_senha(uuid, text) to authenticated;

-- Listas do formulário (cargo/função e área/setor), editáveis em Administração
create table if not exists public.configuracoes (
  chave text primary key,
  valor jsonb not null,
  atualizado_em timestamptz not null default now()
);
alter table public.configuracoes enable row level security;
drop policy if exists config_ler on public.configuracoes;
create policy config_ler on public.configuracoes for select to authenticated using (public.ativo());
drop policy if exists config_gravar on public.configuracoes;
create policy config_gravar on public.configuracoes for all to authenticated
  using (public.is_admin()) with check (public.is_admin());
insert into public.configuracoes (chave, valor) values ('listas',
  '{"cargos":["Gerente","Coordenador","Analista","Supervisor","Assistente","Consultor"],"areas":["CRM","Planejamento","Qualidade","Inovação","Treinamento"]}')
on conflict (chave) do nothing;

-- =====================================================================
-- Dinâmica ao vivo (versão 5): participantes entram pelo QR code, sem login,
-- escolhem nome e avatar e respondem no celular. O organizador comanda pelo telão.
-- =====================================================================
create table if not exists public.salas (
  id uuid primary key default gen_random_uuid(),
  codigo text not null unique,
  owner uuid not null default auth.uid() references public.perfis(id) on delete cascade,
  titulo text not null default 'Desafio do Conhecimento',
  estado jsonb not null default '{"fase":"lobby"}',
  grupos jsonb not null default '[]',
  perguntas jsonb,
  gabarito jsonb,
  aberta boolean not null default true,
  criado_em timestamptz not null default now()
);
create table if not exists public.sala_jogadores (
  id uuid primary key default gen_random_uuid(),
  sala uuid not null references public.salas(id) on delete cascade,
  nome text not null,
  avatar text not null default '',
  grupo text,
  token uuid not null default gen_random_uuid(),
  pontos int not null default 0,
  acertos int not null default 0,
  sequencia int not null default 0,
  melhor_seq int not null default 0,
  visto_em timestamptz not null default now(),
  criado_em timestamptz not null default now()
);
create index if not exists sala_jog_idx on public.sala_jogadores(sala);
create table if not exists public.sala_respostas (
  sala uuid not null references public.salas(id) on delete cascade,
  jogador uuid not null references public.sala_jogadores(id) on delete cascade,
  pergunta int not null,
  resposta int,
  correta boolean not null,
  pontos int not null,
  tempo numeric not null,
  criado_em timestamptz not null default now(),
  primary key (jogador, pergunta)
);
create index if not exists sala_resp_idx on public.sala_respostas(sala, pergunta);

alter table public.salas enable row level security;
alter table public.sala_jogadores enable row level security;
alter table public.sala_respostas enable row level security;

-- Quem pode comandar a sala: o organizador ativo que criou, ou gerente/coordenador
create or replace function public.dono_sala(p_sala uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.salas s where s.id = p_sala
                 and ((s.owner = auth.uid() and public.ativo()) or public.is_admin()));
$$;

drop policy if exists salas_ler on public.salas;
create policy salas_ler on public.salas for select to authenticated using ((owner = auth.uid() and public.ativo()) or public.is_admin());
drop policy if exists salas_criar on public.salas;
create policy salas_criar on public.salas for insert to authenticated with check (owner = auth.uid() and public.ativo());
drop policy if exists salas_editar on public.salas;
create policy salas_editar on public.salas for update to authenticated using ((owner = auth.uid() and public.ativo()) or public.is_admin()) with check ((owner = auth.uid() and public.ativo()) or public.is_admin());
drop policy if exists salas_excluir on public.salas;
create policy salas_excluir on public.salas for delete to authenticated using ((owner = auth.uid() and public.ativo()) or public.is_admin());

drop policy if exists jog_ler on public.sala_jogadores;
create policy jog_ler on public.sala_jogadores for select to authenticated using (public.dono_sala(sala));
drop policy if exists jog_editar on public.sala_jogadores;
create policy jog_editar on public.sala_jogadores for update to authenticated using (public.dono_sala(sala)) with check (public.dono_sala(sala));
drop policy if exists jog_excluir on public.sala_jogadores;
create policy jog_excluir on public.sala_jogadores for delete to authenticated using (public.dono_sala(sala));
drop policy if exists resp_ler on public.sala_respostas;
create policy resp_ler on public.sala_respostas for select to authenticated using (public.dono_sala(sala));

-- Colunas da versão com perguntas diferentes para cada pessoa
alter table public.sala_jogadores add column if not exists ordem int not null default 0;
alter table public.sala_respostas add column if not exists questao int;

-- Qual pergunta do banco da sala cai para cada pessoa em cada rodada (sem repetir para a mesma pessoa)
create or replace function public.din_questao(s public.salas, p_ordem int, p_idx int) returns int
language sql immutable as $$
  select mod(p_ordem * greatest(coalesce((s.perguntas->>'rodadas')::int, 1), 1) + p_idx,
             greatest(jsonb_array_length(s.perguntas->'lista'), 1));
$$;

-- Hora do servidor (para todos os celulares contarem o mesmo tempo)
create or replace function public.din_agora() returns timestamptz
language sql stable as $$ select now() $$;

-- Participante entra na sala com nome e avatar
create or replace function public.din_entrar(p_codigo text, p_nome text, p_avatar text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare s public.salas; j public.sala_jogadores;
begin
  select * into s from public.salas where codigo = upper(trim(p_codigo));
  if not found then raise exception 'Sala não encontrada. Confira o código.'; end if;
  if not s.aberta then raise exception 'Esta dinâmica já foi encerrada.'; end if;
  if coalesce(s.estado->>'fase','lobby') <> 'lobby' and coalesce(s.estado->>'entrada','') <> 'livre' then raise exception 'A dinâmica já começou. Peça ao organizador para entrar na próxima rodada.'; end if;
  if length(trim(coalesce(p_nome,''))) < 2 then raise exception 'Digite o seu nome.'; end if;
  if (select count(*) from public.sala_jogadores where sala = s.id) >= 300 then raise exception 'A sala está cheia.'; end if;
  insert into public.sala_jogadores (sala, nome, avatar, ordem)
  values (s.id, left(trim(p_nome), 40), left(coalesce(p_avatar,''), 16),
          (select coalesce(max(ordem), -1) + 1 from public.sala_jogadores where sala = s.id)) returning * into j;
  return jsonb_build_object('id', j.id, 'token', j.token);
end $$;

-- Celular do participante busca a situação da sala (e avisa que está online)
create or replace function public.din_estado(p_codigo text, p_id uuid, p_token uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare s public.salas; j public.sala_jogadores; r public.sala_respostas; fase text; revela boolean; minha jsonb; pq jsonb;
begin
  select * into s from public.salas where codigo = upper(trim(p_codigo));
  if not found then raise exception 'Sala não encontrada.'; end if;
  select * into j from public.sala_jogadores where id = p_id and token = p_token and sala = s.id;
  if not found then return jsonb_build_object('saiu', true, 'agora', now()); end if;
  if j.visto_em < now() - interval '4 seconds' then
    update public.sala_jogadores set visto_em = now() where id = j.id;
  end if;
  fase := coalesce(s.estado->>'fase', 'lobby');
  revela := fase in ('revelacao', 'apuracao', 'fim');
  select * into r from public.sala_respostas where jogador = j.id and pergunta = coalesce((s.estado->>'idx')::int, -1);
  -- modo "pergunta diferente para cada pessoa": manda só a pergunta desta pessoa
  if s.estado->>'modo' = 'individual' and fase in ('pergunta', 'revelacao') then
    pq := s.perguntas->'lista'->public.din_questao(s, j.ordem, (s.estado->>'idx')::int);
    minha := jsonb_build_object('t', pq->'t', 'opts', pq->'opts', 'cat', pq->'cat', 'tipo', pq->'tipo')
          || case when fase = 'revelacao' then jsonb_build_object('certa', pq->'certa', 'exp', pq->'exp') else '{}'::jsonb end;
  end if;
  return jsonb_build_object(
    'estado', s.estado, 'aberta', s.aberta, 'grupos', s.grupos, 'agora', now(), 'minha', minha,
    'eu', jsonb_build_object('nome', j.nome, 'avatar', j.avatar, 'grupo', j.grupo,
          'pontos', j.pontos - case when not revela and r.jogador is not null then r.pontos else 0 end,
          'acertos', j.acertos - case when not revela and r.correta then 1 else 0 end,
          'sequencia', case when revela then j.sequencia else 0 end, 'melhor_seq', j.melhor_seq),
    'resposta', case when r.jogador is null then null else jsonb_build_object(
          'resposta', r.resposta,
          'correta', case when revela then r.correta end,
          'pontos', case when revela then r.pontos end) end);
end $$;

-- Participante responde (a pontuação é calculada no banco)
create or replace function public.din_responder(p_codigo text, p_id uuid, p_token uuid, p_resposta int) returns jsonb
language plpgsql security definer set search_path = public as $$
declare s public.salas; j public.sala_jogadores; g jsonb; ok boolean; seg numeric; dur numeric; pts int; seq int; qn int; certa int;
begin
  select * into s from public.salas where codigo = upper(trim(p_codigo));
  if not found then raise exception 'Sala não encontrada.'; end if;
  select * into j from public.sala_jogadores where id = p_id and token = p_token and sala = s.id for update;
  if not found then raise exception 'Você não está nesta sala.'; end if;
  g := s.gabarito;
  if coalesce(s.estado->>'fase','') <> 'pergunta' or g is null or (g->>'idx')::int <> (s.estado->>'idx')::int then
    raise exception 'Esta pergunta já foi encerrada.'; end if;
  if now() > (g->>'fim')::timestamptz + interval '1 second' then raise exception 'O tempo acabou.'; end if;
  if exists (select 1 from public.sala_respostas where jogador = j.id and pergunta = (g->>'idx')::int) then
    raise exception 'Você já respondeu esta pergunta.'; end if;
  if g->>'modo' = 'individual' then
    qn := public.din_questao(s, j.ordem, (g->>'idx')::int);
    certa := (s.perguntas->'lista'->qn->>'certa')::int;
  else
    qn := (g->>'idx')::int; certa := (g->>'certa')::int;
  end if;
  ok := p_resposta = certa;
  dur := (g->>'segundos')::numeric;
  seg := least(dur, greatest(0, extract(epoch from now() - (g->>'inicio')::timestamptz)));
  seq := case when ok then j.sequencia + 1 else 0 end;
  pts := case when ok then 100 + round(50 * greatest(0, dur - seg) / dur) + least(100, greatest(0, seq - 1) * 20) else 0 end;
  insert into public.sala_respostas (sala, jogador, pergunta, resposta, correta, pontos, tempo, questao)
  values (s.id, j.id, (g->>'idx')::int, p_resposta, ok, pts, round(seg, 2), qn);
  update public.sala_jogadores set pontos = pontos + pts, acertos = acertos + case when ok then 1 else 0 end,
    sequencia = seq, melhor_seq = greatest(melhor_seq, seq), visto_em = now() where id = j.id;
  return jsonb_build_object('ok', true);
end $$;

-- Organizador abre uma pergunta (o tempo é contado pelo relógio do servidor)
create or replace function public.din_abrir_pergunta(p_sala uuid, p_publico jsonb, p_certa int, p_segundos int) returns jsonb
language plpgsql security definer set search_path = public as $$
declare e jsonb; ini timestamptz := now(); fim timestamptz := now() + make_interval(secs => p_segundos);
begin
  if not public.dono_sala(p_sala) then raise exception 'Sem permissão para comandar esta sala.'; end if;
  e := p_publico || jsonb_build_object('fase', 'pergunta', 'inicio', ini, 'fim', fim, 'segundos', p_segundos);
  update public.salas set estado = e,
    gabarito = jsonb_build_object('certa', p_certa, 'idx', (p_publico->>'idx')::int, 'inicio', ini, 'fim', fim, 'segundos', p_segundos, 'modo', coalesce(p_publico->>'modo', 'mesma'))
  where id = p_sala;
  return jsonb_build_object('estado', e, 'agora', now());
end $$;

revoke all on function public.din_entrar(text, text, text) from public;
revoke all on function public.din_estado(text, uuid, uuid) from public;
revoke all on function public.din_responder(text, uuid, uuid, int) from public;
revoke all on function public.din_abrir_pergunta(uuid, jsonb, int, int) from public;
grant execute on function public.din_agora() to anon, authenticated;
grant execute on function public.din_entrar(text, text, text) to anon, authenticated;
grant execute on function public.din_estado(text, uuid, uuid) to anon, authenticated;
grant execute on function public.din_responder(text, uuid, uuid, int) to anon, authenticated;
grant execute on function public.din_abrir_pergunta(uuid, jsonb, int, int) to authenticated;

-- Ferramentas do administrador da sala (destravar, recalcular, mais tempo)
create or replace function public.din_admin(p_sala uuid, p_acao text, p_idx int default null, p_seg int default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare s public.salas; j record; r record; pts int; ac int; sq int; best int; novo_fim timestamptz;
begin
  if not public.dono_sala(p_sala) then raise exception 'Sem permissão para comandar esta sala.'; end if;
  select * into s from public.salas where id = p_sala for update;
  if p_acao = 'limpar_pergunta' then
    delete from public.sala_respostas where sala = p_sala and pergunta = p_idx;
  elsif p_acao = 'zerar' then
    delete from public.sala_respostas where sala = p_sala;
  elsif p_acao = 'mais_tempo' then
    if s.gabarito is null or coalesce(s.estado->>'fase','') <> 'pergunta' then raise exception 'Não há pergunta aberta.'; end if;
    novo_fim := greatest(now(), (s.gabarito->>'fim')::timestamptz) + make_interval(secs => coalesce(p_seg, 15));
    update public.salas set
      gabarito = s.gabarito || jsonb_build_object('fim', novo_fim),
      estado = s.estado || jsonb_build_object('fim', novo_fim, 'seq', coalesce((s.estado->>'seq')::int, 0) + 1)
    where id = p_sala returning * into s;
    return jsonb_build_object('estado', s.estado, 'agora', now());
  elsif p_acao <> 'recalcular' then
    raise exception 'Ação desconhecida.';
  end if;
  -- recalcula pontos, acertos e sequências a partir das respostas gravadas
  for j in select id from public.sala_jogadores where sala = p_sala loop
    pts := 0; ac := 0; sq := 0; best := 0;
    for r in select correta, pontos from public.sala_respostas where jogador = j.id order by pergunta loop
      pts := pts + r.pontos;
      if r.correta then ac := ac + 1; sq := sq + 1; best := greatest(best, sq); else sq := 0; end if;
    end loop;
    update public.sala_jogadores set pontos = pts, acertos = ac, sequencia = sq, melhor_seq = best where id = j.id;
  end loop;
  return jsonb_build_object('estado', s.estado, 'agora', now());
end $$;
revoke all on function public.din_admin(uuid, text, int, int) from public;
grant execute on function public.din_admin(uuid, text, int, int) to authenticated;

-- Participante sai da sala pelo próprio celular
create or replace function public.din_sair(p_codigo text, p_id uuid, p_token uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  delete from public.sala_jogadores j using public.salas s
  where j.id = p_id and j.token = p_token and j.sala = s.id and s.codigo = upper(trim(p_codigo));
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.din_sair(text, uuid, uuid) from public;
grant execute on function public.din_sair(text, uuid, uuid) to anon, authenticated;
