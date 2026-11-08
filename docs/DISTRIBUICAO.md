# Distribuição do InfiniTypes (macOS)

Os comandos rodam na pasta `apple/` e geram `apple/dist/InfiniTypes-<versão>.dmg`. O app sai universal (Apple Silicon e Intel) e exige macOS 26 ou mais novo.

| Comando | Assinatura | No outro Mac |
|---|---|---|
| `make dmg` | A de `Config/Signing.xcconfig`: ad hoc, ou o seu time se houver `Signing.local.xcconfig` | Na primeira vez: Ajustes do Sistema → Privacidade e Segurança → **Abrir Mesmo Assim** |
| `make notarize` | Developer ID + notarização da Apple | Abre direto, sem aviso |

## Preparar a notarização (uma vez por Mac de desenvolvimento)

É preciso ter o Apple Developer Program pago e o time configurado em `apple/Config/Signing.local.xcconfig` (ver [`CONTRIBUTING.md`](../CONTRIBUTING.md#assinatura)).

### 1. Certificado "Developer ID Application"

Só o **Account Holder** do time pode criar esse certificado.

- **Pelo Xcode (mais simples):** Xcode → Settings → Accounts → adicione o seu Apple ID, se ainda não estiver lá → selecione o time → **Manage Certificates…** → **+** → **Developer ID Application**.
- **Pelo site:**
  1. No Acesso às Chaves, abra Assistente de Certificado → Solicitar um Certificado de uma Autoridade de Certificação → salve em disco.
  2. Em [developer.apple.com/account/resources/certificates](https://developer.apple.com/account/resources/certificates), clique em **+**, escolha **Developer ID Application** e envie o arquivo `.certSigningRequest`.
  3. Baixe o `.cer` e dê dois cliques para instalar.

Para conferir, este comando deve listar uma linha `Developer ID Application: … (<ID do seu time>)`:

```bash
security find-identity -v -p codesigning
```

### 2. Perfil de notarização no Keychain

Há duas formas. As duas guardam a credencial no Keychain, sem deixar nada em arquivo do projeto.

**Com chave da API do App Store Connect (recomendado):** em App Store Connect → Usuários e acesso → Integrações → API do App Store Connect, gere uma chave de equipe e baixe o `.p8`. O Issuer ID aparece no topo da mesma página.

```bash
xcrun notarytool store-credentials "InfiniTypes" --key ~/Downloads/AuthKey_<ID>.p8 --key-id <ID> --issuer <Issuer ID>
```

**Com Apple ID:** crie uma **senha específica de app** em [account.apple.com](https://account.apple.com), em Início de Sessão e Segurança → Senhas Específicas de Apps. O comando pede essa senha.

```bash
xcrun notarytool store-credentials "InfiniTypes" --apple-id <seu Apple ID> --team-id <ID do seu time>
```

Um erro 403 ("A required agreement is missing or has expired") quer dizer que há um contrato pendente em [developer.apple.com/account](https://developer.apple.com/account) ou em App Store Connect → Negócios.

### 3. Gerar

```bash
make notarize
```

O comando assina o app e o `.dmg` com Developer ID e envia o `.dmg` para a Apple. A espera costuma ser de 1 a 5 minutos. No fim, ele grampeia o ticket de aprovação no `.dmg` e confere o resultado com o Gatekeeper.

Se a Apple recusar o envio, o motivo aparece com o comando abaixo, usando o `id` que o `notarytool submit` mostrou:

```bash
xcrun notarytool log <id> --keychain-profile InfiniTypes
```

## Observações

- **Permissões:** Microfone e Acessibilidade ficam ligadas à assinatura. No mesmo Mac, o build com Developer ID conta como um app diferente do build de desenvolvimento e pede as permissões de novo.
- **O que não vai junto:** a chave da API (Keychain de cada Mac), o histórico, o glossário e o modelo de voz, que ficam em `~/Library/Application Support/InfiniTypes`. O modelo é baixado no primeiro uso, ~630 MB.
- **Versão antiga:** na primeira abertura, o app traz os dados da versão 0.1.0, que se chamava InfinidimTypes: a pasta de dados, as preferências e a chave da API.
