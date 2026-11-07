# Distribuição do InfinidimTypes

Há duas formas de gerar o instalador (`dist/InfinidimTypes-<versão>.dmg`). Nas duas, o app sai universal (Apple Silicon e Intel) e exige macOS 26 ou mais novo.

| Comando | Assinatura | No outro Mac |
|---|---|---|
| `make dmg` | Apple Development | Na primeira vez: Ajustes do Sistema → Privacidade e Segurança → **Abrir Mesmo Assim** |
| `make notarize` | Developer ID + notarização da Apple | Abre direto, sem aviso |

## Preparar a notarização (uma vez por Mac de desenvolvimento)

### 1. Certificado "Developer ID Application"

Só o **Account Holder** do time `D93D4Z3ZT7` pode criar esse certificado.

- **Pelo Xcode (mais simples):** Xcode → Settings → Accounts → adicione o seu Apple ID, se ainda não estiver lá → selecione o time → **Manage Certificates…** → **+** → **Developer ID Application**.
- **Pelo site:**
  1. No Acesso às Chaves, abra Assistente de Certificado → Solicitar um Certificado de uma Autoridade de Certificação → salve em disco.
  2. Em [developer.apple.com/account/resources/certificates](https://developer.apple.com/account/resources/certificates), clique em **+**, escolha **Developer ID Application** e envie o arquivo `.certSigningRequest`.
  3. Baixe o `.cer` e dê dois cliques para instalar.

Para conferir, este comando deve listar uma linha `Developer ID Application: … (D93D4Z3ZT7)`:

```bash
security find-identity -v -p codesigning
```

### 2. Perfil de notarização no Keychain

1. Crie uma **senha específica de app** em [account.apple.com](https://account.apple.com), em Início de Sessão e Segurança → Senhas Específicas de Apps.
2. Rode o comando abaixo no Terminal, trocando o Apple ID pelo seu. Ele pede a senha específica de app e guarda tudo no Keychain, sem deixar a senha em arquivo nenhum.

```bash
xcrun notarytool store-credentials "InfinidimTypes" --apple-id seu-apple-id@exemplo.com --team-id D93D4Z3ZT7
```

### 3. Gerar

```bash
make notarize
```

O comando assina o app e o `.dmg` com Developer ID e envia o `.dmg` para a Apple. A espera costuma ser de 1 a 5 minutos. No fim, ele grampeia o ticket de aprovação no `.dmg` e confere o resultado com o Gatekeeper.

Se a Apple recusar o envio, o motivo aparece com o comando abaixo, usando o `id` que o `notarytool submit` mostrou:

```bash
xcrun notarytool log <id> --keychain-profile InfinidimTypes
```

A causa mais comum é um contrato pendente em [developer.apple.com/account](https://developer.apple.com/account), que precisa ser aceito.

## Observações

- **Permissões:** Microfone e Acessibilidade ficam ligadas à assinatura. Neste Mac, o build com Developer ID conta como um app diferente do build de desenvolvimento e pede as permissões de novo.
- **O que não vai junto:** a chave da API (Keychain de cada Mac), o histórico, o glossário e o modelo de voz, que ficam em `~/Library/Application Support/InfinidimTypes`. O modelo é baixado no primeiro uso, ~630 MB.
