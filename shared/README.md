# shared

O que vale igual em todas as plataformas. Cada app (macOS, Windows, iPhone, Android) usa estes arquivos em vez de manter cópias próprias.

| Pasta | Conteúdo |
|---|---|
| `prompts/` | System prompts do refinamento: `SystemPrompt.md` (prompt), `LiteralPrompt.md` (literal) e `RevisionPrompt.md` (revisão). O marcador `{{formato}}` da revisão recebe o conteúdo de `RevisionFormatEdits.md` (lista de alterações) ou de `RevisionFormatFullText.md` (texto completo, a reserva), sem os espaços e quebras de linha das pontas |
| `conformance/` | Casos de conformidade: entradas e saídas esperadas para as regras que cada plataforma implementa no próprio código |

Como cada plataforma usa estes arquivos:

| Plataforma | `prompts/` | `conformance/` |
|---|---|---|
| macOS e iPhone | Recurso dos apps, pelo `apple/project.yml` | Recurso dos testes do Mac (`ConformanceTests.swift`) |
| Windows | Recurso embutido na `InfiniTypes.Core.dll` | Copiado para a pasta dos testes (`ConformanceTests.cs`) |
| Android | Recurso Java do módulo `core` | Lido pelos testes da JVM (`ConformanceTest.kt`) |

## Casos de conformidade

Os testes de cada plataforma leem os mesmos arquivos, para as implementações não divergirem. Ao mudar uma dessas regras, altere ou acrescente o caso aqui primeiro. Depois, ajuste cada plataforma até os testes passarem.

| Arquivo | Regra | Cada caso tem |
|---|---|---|
| `secrets.json` | Detector de segredos, antes de enviar uma seleção para a API | `text` e `findings`: os nomes dos tipos de segredo encontrados, sem repetir, na ordem da lista de padrões |
| `hallucinations.json` | Filtro de frases que o Whisper inventa no silêncio | `input` e `output` |
| `projects.json` | Escolha do projeto do glossário pelo título da janela | `window_title`, `project` e `terms`, todos sobre o glossário do topo do arquivo |
| `revision-edits.json` | Aplicação das alterações devolvidas pela revisão | `text`, `edits` e `result`, ou `error` (`not_found`, `ambiguous` ou `overlapping`) |
| `requests.json` | Montagem da requisição para a API da Anthropic | As entradas (`kind`, `model`, `effort`, `format`, `system_prompt`, `selection`, `transcript`, `context`, `vocabulary`), o `expected_body` e o `expected_beta` (cabeçalho `anthropic-beta`). O `api` do topo traz o endereço e a versão da API |

Detalhes:

- **`text` em `secrets.json`** é uma lista de pedaços, juntados sem separador. As chaves falsas ficam partidas no arquivo para não disparar os detectores de segredos do GitHub e afins.
- **`expected_body`** é comparado como JSON: a ordem das chaves não importa, e campos ausentes não podem aparecer na requisição.
- **Os nomes em `findings`** são os que o app mostra ao recusar uma seleção, por isso precisam ser iguais em todas as plataformas.
