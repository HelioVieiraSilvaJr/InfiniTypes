# InfiniTypes — Planejamento

App de ditado que transforma fala livre em **prompts sólidos para IAs de codificação**. Projeto aberto (licença MIT), com apps para macOS, Windows, iPhone e Android. No computador, você segura um atalho, fala do jeito que pensa e, ao soltar, recebe um prompt limpo, objetivo e estruturado, colado onde está o cursor (Claude Code, Cursor, VS Code, terminal).

Inspirado nos princípios de ferramentas de ditado com IA, mas com outro objetivo: **não é um ditado genérico, é um compositor de prompts técnicos**.

---

## 1. Decisões tomadas

| Tema | Decisão |
|---|---|
| Plataformas | macOS 26+, Windows 10/11, iPhone com iOS 26+ e Android 13+. O macOS foi validado no uso real; nos outros três, o build, os testes e a interface foram validados, e falta o teste num aparelho de verdade |
| Stack | **Nativo por plataforma**: Swift 6 + SwiftUI + AppKit no macOS (projeto gerado com XcodeGen), Swift + SwiftUI no iPhone (com o código comum em `apple/InfiniTypesCore`), C# com .NET 10 e WPF no Windows e Kotlin + Jetpack Compose no Android. Prompts e casos de conformidade ficam em `shared/`, usados por todas |
| Transcrição | **Local**. Mac e iPhone: WhisperKit (large-v3-turbo; small quantizado nos iPhones com menos de 8 GB). Windows: whisper.cpp pelo Whisper.net. Android: o reconhecimento do próprio aparelho |
| Refinamento | Claude via API, HTTP direto (não há SDK oficial em Swift). **Modelo selecionável** entre os modelos da Anthropic; padrão **Claude Opus 5.5** (`claude-opus-5-5`) |
| Idioma de saída | **Português**; termos técnicos e identificadores ficam no original |
| Entrega | **Colar direto** no campo em foco; você revisa e dá Enter |
| Histórico | **Todo ditado fica salvo no app** com data e hora, para copiar e reutilizar depois, inclusive quando não havia campo em foco |
| Nome e bundle ID | **InfiniTypes** · `com.infinidim.InfiniTypes`. Até a 0.1.0 se chamava InfinidimTypes; os dados migram sozinhos na primeira abertura |
| Distribuição | **Projeto aberto, licença MIT.** Cada pessoa usa a própria chave da API da Anthropic. No Mac: fora da App Store, sem App Sandbox, `.dmg` com Developer ID e notarização (ver `docs/DISTRIBUICAO.md`) |

---

## 2. Experiência de uso

**Fluxo principal**

1. Você está no Claude Code (ou em outro app).
2. **Segura o ⌥ direito.** Um HUD discreto aparece com "Ouvindo" e o nível do microfone.
3. Fala livremente: hesita, volta atrás, repete, muda de ideia.
4. **Solta o ⌥.** O HUD mostra "Transcrevendo…" e depois "Refinando…".
5. O prompt é **salvo no histórico** e colado no cursor. O HUD some. Nada é enviado: o Enter é seu.
6. Se não houver campo de texto em foco, nada é colado: o HUD avisa "Salvo no histórico" e o texto fica esperando você no app, pronto para copiar.

**Controles**

| Ação | Atalho (configurável) | Fase |
|---|---|---|
| Ditar prompt (push-to-talk) | Segurar ⌥ direito | 1 |
| Cancelar ditado em andamento | Qualquer outra tecla (ex.: Esc) enquanto segura o ⌥ | 1 |
| Modo literal (só limpa, não reestrutura) | Segurar ⌘ direito | 2 ✅ |
| Revisar o texto selecionado por voz | Toque rápido e segurar o ⌥ direito | ✅ |
| Modo mãos-livres (ditados longos) | Dois toques no ⌘ direito; um toque termina, Esc cancela | 3 ✅ |
| Abrir o histórico | Pelo menu ou atalho global (a definir) | 1 |
| Colar o último resultado de novo | Pelo menu ou atalho | 1 |

---

## 3. Arquitetura

```
┌──────────────────── InfiniTypes (menu bar, sem ícone no Dock) ──────────────────────┐
│                                                                                     │
│  HotkeyMonitor ──▶ DictationCoordinator  (máquina de estados, orquestra tudo)       │
│                         │                                                           │
│     AudioRecorder ◀─────┤  AVAudioEngine → 16 kHz mono Float32                      │
│     Transcriber   ◀─────┤  protocolo · impl: WhisperKitTranscriber                  │
│     ContextCollector ◀──┤  app ativo, título da janela, projeto, seleção            │
│     PromptRefiner ◀─────┤  protocolo · impl: ClaudeRefiner                          │
│     TextInserter  ◀─────┘  área de transferência + ⌘V simulado                      │
│                                                                                     │
│  HUDPanel (NSPanel não ativável)        SettingsWindow / Onboarding (SwiftUI)       │
│  HistoryStore + HistoryWindow (SwiftData)  KeychainStore (chave da API)             │
└─────────────────────────────────────────────────────────────────────────────────────┘
```

**Máquina de estados do ditado**

