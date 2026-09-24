# Ilha Dinâmica — contrato

Este arquivo existe porque a ilha cresceu para além do que cabe na cabeça: são ~100 componentes em
`modules/ii/bar/`, três serviços e uma dúzia de scripts. Quem for mexer aqui (você ou um agente) deve ler isto
antes, para não redescobrir as mesmas regras.

## As peças

| Onde | O quê |
| --- | --- |
| `modules/ii/bar/DynamicIsland.qml` | O maestro: decide qual ilha aparece, larguras, animações, gestos, baralho, fixadas |
| `modules/ii/bar/Di*.qml` | A face **compacta** de cada ilha (o que cabe na pílula da barra) |
| `modules/ii/bar/DiX*.qml` | A face **expandida** de cada ilha (o conteúdo do overlay) |
| `modules/ii/bar/DiExpanded.qml` | A janela do overlay: abertura, recorte, elementos compartilhados, foco |
| `modules/ii/bar/DiExpandedContent.qml` | Mapa `id → componente expandido` |
| `services/IslandEvents.qml` | Centro de eventos: notificações, área de transferência, rede, downloads, atividades |
| `services/IslandHardware.qml` | Hardware: monitores, pendrives, dock, carregador, periféricos, calor, suspensão |
| `services/ClaudeCode.qml` | Sessões de agentes (Claude, Codex, Gemini) vindas dos hooks |
| `scripts/island/` | O que roda fora do shell: hooks de terminal, nethogs, downloads, CI, voz |

## Modelo semântico (refatoração em andamento)

A ilha está sendo reorganizada de "uma lista de prioridade com ~28 ids" para quatro categorias
(`DynamicIsland.qml`, logo acima de `activeIds`):

- **CRITICAL** — pode tomar a pílula inteira. Hoje é dinâmico, não uma lista fixa: `isCriticalNow(id)`
  cobre `hibernate`/`session` sempre, e `battery`/`hardware` só quando o próprio estado diz que é urgente
  (`batteryAlertKind === "critical"`, `IslandHardware.payload.urgent`).
- **PEEK** — o resto de `interruptIds`: flash de 2-5s que devolve a pílula exatamente como estava.
- **LIVE** — `liveIds`: as únicas que o scroll (`cycleIds`) percorre. É o que dura minutos/horas.
- **TOOL** — `toolIds`: conteúdo pedido explicitamente. Não compete pela pílula nem pelo scroll; só abre
  pelo Tool Dock do Home (`DiXIdle.qml`) ou pela tira do switcher na expandida.

Migração em fases (ver histórico de commits "di: fase N"): Fase 1 = essa classificação + `cycleIds`
restrito a Live. Fase 2 = Home minimalista. As fases seguintes (Peek/Live/Expanded/Motion/integrações
novas) ainda não foram feitas — quem continuar, comece por elas antes de inventar categoria nova.

## O ciclo de vida de uma ilha

Uma ilha é um **id** (string). Para existir, ele precisa aparecer em cada um destes lugares de
`DynamicIsland.qml` — esquecer um é a causa mais comum de "aparece mas fica quebrado":

1. `activeIds` — quando ela está acontecendo.
2. `interruptIds` — se ela interrompe o que estiver na tela (evento curto) em vez de conviver (persistente).
3. `baseWidth(id)` — a largura da pílula compacta.
4. `componentForId(id)` (perto do fim do arquivo) — o componente compacto.
5. `iconForId(id)` e `nameForId(id)` — usados pelo baralho, pela visão geral e pelas cápsulas.
6. `hasDetails(id)` — se ela abre num overlay.
7. `DiExpandedContent.componentFor(id)` — o componente expandido.
8. `pinnableIds` — se ela pode ser fixada.
9. `standaloneViews` — se ela pode ser aberta mesmo sem estar ativa.

Uma ilha efêmera (um "flash") vive num `IslandEvents.Flash`: `show(payload, ms)`, `hold(bool)`, `dismiss()`,
com `active` e `payload`. Registre-a também em `flashFor(id)` para que o hover a segure e o clique a dispense.

## Navegação (um eixo só)

Rolar para cima/baixo percorre **uma fila única, só de LIVE Activities** (`cycleIds`), sempre nesta ordem:

```
 ↑  ilhas LIVE ativas (por prioridade)
    ◌ INÍCIO        ← ponto vazado nos marcadores; é para onde a ilha volta sozinha
```

Ferramentas (`toolIds`) e o histórico não entram mais na roda do scroll — pinnar uma delas (`pinnableIds`)
só controla se ela aparece no Tool Dock/switcher, nunca no scroll. Os pips (`cyclePips`) só aparecem quando
`liveActivityCount > 1`; com zero ou uma Live Activity ativa, não há o que indicar.

