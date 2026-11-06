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
