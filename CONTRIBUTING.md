# Como contribuir

Obrigado pelo interesse! Cada plataforma tem a sua pasta e os seus testes; as regras comuns e os prompts ficam em `shared/`.

## Preparar o ambiente (macOS)

Requisitos: macOS 26, Xcode 26 e [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```bash
cd apple
make test      # gera o projeto e roda os testes de unidade do Mac
make run       # compila e abre o app do Mac
make ios-run   # compila e abre o app do iPhone no simulador (IOS_SIM="iPhone 17" por padrão)
```

O código comum ao Mac e ao iPhone fica em `apple/InfiniTypesCore/` e não pode usar AppKit nem UIKit.

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

## Preparar o ambiente (Windows)

Requisitos: [SDK do .NET 10](https://dotnet.microsoft.com/download). Os testes rodam em qualquer sistema; o app WPF compila em qualquer sistema e roda só no Windows. Veja [`windows/README.md`](windows/README.md).

```bash
cd windows
dotnet test
```

## Preparar o ambiente (Android)

Requisitos: JDK 17 e o SDK do Android com a plataforma 36 (`local.properties` com `sdk.dir`). Veja [`android/README.md`](android/README.md).

```bash
cd android
./gradlew :core:test :app:lintDebug :app:assembleDebug
```

## Convenções

- **Swift 6** com isolamento padrão no `MainActor`. O que roda fora dele (áudio, por exemplo) é marcado como `nonisolated`.
- **Português** nos comentários, nos textos da interface e na documentação. Identificadores e termos técnicos ficam em inglês.
- Comentários explicam o porquê, não o quê.
- **Testes:** Swift Testing no Mac e no iPhone, xUnit v3 no Windows e JUnit no Android. Lógica nova sem interface (regras, filtros, montagem de requisições) vem com teste.
- **Windows:** C# com `Nullable` e avisos tratados como erros. **Android:** Kotlin no estilo oficial; o lint não pode ter erros.
- **Prompts** (`shared/prompts/`) valem para todas as plataformas. Ao mudá-los, descreva no PR os ditados que você testou, com o antes e o depois.
- **Regras comuns** (detector de segredos, filtro de alucinações, escolha do projeto, revisão e montagem da requisição) têm os casos em `shared/conformance/`, lidos pelos testes de todas as plataformas. Para mudar uma regra, mude primeiro o caso. Veja [`shared/README.md`](shared/README.md).

## Pull requests

1. Abra uma issue antes de mudanças grandes, para combinarmos a abordagem.
2. Mantenha cada PR focado num assunto.
3. Confira se os testes da plataforma que você mudou passam. A CI roda os de todas.
4. Nunca inclua chaves de API, certificados, perfis de provisionamento ou trechos reais do seu histórico. O `.gitignore` cobre os casos comuns, mas a responsabilidade é de quem faz o commit.

## Segurança

Vulnerabilidades não vão para issues públicas. Veja [`SECURITY.md`](SECURITY.md).
