# SketchyBar config

Configuração pessoal para macOS 27 em Apple Silicon, com fonte nativa em negrito e fundo translúcido.

- Spaces nativos atualizados dinamicamente e título/ícone do app em foco à esquerda.
- Now Playing sem ações de mouse; mostra a sessão selecionada pelo sistema.
- CPU, MEM e SSD com ícones da JetBrainsMono Nerd Font de 11 pt e percentuais de 8 pt abaixo, centralizados.
- Data abreviada em português e horário à direita.
- SketchyBar cede o topo à barra nativa com `sketchybar-toggle` (debounce de 300 ms).

## Instalação

Requer Homebrew em `/opt/homebrew`, Command Line Tools (`xcode-select --install`) e Hammerspoon aberto com permissão de Acessibilidade. A configuração atual usa o `jq` fornecido pelo macOS em `/usr/bin/jq`.

```sh
brew install FelixKratz/formulae/sketchybar malpern/tap/sketchybar-toggle
brew install --cask hammerspoon
```

No Hammerspoon, habilite o IPC e instale o comando `hs` (uma vez pelo console):

```lua
require("hs.ipc")
hs.ipc.cliInstall("/opt/homebrew")
```

Mantenha `require("hs.ipc")` no seu `~/.hammerspoon/init.lua` e recarregue o Hammerspoon. Minha configuração está em [hammerspoon-config](https://github.com/dsbraz/hammerspoon-config).

Com `~/.config/sketchybar` livre (faça backup se já existir):

```sh
git clone https://github.com/dsbraz/sketchybar-config.git ~/.config/sketchybar
cd ~/.config/sketchybar
./install.sh
brew services start sketchybar
```

O instalador compila `system_usage` e baixa o [sketchybar-now-playing](https://github.com/wthrajat/sketchybar-now-playing) v0.4.3, verificando o SHA-256 do pacote. Os binários não são versionados. A licença MIT do helper está em `bin/sketchybar-now-playing.LICENSE`.

Ative a opção de ocultar automaticamente a barra de menus nativa no macOS. Para aplicar alterações posteriores: `sketchybar --reload`.

## Métricas e limites

CPU usa uma amostra de 250 ms a cada 5 segundos. MEM estima memória de apps, wired e comprimida. SSD indica a porcentagem ocupada do contêiner APFS compartilhado, atualizada a cada minuto; não representa atividade de leitura/escrita.

A barra usa altura de 30 pt (33 pt na tela com notch), opacidade de aproximadamente 15% e blur 10. As colunas das métricas têm largura fixa para manter o alinhamento.

Spaces e título da janela dependem do Hammerspoon. O layout considera os monitores conectados, mas a validação visual foi feita na tela interna. A integração de mídia e a fonte nativa dependem do comportamento do macOS.