```
idle ──(⌥ pressionado)──▶ recording ──(⌥ solto)──▶ transcribing ──▶ refining ──▶ saving ──▶ inserting ──▶ idle
                                                                        sem campo em foco: saving ──▶ idle
          qualquer estado ──(Esc / erro)──▶ cancelled / failed ──▶ idle
```

`Transcriber` e `PromptRefiner` são protocolos: trocar o Whisper por outro motor ou o Opus por outro modelo não mexe no resto do app.

### 3.1 HotkeyMonitor
- Monitor global de `flagsChanged` (`NSEvent.addGlobalMonitorForEvents`) detectando o ⌥ direito (keyCode 61).
- Segurou por menos de ~150 ms: ignora (toque acidental).
- Outra tecla pressionada enquanto o ⌥ está segurado: cancela, pois era um atalho comum (ex.: ⌥+E para acento).
- Se for preciso *consumir* o evento no futuro, migrar para `CGEventTap`.

### 3.2 AudioRecorder
- `AVAudioEngine` com tap no `inputNode` e `AVAudioConverter` para 16 kHz mono Float32 (formato do Whisper).
- Engine preparado com antecedência (`prepare()`) para não cortar as primeiras palavras.
- Nível RMS em tempo real para o HUD.
- Limite de duração (ex.: 5 min) e duração mínima (ex.: 0,5 s; abaixo disso, descarta).
- O microfone só abre enquanto você grava. Nada de escuta contínua.

### 3.3 Transcriber (WhisperKit)
- Dependência SPM: `argmaxinc/WhisperKit`.
- Modelo large-v3-turbo baixado no primeiro uso para `~/Library/Application Support/InfiniTypes/Models` (~1 GB) e carregado na memória ao iniciar o app, para a primeira transcrição já sair rápida.
- Idioma fixo em `pt`. A detecção automática tende a trocar para inglês quando há muitos termos técnicos.
- O glossário entra como *prompt* inicial do Whisper, para ele acertar nomes como `Supabase`, `useEffect`, `Zod`.
- **Proteção contra alucinações**: o Whisper inventa frases em silêncio, como "Legendas pela comunidade Amara.org" ou "Obrigado.". Mitigação: corte de silêncio (VAD), duração mínima e lista de frases conhecidas a descartar.
- Fase 3: transcrever em blocos *durante* a fala, para sobrar menos trabalho quando você solta a tecla.

### 3.4 ContextCollector
- `NSWorkspace.frontmostApplication`: qual app vai receber o texto.
- Accessibility API: título da janela focada. Cursor e VS Code mostram `arquivo — projeto`; terminais costumam mostrar o diretório ou o processo.
- Accessibility API: texto selecionado (modo de edição).
- Classifica o destino: terminal (Terminal, iTerm2, Ghostty, Warp), editor (Cursor, VS Code, Xcode, Zed), navegador ou outro.
- O contexto vai ao modelo só como **referência**: serve para acertar o nome do projeto e do arquivo, nunca para inventar requisitos.

### 3.5 PromptRefiner (Claude Opus 5.5)
- `POST https://api.anthropic.com/v1/messages` com `x-api-key` e `anthropic-version: 2026-10-21`, via `URLSession` + `Codable`. Sem streaming: o prompt é colado inteiro no fim. Streaming entra na Fase 3, se a prévia progressiva fizer sentido.
- **Modelo escolhido por você**, nas preferências ou no menu. A lista vem da Models API (`GET /v1/models`) com a sua chave, então modelos novos aparecem sem atualizar o app. Se a consulta falhar, usa uma lista embutida: Opus 5.5, Sonnet 5.5, Haiku 5.5 e Fable 5.1. Padrão: `claude-opus-5-5`.
- Os modelos têm diferenças de API, então a requisição é montada por modelo (`ModelCatalog`). O parâmetro `thinking` é omitido (pensamento adaptativo, aceito por todos os atuais) e a profundidade fica em `output_config.effort`: padrão `low` para priorizar latência, ajustável nas preferências.
- *Fallback* de recusa (`anthropic-beta: server-side-fallback-2026-07-01` + `fallbacks: "default"`) enviado só para os modelos que aceitam (Opus 5.5, Sonnet 5.5, Fable 5.1). O Haiku 5.5 não tem esse recurso. Em todos os casos, checa o `stop_reason` antes de ler a resposta.
- System prompt fixo (seção 4) com `cache_control`. Glossário, contexto e transcrição vão na mensagem do usuário.
- Timeout de 45 s e uma nova tentativa em erros temporários (429 e 5xx). **Em qualquer falha, salva e cola a transcrição bruta** e avisa no HUD ("Não entre em pânico…"): o ditado nunca se perde.
- Chave da API guardada no Keychain. É uma chave do Console da Anthropic, cobrada à parte da assinatura do Claude.
- Registra no histórico o `usage` (tokens) de cada chamada, para acompanhar o custo.

