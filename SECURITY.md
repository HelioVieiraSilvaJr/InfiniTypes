# Segurança

## Como relatar uma vulnerabilidade

**Não abra uma issue pública.** Use o relato privado do GitHub: aba **Security → Report a vulnerability** deste repositório. Descreva o problema, como reproduzir e o impacto que você vê.

A resposta inicial deve sair em até 7 dias. A correção vai para a versão mais recente; versões antigas não recebem atualizações.

## O que o app faz com os seus dados

| Dado | Onde fica | Para onde vai |
|---|---|---|
| Áudio do microfone | Só na memória, durante o ditado | Lugar nenhum: a transcrição é local. No Android, só se você permitir o reconhecimento pela rede nos Ajustes, para aparelhos sem reconhecimento offline |
| Chave da API da Anthropic | Keychain (Mac e iPhone), Gerenciador de Credenciais (Windows), cifrada pelo Android Keystore (Android) | Só para `api.anthropic.com`, no cabeçalho de cada requisição |
| Texto transcrito, glossário e contexto (nome do app, título da janela ou projeto escolhido) | Histórico local | API da Anthropic, para o refinamento |
| Texto selecionado ou copiado (modo de revisão) | Histórico local | API da Anthropic. Antes do envio, o app bloqueia textos com chaves e senhas conhecidas e limita o tamanho a 15 mil caracteres |
| Histórico, glossário e modelo de voz | `~/Library/Application Support/InfiniTypes` (Mac), contêiner do app (iPhone), `%LOCALAPPDATA%\InfiniTypes` (Windows), dados do app sem backup (Android) | Lugar nenhum |

O app não tem servidor próprio, telemetria nem análise de uso. Os logs trazem tempos e decisões, nunca o texto ditado.

## Permissões

- **Microfone:** só grava enquanto o atalho está pressionado (ou, no mãos-livres e nos celulares, até você terminar o ditado).
- **Acessibilidade (Mac):** detecta o atalho, lê o texto selecionado, identifica o campo em foco e cola o resultado com ⌘V simulado. A área de transferência é restaurada depois da colagem.
- **Windows:** o gancho de teclado vê as teclas para detectar o atalho, sem guardar nada; a colagem simula Ctrl+V e restaura a área de transferência.
- **Android:** o teclado InfiniTypes só ouve quando você toca no microfone e só escreve no campo em que você está.

## Escopo

Interessam especialmente:
- vazamento da chave da API ou do histórico;
- envio de dados para qualquer destino além de `api.anthropic.com`;
- texto colado num lugar diferente do esperado, ou execução de comandos no terminal: o app nunca envia Enter;
- falhas no bloqueio de segredos do modo de revisão.
