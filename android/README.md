# InfiniTypes para Android

App para Android 13 ou mais novo, em Kotlin com Jetpack Compose. Funciona de três jeitos:

| Jeito | Como usar | Entrega |
|---|---|---|
| **Teclado InfiniTypes** | Troque para o teclado de voz, toque no microfone, fale e toque de novo | O texto entra direto no campo |
| **Bloco nas Configurações Rápidas** | Puxe as Configurações Rápidas e toque em "Ditar prompt" | Copiado para a área de transferência |
| **App** | Aba Ditar | Copiado para a área de transferência |

No teclado, a revisão usa o texto **selecionado** no campo e o substitui pela versão revisada. No bloco e no app, o original é o texto colado no **campo de revisão** da tela: cada revisão substitui o conteúdo do campo pelo resultado, que também é copiado, para você revisar de novo sobre ele.

## Reconhecimento de voz

O app usa o reconhecimento de voz do próprio Android, **no aparelho** (`SpeechRecognizer` no modo offline), com os termos do glossário como dica (`EXTRA_BIASING_STRINGS`). Se o pacote de português ainda não estiver no aparelho, o app pede o download na primeira vez.

Em aparelhos sem reconhecimento offline, dá para permitir o reconhecimento pela rede nos Ajustes. Com isso, o áudio vai para o serviço de voz do Android. Fica desligado por padrão.

## Instalar

1. Baixe o `InfiniTypes-android-<versão>.apk` da [última versão](https://github.com/HelioVieiraSilvaJr/InfiniTypes/releases/latest), ou o `app-debug.apk` da última execução da CI "Android". O APK ainda tem assinatura de testes: para instalar uma versão nova, desinstale a anterior antes.
2. Abra o arquivo no Android e permita a instalação de fontes desconhecidas para o navegador ou o gerenciador de arquivos.
3. No app, cole a sua chave da API da Anthropic em **Ajustes**, ative o teclado e, se quiser, adicione o bloco às Configurações Rápidas.

## Onde ficam os dados

| O quê | Onde |
|---|---|
| Chave da API | `SharedPreferences`, cifrada com AES-GCM por uma chave do Android Keystore |
| Histórico | `History.db` (SQLite), com as mesmas colunas do Windows |
| Preferências e glossário | `SharedPreferences` e `files/Glossary.json` |

O backup na nuvem e a transferência entre aparelhos estão desligados para todos esses dados.

## Compilar

Requer o JDK 17 e o SDK do Android com a plataforma 36. Crie `local.properties` com `sdk.dir=<caminho do SDK>` (o arquivo não vai para o git) e rode:

```bash
cd android
./gradlew :core:test           # casos de conformidade, na JVM
./gradlew :app:assembleDebug   # APK em app/build/outputs/apk/debug
adb install -r app/build/outputs/apk/debug/app-debug.apk   # no aparelho (Depuração USB) ou no emulador aberto
```

Para testar sem aparelho, crie um emulador com Android 13 ou mais novo no Device Manager do Android Studio. O microfone do computador funciona no emulador quando a entrada de áudio do aparelho virtual está ligada.

## Estrutura

```
core/   regras sem dependência do Android: API da Anthropic, refinador, revisão, detector de segredos,
        filtro de alucinações, glossário, histórico; testes com os casos de ../shared/conformance
app/    teclado (InputMethodService), bloco das Configurações Rápidas, app em Compose,
        reconhecimento de voz, Keystore e SQLite
```
