# InfiniTypes

Fale do jeito que você pensa e receba um **prompt sólido para a sua IA de codificação**.

Você segura um atalho, explica o que quer em voz alta (com hesitações, voltas e mudanças de ideia) e, ao soltar, o InfiniTypes cola no cursor um prompt limpo, objetivo e estruturado: no Claude Code, no Cursor, no VS Code, no terminal ou em qualquer campo de texto. Todo ditado fica salvo num histórico local, para você nunca perder o que falou.

> Projeto em fase inicial (0.1). A interface e os prompts estão em português.

## Plataformas

| Plataforma | Situação |
|---|---|
| macOS 26+ | ✅ Disponível (código em [`apple/`](apple)) |
| Windows | 🛠️ Próxima na fila |
| iPhone | 📋 Planejado |
| Android | 📋 Planejado |

O plano de cada uma está em [`docs/PLANEJAMENTO.md`](docs/PLANEJAMENTO.md).

## Como funciona

1. **Transcrição local.** A fala vira texto no próprio computador, com o Whisper ([WhisperKit](https://github.com/argmaxinc/WhisperKit) no Mac). O áudio nunca sai da máquina.
2. **Refinamento com o Claude.** A transcrição vai para a API da Anthropic, que remove vícios de fala, organiza as ideias e devolve o prompt. Você escolhe o modelo (Opus, Sonnet, Haiku ou Fable).
3. **Entrega.** O texto é colado no campo em foco. Nada é enviado por você: o Enter é sempre seu. Se não houver campo de texto, o resultado fica no histórico, pronto para copiar.

### Atalhos (macOS)

| Ação | Atalho |
|---|---|
| Ditar um prompt | Segurar o **⌥ direito** |
| Ditar só limpando a fala, sem reestruturar | Segurar o **⌘ direito** |
| Revisar o texto selecionado por voz | Um toque rápido e segurar o **⌥ direito** |
| Cancelar o ditado | Qualquer outra tecla enquanto segura |

O histórico, as preferências e o glossário (termos do seu projeto, para a transcrição acertar nomes como `useAuthStore`) ficam no menu do ícone na barra de menus.

## Use a sua própria chave da API

O InfiniTypes não tem servidor nem assinatura. Cada pessoa usa a **própria chave da API da Anthropic**:

1. Crie uma chave em [console.anthropic.com](https://console.anthropic.com/settings/keys).
2. Cole a chave em **Preferências → Geral** no primeiro uso.

A chave fica no Keychain do seu Mac e só é enviada para `api.anthropic.com`. O custo vai para a sua conta da Anthropic: com o Sonnet 5.5, um ditado típico custa menos de US$ 0,01 (estimativas por modelo em [`docs/PLANEJAMENTO.md`](docs/PLANEJAMENTO.md#10-custo-estimado)).

## Privacidade

- **Fica no seu computador:** o áudio, o histórico, o glossário e o modelo de voz.
- **Vai para a Anthropic:** o texto transcrito, o glossário do projeto e o contexto da janela (nome do app e título da janela). No modo de revisão, também o texto selecionado. Antes de enviar uma seleção, o app bloqueia textos com chaves e senhas conhecidas.
- **Permissões do macOS:** o microfone, só enquanto você segura o atalho, e a Acessibilidade, para detectar o atalho, ler a seleção e colar o resultado.

## Instalar

Ainda não há versão publicada nas Releases. Por enquanto, compile a partir do código:

```bash
brew install xcodegen
git clone <url-deste-repositório>
cd InfiniTypes/apple
make run
```

Requer macOS 26 e Xcode 26. Na primeira transcrição, o app baixa o modelo de voz (~630 MB). Detalhes de assinatura e de como gerar o instalador estão em [`CONTRIBUTING.md`](CONTRIBUTING.md) e [`docs/DISTRIBUICAO.md`](docs/DISTRIBUICAO.md).

## Estrutura do repositório

```
apple/     app do macOS (Swift, SwiftUI, XcodeGen); o do iPhone vai morar aqui também
shared/    prompts e regras comuns a todas as plataformas
docs/      planejamento e distribuição
```

## Contribuir

Contribuições são bem-vindas. Veja [`CONTRIBUTING.md`](CONTRIBUTING.md). Para relatar uma vulnerabilidade, siga [`SECURITY.md`](SECURITY.md), sem abrir issue pública.

## Licença

[MIT](LICENSE).
