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
- [ ] Split View (seção 13) — duas Tools/Activities lado a lado, ação explícita do usuário. **Não existe ainda.**

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
8. [ ] Dev Activity (seção 26) — detecção de servidor local (localhost:PORT), building/ready/error. **Não existe.**
9. [ ] Focus Mode (seção 33) — toggle que manda não-importantes pro histórico sem peek. **Não existe.**
10. [ ] Periféricos (seção 27) — USB/SSD, bateria de fones/mouse/controle, armazenamento cheio,
    thermal — não auditado a fundo ainda (thermal já existe via `IslandHardware`)
11. [ ] HDMI/Monitor (seção 28) — não auditado a fundo ainda; `IslandHardware` já tem
    `applyMonitorLayout`/rollback, checar se o Peek de conexão já existe

## Bugs / achados avulsos

- [x] `Gofile.qml` (seção 42) não existe no projeto nem no histórico git — não havia bug pendente
- [x] Ícone de agente duplicado (DiIdle/DiAgents mostrando 1 selo por tipo aberto) — corrigido

## Ordem sugerida daqui pra frente

Split View → Dev Activity → Focus Mode → Smart Drop → periféricos/HDMI (auditoria) → Motion (Fase 6).
