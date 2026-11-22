# InfiniTypes

Fale do jeito que você pensa e receba um **prompt sólido para a sua IA de codificação**.

Você segura um atalho, explica o que quer em voz alta (com hesitações, voltas e mudanças de ideia) e, ao soltar, o InfiniTypes cola no cursor um prompt limpo, objetivo e estruturado: no Claude Code, no Cursor, no VS Code, no terminal ou em qualquer campo de texto. No celular, o prompt sai pelo teclado de voz ou vai para a área de transferência. Todo ditado fica salvo num histórico local, para você nunca perder o que falou.

> Projeto em fase inicial (0.1). A interface e os prompts estão em português.

## Plataformas

| Plataforma | Situação | Código |
|---|---|---|
| macOS 26+ | ✅ Disponível, em uso diário | [`apple/`](apple) |
| Windows 10 e 11 | 🧪 Beta: compila e passa nos testes na CI; falta o teste num Windows de verdade | [`windows/`](windows) |
| iPhone (iOS 26+) | 🧪 Beta: ditado pela área de transferência, Atalhos, Botão de Ação e Central de Controle | [`apple/InfiniTypesiOS`](apple/InfiniTypesiOS) |
| Android 13+ | 🧪 Beta: teclado de voz, bloco nas Configurações Rápidas e app | [`android/`](android) |

As regras comuns (detector de segredos, filtro de alucinações, escolha do projeto, revisão e montagem da requisição) passam nos mesmos casos de [`shared/conformance`](shared/conformance) em todas as plataformas. O plano e o estado de cada uma estão em [`docs/PLANEJAMENTO.md`](docs/PLANEJAMENTO.md).

## Instalar