Arrastar/rolar para os lados **não troca de ilha**: age dentro da que está na tela (faixa anterior/próxima na
mídia, item anterior/próximo na área de transferência, métrica no sistema). Isso é `cyclePinned()`, que apesar do
nome antigo virou "ação lateral".

O único indicador de posição é a fileira de pontinhos **abaixo da pílula** (`cyclePips`). O arco de pontos à
esquerda foi removido: desenhava em `x = −4,5`, isto é, fora da pílula, e girava cada ponto para fora da curva.

Sair do início é sempre temporário: 8 s sem interação e `returnHomeTimer` leva a ilha de volta. Enquanto você
está fora, a abinha `homeTab` aparece ao lado da pílula.

**Dispensar** (clique do meio) tira a ilha da fila guardando o *estado* que estava na tela — `stampFor(id)`.
Quando esse estado muda (outra faixa, outro arquivo, outra sessão), ela volta sozinha. **Segurar o clique do
meio** silencia até o fim da sessão, e o chip "trazer de volta" na expandida do início desfaz. Pelo IPC:
`island dismiss`, `island silence`, `island restore <id>`.

## Regras aprendidas do jeito difícil

- **Ícone é fonte, não imagem.** `MaterialSymbol` desenha o texto numa fonte de ícones: um nome inexistente vira
  uma caixinha com letras. Marcas (Claude, Codex, Gemini, WhatsApp) são SVG e vão em `DiClaudeIcon`/`DiBrandIcon`.
- **Nunca sobreponha com âncoras.** Foto à esquerda + texto à direita, ambos ancorados, colidem no primeiro texto
  longo. Use um `RowLayout` único com espaçador; quem não couber elide.
- **`Layout.minimumWidth: 0`** em todo texto que deve elidir dentro de um layout, senão ele empurra os vizinhos.
- **`data` é propriedade reservada do Qt.** Nunca nomeie uma property assim (use `commandData`).
- **Largura de conteúdo sem laço:** meça com cópias invisíveis do texto (ver `DiNotifs.qml`), nunca com o
  `implicitWidth` de um layout cuja largura depende do resultado.
- **Animação de camada é do Hyprland.** O overlay só abre "da barra" porque existe
  `hl.layer_rule({ match = { namespace = "^quickshell:dynamicIsland$" }, no_anim = true })`.
- **Janela sempre criada precisa de máscara vazia**, não de `item: null`, ou ela engole o mouse da barra inteira.
- **Timer de notificação:** `expireTimeout == 0` significa "nunca sair" e só vale para `critical`; qualquer outra
  ganha um timer, ou uma live do YouTube trava a ilha para sempre.

## Como testar

- `scripts/island/ilha-teste.sh` — menu com ~100 cenários simulados.
- `qs -c end4-pC ipc call island simulate <nome>` — dispara um cenário isolado.
- `qs -c end4-pC ipc call island open <view>` — abre uma expandida direto (só funciona para `standaloneViews`).
- `qs list --all` e `qs log -i <instância>` — o log da instância viva; sem isso não dá para ver erro de QML.
- Capturas ficam em `~/Imagens/Ilha-testes/<data>/`.

## O que fica fora do shell

- `~/.claude/settings.json`, `~/.codex/hooks.json`, `~/.gemini/config/hooks.json` — hooks dos agentes.
- `~/.config/fish/conf.d/island.fish` e `scripts/island/cmd-island.zsh` — comandos longos do terminal.
- `scripts/island/dev-island.sh <id> [título]` — Dev Activity (seção 26): `npm run dev 2>&1 | dev-island.sh
  myapp "My App"`. Genérico por design — só procura uma URL localhost e palavras de erro/pronto na saída,
  não entende nenhum framework específico. Mantém a Live Activity viva enquanto a porta responder.
- `scripts/island/watch-rating.user.js` — userscript (Tampermonkey) da nota do IMDb: escreve série/temporada/
  episódio nos metadados de mídia da Netflix/Disney+ (title = episódio, artist = série, album = `S03E05`), que
  o Chrome repassa ao MPRIS. `services/WatchRating.qml` lê isso, consulta a OMDb (cache por série e por
  temporada) e dispara o Peek `watchRating` uma vez por episódio. Sem o script, só a nota da série.
- `~/.config/illogical-impulse/omdb.key` — chave da OMDb. **Nunca no repo** (tem remoto público).
- `~/.config/foot/foot.ini` — `pipe-command-output`, que é como a ilha lê a saída de um comando que falhou.
- `~/.config/hypr-profiles/end4/custom/rules.lua` — a regra `no_anim` acima.
