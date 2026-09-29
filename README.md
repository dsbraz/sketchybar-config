# SketchyBar config

Configuração pessoal para macOS 27 em Apple Silicon. Uma faixa compacta com blur à esquerda cobre os menus: 6 pt de recuo lateral, 2 pt do topo, 30 pt de altura e cantos de 10 pt. A borda inferior fica em 32 pt, alinhada ao fim do notch do monitor integrado. O espaço de 2 pt existe somente no topo (4 pixels físicos em Retina 2×). Cada monitor mantém a largura do menu medido quando recebe foco, com 12 pt de margem e limite na borda do monitor. O lado direito fica livre para os itens nativos do macOS.

- Apple alinhada horizontalmente à maçã nativa e centralizada no fundo, Spaces claros com seleção apenas pelo fundo neutro e ícone e texto `App — título da janela` do aplicativo ativo.
- Fonte do sistema em semibold; o título da janela recebe reticências quando necessário, priorizando o nome do app.
- Fundo `0x33242426` (80% de transparência), blur 30, cantos arredondados e contorno discreto. Desenhado pela própria SketchyBar; nenhum painel de material nativo é criado.
- Largura independente por monitor, medida por evento de app/janela e eventos AX de menu disponíveis, sem polling ou cache por app. O fim mínimo é 320 pt para preservar espaço para o conteúdo. Antes da primeira medição de uma tela, usa o limite próximo ao notch ou ao centro do monitor.
- Deslizamento vertical de 32 pt com curva `sin`, 16 frames (~267 ms) e debounce de retorno de 150 ms. Reaparecer não reaplica estilos dos itens.
- App, mouse e Spaces reagem a eventos pelo **SketchyBar Helper**, sem Hammerspoon e sem polling. O fundo só é redimensionado quando a medida muda. Crescimentos são imediatos; reduções mantêm a cobertura anterior por 250 ms e aplicam apenas a última largura numa única etapa, junto com nome, título e ícone do app na mesma transação Mach. Durante essa espera, atualizações independentes de nome/ícone ficam retidas; uma troca rápida invalida o envio pendente anterior. A espera é acionada por evento, sem polling.
- CPU/GPU, data e relógio não fazem parte do layout ativo; seus scripts ficam disponíveis para uso futuro.

## Instalação

Requer Homebrew em `/opt/homebrew` e Command Line Tools (`xcode-select --install`).

```sh
brew install FelixKratz/formulae/sketchybar
# Com ~/.config/sketchybar livre:
git clone https://github.com/dsbraz/sketchybar-config.git ~/.config/sketchybar
cd ~/.config/sketchybar
mkdir -p bin
clang -O2 -Wall -Wextra src/system_usage.c -framework IOKit -framework CoreFoundation -o bin/system_usage
bash build-toggle.sh
brew services start sketchybar
```

Em **Ajustes do Sistema → Privacidade e Segurança → Acessibilidade** (nesta versão do macOS, **Device Control and Data Access**), habilite **SketchyBar Helper**. Se necessário, adicione `~/.config/sketchybar/bin/SketchyBar Helper.app`. O app é local, sem janela ou ícone no Dock, e inicia pelo `sketchybarrc`. Após recompilar, o macOS pode exigir renovar a autorização da assinatura local: remova a entrada antiga e adicione novamente o bundle atual. Se a chave estiver ligada mas o helper continuar sem acesso, `tccutil reset Accessibility com.dsbraz.sketchybar.helper` limpa somente essa autorização; recarregue a barra e habilite a entrada nova.

Mantenha a barra de menus nativa sempre visível: ela reserva o espaço das janelas. Ative “As telas têm Spaces separados”. Para aplicar mudanças: `sketchybar --reload`.

## Integração nativa