### 3.6 TextInserter
**Antes de colar, verifica se há campo de texto em foco** (`FocusDetector`):
- Via Accessibility: o elemento focado tem papel `AXTextField` / `AXTextArea` ou expõe uma seleção de texto.
- **Na dúvida, cola**, porque o texto já está no histórico. Apps que desenham o próprio documento, como o Pages, informam o foco como área de rolagem (`AXScrollArea`). Só deixa de colar quando é claro que não há onde digitar: nenhum elemento em foco, a área de trabalho ou as listas do Finder, ou o próprio InfiniTypes.
- Cada decisão vai para o log (`Foco: <app> (papel …) → resultado`), para ajustar a regra com casos reais.
- Terminais e editores conhecidos (Terminal, iTerm2, Ghostty, Warp, Cursor, VS Code, Xcode, Zed) contam como campo mesmo quando a Accessibility responde mal, porque apps Electron e terminais expõem isso de forma irregular.
- **Sem campo em foco: não cola.** O HUD mostra "Salvo no histórico" e o atalho para abrir o histórico. Uma preferência opcional também copia o texto para a área de transferência.

**Com campo em foco:**
1. Salva todo o conteúdo atual da área de transferência (todos os tipos).
2. Escreve o prompt, marcado como transitório (`org.nspasteboard.TransientType`) para gerenciadores de clipboard ignorarem.
3. Simula ⌘V com `CGEvent`.
4. Restaura o conteúdo original após ~300 ms (atraso configurável para apps lentos).
- **Nunca envia Enter** nem quebra de linha final.

### 3.7 HUD, menu e preferências
- **HUD**: `NSPanel` não ativável, sem foco e sem cliques, centralizado embaixo da tela. Estados: ouvindo (com nível de áudio), transcrevendo, refinando, erro.
- **Menu**: estado atual, troca rápida de modelo, último prompt (copiar ou colar de novo), histórico, preferências, sair.
- **Preferências**: chave da API, **modelo da Anthropic** (com preço por milhão de tokens ao lado de cada um), effort, atalhos, glossário, iniciar com o macOS (`SMAppService`), sons de início e fim.

### 3.8 Histórico (recurso principal)
- **Todo ditado é salvo antes de qualquer tentativa de colar.** Se a colagem falhar, o app travar ou não houver campo em foco, o texto continua lá.
- Cada registro guarda: data e hora, prompt final, transcrição bruta, app e janela de destino, status (`colado`, `só no histórico` ou `texto bruto por falha no refinamento`), latência de cada etapa e tokens usados.
- Persistência com SwiftData em Application Support. **Sem limite de retenção por padrão**; você apaga quando quiser, item a item ou por período.
- **Janela de histórico**, aberta pelo menu ou por atalho global:
  - Lista agrupada por dia (Hoje, Ontem, datas anteriores), com hora, app de destino e as primeiras linhas do texto.
  - Busca por texto.
  - Detalhe com o prompt completo e, se quiser, a transcrição bruta.
  - Ações: **Copiar** (⌘C ou Enter), colar no app anterior, apagar.
  - Itens que não chegaram a ser colados ficam destacados.
- Os registros também servem para **calibrar o system prompt com exemplos reais**.
- Na revisão, o detalhe alterna entre **Revisado**, **Fala** e **Original**.

### 3.9 Revisão do texto selecionado
Você seleciona um texto já escrito (um prompt colado, por exemplo), dá um toque rápido no ⌥ direito, segura e dita o que falta ou o que corrigir. O app junta a seleção e a fala e substitui a seleção pelo texto consolidado.

- **Captura da seleção:** primeiro pela Accessibility, ao apertar o atalho, sem tocar na área de transferência. Se o app não expõe a seleção (VS Code, Cursor, Pages), simula ⌘C depois que o atalho é solto, com todos os modificadores livres, e restaura a área de transferência. Assim o ⌘C não vira outro atalho, como ⌥⌘C.
- **Só alterações:** o modelo devolve, em JSON (saída estruturada), uma lista `original → revised` com trechos copiados literalmente do texto. O app aplica a lista localmente: o resto fica idêntico, byte a byte, e a resposta é curta (teste: 3,0 s para 2 alterações em 4 pontos do texto). Se algum trecho não casar exatamente uma vez, o app pede a reescrita completa como reserva e avisa se o resultado encolher mais de 30%.
- **Salvaguardas:**
  - Só envia com o atalho explícito.
  - Bloqueia seleções com chaves ou segredos conhecidos (Anthropic, OpenAI, AWS, GitHub, Slack, Google, Stripe, chaves privadas, JWT, `password=`). Nesse caso, nada é enviado e só a fala vai para o histórico.
  - Limita a seleção a 15 mil caracteres.
  - Recusa campos de senha.
  - A seleção vai marcada como conteúdo, não como instrução.
- **Terminais:** colar não substitui uma seleção feita com o mouse, então o resultado vai para a área de transferência, com um aviso. Apagar o texto antigo automaticamente exigiria Ctrl+C, que no Claude Code pode encerrar a sessão.
- **Sem seleção:** a fala vira um prompt novo, como no ⌥ direito.
- **Falha na revisão:** o texto original não é tocado, e a fala fica no histórico.

---

## 4. O coração: o system prompt de refinamento

É aqui que o app se diferencia de um ditado comum. Regras do prompt v1:

