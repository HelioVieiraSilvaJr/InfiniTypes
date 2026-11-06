# InfinidimTypes — Planejamento

App de barra de menu para macOS que transforma fala livre em **prompts sólidos para IAs de codificação**. Você segura um atalho, fala do jeito que pensa e, ao soltar, recebe um prompt limpo, objetivo e estruturado, colado onde está o cursor (Claude Code, Cursor, VS Code, terminal).

Inspirado nos princípios de ferramentas de ditado com IA, mas com outro objetivo: **não é um ditado genérico, é um compositor de prompts técnicos**.

---

## 1. Decisões tomadas

| Tema | Decisão |
|---|---|
| Plataforma | macOS 26+, Apple Silicon (máquina de desenvolvimento: M5, 16 GB) |
| Stack | Swift 6 + SwiftUI + AppKit, projeto gerado com XcodeGen |
| Transcrição | **Local**, WhisperKit com Whisper large-v3-turbo (Core ML) |
| Refinamento | Claude via API, HTTP direto (não há SDK oficial em Swift). **Modelo selecionável** entre os modelos da Anthropic; padrão **Claude Opus 5.5** (`claude-opus-5-5`) |
| Idioma de saída | **Português**; termos técnicos e identificadores ficam no original |
| Entrega | **Colar direto** no campo em foco; você revisa e dá Enter |
| Histórico | **Todo ditado fica salvo no app** com data e hora, para copiar e reutilizar depois, inclusive quando não havia campo em foco |
| Nome e bundle ID | **InfinidimTypes** · `com.infinidim.InfinidimTypes` |
| Distribuição | Uso pessoal, fora da App Store, sem App Sandbox, assinado com o certificado Apple Development (time `D93D4Z3ZT7`) |

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
| Modo mãos-livres (ditados longos) | Toque duplo no ⌥ direito; toque de novo para encerrar | 3 |
| Modo literal (só limpa, não reestrutura) | A definir | 2 |
| Editar seleção por voz ("resume", "deixa mais direto") | A definir | 3 |
| Abrir o histórico | Pelo menu ou atalho global (a definir) | 1 |
| Colar o último resultado de novo | Pelo menu ou atalho | 1 |

---

## 3. Arquitetura

```
┌──────────────────── InfinidimTypes (menu bar, sem ícone no Dock) ────────────────────┐
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
- Modelo large-v3-turbo baixado no primeiro uso para `~/Library/Application Support/InfinidimTypes/Models` (~1 GB) e carregado na memória ao iniciar o app, para a primeira transcrição já sair rápida.
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
- **Na dúvida, cola**, porque o texto já está no histórico. Apps que desenham o próprio documento, como o Pages, informam o foco como área de rolagem (`AXScrollArea`). Só deixa de colar quando é claro que não há onde digitar: nenhum elemento em foco, a área de trabalho ou as listas do Finder, ou o próprio InfinidimTypes.
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
InfinidimTypes/
├── project.yml                     # XcodeGen → gera InfinidimTypes.xcodeproj
├── Makefile                        # make build · make run · make clean
├── InfinidimTypes/
│   ├── App/                        # InfinidimTypesApp, AppDelegate, MenuBarContent
│   ├── Core/                       # DictationCoordinator, DictationState, PermissionsManager, Log
│   ├── Input/                      # HotkeyMonitor, AudioRecorder
│   ├── Transcription/              # Transcriber (protocolo), WhisperKitTranscriber, HallucinationFilter
│   ├── Context/                    # ContextCollector (+ leitura da Accessibility), AppActivityTracker
│   ├── Refinement/                 # PromptRefiner (protocolo), ClaudeRefiner, AnthropicClient, ModelCatalog, SystemPrompt.md
│   ├── Output/                     # TextInserter, FocusDetector, PasteboardSnapshot
│   ├── UI/                         # HUDPanel, HistoryView, SettingsView, OnboardingView, WindowPresenter
│   ├── Storage/                    # KeychainStore, AppSettings, HistoryStore (SwiftData), AppPaths
│   └── Resources/                  # Info.plist, .entitlements, AppIcon.icon, Assets.xcassets
├── InfinidimTypesTests/            # testes de unidade (make test) + golden set do refinador (Fase 2)
└── docs/
    └── PLANEJAMENTO.md
```

Dependência externa única no início: **WhisperKit**. O resto é framework da Apple.

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

### Fase 2 — Contexto e qualidade
- ContextCollector (app, janela, projeto).
- Glossário global e por projeto, alimentando o Whisper e o Claude.
- Modo literal (só limpeza) em atalho próprio.
- Filtro de alucinações ampliado com casos reais do histórico.
- Golden set com 20 a 30 ditados reais (tirados do histórico) e avaliação do refinador.
- **Pronto quando:** os termos do projeto saem corretos e o golden set passa sem regressões.

### Fase 3 — Recursos avançados
- Modo mãos-livres.
- Editar texto selecionado por voz.
- Transcrição em streaming durante a fala.
- Iniciar com o macOS.

### Fase 4 — Ideias futuras
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

- Atalhos do modo literal e da edição por voz.
