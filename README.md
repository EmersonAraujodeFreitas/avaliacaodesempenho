# Avaliação de Desempenho do Consultor

Site de avaliação de desempenho da Inovação Casa (área de Inovação): formulário de competências, perfil DISC, painel da equipe, histórico com evolução, dinâmica gamificada e relatório em PDF.

## Banco de dados (Supabase)

Os dados ficam no Supabase, separados por usuário:

- **Gerente e Coordenador** veem todos os dados e têm a aba **Administração**, onde definem o cargo de cada pessoa.
- **Supervisor, Analista e Assistente** veem só o que eles mesmos lançaram.
- A regra é garantida pelo próprio banco (Row Level Security), não só pela tela.
- O acesso é por **usuário e senha** (sem e-mail). A primeira conta criada vira Gerente e já entra ativa.
- Toda conta nova fica **aguardando aprovação**: só entra depois que um gerente ou coordenador aprova e define o cargo em Administração. Também é possível bloquear e reativar o acesso.
- Quem esquecer a senha pede ao gerente ou coordenador, que cria uma nova em Administração.

### Como configurar

1. Crie um projeto gratuito em https://supabase.com.
2. Em **SQL Editor**, cole o conteúdo de `supabase.sql` e clique em **Run**.
3. Em **Authentication → Sign In / Providers → Email**, desligue **Confirm email**.
4. Em **Authentication → URL Configuration**, coloque em **Site URL** o endereço do site:
   `https://emersonaraujodefreitas.github.io/avaliacaodesempenho/`
5. Em **Project Settings → API Keys**, copie a **Project URL** e a chave **anon public** e coloque nas constantes `SUPA_URL` e `SUPA_KEY` do `index.html`.

Sem essas duas constantes preenchidas, o site funciona como antes, guardando os dados só no navegador.

## Dinâmica ao vivo (QR code)

Página: `dinamica.html` (link no menu Dinâmica do site).

1. Rode de novo o `supabase.sql` no SQL Editor do Supabase (ele cria as tabelas `salas`, `sala_jogadores` e `sala_respostas`).
2. O organizador abre a página, entra com usuário e senha e cria uma sala.
3. Projete o telão. As pessoas leem o QR code, digitam o nome e escolhem um avatar (não precisam de login).
4. O contador mostra quantas pessoas entraram e quantas estão online. Monte os grupos clicando na pessoa e depois no grupo (ou arrastando).
5. Clique em "Começar a dinâmica". Todos respondem ao mesmo tempo no celular; o ranking de equipes e o individual só aparecem no final.
6. O resultado fica salvo no Painel da equipe.
7. Painel do administrador: botão "Painel admin" no telão (abre em outra guia). Mostra quem está online, a performance de cada equipe em tempo real e tem controles para destravar (atualizar telão, recarregar celulares, recalcular pontos, repetir pergunta, +15 s, avanço automático, remover um ou todos).

`qrcode.js`: QR Code Generator for JavaScript, (c) Kazuhiko Arase, licença MIT.