No Mac e no Windows, dá para instalar e atualizar pelo terminal. Em todas as plataformas, também dá para baixar o pacote na [página de versões](https://github.com/HelioVieiraSilvaJr/InfiniTypes/releases): abra a versão do topo, a mais recente, e procure os arquivos em **Assets**, no fim dela. Você também vai precisar de uma chave da API da Anthropic (veja [Use a sua própria chave da API](#use-a-sua-própria-chave-da-api)).

Os pacotes ainda não passam pela verificação da Apple, da Microsoft nem do Google, por isso o sistema avisa na primeira abertura. Os passos abaixo mostram como liberar.

### Mac (macOS 26, com chip Apple)

**Pelo terminal, com o [Homebrew](https://brew.sh):**

```bash
brew tap heliovieirasilvajr/tap
brew trust heliovieirasilvajr/tap      # o Homebrew pede para confiar em taps que não são oficiais
brew install --cask infinitypes
```

Depois, siga do passo 3 em diante. Para atualizar, rode `brew upgrade --cask infinitypes`.

**Pelo navegador:**

1. Baixe o `InfiniTypes-macos-<versão>.dmg`.
2. Abra o `.dmg` e arraste o InfiniTypes para a pasta **Aplicativos**. Se já tiver uma versão anterior, substitua.
3. Abra o app. O macOS bloqueia, porque o app ainda não é verificado pela Apple.
4. Vá em **Ajustes → Privacidade e Segurança**, role até o aviso do InfiniTypes e clique em **Abrir Mesmo Assim**.
5. Quando o app pedir, permita o **Microfone** e a **Acessibilidade**.
6. Cole a sua chave da API nas **Preferências**, que abrem sozinhas na primeira vez.
7. Para testar, segure o **⌥ direito**, fale e solte. Na primeira vez, o app baixa o modelo de voz (cerca de 630 MB).

O app fica no ícone da barra de menus, no topo da tela.

### Windows (10 ou 11)

**Pelo terminal, com o [Scoop](https://scoop.sh):**

```powershell
scoop bucket add infinitypes https://github.com/HelioVieiraSilvaJr/scoop-bucket
scoop install infinitypes
```

Depois, abra o InfiniTypes pelo menu Iniciar e siga do passo 4 em diante. Para atualizar, feche o app e rode `scoop update` e depois `scoop update infinitypes`.

**Pelo navegador:**

1. Baixe o `.zip` do seu PC:
   - `InfiniTypes-windows-x64.zip` para a maioria dos PCs, com processador Intel ou AMD.
   - `InfiniTypes-windows-arm64.zip` para PCs com processador ARM, como o Snapdragon.
2. Clique com o botão direito no `.zip`, escolha **Extrair tudo** e extraia para uma pasta sua, como `Documentos\InfiniTypes`. Se já tiver uma versão anterior, extraia por cima.
3. Abra o `InfiniTypes.exe` dentro dessa pasta.
4. No aviso do SmartScreen, clique em **Mais informações → Executar assim mesmo**. O aviso aparece porque o app ainda não é assinado.
5. Cole a sua chave da API nas **Preferências**, que abrem sozinhas na primeira vez. Enquanto isso, o app baixa o modelo de voz (cerca de 550 MB).
6. Para testar, segure o **Ctrl direito**, fale e solte.

O app fica no ícone da área de notificação, perto do relógio. Se o microfone não funcionar, libere-o para apps da área de trabalho em **Configurações → Privacidade e segurança → Microfone**.

### Android (13 ou mais novo)

1. No celular, baixe o `InfiniTypes-android-<versão>.apk` e abra o arquivo.
2. Permita a instalação de apps desconhecidos quando o Android pedir.
3. Se já tiver uma versão anterior, desinstale-a antes. O APK ainda tem assinatura de testes, então não instala por cima. Desinstalar apaga a chave da API e o histórico do app.
4. No app, cole a sua chave da API em **Ajustes**.

Para ditar pelo teclado ou pelo bloco das Configurações Rápidas, veja [`android/README.md`](android/README.md).

### iPhone

Não há pacote: o app é instalado pelo Mac, a partir do código (veja [Compilar o app do iPhone](#compilar-o-app-do-iphone)).

### Problemas comuns

- **Mac: "Conceda as permissões" com o Microfone e a Acessibilidade já ligados.** A permissão de Acessibilidade fica presa à assinatura do app que a recebeu. Em **Ajustes → Privacidade e Segurança → Acessibilidade**, selecione o InfiniTypes, remova com o botão **−** e permita de novo pelo app. Se um build novo for instalado com o app aberto, o app se reabre sozinho no próximo atalho.
- **Mac: "Não foi possível verificar" ao abrir o app baixado.** Em **Ajustes → Privacidade e Segurança**, clique em **Abrir Mesmo Assim**.
- **Windows: o SmartScreen bloqueia o app.** O app ainda não é assinado: **Mais informações → Executar assim mesmo**.
- **Android: o teclado InfiniTypes não aparece.** Ative-o em **Configurações → Sistema → Teclado** (o nome do menu muda de fabricante para fabricante), ou pelo botão **Ativar** nos Ajustes do app.

## Como funciona

1. **Transcrição local.** A fala vira texto no próprio aparelho: Whisper com o [WhisperKit](https://github.com/argmaxinc/WhisperKit) no Mac e no iPhone, com o [Whisper.net](https://github.com/sandrohanea/whisper.net) no Windows e o reconhecimento offline do próprio Android. O áudio não sai do aparelho.
2. **Refinamento com o Claude.** A transcrição vai para a API da Anthropic, que remove vícios de fala, organiza as ideias e devolve o prompt. Você escolhe o modelo (Opus, Sonnet, Haiku ou Fable).
3. **Entrega.** O texto é colado no campo em foco. Nada é enviado por você: o Enter é sempre seu. Se não houver campo de texto, o resultado fica no histórico, pronto para copiar.

### Atalhos

| Ação | macOS | Windows |
|---|---|---|
| Ditar um prompt | Segurar o **⌥ direito** | Segurar o **Ctrl direito** |
| Ditar só limpando a fala, sem reestruturar | Segurar o **⌘ direito** | Segurar o **Shift direito** |
| Revisar o texto selecionado por voz | Um toque rápido e segurar o **⌥ direito** | Um toque rápido e segurar o **Ctrl direito** |
| Ditar sem segurar (mãos livres) | Dois toques no **⌘ direito**; um toque termina | Dois toques no **Shift direito**; um toque termina |
| Cancelar o ditado | Outra tecla enquanto segura, ou Esc | Outra tecla enquanto segura, ou Esc |

No Windows o Alt direito fica de fora: no teclado ABNT2 ele é o AltGr. No iPhone e no Android, o ditado é por toque: grava até você tocar em parar.

O histórico, as preferências e o glossário (termos do seu projeto, para a transcrição acertar nomes como `useAuthStore`) ficam no menu do ícone na barra de menus.

## Use a sua própria chave da API

O InfiniTypes não tem servidor nem assinatura. Cada pessoa usa a **própria chave da API da Anthropic**:

1. Crie uma chave em [console.anthropic.com](https://console.anthropic.com/settings/keys).
2. Cole a chave nas **Preferências** do app (**Ajustes**, no celular), que abrem sozinhas no primeiro uso.

A chave fica no cofre de senhas do sistema (Keychain, Gerenciador de Credenciais do Windows ou Android Keystore) e só é enviada para `api.anthropic.com`. O custo vai para a sua conta da Anthropic: com o Sonnet 5.5, um ditado típico custa menos de US$ 0,01 (estimativas por modelo em [`docs/PLANEJAMENTO.md`](docs/PLANEJAMENTO.md#10-custo-estimado)).

## Privacidade

- **Fica no seu aparelho:** o áudio, o histórico, o glossário e o modelo de voz. No Android, o reconhecimento pela rede só é usado se você permitir, nos aparelhos sem reconhecimento offline.
- **Vai para a Anthropic:** o texto transcrito, o glossário do projeto e o contexto da janela (nome do app e título da janela). No modo de revisão, também o texto selecionado. Antes de enviar uma seleção, o app bloqueia textos com chaves e senhas conhecidas.
- **Permissões do macOS:** o microfone, só enquanto você dita, e a Acessibilidade, para detectar o atalho, ler a seleção e colar o resultado. Detalhes de cada plataforma em [`SECURITY.md`](SECURITY.md).

## Compilar a partir do código

Para ter a versão mais recente do código, compile você mesmo. A CI também gera pacotes do Windows e do Android a cada commit (aba **Actions** → execução mais recente da plataforma → **Artifacts**; é preciso estar logado no GitHub).

Primeiro, baixe o código:

```bash
git clone https://github.com/HelioVieiraSilvaJr/InfiniTypes.git
cd InfiniTypes
```

### Compilar o app do Mac

Requer macOS 26, [Xcode 26](https://apps.apple.com/app/xcode/id497799835) e o [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```bash
cd apple
make install   # compila e instala em /Applications/InfiniTypes.app
```

Na primeira abertura, o app pede o **Microfone** e a **Acessibilidade**. Depois, cole a chave da API nas Preferências, no menu do ícone na barra de menus. Na primeira transcrição, o app baixa o modelo de voz (~630 MB).

`make run` é para o desenvolvimento: abre o build da pasta `apple/build/` sem tocar na cópia de /Applications.

Para o macOS manter as permissões de um build para o outro, assine com o seu time da Apple (uma conta gratuita serve): veja [Assinatura em `CONTRIBUTING.md`](CONTRIBUTING.md#assinatura). Para instalar em outro Mac, `make dmg` gera o instalador em `apple/dist/`; no outro Mac, a primeira abertura pede **Ajustes → Privacidade e Segurança → Abrir Mesmo Assim**.

### Compilar o app do iPhone

Requer um Mac com o Xcode 26 e o XcodeGen, um iPhone com iOS 26 e o [Modo de Desenvolvedor](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device) ligado, e o seu time da Apple em `apple/Config/Signing.local.xcconfig` (veja [Assinatura](CONTRIBUTING.md#assinatura)). Com uma conta gratuita, o app instalado vale por 7 dias; depois, é só instalar de novo.

```bash
cd apple
make ios-run                                     # no simulador
make ios-device IOS_DEVICE="iPhone de Fulano"    # no aparelho pareado (nome em: xcrun devicectl list devices)
```

### Compilar o app do Windows

Requer Windows 10 ou 11. Para compilar, instale o [SDK do .NET 10](https://dotnet.microsoft.com/download) e o Git (`winget install Microsoft.DotNet.SDK.10 Git.Git`) e rode no PowerShell:

```powershell
cd windows
dotnet publish src\InfiniTypes -c Release -r win-x64 --self-contained -o publish   # win-arm64 nos PCs ARM
.\publish\InfiniTypes.exe
```

O pacote pronto da CI é o `InfiniTypes-windows`, com um `.zip` para x64 e outro para ARM64. Detalhes, SmartScreen e onde ficam os dados: [`windows/README.md`](windows/README.md).

### Compilar o app do Android

Requer Android 13 ou mais novo. O pacote pronto da CI é o `InfiniTypes-android`, com o APK. Para compilar, instale o JDK 17 e o [SDK do Android](https://developer.android.com/studio) (o Android Studio já traz os dois) e rode:

```bash
cd android
echo "sdk.dir=$HOME/Library/Android/sdk" > local.properties   # caminho do seu SDK
./gradlew :app:assembleDebug
adb install app/build/outputs/apk/debug/app-debug.apk         # aparelho com Depuração USB, ou emulador aberto
```

Também dá para abrir a pasta `android/` no Android Studio e usar o botão Run. Primeiros passos no aparelho: [`android/README.md`](android/README.md).

Assinatura, instalador do Mac e notarização: [`CONTRIBUTING.md`](CONTRIBUTING.md) e [`docs/DISTRIBUICAO.md`](docs/DISTRIBUICAO.md).

## Estrutura do repositório

```
apple/     apps do macOS e do iPhone (Swift, SwiftUI, XcodeGen), com o código comum em InfiniTypesCore
windows/   app do Windows (C#, .NET 10, WPF)
android/   app do Android (Kotlin, Jetpack Compose)
shared/    prompts e casos de conformidade, usados por todas as plataformas
docs/      planejamento e distribuição
```

## Contribuir

Contribuições são bem-vindas. Veja [`CONTRIBUTING.md`](CONTRIBUTING.md). Para relatar uma vulnerabilidade, siga [`SECURITY.md`](SECURITY.md), sem abrir issue pública.

## Licença

[MIT](LICENSE).
