# InfiniTypes para Windows

App da área de notificação para Windows 10 e 11, em C# com .NET 10 e WPF. Funciona como o do Mac: você segura o atalho, fala e solta, e o prompt é colado no campo em foco.

| Ação | Atalho |
|---|---|
| Ditar um prompt | Segurar o **Ctrl direito** |
| Ditar só limpando a fala, sem reestruturar | Segurar o **Shift direito** |
| Revisar o texto selecionado por voz | Um toque rápido e segurar o **Ctrl direito** |
| Ditar sem segurar (mãos livres) | Dois toques no **Shift direito**; um toque termina |
| Cancelar o ditado | Qualquer outra tecla enquanto segura, ou Esc |

O Alt direito fica de fora: no teclado ABNT2 ele é o AltGr, usado para digitar `/`, `?` e `°`.

## Instalar

1. Baixe o `.zip` da sua arquitetura (x64 ou ARM64) na [última versão](https://github.com/HelioVieiraSilvaJr/InfiniTypes/releases/latest), ou nos artefatos da última execução da CI "Windows".
2. Extraia numa pasta sua (por exemplo, `%LOCALAPPDATA%\Programs\InfiniTypes`) e abra o `InfiniTypes.exe`.
3. O app ainda não é assinado, então o SmartScreen avisa na primeira vez: **Mais informações → Executar assim mesmo**.
4. Cole a sua chave da API da Anthropic nas Preferências, que abrem sozinhas na primeira vez.

Na primeira abertura, o app baixa o modelo de voz (~550 MB) em segundo plano. O microfone precisa estar liberado para apps da área de trabalho em **Configurações → Privacidade e segurança → Microfone**.

## Onde ficam os dados

| O quê | Onde |
|---|---|
| Chave da API | Gerenciador de Credenciais do Windows (`InfiniTypes/anthropic-api-key`) |
| Histórico | `%LOCALAPPDATA%\InfiniTypes\History.db` (SQLite) |
| Preferências e glossário | `%LOCALAPPDATA%\InfiniTypes\Settings.json` e `Glossary.json` |
| Modelo de voz | `%LOCALAPPDATA%\InfiniTypes\Models` |
| Log (sem o texto ditado) | `%LOCALAPPDATA%\InfiniTypes\Logs` |

## Compilar

Requer o [SDK do .NET 10](https://dotnet.microsoft.com/download).

```bash
cd windows
dotnet test                              # núcleo e casos de conformidade (roda em qualquer sistema)
dotnet run --project src/InfiniTypes     # só no Windows
```

Para gerar a pasta que vai para outro PC (é o que a CI empacota no `.zip`):

```powershell
dotnet publish src\InfiniTypes -c Release -r win-x64 --self-contained -o publish   # win-arm64 nos PCs ARM
```

O app WPF também compila no Mac e no Linux (`EnableWindowsTargeting`), o que basta para conferir o build. Para rodar, só no Windows.

## Estrutura

```
src/InfiniTypes.Core/    regras sem dependência do Windows: API da Anthropic, refinador, revisão,
                         detector de segredos, filtro de alucinações, glossário, histórico, atalho
src/InfiniTypes/         app WPF: gancho de teclado, microfone (WASAPI), Whisper.net, colagem,
                         seleção pela Automação da Interface, área de notificação, HUD e janelas
tests/                   testes do núcleo, incluindo os casos de ../shared/conformance
```

## Limitações conhecidas

- **Apps abertos como administrador:** o Windows não deixa um app comum colar neles nem ler a seleção. Abra o InfiniTypes como administrador se precisar ditar nesses apps.
- **Revisão no terminal:** colar não substitui a seleção, então a revisão vai para a área de transferência.
- **Git Bash (mintty):** a colagem usa Shift+Insert.
