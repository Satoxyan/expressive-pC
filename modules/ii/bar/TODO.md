# Refatoração da Dynamic Island — checklist

Acompanha a refatoração completa pedida (arquitetura de estados + UX/UI + integrações novas). Ver
`ILHA.md` para o contrato/arquitetura atual. Marcado `[x]` = feito e ao vivo, `[~]` = parcial/já
satisfeito por implementação existente (sem trabalho novo necessário), `[ ]` = pendente.

## Fase 1 — Arquitetura

- [x] Auditoria do código atual (`DynamicIsland.qml`, serviços, ~100 componentes Di*/DiX*)
- [x] Modelo semântico CRITICAL/PEEK/LIVE/TOOL (`criticalIds`, `liveIds`, `toolIds`, `peekIds`, `isCriticalNow`)
- [x] Documentado em `ILHA.md`

## Fase 2 — Compact

- [x] Scroll restrito a Live Activities + Home (`cycleIds`), tools fora da roda do mouse
- [x] Pips só aparecem com `liveActivityCount > 1`
- [x] Home (`DiXIdle.qml`) reescrito: sem foto/saudação/semana/tiles permanentes; header
      dia+hora+clima, mini player contextual, Tool Dock (Now/Drawer/Clipboard/Agents/More)
- [~] Primary + Minimal — já existia via `anchorInfo` + `secondaryIds` (split capsules), mantido como estava
- [~] Return timer nunca volta pra "Home só por timeout" — já era o comportamento de `goHome()`
      (volta pra `persistentIds[0]`, i.e. a Live Activity mais importante, ou idle se nenhuma)

## Fase 3 — Peek

- [~] OSD, notificação, bluetooth, áudio, bateria, screenshot, downloadDone, SongRec, hardware —
      já eram `Flash`/interrupt com hold/dismiss/silence; só formalizado em `peekIds`
- [x] Fullscreen Quiet Mode: Critical (hibernação iminente, bateria crítica, `kind:"thermal"`) agora
      fura o layer do fullscreen (`Bar.qml`); resto continua enterrado como já era

## Fase 4 — Live

- [~] F1 unificado (seção 5) — já funciona assim na prática (`f1Flag`/`f1Start`/`f1Event` já são
      peeks transitórios que devolvem `f1` exatamente como estava); não reescrito para não arriscar
      regressão de algo que já está correto
- [x] Agentes: nunca mais de 1 selo repetido por tipo/sessão (`DiIdle.qml`, `DiAgents.qml`) — mostra
      o agente mais relevante + badge "+N"

## Fase 5 — Expanded

- [x] Home simplificado (ver Fase 2)
- [x] Tool Dock (Now/Shelf/Clipboard/Agents/More) — dentro do Home
- [~] Weather/System/ZeroTier/Calendar/History/Settings — já existiam como `standaloneViews`,
      só religados ao novo Dock
- [x] Split View (seção 13) — duas Tools/Activities lado a lado; botão "splitscreen" no pager arma,
      próximo pip vira parceiro, X fecha só o split. Nunca abre sozinho.

## Fase 6 — Motion e design system

- [ ] Não auditado ainda. Suspeita: já segue boa parte das regras (durações curtas, sem
      SpringAnimation indiscriminado — ver comentários em `DynamicIsland.qml`), mas não verificado
      seção a seção.

## Fase 7 — Integrações novas (prioridade da seção 43)

1. [x] Privacy Island — já completo (PipeWire real + indicador ambiente `privacyDots`), melhor que a
   spec literal (sem peek a cada toggle, ambient dots)
2. [ ] Smart Drop (seção 21) — ações contextuais por tipo de arquivo (MIME) no drop da Shelf. **Não existe.**
3. [~] Clipboard inteligente (seção 22) — já detecta URL/YouTube/PDF/endereço/idioma estrangeiro;
   falta cor (hex) e rótulo de linguagem de código
4. [~] Agents 2.0 (seção 23) — já tem Live/waiting→attention/dashboard; falta confirmar promoção
   completa pra CRITICAL quando agente pede aprovação obrigatória
