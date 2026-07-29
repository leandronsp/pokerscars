# Prompt inicial — pokerscars

> Este é o prompt que deu start no projeto, em 2026-07-29. Único documento em
> português da codebase, preservado como registro de intenção. O plano vivo
> está em `ROADMAP.md`.

## O pedido

Quero fazer um game web de poker para jogar com amigos. A gente costuma
apostar, então deveria ter uma forma de aceitar buy-in, sem pagamento
automático por agora. Desenvolver a engine e criar um MVP: uma mesa jogável
multiplayer, que vou expor num ngrok e testar com os amigos.

Stack Phoenix, pela parada real-time. Pensar como um UX product senior e um
Elixir developer senior com experiência em arquitetura web, websockets, como o
browser funciona, interfaces modernas de UI com variados temas, interação
extrema de UX e real-time.

## Como construir

- Esqueleto Phoenix com Docker, última versão do Elixir, make stuff igual
  voxquad e barbie-shop. `docker compose up -d` sobe o que é preciso. Cuidado
  com portas já utilizadas.
- Tipagem extrema para simular pyright/pydantic: guardrails para garantir que
  cada funcionalidade entra com a corretude esperada, testável via browser.
- Clean code, arquitetura limpa e DDD como CARRO CHEFE: bounded contexts,
  aggregate root, manutenção de código em primeiro lugar.
- UI componentizável e reutilizável, temas variados, mesa bonita, design das
  cartas e dos call to actions, andamento da table.
- R&D: como funciona uma poker engine, bom design de mesa. Insights de
  voxquad, mendio, pitchr — o que faz sentido e o que não faz.
- Roadmap em passos pequenos (skill /step), CLAUDE.md sempre refletindo as
  decisões, com as .claude/rules adequadas. Trabalho em conjunto: perguntas
  socráticas, autonomia com o dono no loop.
- Código, comentários e docs em inglês. Só este prompt fica em português.

## Decisões do kickoff

| Pergunta | Decisão |
|---|---|
| Formato de jogo | Cash game No-Limit Texas Hold'em. Torneio é fase 2. |
| Buy-in | Ledger de fichas em centavos (integer). Acerto via Pix fora do app. |
| Identidade | Link da mesa + apelido, sem cadastro. Contas são fase 2. |
| Idioma da UI | i18n desde o início (Gettext), pt-BR como locale fonte. |