1. **Fidelidade acima de tudo.** Nunca adicionar requisitos, arquivos, bibliotecas ou decisões que você não falou.
2. **Limpeza.** Remover vícios ("é", "tipo", "né", "então"), repetições e hesitações.
3. **Autocorreção.** "No arquivo X, não, no Y" vira só "no Y". Vale sempre a última versão.
4. **Termos técnicos corretos.** Corrigir a grafia fonética ("iúz efeque" → `useEffect`, "dóker compôs" → Docker Compose) usando o glossário e conhecimento técnico, só quando não houver ambiguidade.
5. **Preservação literal.** Caminhos, nomes de arquivos, comandos, identificadores, mensagens de erro e números vão em `código`, exatamente como ditos.
6. **Estrutura proporcional.** Pedido curto vira 1 a 3 frases diretas, sem seções. Pedido longo ganha seções (Objetivo, Contexto, Requisitos, Restrições, Critério de pronto), **só as que tiverem conteúdo**.
7. **Tom de instrução.** Imperativo e objetivo, dirigido ao agente: "Implemente…", "Investigue…", "Não altere…".
8. **Ambiguidade não se chuta.** Se você deixou algo em aberto, o prompt mantém em aberto.
9. **Saída pura.** Só o prompt, em português, Markdown leve (listas e `código`), sem preâmbulo nem comentários.

**Exemplo**

Fala bruta (o que o Whisper entrega):

> é… então, eu quero que você, tipo, crie um endpoint, um endpoint de… de login, né, no no arquivo auth routes ponto ts, que recebe e-mail e senha, aliás, e-mail ou usuário e senha, e retorna um JWT, e, é, não esquece de validar com zod, tá, e escreve teste também

Prompt final (o que é colado):

```markdown
Crie um endpoint de login em `auth.routes.ts`.

Requisitos:
- Recebe e-mail ou nome de usuário, e senha.
- Valida a entrada com Zod.
- Retorna um JWT.
- Inclua testes.
```

O system prompt fica num arquivo versionado (`Refinement/SystemPrompt.md`), e um conjunto de casos reais (*golden set*) garante que mudanças nele não pioram a qualidade.

---

## 5. Orçamento de latência

Os números abaixo são estimativas e serão medidos já na Fase 1.

| Etapa | Alvo |
|---|---|
| Apertar o atalho → microfone gravando | < 150 ms |
| Transcrição local (ditado de ~20 s) | **~1,1 s medido** no M5 (o modelo carrega em ~3 s ao abrir o app; na primeira vez, download e preparo levaram ~2,8 min) |
| Refinamento Opus 5.5 (effort `low`) | ~2–5 s, cresce com o tamanho do prompt |
| Colagem | ~0,3 s |
| **Total após soltar a tecla** | **< 5 s em ditados típicos** |

Se o Opus ficar lento demais na prática, basta trocar o modelo nas preferências (ex.: Claude Haiku 5.5).

---

## 6. Permissões, segurança e privacidade

- **Microfone** (`NSMicrophoneUsageDescription`, entitlement `com.apple.security.device.audio-input`).
- **Acessibilidade**: monitorar o atalho global, ler o contexto da janela e simular ⌘V.
- Onboarding na primeira execução verifica e pede cada permissão (`AXIsProcessTrustedWithOptions`, `AVCaptureDevice.authorizationStatus`).
- **Sem App Sandbox**: Acessibilidade e eventos sintéticos não funcionam dentro dele. Hardened Runtime ativo.
- **Assinatura estável**: o macOS (TCC) vincula as permissões à assinatura. Assinatura ad-hoc faria o sistema pedir as permissões de novo a cada build.
- **Privacidade**: o áudio e o histórico nunca saem do Mac. Para a API vão só o texto transcrito, o glossário e o contexto (nome do app e título da janela).

---

## 7. Estrutura do projeto

```
InfiniTypes/
├── README.md · LICENSE · CONTRIBUTING.md · SECURITY.md
├── .github/                        # CI do macOS/iPhone, do Windows e do Android, modelos de issue e de PR
├── apple/
│   ├── project.yml                 # XcodeGen → gera InfiniTypes.xcodeproj
│   ├── Makefile                    # make build · test · run · dmg · notarize
│   ├── Config/                     # Signing.xcconfig (ad hoc) + Signing.local.xcconfig de cada pessoa
│   ├── InfiniTypes/
│   │   ├── App/                    # InfiniTypesApp, AppDelegate, MenuBarContent
│   │   ├── Core/                   # DictationCoordinator, PermissionsManager
│   │   ├── Input/                  # HotkeyMonitor (atalhos e mãos-livres)
│   │   ├── Context/                # ContextCollector, SelectionReader, AppActivityTracker
│   │   ├── Output/                 # TextInserter, FocusDetector
│   │   ├── UI/                     # HUDPanel, HistoryView, SettingsView, GlossarySettingsView, OnboardingView
│   │   └── Resources/              # Info.plist, .entitlements, AppIcon.icon, Assets.xcassets
│   ├── InfiniTypesCore/            # código comum ao Mac e ao iPhone: refinamento, transcrição, gravação, histórico
│   ├── InfiniTypesiOS/             # app do iPhone (ditado, histórico, ajustes, intenções dos Atalhos)
│   ├── InfiniTypesControls/        # extensão do botão da Central de Controle
│   └── InfiniTypesTests/           # testes de unidade (make test)
├── windows/                        # InfiniTypes.Core (.NET 10), app WPF e testes (dotnet test)
├── android/                        # core (Kotlin/JVM), app (Compose, teclado, bloco) e testes (./gradlew)
├── shared/
│   ├── prompts/                    # SystemPrompt, LiteralPrompt, RevisionPrompt e os dois formatos da revisão
│   └── conformance/                # casos lidos pelos testes de todas as plataformas
└── docs/                           # PLANEJAMENTO.md, DISTRIBUICAO.md
```