5. [x] Fullscreen/Game Quiet Mode (seção 29) — feito na Fase 3
6. [~] Call Activity (seção 30) — já detecta chamada via PipeWire e mostra no anchor; falta
   mute/deafen/sair como controles na expandida
7. [~] Terminal Activity (seção 25) — já existe (`scripts/island/cmd-island.zsh`/`.sh`)
8. [x] Dev Activity (seção 26) — `scripts/island/dev-island.sh` (genérico, testado com input simulado):
   building → ready (URL detectada, fica Live enquanto a porta responder) → error/remove. Usa o handler
   IPC novo `island dev` (`IslandEvents.qml`). Sem botão de ação na expandida ainda — mesmo nível que
   Terminal Activity hoje (ação só existe no Histórico depois). Sem suporte por framework de propósito.
9. [x] Focus Mode (seção 33) — `IslandEvents.focusOn`/`toggleFocus()`. Enquanto ligado, notificação
   não-crítica nunca vira Peek (via `isMuted`, sem efeito colateral em binding — contagem via
   `Connections.onNotify`, que é imperativo). Ao desligar, mostra "Focus finished · N min · M waiting"
   como Live Activity (`upsertActivity`, mesmo padrão do caffeine). Chip em Home → More.
10. [ ] Periféricos (seção 27) — USB/SSD, bateria de fones/mouse/controle, armazenamento cheio,
    thermal — não auditado a fundo ainda (thermal já existe via `IslandHardware`)
11. [ ] HDMI/Monitor (seção 28) — não auditado a fundo ainda; `IslandHardware` já tem
    `applyMonitorLayout`/rollback, checar se o Peek de conexão já existe

## Bugs / achados avulsos

- [x] `Gofile.qml` (seção 42) não existe no projeto nem no histórico git — não havia bug pendente
- [x] Ícone de agente duplicado (DiIdle/DiAgents mostrando 1 selo por tipo aberto) — corrigido
- [x] Causa raiz real do "Claude duplicado": `activity` (tarefa específica) e `agents` (resumo geral)
      ficavam ativos ao mesmo tempo pro mesmo agente — um na pílula, outro no deck atrás dela.
      `agents` agora só entra em `activeIds` quando nenhuma `activity` atual já é desse agente.
## Rodada 2 — feedback de uso (2026-09-24)

- [x] Bug: ícone da gaveta não abria — clicar numa cápsula lateral só trocava ela de lugar com a principal; agora abre a expandida dela direto
- [x] Bug: capacete da F1 não tinha área de clique; agora abre a F1. `agents`/`clipboard`/`zerotier` entraram em `standaloneViews` (antes a expandida voltava sozinha pra Home)
- [ ] Animação da gaveta melhor
- [x] Indicador de privacidade: saiu de dentro da pílula (cobria o relógio) pra um ponto do lado de fora, à esquerda; halo respirando lento, um ripple só ao ligar
- [x] Split na pílula COMPACTA (testado com print ao vivo): segunda pílula brota da principal ("mitose",
      pescoço que afina e solta), scroll em cima troca a ilha (rolagem tipo caça-níquel), arrastar pra
      longe joga fora, empurrar de volta pra principal reabsorve, clique do meio descarta, × só no hover.
      Entrada: "+" que aparece ao lado no hover, clique direito na pílula, ou botão fixo na expandida →
      seletor com todas as candidatas (ativas + Sistema/Gaveta/Agentes/ZeroTier/Histórico/F1/Mídia).
      Mesmo `splitId` alimenta a expandida lado a lado. IPC: `island split <id>` / `island split ""`.
- [x] Home compacta: bandeja de status uniforme (`StatusGlyph`): mesmo tamanho/tom, cor só em alerta, contagem como badge, hover circular, todos clicáveis
- [ ] Home expandida confusa: difícil chegar nas ilhas ativas úteis
- [ ] Motion graphics criativos (Fase 6)

## Ordem sugerida daqui pra frente

Rodada 2 → Smart Drop → periféricos/HDMI (auditoria).
