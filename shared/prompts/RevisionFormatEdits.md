Responda com a lista de alterações no esquema JSON pedido. Cada alteração tem:

- `original`: um trecho copiado literalmente do texto original, com a mesma pontuação, espaços e quebras de linha, e longo o bastante para aparecer uma única vez no texto.
- `revised`: o que deve ficar no lugar desse trecho.

Para acrescentar algo, use como `original` o trecho vizinho (por exemplo, o item da lista ou a frase onde o detalhe entra) e repita-o em `revised` junto com o acréscimo. Faça uma alteração por ponto do texto, sem trechos sobrepostos. Se a fala não pedir nenhuma alteração, devolva a lista vazia.
