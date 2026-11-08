# shared

O que vale igual em todas as plataformas. Cada app (macOS, Windows, iPhone, Android) usa estes arquivos em vez de manter cópias próprias.

| Pasta | Conteúdo |
|---|---|
| `prompts/` | System prompts do refinamento: `SystemPrompt.md` (prompt), `LiteralPrompt.md` (literal) e `RevisionPrompt.md` (revisão, com o marcador `{{formato}}`) |

No macOS, o `apple/project.yml` inclui `prompts/` como recurso do app.

Antes da versão para Windows, entram aqui os **casos de conformidade**: arquivos JSON com entradas e saídas esperadas para o detector de segredos, o filtro de alucinações, a escolha do projeto pelo título da janela, a aplicação das alterações da revisão e a montagem da requisição para a API. Os testes de cada plataforma leem os mesmos casos, para as implementações não divergirem.