Dependências externas, todas fixadas em versões exatas: **WhisperKit** (Mac e iPhone); **Whisper.net**, **NAudio.Wasapi** e **Microsoft.Data.Sqlite** (Windows); **AndroidX**, **Compose** e **kotlinx.coroutines** (Android). O resto é do sistema de cada plataforma.

---

## 8. Fases

### Fase 0 — Fundação
- `project.yml`, app de barra de menu vazio (`LSUIElement`), Info.plist, entitlements, assinatura.
- Onboarding de permissões (microfone e Acessibilidade).
- **Pronto quando:** o app roda na barra de menu, obtém as permissões e as mantém depois de um rebuild.
- **Status:** ✅ concluída (06/11/2026). Depois de recompilar do zero, as duas permissões continuaram valendo.

### Fase 1 — MVP ponta a ponta
- ⌥ direito → gravação → WhisperKit → Claude Opus 5.5 → colar.
- HUD básico, chave no Keychain, system prompt v1, fallback para a transcrição bruta.
- Escolha do modelo da Anthropic nas preferências e no menu.
- Histórico persistente com janela própria (lista por data e hora, busca, copiar) e detecção de campo em foco.
- Filtro básico de alucinações do Whisper.
- Verificação: `make test` roda os testes de unidade. Em Debug, abrir o app com `-transcribeFile <áudio>` passa um arquivo pela transcrição e pelo refinamento, sem colar, com o resultado no log.
- **Pronto quando:** ditar no Claude Code devolve um prompt limpo em menos de ~5 s, sem perder o que estava na área de transferência, e todo ditado aparece no histórico, inclusive quando não havia campo em foco.
- **Status:** ✅ concluída (06/11/2026), com 14 testes de unidade passando. Nos ditados reais de 14–39 s, a transcrição levou 0,9–2,3 s e o refinamento (Sonnet 5.5) 1,7–2,4 s: ~3–5 s depois de soltar a tecla. No Pages, o texto não era colado porque o foco aparece como `AXScrollArea`. A regra foi corrigida e a colagem confirmada.

### Revisão de seleção por voz (antecipada da Fase 3)
- **Status:** ✅ concluída (06/11/2026), com 33 testes de unidade passando. No teste real no Pages, o ⌘C leu a seleção em 65 ms e a revisão aplicou 4 alterações (170 → 298 caracteres), preservando o texto original. Foram ~5 s depois de soltar a tecla: 1,1 s de transcrição e 3,8 s de revisão com o Sonnet 5.5. A reescrita completa (reserva) só foi verificada pelos testes de unidade.
- **Lição do primeiro teste:** numa tentativa anterior, o ⌘C não leu a seleção do Pages, e o app colou um prompt novo por cima do texto. A causa exata não foi confirmada; a espera de 0,4 s era a suspeita, mas a cópia bem-sucedida levou só 65 ms. Duas mudanças garantem que isso não se repita: a revisão nunca cola um prompt novo quando não consegue ler a seleção, e o log registra o tempo de cada leitura por ⌘C e de cada gesto do atalho.

### Fase 2 — Contexto e qualidade
- ✅ Projeto reconhecido pelo título da janela, com base no glossário.
- ✅ Glossário global e por projeto alimentando o Whisper (`promptTokens`) e o Claude (`<glossario>`), salvo em `Glossary.json` e editável em Preferências → Glossário. A tela mostra o título da última janela, para ajudar a dar nome aos projetos.
- ✅ Modo literal no ⌘ direito segurado. Toques rápidos (ex.: ⌘C) não abrem o microfone, e o HUD só aparece depois de 300 ms.
- ✅ Filtro de alucinações ampliado (créditos de legenda em pt/es/fr, despedidas de vídeo, "Thank you." etc.). Cada remoção vai para o log com o nome da regra, nunca com o texto, para o filtro crescer com casos reais.
- ✅ Estrela no histórico marca ditados para a avaliação, e "Exportar avaliação" grava `Eval/cases.jsonl` (transcrição bruta, contexto, original da revisão e texto entregue).
- Montar e rodar a avaliação do refinador quando houver 15 ou mais casos reais marcados.
- **Pronto quando:** os termos do projeto saem corretos e o conjunto de avaliação passa sem regressões.
- **Status:** termos do projeto ✅. Teste com voz sintetizada e glossário `HotkeyLogic`, `WhisperKitTranscriber` e `DictationCoordinator`: sem glossário, o Whisper ouviu "ROTIC e LOGIC" e "esper kit transcriber"; com glossário, a própria transcrição saiu certa e o Claude ainda corrigiu "tecla FM" para "Fn". Para isso, o prompt passou a dizer que os termos do glossário existem porque a transcrição os erra; antes, o modelo era cauteloso demais e mantinha `alt-hosts.ts` mesmo com `auth.routes.ts` no glossário. A avaliação fica pendente até haver casos reais suficientes. 34 testes de unidade passando.

