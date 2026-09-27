#!/usr/bin/env bash
# Menu no terminal para disparar todos os estados da Ilha Dinâmica.
#   ilha-teste            menu fzf (ou select) no terminal atual
#   ilha-teste --janela   abre o menu numa janela flutuante do foot
#   ilha-teste tour       passa por tudo sozinho
#   ilha-teste --run ID   dispara uma ação em segundo plano (usado pelo menu)
#   ilha-teste --list     lista os ids disponíveis

SELF=$(readlink -f "${BASH_SOURCE[0]}")
QS=(qs -c end4-pC ipc call)
PRINTS="$HOME/Imagens/Prints"
IMG=$(ls -t "$PRINTS"/*.png 2>/dev/null | head -1)
LOG="${XDG_RUNTIME_DIR:-/tmp}/ilha-teste.log"

ipc() { "${QS[@]}" "$@" >/dev/null 2>&1; }

notify_image() { notify-send -a WhatsApp -h "string:image-path:$IMG" "Maria" "Olha essa foto 😄 bora naquele lugar amanhã?"; }
notify_critical() { notify-send -u critical -a Sistema "Disco quase cheio" "Restam só 2 GB em /"; }
notify_actions() { notify-send -a Discord -A reply=Responder -A later=Depois "Lucas" "partiu jogar hoje?" >/dev/null & }
notify_stack() { for m in "oi" "tá aí?" "responde aí 😅"; do notify-send -a WhatsApp "João" "$m"; sleep 0.6; done; }
notify_group() { notify-send -a "Google Chrome" "Família 🏠" "web.whatsapp.com
Mãe: Bom dia, alguém vai almoçar aqui hoje?"; }
notify_sticker() { notify-send -a "Google Chrome" "Princesa 🌸" "web.whatsapp.com
💟 Figurinha"; }

copy() { printf '%s' "$1" | wl-copy; }
copy_image() { wl-copy --type image/png < "$IMG"; }
copy_file() { printf 'file://%s' "$IMG" | wl-copy; }
screenshot() { mkdir -p "$PRINTS"; grim "$PRINTS/Print_$(date '+%Y-%m-%d_%H.%M.%S').png"; }

activity_progress() {
    for p in 0.05 0.25 0.5 0.75 0.95; do ipc island activity build "Compilando projeto" "cargo build --release" build "$p"; sleep 1.2; done
    ipc island done build "Pronto em 6s"
}
activity_error() { ipc island indeterminate deploy "Deploy" "enviando para o servidor…" rocket_launch; sleep 3; ipc island fail deploy "Falhou: timeout"; }
activity_notify() {
    notify-send -h string:x-island-id:dl -h int:value:30 -h string:x-island-icon:download "Baixando" "archlinux.iso"
    sleep 2; notify-send -h string:x-island-id:dl -h int:value:80 "Baixando" "archlinux.iso"
    sleep 2; notify-send -h string:x-island-id:dl -h string:x-island-state:done "Baixando" "concluído"
}
git_push() { ipc island indeterminate git-demo "git push" "end4-pC" upload; sleep 3; ipc island done git-demo "end4-pC · 3s"; }

# Claude Code: uma sessão de mentira ("meu-projeto") passando pelos mesmos eventos dos hooks reais.
# ISLAND_TEST_TERM é a janela do menu: as opções da pergunta digitam o número nela (inofensivo no fzf).
CLAUDE_SID="ilha-teste-demo"
claude() { ipc claude hook "$1" "$CLAUDE_SID" "$HOME/meu-projeto" "${2:-}" "${3:-0}"; }
claude_work() {
    claude UserPromptSubmit; sleep 0.5
    claude PreToolUse "$(printf 'Read\tDynamicIsland.qml')"; sleep 3.5
    claude PreToolUse "$(printf 'Bash\tRoda os testes')"; sleep 4
    claude PreToolUse "$(printf 'Edit\tClaudeCode.qml')"; sleep 4
    claude Stop "Corrigi o hook e atualizei a ilha de testes."
}
claude_question() {
    claude UserPromptSubmit; sleep 1
    claude PreToolUse "$(printf 'AskUserQuestion\tQual banco de dados usar?\tPostgreSQL\037SQLite\037MySQL')" "${ISLAND_TEST_TERM:-0}"
}
claude_permission() { claude UserPromptSubmit; sleep 3.5; claude PermissionRequest "$(printf 'Bash\tnpm install --global pacote')"; }
# Codex e Gemini: sessões de mentira pelos mesmos eventos dos hooks reais (agent-island.sh)
agent() { ipc claude agent "$1" "$2" "$3" "$HOME/$4" "${5:-}" "${6:-0}"; }
codex_work() {
    agent codex UserPromptSubmit ilha-teste-codex outro-projeto; sleep 0.5
    agent codex PreToolUse ilha-teste-codex outro-projeto "$(printf 'shell\tcargo test')"; sleep 4
    agent codex Stop ilha-teste-codex outro-projeto "$(printf 'Todos os testes passaram.\x1e42,7,3')"
}
gemini_work() {
    agent gemini PreInvocation ilha-teste-gemini site; sleep 0.5
    agent gemini PostToolUse ilha-teste-gemini site "$(printf 'read_file\tindex.html')"; sleep 4
    agent gemini Stop ilha-teste-gemini site "Atualizei o layout da página inicial."
}
agents_waiting() {
    claude UserPromptSubmit; sleep 0.3
    claude PreToolUse "$(printf 'AskUserQuestion\tQual banco de dados usar?\tPostgreSQL\037SQLite')" "${ISLAND_TEST_TERM:-0}"
    agent codex UserPromptSubmit ilha-teste-codex outro-projeto; sleep 0.3
    agent codex PermissionRequest ilha-teste-codex outro-projeto "$(printf 'shell\trm -rf build')"
}
agents_limits() {
    local now; now=$(date +%s)
    ipc claude limits codex 84 $((now + 3600)) 40 $((now + 400000))
    ipc claude demo near
}
agents_end() {
    claude SessionEnd
    agent codex SessionEnd ilha-teste-codex outro-projeto
    agent gemini SessionEnd ilha-teste-gemini site
}
claude_error() { claude UserPromptSubmit; sleep 3.5; claude StopFailure "$(printf "rate_limit\tYou've hit your limit")"; }

# Terminal: comando longo terminando (a saída do erro é um log de exemplo)
cmd_fail() {
    local log=/tmp/quickshell/island/ilha-teste-cmd.log
    mkdir -p "${log%/*}"
    printf '%s\n' "> meu-projeto@1.0.0 build" "> tsc && vite build" "" \
        "src/app.ts(42,7): error TS2322: Type 'string' is not assignable to type 'number'." \
        "src/api/client.ts(18,3): error TS2554: Expected 2 arguments, but got 1." \
        "npm ERR! code ELIFECYCLE" "npm ERR! Failed at the meu-projeto@1.0.0 build script." > "$log"
    ipc island command "cmd-teste-$RANDOM" "npm run build" "meu-projeto · 2min 14s · erro 1" false "$HOME" "npm run build" "${ISLAND_TEST_TERM:-0}" "$log"
}
cmd_ok() { ipc island command "cmd-teste-$RANDOM" "cargo build --release" "meu-projeto · 1min 03s" true "$HOME" "cargo build --release" 0 ""; }

tour() {
    local steps=(
        "notify_image" "notify_group" "copy '#FF9F0A'" "copy_image" "screenshot" "activity_progress"
        "claude_work" "cmd_fail" "ipc island simulate bluetooth" "ipc island simulate headphonesLow"
        "ipc island simulate audioOutput" "ipc island simulate weather" "ipc island simulate wifiWeak"
        "ipc island simulate batteryLow" "ipc island simulate charging" "ipc island simulate songRec"
        "ipc island simulate privacy" "ipc island simulate osd" "ipc island simulate recording"
        "ipc island simulate systemLoad" "ipc shelf add $IMG" "ipc island simulate lights" "ipc island simulate flag"
        "ipc island simulate f1Fastest" "ipc island simulate f1Radio" "notify_critical"
    )
    for s in "${steps[@]}"; do
        notify-send -t 1500 -h string:x-island-id:tour -h string:x-island-icon:tour "Tour da ilha" "$s" 2>/dev/null
        eval "$s"
        sleep 6
    done
    ipc island remove tour
}

# id|categoria|rótulo|dica (uma frase sobre o que testar e como interagir)
ENTRIES=$(cat <<'EOF'
tour|Geral|🎬  Tour completo (passa por tudo sozinho)|Dispara ~26 estados, um a cada 6 s. Só observe a ilha; Esc no menu não interrompe o tour.
notif-imagem|Notificações|🔔  Notificação do WhatsApp com imagem|Notificação com miniatura do último print. Passe o mouse na ilha e clique pra expandir.
notif-pilha|Notificações|📚  Várias notificações da mesma conversa|Três mensagens seguidas do mesmo contato: uma linha só, com contador.
notif-grupo|Notificações|👪  Mensagem de grupo (WhatsApp Web)|Grupo com autor: “Família 🏠  Mãe: Bom dia…”, sem o web.whatsapp.com.
notif-figurinha|Notificações|💟  Figurinha no WhatsApp|Mídia vira ícone + nome (“Figurinha”). Passe o mouse pra ver o botão de responder.
notif-critica|Notificações|🚨  Notificação crítica|Urgência crítica: deve ficar fixa até você fechar. Clique pra dispensar.
notif-acoes|Notificações|💬  Notificação com botões de ação|Notificação com “Responder” e “Depois”. Abra a ilha e clique num botão.
claude-trabalho|Claude Code|✳️  Sessão trabalhando → concluída|Lendo, rodando testes, editando e “Concluído · 12s · resumo”. Clique pra ver a sessão.
claude-pergunta|Claude Code|❓  Pergunta com opções|Ilha âmbar pulsando. Clique: as opções aparecem como botões (digitam o número neste menu).
claude-permissao|Claude Code|✋  Pedido de permissão|“Precisa de permissão: npm install…” em âmbar até mudar.
claude-erro|Claude Code|⛔  Limite de uso atingido|Erro do turno (rate limit) na atividade da sessão.
claude-perto|Claude Code|⚖️  Aviso: agentes perto do limite|Quando dois agentes passam de 80% das 5 h.
claude-limite|Claude Code|⏳  Aviso: limite de 5h em 86%|Aviso com o horário do reset; some sozinho em 12 s.
claude-reset|Claude Code|🔄  Aviso: limite reseta em 12 min|Quando vale a pena esperar em vez de parar.
claude-contexto|Claude Code|📦  Aviso: contexto em 82%|A sessão vai compactar em breve.
claude-encerrar|Claude Code|🚪  Encerrar a sessão de teste|Remove a sessão “meu-projeto” da ilha e da lista.
agente-codex|Agentes de IA|🤖  Codex trabalhando → concluído com diff|“Codex · outro-projeto”, depois “Concluído · +42 −7 · 3 arquivos”. Abra pra ver Ver diff.
agente-gemini|Agentes de IA|✨  Gemini (Antigravity) trabalhando → concluído|Eventos PreInvocation/PostToolUse/Stop do Antigravity.
agentes-esperando|Agentes de IA|🙋  Dois agentes esperando você|Claude com pergunta + Codex pedindo permissão viram “2 agentes esperando você”.
agentes-limites|Agentes de IA|⚖️  Limites: Codex 84% e aviso “perto do limite”|Anel do Codex na lista de agentes e o aviso de quando todos estão perto do limite.
agentes-encerrar|Agentes de IA|🚪  Encerrar sessões de teste|Encerra Claude, Codex e Gemini de teste (ficam em “Encerrada · Retomar”).
hw-monitor|Hardware|🖥️  Monitor conectado|Clique: desenho das telas e Estender / Espelhar / Só o externo (no teste não muda nada).
hw-pendrive|Hardware|💾  Pendrive conectado|Clique: Abrir, Copiar prints de hoje, Ejetar (no teste o dispositivo não existe).
hw-seguro|Hardware|✅  Pendrive pode ser removido|Confirmação depois de ejetar.
hw-dock|Hardware|🔌  Dock conectado|Monitor, rede, USB e energia chegando juntos viram um aviso só.
hw-carregador|Hardware|🐢  Carregador lento|“Carregando a 15 W · vai demorar mais”.
hw-mouse|Hardware|🖱️  Bateria do mouse fraca|Aviso em 15% e de novo em 5%.
hw-controle|Hardware|🎮  Controle conectado|Nome do controle e bateria.
hw-caps|Hardware|⇪  Caps Lock ativado|Aviso rápido e urgente (1,4 s).
hw-layout|Hardware|⌨️  Layout do teclado mudou|Aviso rápido com o código do layout.
hw-retomada|Hardware|🌙  Voltou da suspensão|“Dormiu por 2 h 14 min · Bateria −3%”.
hw-quente|Hardware|🌡️  Notebook esquentando|Temperatura, ventoinha e processo; botões Economia de energia e Ver processos.
cmd-falhou|Terminal|💥  Comando longo que falhou|“npm run build · erro 1”. Clique: Ver saída, Rodar de novo e Ir para o terminal.
cmd-ok|Terminal|✅  Comando longo concluído|“cargo build --release · 1min 03s” com ✓.
copiar-texto|Transferência/prints|📋  Copiar texto|Copia texto pro clipboard. Arraste o chip da ilha ou use converter/guardar.
copiar-link|Transferência/prints|🔗  Copiar link|Copia uma URL. Clique na ilha pra abrir o link.
copiar-youtube|Transferência/prints|▶️  Copiar link do YouTube|Clique na ilha: Baixar vídeo / Baixar áudio (vai pra gaveta).
copiar-pdf|Transferência/prints|📄  Copiar link de PDF|Clique na ilha: Abrir PDF / Guardar na gaveta.
copiar-endereco|Transferência/prints|🗺️  Copiar endereço|Clique na ilha: Abrir no Maps.
copiar-ingles|Transferência/prints|🌐  Copiar texto em inglês|Clique na ilha: Traduzir (mostra a tradução com Copiar).
copiar-cor|Transferência/prints|🎨  Copiar cor (#FF9F0A)|Amostra da cor + HEX, RGB e HSL pra copiar.
copiar-json|Transferência/prints|🧩  Copiar JSON|Formatar ou compactar o JSON.
copiar-telefone|Transferência/prints|📞  Copiar telefone|Abrir a conversa no WhatsApp.
copiar-email|Transferência/prints|✉️  Copiar e-mail|Escrever e-mail.
copiar-rastreio|Transferência/prints|📦  Copiar código de rastreio|Rastrear a encomenda nos Correios.
copiar-imagem|Transferência/prints|🖼️  Copiar imagem|Copia o último print como PNG. Arraste a imagem da ilha pra outro app.
copiar-arquivo|Transferência/prints|📁  Copiar arquivo|Copia o último print como file://. Arraste da ilha pro gerenciador de arquivos.
screenshot|Transferência/prints|📸  Tirar screenshot (salva em Prints)|Tira um print da tela inteira com grim. Veja a prévia aparecer na ilha.
ocr|Transferência/prints|🔤  OCR do último print (copia o texto)|Extrai o texto do último print e copia. Confira o resultado na ilha.
lens|Transferência/prints|🔎  Google Lens do último print|Envia o último print pro Google Lens.
gaveta-guardar|Gaveta|🗄️  Guardar último print na gaveta|Adiciona o último print à gaveta. Passe o mouse e arraste o item pra fora.
gaveta-limpar|Gaveta|🧹  Limpar gaveta|Esvazia a gaveta.
atv-progresso|Atividades|⚡  Atividade com progresso (build)|Barra de progresso em 5 passos até concluir (~6 s). Passe o mouse pra ver detalhes.
atv-notify|Atividades|📨  Atividade via notify-send (download)|Atividade atualizada por notify-send com hints x-island-*: 30%, 80%, concluído.
atv-falha|Atividades|❌  Atividade que falha|Estado indeterminado por 3 s e depois erro de timeout.
atv-git|Atividades|🧾  Git push (simulado)|Atividade indeterminada “git push” que conclui em 3 s.
atv-download|Atividades|⬇️  Download em andamento|Simula um download com a origem (Chrome, playit…). Clique pra ver de onde vem.
timer|Atividades|⏱️  Timer de 1 minuto|Inicia um timer de 1 min. Abra a ilha pra pausar ou cancelar.
f1-largada|F1|🏁  F1: largada (replay)|Replay da última corrida a partir da largada, velocidade 1×.
f1-vsc|F1|🟡  F1: VSC e bandeiras (replay)|Replay em 3× a partir do trecho com VSC e bandeiras.
f1-acelerada|F1|🏎️  F1: corrida acelerada (ultrapassagens)|Replay em 25× pra ver ultrapassagens em sequência.
f1-aovivo|F1|📡  F1: voltar ao vivo|Sai do replay e volta aos dados ao vivo.
f1-pneu|F1|🛞  F1: troca de pneu|Simula um pit stop com troca de pneu.
f1-chuva|F1|🌦️  F1: chuva na pista|Simula alerta de chuva na pista.
f1-resultado|F1|🏆  F1: resultado da sessão|Mostra o pódio/resultado. Abra a ilha pra ver a tabela.
f1-pole|F1|🥇  F1: pole e grid da classificação|“Pole: VER · 1:10.270” com o grid.
f1-volta-rapida|F1|🟣  F1: volta mais rápida|Evento roxo com o tempo da volta.
f1-azul|F1|🔵  F1: bandeira azul pro seu piloto|“Deixe o carro mais rápido passar”.
f1-10voltas|F1|🔟  F1: faltam 10 voltas|Com a posição do seu piloto.
f1-ultima|F1|🏁  F1: última volta|Evento da volta final.
f1-radio|F1|📻  F1: rádio da equipe|Rádio do seu piloto (no teste não há áudio pra tocar).
f1-luzes|F1|🏁  Luzes de largada (animação)|Animação das cinco luzes vermelhas apagando.
f1-bandeira|F1|🚩  Bandeira amarela (animação)|Animação de bandeira amarela.
bat-fraca|Sistema|🔋  Bateria fraca|Aviso de bateria fraca.
bat-critica|Sistema|🪫  Bateria crítica|Aviso de bateria crítica.
carregador|Sistema|🔌  Carregador conectado|Animação de carregador conectado.
carga-80|Sistema|💚  Carga chegou a 80%|Aviso de carga em 80%.
hibernar|Sistema|🌙  Contagem para hibernar (simulada)|Contagem de 60 s com botão Cancelar. Não hiberna de verdade.
bluetooth|Fones|🎧  Fone conectando → conectado (estojo)|Estojo fechado balançando, depois abre. Passe o mouse pra ver a bateria.
fone-bateria|Fones|🔴  Fone com bateria fraca|“Bateria fraca · Liberty 4 NC · carregue no estojo” com a % em destaque.
audio-saida|Fones|🔊  Troca de saída de áudio|Troca da saída de áudio. Clique pra escolher outra.
osd-volume|Sistema|🔈  OSD de volume|OSD de volume. Clique nas laterais pra ±5%.
chuva|Sistema|🌧️  Começou a chover|Alerta de clima: começou a chover.
cpu-alta|Sistema|🔥  CPU alta|Alerta de carga alta de CPU. Abra pra ver os processos.
musica|Sistema|🎵  Música reconhecida|Resultado de reconhecimento de música.
privacidade|Sistema|🎙️  Privacidade (mic + câmera em uso)|Indicadores de microfone e câmera em uso.
gravacao|Sistema|⏺️  Gravação de tela|Indicador de gravação de tela. Clique pra parar.
rede-perdida|Rede|📴  Conexão perdida|Aviso de conexão perdida.
rede-nova|Rede|📶  Nova rede Wi-Fi|Aviso de nova rede Wi-Fi.
wifi-fraco|Rede|📉  Wi-Fi fraco durante chamada/download|Sinal e taxa do link em âmbar.
zerotier|Rede|🛡️  ZeroTier ligado na chamada|Só visual. Atenção: tocar na ilha desliga o ZeroTier de verdade.
visao-geral|Navegação da ilha|🗂️  Visão geral das ilhas ativas|Abre a lista com todas as ilhas ativas e controles rápidos (igual clicar no baralho).
visao-inicio|Navegação da ilha|🏠  Visão principal (foto, fixas, não perturbe)|Abre a visão principal da ilha.
visao-atividades|Navegação da ilha|📋  Visão de atividades e sessões do Claude|Abre a lista de atividades ao vivo com a seção do Claude Code.
rolar-baixo|Navegação da ilha|🖱️  Rolar para baixo na ilha|Nas ativas troca de ilha; na área de transferência fixa passa o histórico; no sistema fixo troca a métrica.
rolar-cima|Navegação da ilha|🖱️  Rolar para cima na ilha|O mesmo que rolar, no sentido contrário.
voltar-principal|Navegação da ilha|🏡  Voltar para a ilha principal|Igual ao botão de casinha que aparece ao lado de uma ilha fixa.
nav-ativa|Navegação da ilha|↕️  Próxima ilha ativa|Alterna pra próxima ilha ativa (igual a rolar sobre a ilha).
nav-fixa|Navegação da ilha|↔️  Próxima ilha fixa|Alterna pra próxima ilha fixada.
nav-fixar|Navegação da ilha|📌  Fixar / desafixar ilha atual|Fixa ou desafixa a ilha exibida agora.
nav-abrir|Navegação da ilha|⬇️  Abrir ilha (clique)|Expande a ilha (nível 2), como um clique.
nav-fechar|Navegação da ilha|⬆️  Fechar ilha|Recolhe a ilha (nível 0).
EOF
)

run() {
    case "$1" in
        tour) tour ;;
        notif-imagem) notify_image ;;
        notif-pilha) notify_stack ;;
        notif-grupo) notify_group ;;
        notif-figurinha) notify_sticker ;;
        notif-critica) notify_critical ;;
        notif-acoes) notify_actions ;;
        claude-trabalho) claude_work ;;
        claude-pergunta) claude_question ;;
        claude-permissao) claude_permission ;;
        claude-erro) claude_error ;;
        claude-perto) ipc claude demo near ;;
        claude-limite) ipc claude demo limit ;;
        claude-reset) ipc claude demo soon ;;
        claude-contexto) ipc claude demo context ;;
        claude-encerrar) claude SessionEnd ;;
        agente-codex) codex_work ;;
        agente-gemini) gemini_work ;;
        agentes-esperando) agents_waiting ;;
        agentes-limites) agents_limits ;;
        agentes-encerrar) agents_end ;;
        hw-monitor) ipc hardware simulate monitor ;;
        hw-pendrive) ipc hardware simulate drive ;;
        hw-seguro) ipc hardware simulate driveSafe ;;
        hw-dock) ipc hardware simulate dock ;;
        hw-carregador) ipc hardware simulate charger ;;
        hw-mouse) ipc hardware simulate peripheral ;;
        hw-controle) ipc hardware simulate controller ;;
        hw-caps) ipc hardware simulate caps ;;
        hw-layout) ipc hardware simulate layout ;;
        hw-retomada) ipc hardware simulate resume ;;
        hw-quente) ipc hardware simulate thermal ;;
        cmd-falhou) cmd_fail ;;
        cmd-ok) cmd_ok ;;
        copiar-texto) copy 'Texto de teste da Ilha Dinâmica — dá pra arrastar, converter e guardar' ;;
        copiar-link) copy 'https://www.formula1.com/en/racing/2026' ;;
        copiar-youtube) copy 'https://www.youtube.com/watch?v=dQw4w9WgXcQ' ;;
        copiar-pdf) copy 'https://www.w3.org/WAI/ER/tests/xhtml/testfiles/resources/pdf/dummy.pdf' ;;
        copiar-endereco) copy 'Av. Paulista, 1578 - Bela Vista, São Paulo - SP, 01310-200' ;;
        copiar-ingles) copy 'The build finished but some tests are still failing on the server' ;;
        copiar-cor) copy '#FF9F0A' ;;
        copiar-json) copy '{"nome":"Ilha","versao":2,"recursos":["clipboard","f1","claude"]}' ;;
        copiar-telefone) copy '(11) 98765-4321' ;;
        copiar-email) copy 'contato@exemplo.com.br' ;;
        copiar-rastreio) copy 'AA123456789BR' ;;
        copiar-imagem) copy_image ;;
        copiar-arquivo) copy_file ;;
        screenshot) screenshot ;;
        ocr) ipc island ocr "$IMG" ;;
        lens) ipc island lens "$IMG" ;;
        gaveta-guardar) ipc shelf add "$IMG" ;;
        gaveta-limpar) ipc shelf clear ;;
        atv-progresso) activity_progress ;;
        atv-notify) activity_notify ;;
        atv-falha) activity_error ;;
        atv-git) git_push ;;
        atv-download) ipc island simulate download ;;
        timer) ipc island simulate timer ;;
        f1-largada) ipc f1 replayFrom latest 1 "00:57:45" ;;
        f1-vsc) ipc f1 replayFrom latest 3 "01:21:05" ;;
        f1-acelerada) ipc f1 replayFrom latest 25 "00:58:00" ;;
        f1-aovivo) ipc f1 live ;;
        f1-pneu) ipc island simulate f1Tyre ;;
        f1-chuva) ipc island simulate f1Rain ;;
        f1-resultado) ipc island simulate f1Result ;;
        f1-pole) ipc island simulate f1Pole ;;
        f1-volta-rapida) ipc island simulate f1Fastest ;;
        f1-azul) ipc island simulate f1Blue ;;
        f1-10voltas) ipc island simulate f1Laps ;;
        f1-ultima) ipc island simulate f1Final ;;
        f1-radio) ipc island simulate f1Radio ;;
        f1-luzes) ipc island simulate lights ;;
        f1-bandeira) ipc island simulate flag ;;
        bat-fraca) ipc island simulate batteryLow ;;
        bat-critica) ipc island simulate batteryCritical ;;
        carregador) ipc island simulate charging ;;
        carga-80) ipc island simulate eighty ;;
        hibernar) ipc island simulate hibernate ;;
        bluetooth) ipc island simulate bluetooth ;;
        fone-bateria) ipc island simulate headphonesLow ;;
        audio-saida) ipc island simulate audioOutput ;;
        osd-volume) ipc island simulate osd ;;
        chuva) ipc island simulate weather ;;
        cpu-alta) ipc island simulate systemLoad ;;
        musica) ipc island simulate songRec ;;
        privacidade) ipc island simulate privacy ;;
        gravacao) ipc island simulate recording ;;
        rede-perdida) ipc island simulate netLost ;;
        rede-nova) ipc island simulate netNew ;;
        wifi-fraco) ipc island simulate wifiWeak ;;
        zerotier) ipc island simulate zerotier ;;
        visao-geral) ipc island open overview ;;
        visao-inicio) ipc island open idle ;;
        visao-atividades) ipc island open activity ;;
        rolar-baixo) ipc island scroll 1 ;;
        rolar-cima) ipc island scroll -1 ;;
        voltar-principal) ipc island home ;;
        nav-ativa) ipc island cycle 1 ;;
        nav-fixa) ipc island cyclePinned 1 ;;
        nav-fixar) ipc island togglePin ;;
        nav-abrir) ipc island setLevel 2 ;;
        nav-fechar) ipc island setLevel 0 ;;
        *) return 1 ;;
    esac
}

label_of() { awk -F'|' -v id="$1" '$1 == id { print $3; exit }' <<<"$ENTRIES"; }

# The terminal window this menu runs in (the Claude question test types its option number there)
terminal_pid() {
    local pid=$1 comm
    for _ in 1 2 3 4 5 6 7 8 9 10 11 12; do
        comm=$(ps -o comm= -p "$pid" 2>/dev/null) || return
        case "$comm" in
            foot|footclient|kitty|alacritty|wezterm-gui|ghostty|konsole|xterm) echo "$pid"; return ;;
        esac
        pid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')
        [[ -n $pid && $pid -gt 1 ]] || return
    done
}

# Dispara em segundo plano, desacoplado do terminal, e registra no log
dispatch() {
    local id=$1 label term
    label=$(label_of "$id")
    [ -n "$label" ] || { echo "id desconhecido: $id" >&2; return 1; }
    term=$(terminal_pid $$)
    ISLAND_TEST_TERM=${term:-0} setsid bash -c '. "$1" --source-only; run "$2"' _ "$SELF" "$id" </dev/null >/dev/null 2>&1 &
    disown 2>/dev/null
    printf '%s  %s\n' "$(date +%H:%M:%S)" "$label" >>"$LOG"
}

header() {
    local last
    last=$(tail -n 3 "$LOG" 2>/dev/null)
    printf 'Enter dispara · digite pra filtrar · Esc sai\n'
    if [ -n "$last" ]; then printf '%s\n' "$last" | sed 's/^/▸ /'; else printf '▸ nenhuma ação disparada ainda\n'; fi
}

# Linhas pro fzf: id|[Categoria] rótulo|dica
fzf_lines() {
    local colors=(33 36 35 32 31 34 96 93) i=0 prev=""
    while IFS='|' read -r id cat label hint; do
        [ "$cat" != "$prev" ] && { i=$(( (i + 1) % ${#colors[@]} )); prev=$cat; }
        printf '%s|\e[%sm%-22s\e[0m %s|%s\n' "$id" "${colors[$i]}" "$cat" "$label" "$hint"
    done <<<"$ENTRIES"
}

menu_fzf() {
    fzf_lines | fzf --ansi --delimiter '|' --with-nth 2 \
        --prompt 'Ilha › ' --reverse --no-sort --cycle \
        --header-first --header "$(header)" \
        --preview 'echo {3}' --preview-window 'down,3,wrap,border-top' \
        --bind "enter:execute-silent('$SELF' --run {1})+transform-header('$SELF' --header)" \
        --bind 'double-click:ignore' >/dev/null
}

menu_select() {
    local ids=() labels=() id cat label hint
    while IFS='|' read -r id cat label hint; do
        ids+=("$id"); labels+=("[$cat] $label")
    done <<<"$ENTRIES"
    PS3=$'\nNúmero da ação (Ctrl-D ou Ctrl-C sai): '
    trap 'echo; exit 0' INT
    while true; do
        select choice in "${labels[@]}"; do
            [ -n "$choice" ] || { echo "Opção inválida"; break; }
            dispatch "${ids[$((REPLY - 1))]}"
            echo "▸ disparado: $choice"
            break
        done || exit 0
        [ -z "$REPLY" ] && exit 0
    done
}

case "$1" in
    --source-only) return 0 2>/dev/null ;;
    tour) tour; exit 0 ;;
    --run) dispatch "$2"; exit $? ;;
    --header) header; exit 0 ;;
    --list) cut -d'|' -f1,3 <<<"$ENTRIES" | tr '|' '\t'; exit 0 ;;
    --janela)
        setsid foot --app-id ilha-teste --title 'Ilha – testes' "$SELF" </dev/null >/dev/null 2>&1 &
        exit 0 ;;
esac

: >"$LOG"
if command -v fzf >/dev/null; then menu_fzf; else menu_select; fi
exit 0
