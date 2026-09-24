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
2. [x] Smart Drop (seção 21) — ver Rodada 3
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
- [x] Gaveta: na compacta o leque de miniaturas abre no hover; na expandida os arquivos são distribuídos um a um (caem inclinados e assentam), sobem um pouco no hover
- [x] Indicador de privacidade: saiu de dentro da pílula (cobria o relógio) pra um ponto do lado de fora, à esquerda; halo respirando lento, um ripple só ao ligar
- [x] Split na pílula COMPACTA (testado com print ao vivo): segunda pílula brota da principal ("mitose",
      pescoço que afina e solta), scroll em cima troca a ilha (rolagem tipo caça-níquel), arrastar pra
      longe joga fora, empurrar de volta pra principal reabsorve, clique do meio descarta, × só no hover.
      Entrada: "+" que aparece ao lado no hover, clique direito na pílula, ou botão fixo na expandida →
      seletor com todas as candidatas (ativas + Sistema/Gaveta/Agentes/ZeroTier/Histórico/F1/Mídia).
      Mesmo `splitId` alimenta a expandida lado a lado. IPC: `island split <id>` / `island split ""`.
- [x] Home compacta: bandeja de status uniforme (`StatusGlyph`): mesmo tamanho/tom, cor só em alerta, contagem como badge, hover circular, todos clicáveis
- [x] Home expandida: seção "Agora" (uma linha tocável por ilha ativa + F1 quando a sessão está a <3 dias, entrada escalonada), cabeçalho alinhado à esquerda, dock com colunas iguais, rótulos em pt-BR, contagem legível ("13h 52min")
- [x] Motion: mitose/reabsorção do split com "gole" da pílula principal, rolagem caça-níquel ao trocar a ilha do split, arremesso ao arrastar, ripple da privacidade, "+" que gira ao entrar, bandeja com hover que salta, lista "Agora" e seletor de split entrando escalonados

## Rodada 3

- [x] Hover que "foge" do mouse: a ilha agora cresce para o lado oposto ao do ponteiro (o lado por onde o
      mouse entrou fica parado — botões de mídia na borda direita não escapam mais). `growShift` em
      `DynamicIsland.qml`, espelhado na superfície material via `GlobalStates.islandGrowShift`.
      Validação visual pendente (usuário estava em tela cheia).
- [x] IMDb/OMDb (testado com dado real: Modern Family ★8.5): `services/WatchRating.qml` + Peek `DiWatch`
      (nota conta até o valor; coroa + brilho no melhor da temporada) + expandida `DiXWatch` (temporada em
      barras que crescem em sequência, atual destacado, melhor em dourado, hover mostra o episódio). Fonte do
      episódio: `scripts/island/watch-rating.user.js` (Tampermonkey). Aparece em "Agora" enquanto toca.
      Pendente: validar os seletores do userscript na Netflix/Disney+ reais (só testei o caminho sem script).
- [x] Smart Drop (seção 21): `services/SmartDrop.qml` (tipo por extensão → ações; argv separado, testado
      com nome de arquivo malicioso sem injeção). Ao arrastar, a pílula vira zonas de ação com um destaque
      que desliza pra zona sob o cursor; soltar executa. Imagem: Gaveta/Editar(swappy)/Copiar/PNG ·
      PDF: Gaveta/Abrir/Caminho · zip: Extrair/Gaveta/Abrir · código: Gaveta/Copiar/Editor(code) ·
      link: Abrir/Copiar/QR/Gaveta. Arraste real não testado (só os comandos).
- [x] Nota por episódio, sempre que um episódio começa (inclusive autoplay), com logo do serviço:
      - validado na página real do Disney+: player em Shadow DOM; episódio atual em `title-bug` (só com os
        controles na tela); "a seguir" em `pivot-tray-tile.episodeTitle` (sempre presente) → usado no autoplay
        e pra inferir o atual (próximo − 1). Userscript v3 orientado a eventos (sem setInterval).
      - notas: OMDb deixava 15/24 episódios sem nota; agora 1 requisição GraphQL do IMDb por temporada, só
        quando um episódio começa (endpoint não oficial do site do IMDb; OMDb só identifica a série).
      - pílula só com a nota do EPISÓDIO (série fica pequena na expandida); anel que se desenha até a nota
        com o número contando, cor pela qualidade, título sobe depois, coroa + brilho no melhor.
      - logos: Simple Icons (Netflix, Prime Video, Max, Apple TV, Crunchyroll, Paramount+) + Disney+
        (Wikimedia, domínio público) em `assets/island/apps/`.
- [x] Destaques da nota por categoria (testado ao vivo com Suits/Netflix e Modern Family/Disney+):
      top 3 da série (medalha ouro/prata/bronze, confete, brilho dourado), top 10 (troféu e brilho
      violeta), melhor da temporada (coroa), nota ≥ 8.5 (anel pulsa). Série inteira numa requisição por
      série (paginada acima de 250). Teste: `island simulate watchTop3|watchTop10|watchBest|watchHigh`.
      Validado: Netflix por estado do player (a tela não mostra a temporada), Disney+ por Shadow DOM.
      Limitação do Chrome: só a aba que tocou por último vai pro MPRIS (YouTube em 2º plano esconde a série).
- [x] Auditoria de passividade (regra no ILHA.md). Parado agora: nenhum processo auxiliar da Ilha rodando.
      - F1: sem processo entre sessões (`live --until-idle` + um despertador 30 min antes); contagem por minuto,
        por segundo só na última hora.
      - downloads: FolderListModel (inotify) liga o watcher só com um parcial sendo escrito; ele sai sozinho.
        Parciais abandonados não contam (havia um .crdownload de 4 GB de agosto segurando o processo).
      - CPU e temperatura: escutam o ResourceUsage (que já amostra pra barra) em vez de timers próprios.
      - rede: /proc/net/dev a cada 5 s parada, 1 s só com tráfego/download/chamada/tela aberta.
      - net_sources.py: não roda mais só porque um filme está tocando (só download real ou tela de rede).
      - periféricos: sem tick de 30 s (UPower/BlueZ avisam sozinhos); perfil/ventoinha só com a tela Sistema;
        limite dos agentes só perto de 70%; limpeza de atividades 1 s → 2 s.
      - fica: Caps Lock (0,5 s lendo /sys, irrisório — o 100% por evento seria um bind do Hyprland avisando a
        Ilha) e ZeroTier (2 min parado; 5 s só em chamada).
- [ ] Periféricos/HDMI (auditoria): já existem disco conectado/remoção segura, monitor conectado com
      Estender/Espelhar/Só externo + confirmação/reversão, bateria de periférico baixa, temperatura.
      Falta: aviso de armazenamento quase cheio (deve ser por evento, não polling).

## Ordem sugerida daqui pra frente

Rodada 2 → Smart Drop → periféricos/HDMI (auditoria).