### Projeto aberto e novo nome
- Nome **InfiniTypes**. Na primeira abertura, o app traz a pasta de dados, as preferências e a chave da API do nome antigo.
- Repositório organizado para várias plataformas: `apple/`, `shared/prompts/` e `docs/`, com README, licença MIT, guia de contribuição, política de segurança, modelos de issue e de PR e CI do macOS no GitHub Actions.
- Assinatura ad hoc por padrão, para qualquer pessoa compilar. Quem tem conta da Apple põe o próprio time em `Config/Signing.local.xcconfig`, fora do git.
- Os testes usam uma pasta temporária e não tocam mais no histórico real. As chaves falsas dos testes são montadas por partes, para não disparar detectores de segredos.
- O log de falha da revisão deixou de registrar trechos do texto do usuário.
- **Status:** ✅ concluído (08/11/2026). 34 testes passando com assinatura ad hoc e com o time. Migração verificada no Mac de desenvolvimento: 23 ditados, modelo de voz, preferências e chave da API. Repositório público no GitHub, com a CI do macOS passando.

### Fase 3 — Recursos avançados
- ✅ Modo mãos-livres: dois toques rápidos no ⌘ direito (Mac) ou no Shift direito (Windows) começam um ditado de prompt sem segurar a tecla. Só um toque isolado no atalho termina; digitar, usar ⌘C ou fazer uma maiúscula no meio da fala não encerra. O Esc cancela. No iPhone e no Android o ditado já é por toque (gravar e parar).
- ✅ Iniciar com o sistema: no Mac pelo `SMAppService`, nas preferências; no Windows pela chave Run do usuário.
- Transcrição em streaming durante a fala: **fica para depois**. O ganho (mostrar o texto enquanto fala e encurtar a espera depois de soltar) depende de medir latência e qualidade com voz real; sem isso, o risco é piorar a transcrição, que hoje leva ~1–2 s.
- **Status:** mãos-livres e iniciar com o sistema ✅ (09/11/2026), com testes da máquina de estados do atalho no Mac (25 testes) e no Windows (81). Streaming pendente.

### Fase 4 — Windows

Mesmo uso do Mac: atalho segurado, fala livre e prompt colado no campo em foco.

- **Stack:** C# com .NET 10 e WinUI 3. O app fica na área de notificação, sem janela principal.
- **Antes de começar:** extrair os casos de conformidade para `shared/conformance/` (detector de segredos, filtro de alucinações, escolha do projeto, aplicação das alterações da revisão e montagem da requisição) e fazer os testes do Mac lerem esses arquivos. Os testes do Windows usam os mesmos.
  - ✅ Feito em 09/11/2026: 54 casos em cinco arquivos, descritos em `shared/README.md`. As instruções de formato da revisão saíram do código Swift para `shared/prompts/`. Na extração, o detector parou de apontar as chaves da Anthropic também como chaves da OpenAI.
- **Atalho:** gancho de teclado de baixo nível (`WH_KEYBOARD_LL`) para a tecla segurada e o toque duplo. No teclado ABNT2, o Alt direito é o AltGr, usado para digitar `/`, `?` e `°`. Por isso o padrão no Windows é o **Ctrl direito**, configurável.
- **Áudio:** WASAPI, convertido para 16 kHz mono.
- **Transcrição local:** whisper.cpp pelo Whisper.net, com o large-v3-turbo quantizado. GPU quando houver (CUDA ou Vulkan), CPU como reserva.
- **Contexto:** título da janela em foco, para escolher o projeto do glossário.
- **Colar:** área de transferência + `SendInput` com Ctrl+V, restaurando o conteúdo anterior. Alguns terminais pedem Ctrl+Shift+V.
- **Seleção para a revisão:** UI Automation (`TextPattern`) e, como reserva, Ctrl+C simulado.
- **Chave da API** no Gerenciador de Credenciais do Windows. **Histórico** em SQLite, em `%LOCALAPPDATA%\InfiniTypes`.
- **Distribuição:** instalador assinado nas Releases do GitHub; sem assinatura de código, o SmartScreen mostra aviso. Depois, winget.
- **CI:** build e testes num executor Windows do GitHub Actions.
- **Teste:** exige um Windows 11 de verdade ou uma máquina virtual (no Mac com Apple Silicon, Windows 11 ARM).
- **Pronto quando:** no Windows 11, ditar no Claude Code ou no VS Code devolve o prompt colado em menos de ~5 s, e todo ditado aparece no histórico.
- **Feito (09/11/2026):** app em `windows/`, com **WPF em vez de WinUI 3**. O WPF tem o ícone da área de notificação (pelo `NotifyIcon`), janelas que não recebem foco para o HUD e roda sem o Windows App Runtime; o WinUI 3 não tem nenhum dos três. O WPF também compila no Mac, o que permitiu conferir o build daqui. Literal no Shift direito. A gravação usa o `WasapiRecorder` do NAudio 3, com o Windows convertendo para 16 kHz mono. Distribuição por `.zip` (x64 e ARM64) gerado na CI, anexado às Releases nas tags `v*`; instalador assinado e winget ficam para depois.
- **Status:** núcleo com 81 testes, incluindo os 54 casos de conformidade, passando no Mac e no executor Windows da CI. O app compila e é publicado na CI. **Falta o teste num Windows 11 de verdade**: atalho, microfone, colagem, seleção pela Automação da Interface e o download do modelo.

