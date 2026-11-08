# Como contribuir

Obrigado pelo interesse! Este guia cobre o app do macOS, que hoje é o único implementado. As outras plataformas ganham seções aqui quando começarem.

## Preparar o ambiente (macOS)

Requisitos: macOS 26, Xcode 26 e [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```bash
cd apple
make test   # gera o projeto e roda os testes de unidade
make run    # compila e abre o app
```

O `InfiniTypes.xcodeproj` é gerado a partir do `apple/project.yml` e não vai para o repositório. Para mudar alvos, arquivos ou ajustes de build, edite o `project.yml`.

### Assinatura

Sem nenhuma configuração, o app é assinado **ad hoc**. Isso basta para compilar e testar, mas o macOS pode pedir as permissões de microfone e Acessibilidade de novo a cada build. Para manter as permissões entre um build e outro, assine com o seu time da Apple (uma conta gratuita serve):

```bash
cp apple/Config/Signing.local.xcconfig.example apple/Config/Signing.local.xcconfig
# edite o arquivo e coloque o ID do seu time
```

O `Signing.local.xcconfig` é ignorado pelo git.

### Testar com um arquivo de áudio

Em Debug, dá para passar um áudio pela transcrição e pelo refinamento sem usar o microfone. O resultado aparece no log:

```bash
open apple/build/DerivedData/Build/Products/Debug/InfiniTypes.app --args -transcribeFile /caminho/audio.wav
```

Outros argumentos: `-literal YES` (modo literal), `-reviseFile <texto.txt>` (revisão sobre o conteúdo do arquivo) e `-glossaryFile <glossario.json>`.

## Convenções

- **Swift 6** com isolamento padrão no `MainActor`. O que roda fora dele (áudio, por exemplo) é marcado como `nonisolated`.
- **Português** nos comentários, nos textos da interface e na documentação. Identificadores e termos técnicos ficam em inglês.
- Comentários explicam o porquê, não o quê.
- **Testes:** Swift Testing (`@Test`). Lógica nova sem interface (regras, filtros, montagem de requisições) vem com teste.
- **Prompts** (`shared/prompts/`) valem para todas as plataformas. Ao mudá-los, descreva no PR os ditados que você testou, com o antes e o depois.

## Pull requests

1. Abra uma issue antes de mudanças grandes, para combinarmos a abordagem.
2. Mantenha cada PR focado num assunto.
3. Confira se `make test` passa.
4. Nunca inclua chaves de API, certificados, perfis de provisionamento ou trechos reais do seu histórico. O `.gitignore` cobre os casos comuns, mas a responsabilidade é de quem faz o commit.

## Segurança

Vulnerabilidades não vão para issues públicas. Veja [`SECURITY.md`](SECURITY.md).
