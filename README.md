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
2. Cole a chave em **Preferências → Geral** no primeiro uso.

A chave fica no cofre de senhas do sistema (Keychain, Gerenciador de Credenciais do Windows ou Android Keystore) e só é enviada para `api.anthropic.com`. O custo vai para a sua conta da Anthropic: com o Sonnet 5.5, um ditado típico custa menos de US$ 0,01 (estimativas por modelo em [`docs/PLANEJAMENTO.md`](docs/PLANEJAMENTO.md#10-custo-estimado)).

## Privacidade

- **Fica no seu aparelho:** o áudio, o histórico, o glossário e o modelo de voz. No Android, o reconhecimento pela rede só é usado se você permitir, nos aparelhos sem reconhecimento offline.
- **Vai para a Anthropic:** o texto transcrito, o glossário do projeto e o contexto da janela (nome do app e título da janela). No modo de revisão, também o texto selecionado. Antes de enviar uma seleção, o app bloqueia textos com chaves e senhas conhecidas.
- **Permissões do macOS:** o microfone, só enquanto você dita, e a Acessibilidade, para detectar o atalho, ler a seleção e colar o resultado. Detalhes de cada plataforma em [`SECURITY.md`](SECURITY.md).

## Instalar

Ainda não há versão publicada nas Releases.

**macOS** (requer macOS 26 e Xcode 26; na primeira transcrição, o app baixa o modelo de voz, ~630 MB):

```bash
brew install xcodegen
git clone https://github.com/HelioVieiraSilvaJr/InfiniTypes.git
cd InfiniTypes/apple
make run
```

**iPhone:** `make ios-run` abre no simulador. Para o aparelho, abra `apple/InfiniTypes.xcodeproj` no Xcode, escolha o esquema `InfiniTypesiOS` e o seu time em Signing & Capabilities.

**Windows:** baixe o `.zip` da última execução da CI "Windows" e siga [`windows/README.md`](windows/README.md).

**Android:** baixe o APK da última execução da CI "Android" e siga [`android/README.md`](android/README.md).

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