### Fase 5 — iPhone (iOS)

A ideia continua a mesma (fala livre → prompt sólido), mas a entrega muda. O iOS não permite atalho global, colar em outro app nem ler a seleção pela Acessibilidade, e um teclado personalizado não tem acesso ao microfone. Por isso a fase tem duas etapas, e a segunda só vale a pena se o uso no iPhone pegar.

**5a — Gatilho rápido + área de transferência**
- App para iOS 26 com o mesmo histórico, glossário e seletor de modelo do Mac.
- Gatilhos por um App Intent: Botão de Ação (iPhone 15 Pro em diante), controle na Central de Controle e na tela bloqueada, e app Atalhos.
- Fluxo: gatilho → grava até tocar em parar → transcreve → refina → copia para a área de transferência e salva no histórico. Você cola onde quiser.
- Revisão: o texto que está na área de transferência é o original. Você copia o trecho, aciona a revisão, dita a instrução, e o resultado volta para a área de transferência.
- Sem título de janela, o projeto do glossário é escolhido numa lista, e o app lembra o último.
- Transcrição: comparar o SpeechAnalyzer (nativo do iOS 26, sem download) com o WhisperKit num modelo menor. O large-v3-turbo de 632 MB é pesado demais para o iPhone. Verificar também se o SpeechAnalyzer aceita o glossário como vocabulário.
- **Pronto quando:** do Botão de Ação até o prompt na área de transferência em menos de ~5 s depois de parar de falar, e todo ditado aparece no histórico.

**5b — Teclado próprio**
- Extensão de teclado com acesso total (rede e App Group compartilhado com o app).
- O teclado não pode gravar. O botão de ditado abre o app principal, que liga o microfone e mantém a sessão de áudio em segundo plano; você volta ao app anterior e fala. O texto volta pelo App Group e entra no campo com `insertText`.
- Revisão direta: o `textDocumentProxy` entrega o texto selecionado, e o resultado substitui a seleção. Alguns apps expõem pouco contexto ao teclado.
- **Pronto quando:** ditar no app do Claude ou no navegador e o prompt entrar no campo, com uma única troca de app no começo da sessão.

**Reaproveitamento do código**
- Extrair um pacote Swift compartilhado (`InfiniTypesCore`) com Refinement inteiro (cliente da Anthropic, refinador, revisão por trechos, detector de segredos, catálogo de modelos e prompts), Storage (`DictationRecord`, glossário, exportação da avaliação), `HallucinationFilter` e o protocolo `Transcriber`.
- Fica só no Mac: `HotkeyMonitor`, `TextInserter`, `FocusDetector`, `SelectionReader`, `ContextCollector`, `HUDPanel` e o menu.
- O bloco `<contexto>` enviado ao Claude passa a trazer o projeto escolhido, em vez de app e janela.

**Dados entre aparelhos**
- Chave da API colada uma vez em cada aparelho. Sincronizar pelo Keychain do iCloud fica como opção.
- Histórico e glossário separados por aparelho no começo. A sincronização pelo CloudKit (o SwiftData suporta) exige ajustes no modelo de dados e fica para depois.

**Distribuição**
- TestFlight com teste interno, que dispensa a revisão da Apple. Exige os contratos ativos no App Store Connect.
- Etapa 5b: a sessão de microfone em segundo plano precisa de justificativa clara se o app for para a App Store.

**Feito (09/11/2026): etapa 5a**
- Em vez de um pacote Swift, o código comum fica em `apple/InfiniTypesCore/` e entra nos dois apps pelo `project.yml`. O efeito é o mesmo, sem precisar marcar tudo como `public`; dá para virar pacote depois.
- App `InfiniTypesiOS`: abas Ditar (gravar até tocar em parar, com o modo e o projeto do glossário), Histórico e Ajustes. O resultado vai para a área de transferência; na revisão, o texto copiado é o original.
- Gatilhos: a intenção "Ditar no InfiniTypes" (Atalhos, Siri e Botão de Ação) e o botão da Central de Controle e da tela bloqueada (extensão `InfiniTypesControls`).
- Transcrição: WhisperKit, com o large-v3-turbo nos iPhones com 8 GB ou mais e o small quantizado (216 MB) nos demais. A comparação com o SpeechAnalyzer continua pendente.
- Mesmo bundle ID do Mac (`com.infinidim.InfiniTypes`), que deixa a porta aberta para uma compra universal.
- **Status:** compila na CI e no Xcode, e a tela de ditado foi conferida no simulador do iOS 26. **Falta o teste no iPhone**: microfone, tempo de transcrição, Botão de Ação e Central de Controle. A etapa 5b (teclado) não foi começada.