O helper deriva de [malpern/sketchybar-toggle](https://github.com/malpern/sketchybar-toggle), com alterações locais descritas em `src/sketchybar-toggle/LOCAL-CHANGES.md`.

- **Comunicação:** protocolo Mach da SketchyBar, com argumentos separados por NUL; nomes não passam pelo shell. Recebe `space_change`, `display_change` e `system_woke` via `mach_helper`.
- **App e janela:** o nome vem de `NSWorkspace.frontmostApplication.localizedName`; o título vem da janela focada via AX. Exibe `App — título`, priorizando o nome do app e recortando o título com reticências. Título vazio ou igual ao nome não é repetido; sem espaço para o complemento, mostra só o app. Alterações internas de título são agrupadas por até 1 s em uma tarefa única acionada por eventos; troca de app/janela usa o caminho imediato, respeitando a sincronização com o fundo. Spinner Braille inicial é omitido. Nome/título/largura iguais reutilizam o recorte atual, e mudanças sem efeito visual não reenviam texto ou ícone.
- **Menus:** AX continua observando troca/criação de janela e eventos de menu suportados. App/janela, Spaces, despertar e reaparecimento medem apenas os itens superiores do menu, sem percorrer submenus. As coordenadas AX associam a medida ao monitor correto; as outras telas preservam seu estado. Sem cache por app ou polling. Telas desconectadas perdem a medida; após conectar/reiniciar, usam a faixa de reserva até receber foco. Notificações AX de menu/layout dependem do app. O blur é aplicado à própria superfície da SketchyBar; não consulta metadados de janelas para ordenar painéis adicionais.
- **Spaces:** consulta somente leitura a `SLSCopyManagedDisplaySpaces` (SkyLight), sem modificar SIP. Uma sondagem inicial cria os itens antes do primeiro `--update`, para associá-los aos monitores. Depois mantém os índices Mission Control usados pela SketchyBar e atualiza a topologia nos eventos de Spaces, monitores e despertar. Slots de tela cheia não recebem item, mas continuam contando na associação dos índices.
- **Mouse:** monitores passivos `NSEvent` recebem movimentos e cliques; não há timer de consulta do cursor nem captura de teclado.
- **Texto:** usa a largura disponível até 16 pt antes do fim da faixa, respeitando o menor espaço entre os monitores. O nome do app tem prioridade; somente se ele próprio exceder o espaço físico será abreviado. Não há rolagem de texto.
- **Falhas:** IPC limita envio a 100 ms e resposta a 200 ms, resolve novamente a porta em cada pedido e mantém o último layout válido se a descoberta de Spaces falhar. Sem Acessibilidade, o fundo, Spaces e animação continuam funcionando; o nome do app continua disponível pelo AppKit; a cobertura usa a faixa de reserva até poder medir os menus.

SkyLight é uma API privada do macOS: a descoberta de Spaces precisa ser revalidada em futuras atualizações do sistema.

## Validação

```sh
swift test --package-path src/sketchybar-toggle
bin/sketchybar-toggle --probe-native-app
bin/sketchybar-toggle --probe-native-spaces
```

As sondagens pelo terminal usam o contexto de permissão do terminal; valide também o helper iniciado pela própria barra. O log de inicialização fica em `/private/tmp/sketchybar-toggle.log`.

Os indicadores opcionais CPU/GPU usam o coletor local `system_usage`: CPU por amostra de 250 ms e GPU via IOKit. O modo `--normalized` entrega valores entre 0 e 1, e o plugin envia ambos os gráficos numa única chamada, sem processos `awk`. Valores repetidos continuam avançando o histórico. GPU indisponível não gera amostra artificial de zero. A integração de mídia permanece opcional e fora do layout ativo. `install.sh` também prepara esse componente. Binários e o bundle `.app` são gerados localmente e não são versionados.

### Histórico de comparação visual e de consumo

Amostras locais de 20 s, com menus por evento e atividade real de títulos: helper com blur nativo **1,15% de um núcleo / 13,8 MiB de footprint físico**; fundo sólido **0,70% / ~8,9 MiB**. SketchyBar: **0,90% vs 0,85%**. São amostras curtas, não um benchmark controlado nem uma medida completa do custo no WindowServer/GPU. Naquela etapa, o opaco foi escolhido por priorizar consumo. A comparação ocorreu antes do ajuste de estado independente por monitor e da redução diferida. Uma amostra posterior, com apenas o monitor integrado conectado, registrou helper em 1,10% / ~8,4 MiB e SketchyBar em 0,55%; a variação de CPU impede atribuir toda a diferença ao blur.

Após agrupar eventos internos de título por 1 s, omitir spinner Braille inicial e reutilizar o recorte do título atual: três amostras de 30 s com um monitor registraram CPU combinada de **0,166%, 0,732% e 0,166%** (média **0,355% de um núcleo**), contra média anterior **1,364%**. Médias por processo: helper **0,321%**, SketchyBar **0,033%**. Footprint físico observado: helper **~8,3 MiB**, SketchyBar **28,3 MiB**. Redução observada de aproximadamente **74%** na média; atividade variável, não um benchmark controlado. Trocas de app/janela continuam fora dessa espera de 1 s; a sincronização existente com o fundo permanece.

Com o **nome do aplicativo**, sem leitura nem observação dos títulos das janelas: três amostras de 30 s com um monitor registraram CPU combinada de **0,000%, 0,599% e 0,965%** (média **0,521% de um núcleo**). Médias por processo: helper **0,377%**, SketchyBar **0,144%**. Footprint físico observado: helper **~7,7 MiB**, SketchyBar **28,3 MiB**. A atividade variável não permite afirmar redução adicional de CPU em relação aos 0,355% da rodada anterior. Um perfil posterior de 5 s encontrou apenas threads esperando eventos; não capturou os picos. O valor 0,000% é a leitura na resolução da amostra, não uma garantia de custo zero.

Com **app + título**, ainda com fundo opaco: três amostras de 30 s registraram CPU combinada de **0,233%, 0,997% e 0,166%** (média **0,465% de um núcleo**) e footprint físico total de **~37,7 MiB**. As rodadas ocorreram em momentos distintos, sem controlar a atividade; não isolam o custo adicional do título. Na conferência visual, a faixa do Ghostty tinha 371 pt e quase nenhum espaço para o complemento; a do Chrome tinha 629 pt e mostrava uma parte útil do título da página. A combinação foi mantida por esse benefício.

O blur da própria SketchyBar foi adotado após confirmação visual de cobertura e cantos no monitor integrado. Duas amostras válidas de 15 s por opção registraram barra + helper em média 0,232% no opaco e 0,332% com 80% de transparência/blur 30. WindowServer global: 25,107% e 32,641%. Atividade variável e trocas de app invalidaram outros intervalos; os valores não isolam o custo gráfico do efeito. GPU/bateria não foram medidas. Esse blur não é o material Liquid Glass nativo.
