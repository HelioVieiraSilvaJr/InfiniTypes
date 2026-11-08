# Segurança

## Como relatar uma vulnerabilidade

**Não abra uma issue pública.** Use o relato privado do GitHub: aba **Security → Report a vulnerability** deste repositório. Descreva o problema, como reproduzir e o impacto que você vê.

A resposta inicial deve sair em até 7 dias. A correção vai para a versão mais recente; versões antigas não recebem atualizações.

## O que o app faz com os seus dados

| Dado | Onde fica | Para onde vai |
|---|---|---|
| Áudio do microfone | Só na memória, durante o ditado | Lugar nenhum: a transcrição é local |
| Chave da API da Anthropic | Keychain do macOS | Só para `api.anthropic.com`, no cabeçalho de cada requisição |
| Texto transcrito, glossário e contexto (nome do app e título da janela) | Histórico local | API da Anthropic, para o refinamento |
| Texto selecionado (modo de revisão) | Histórico local | API da Anthropic. Antes do envio, o app bloqueia textos com chaves e senhas conhecidas e limita o tamanho a 15 mil caracteres |
| Histórico, glossário e modelo de voz | `~/Library/Application Support/InfiniTypes` | Lugar nenhum |

O app não tem servidor próprio, telemetria nem análise de uso. Os registros no log do sistema (`com.infinidim.InfiniTypes`) trazem tempos e decisões, nunca o texto ditado.

## Permissões

- **Microfone:** só grava enquanto o atalho está pressionado.
- **Acessibilidade:** detecta o atalho, lê o texto selecionado, identifica o campo em foco e cola o resultado com ⌘V simulado. A área de transferência é restaurada depois da colagem.

## Escopo

Interessam especialmente:
- vazamento da chave da API ou do histórico;
- envio de dados para qualquer destino além de `api.anthropic.com`;
- texto colado num lugar diferente do esperado, ou execução de comandos no terminal: o app nunca envia Enter;
- falhas no bloqueio de segredos do modo de revisão.
