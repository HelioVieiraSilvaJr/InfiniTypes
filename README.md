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

## Instalar

**Pacotes prontos:** a [última versão](https://github.com/HelioVieiraSilvaJr/InfiniTypes/releases/latest) traz o `.dmg` do Mac, os `.zip` do Windows e o APK do Android, com as instruções de cada um. O iPhone não tem pacote: o app é instalado a partir do código, pelo Mac.

Os pacotes ainda não passam pela verificação da Apple nem da Microsoft, por isso o sistema avisa na primeira abertura (veja [Problemas comuns](#problemas-comuns)). Para ter a versão mais recente do código, compile você mesmo. A CI também gera pacotes do Windows e do Android a cada commit (aba **Actions** → execução mais recente da plataforma → **Artifacts**; é preciso estar logado no GitHub).

Para compilar, primeiro baixe o código:

```bash
git clone https://github.com/HelioVieiraSilvaJr/InfiniTypes.git
cd InfiniTypes
```

### macOS

Requer macOS 26, [Xcode 26](https://apps.apple.com/app/xcode/id497799835) e o [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```bash
cd apple
make install   # compila e instala em /Applications/InfiniTypes.app
```

Na primeira abertura, o app pede o **Microfone** e a **Acessibilidade**. Depois, cole a chave da API nas Preferências, no menu do ícone na barra de menus. Na primeira transcrição, o app baixa o modelo de voz (~630 MB).

`make run` é para o desenvolvimento: abre o build da pasta `apple/build/` sem tocar na cópia de /Applications.

Para o macOS manter as permissões de um build para o outro, assine com o seu time da Apple (uma conta gratuita serve): veja [Assinatura em `CONTRIBUTING.md`](CONTRIBUTING.md#assinatura). Para instalar em outro Mac, `make dmg` gera o instalador em `apple/dist/`; no outro Mac, a primeira abertura pede **Ajustes → Privacidade e Segurança → Abrir Mesmo Assim**.

### iPhone

Requer um Mac com o Xcode 26 e o XcodeGen, um iPhone com iOS 26 e o [Modo de Desenvolvedor](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device) ligado, e o seu time da Apple em `apple/Config/Signing.local.xcconfig` (veja [Assinatura](CONTRIBUTING.md#assinatura)). Com uma conta gratuita, o app instalado vale por 7 dias; depois, é só instalar de novo.

```bash
cd apple
make ios-run                                     # no simulador
make ios-device IOS_DEVICE="iPhone de Fulano"    # no aparelho pareado (nome em: xcrun devicectl list devices)
```

### Windows

Requer Windows 10 ou 11. Para compilar, instale o [SDK do .NET 10](https://dotnet.microsoft.com/download) e o Git (`winget install Microsoft.DotNet.SDK.10 Git.Git`) e rode no PowerShell:

```powershell
cd windows
dotnet publish src\InfiniTypes -c Release -r win-x64 --self-contained -o publish   # win-arm64 nos PCs ARM
.\publish\InfiniTypes.exe
```

O pacote pronto da CI é o `InfiniTypes-windows`, com um `.zip` para x64 e outro para ARM64. Detalhes, SmartScreen e onde ficam os dados: [`windows/README.md`](windows/README.md).

### Android

Requer Android 13 ou mais novo. O pacote pronto da CI é o `InfiniTypes-android`, com o APK. Para compilar, instale o JDK 17 e o [SDK do Android](https://developer.android.com/studio) (o Android Studio já traz os dois) e rode:

```bash
cd android
echo "sdk.dir=$HOME/Library/Android/sdk" > local.properties   # caminho do seu SDK
./gradlew :app:assembleDebug
adb install app/build/outputs/apk/debug/app-debug.apk         # aparelho com Depuração USB, ou emulador aberto
```

Também dá para abrir a pasta `android/` no Android Studio e usar o botão Run. Primeiros passos no aparelho: [`android/README.md`](android/README.md).

### Problemas comuns

- **Mac: "Conceda as permissões" com o Microfone e a Acessibilidade já ligados.** A permissão de Acessibilidade fica presa à assinatura do app que a recebeu. Em **Ajustes → Privacidade e Segurança → Acessibilidade**, selecione o InfiniTypes, remova com o botão **−** e permita de novo pelo app. Se um build novo for instalado com o app aberto, o app se reabre sozinho no próximo atalho.
- **Mac: "Não foi possível verificar" ao abrir o app baixado.** Em **Ajustes → Privacidade e Segurança**, clique em **Abrir Mesmo Assim**.
- **Windows: o SmartScreen bloqueia o app.** O app ainda não é assinado: **Mais informações → Executar assim mesmo**.
- **Android: o teclado InfiniTypes não aparece.** Ative-o em **Configurações → Sistema → Teclado** (o nome do menu muda de fabricante para fabricante), ou pelo botão **Ativar** nos Ajustes do app.

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