### Fase 6 — Android
- **Stack:** Kotlin + Jetpack Compose.
- **Forma principal: teclado próprio** (`InputMethodService`). Diferente do iOS, o teclado do Android pode usar o microfone depois que o app recebe a permissão. O botão de ditado grava, e o texto entra no campo com `commitText`. A revisão lê a seleção com `getSelectedText` e a substitui.
- **Atalho rápido:** bloco nas Configurações Rápidas, com entrega pela área de transferência, para quem não quiser trocar de teclado.
- **Transcrição:** comparar o whisper.cpp (via JNI, com modelo menor) com o reconhecimento no próprio aparelho do Android 13 em diante.
- **Chave da API** cifrada com uma chave do Android Keystore. **Histórico** em Room (SQLite).
- **Distribuição:** APK assinado nas Releases do GitHub; depois, Google Play e F-Droid.
- **Pronto quando:** ditar pelo teclado no app do Claude ou no navegador e o prompt entrar no campo em menos de ~5 s.
- **Feito (09/11/2026):** app em `android/`, com o teclado, o bloco "Ditar prompt" nas Configurações Rápidas e o app (aba Ditar). Decisões: o **reconhecimento do próprio aparelho** (`SpeechRecognizer` offline, Android 13+, com o glossário como dica) em vez do whisper.cpp, porque não precisa de código nativo nem de baixar um modelo grande; o reconhecimento pela rede só com permissão explícita nos Ajustes. Histórico em SQLite direto (sem Room, para não depender de geração de código). Chave cifrada com o Android Keystore. AGP 9.5, Gradle 9.9 e Kotlin 2.4, com o `compileSdk` 36: o Compose fica no BOM 2026.06, o último que não exige o SDK 37.
- **Status:** núcleo passa nos casos de conformidade (JVM), o lint não acusa erros e o APK é gerado na CI. No emulador, o app abriu, o teclado apareceu e o reconhecimento pediu o pacote de português offline. **Falta o teste com voz num aparelho**. Distribuição na Play Store e no F-Droid ainda não foi feita (o APK da CI é de debug).

### Ideias futuras
- Glossário automático extraído do repositório aberto (nomes de módulos, classes, funções).
- Saída em inglês por atalho.
- Painel de custo mensal.

---

## 9. Riscos e mitigação

| Risco | Mitigação |
|---|---|
| Whisper inventa frases em silêncio | VAD, duração mínima e lista de alucinações conhecidas |
| Primeiras palavras cortadas | Engine preparado antes; HUD só mostra "Ouvindo" com o microfone ativo |
| Opus lento em ditados longos | Effort `low`, medição desde o MVP, refinador trocável |
| Modelo "inventa" requisitos | Regra de fidelidade e casos-armadilha no golden set |
| ⌥ direito conflita com acentos e atalhos | Cancela se outra tecla for pressionada; atalho configurável |
| App lento cola o clipboard já restaurado | Restauração com atraso configurável |
| Colar em terminal executar algo | O app nunca envia Enter nem quebra de linha final |
| Ditado sem campo em foco | Não cola; salva no histórico e avisa no HUD |
| Perder texto por falha ou travamento | Salvo no histórico antes de qualquer tentativa de colar |
| Permissões perdidas a cada build | Assinatura estável com o mesmo time |
| Modelo novo com parâmetros diferentes | Requisição montada por modelo no `ModelCatalog` e lista atualizada pela Models API |
| Teclado do iOS sem microfone | O app principal grava em segundo plano; o teclado só insere o texto (Fase 5b) |
| Alt direito é o AltGr no Windows (ABNT2) | Ctrl direito como padrão no Windows; atalho configurável |
| Plataformas divergirem no comportamento | Prompts únicos em `shared/` e casos de conformidade rodados pelos testes de cada plataforma |

---

## 10. Custo estimado

Base de cálculo: ditado típico com ~1.500 tokens de entrada (system prompt + transcrição + contexto) e ~300 de saída, 50 ditados por dia útil. Os valores mensais já contam com os tokens de raciocínio.

| Modelo | Entrada / saída (US$ por milhão de tokens) | Por ditado | Por mês |
|---|---|---|---|
| Claude Opus 5.5 (padrão) | 4 / 20 | ~US$ 0,012 | ~US$ 10–20 |
| Claude Sonnet 5.5 | 2 / 10 | ~US$ 0,006 | ~US$ 5–10 |
| Claude Haiku 5.5 | 0,10 / 0,50 | ~US$ 0,0003 | < US$ 1 |
| Claude Fable 5.1 | 10 / 50 | ~US$ 0,03 | ~US$ 30–50 |

A transcrição local tem **custo zero**.

---

## 11. Pontos ainda em aberto

- Transcrição em streaming (Fase 3).
- Windows: instalador assinado (MSIX ou clássico) e winget.
- iOS: comparar o SpeechAnalyzer com o WhisperKit no aparelho; etapa 5b (teclado).
- Android: comparar o reconhecimento do aparelho com o whisper.cpp; release assinado, Play Store e F-Droid.
- Idiomas: hoje a interface e os prompts são só em português. Abrir para outros idiomas amplia o público do projeto.
