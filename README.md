# SketchyBar config

Configuração pessoal para macOS 27 em Apple Silicon. A faixa opaca e arredondada cobre apenas o conteúdo à esquerda e os menus nativos. O lado direito fica livre.

- Apple, Spaces nativos e ícone/título da janela em foco.
- Barra de 32 pt, fundo de 28 pt, margem superior de 4 pt e raio de 8 pt, sem transparência ou blur.
- Deslizamento vertical de 32 pt com curva `sin`, 16 frames (~267 ms) e debounce de retorno de 150 ms.
- App, título, menus e Spaces são lidos pelo **SketchyBar Helper**, sem Hammerspoon.

## Instalação

Requer Homebrew em `/opt/homebrew` e Command Line Tools (`xcode-select --install`).

```sh
brew install FelixKratz/formulae/sketchybar
# Com ~/.config/sketchybar livre:
git clone https://github.com/dsbraz/sketchybar-config.git ~/.config/sketchybar
cd ~/.config/sketchybar
bash build-toggle.sh
brew services start sketchybar
```

Em **Ajustes do Sistema → Privacidade e Segurança → Acessibilidade** (nesta versão do macOS, **Device Control and Data Access**), habilite **SketchyBar Helper**. Se necessário, adicione `~/.config/sketchybar/bin/SketchyBar Helper.app`. O app é local, sem janela ou ícone no Dock, e inicia pelo `sketchybarrc`. Após recompilar, o macOS pode exigir renovar a autorização da assinatura local: remova a entrada antiga e adicione novamente o bundle atual. Se a chave estiver ligada mas o helper continuar sem acesso, `tccutil reset Accessibility com.dsbraz.sketchybar.helper` limpa somente essa autorização; recarregue a barra e habilite a entrada nova.

Mantenha a barra de menus nativa sempre visível: ela reserva o espaço das janelas. Ative “As telas têm Spaces separados”. Para aplicar mudanças: `sketchybar --reload`.

## Integração nativa

O helper deriva de [malpern/sketchybar-toggle](https://github.com/malpern/sketchybar-toggle), com alterações locais descritas em `src/sketchybar-toggle/LOCAL-CHANGES.md`.

- **Comunicação:** protocolo Mach da SketchyBar, com argumentos separados por NUL; títulos não passam pelo shell. Recebe `space_change`, `display_change` e `system_woke` via `mach_helper`.
- **Menus:** AppKit e Accessibility observam app/janela/título; reconciliação a cada 250 ms cobre notificações ausentes. Crescimento imediato, redução após 400 ms estáveis; título e cobertura são enviados juntos. Não há cache por aplicativo.
- **Spaces:** consulta somente leitura a `SLSCopyManagedDisplaySpaces` (SkyLight), sem modificar SIP. Mantém os índices Mission Control usados pela SketchyBar e verifica a topologia a cada 2 s para detectar desktops criados/removidos. Slots de tela cheia não recebem item, mas continuam contando na associação dos índices.
- **Falhas:** IPC limita envio a 100 ms e resposta a 200 ms, resolve novamente a porta em cada pedido e mantém o último layout válido se a descoberta de Spaces falhar. Sem Acessibilidade, Spaces e animação continuam funcionando; o título usa o nome do app enquanto a permissão não for concedida.

SkyLight é uma API privada do macOS: a descoberta de Spaces precisa ser revalidada em futuras atualizações do sistema. Eventos nativos reduzem intermediários, mas não garantem que o macOS exponha a geometria antes de desenhar os menus.

## Validação

```sh
swift test --package-path src/sketchybar-toggle
bin/sketchybar-toggle --probe-native-menu
bin/sketchybar-toggle --probe-native-spaces
```

As sondagens pelo terminal usam o contexto de permissão do terminal; valide também o helper iniciado pela própria barra. O log de inicialização fica em `/private/tmp/sketchybar-toggle.log`.

Scripts de CPU/GPU e mídia permanecem disponíveis no repositório como componentes opcionais, mas não fazem parte do layout ativo. `install.sh` também prepara esses componentes. Binários e o bundle `.app` são gerados localmente e não são versionados.
