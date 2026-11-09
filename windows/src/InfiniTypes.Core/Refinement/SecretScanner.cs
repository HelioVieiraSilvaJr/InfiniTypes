using System.Text.RegularExpressions;

namespace InfiniTypes.Core.Refinement;

/// <summary>Procura chaves e segredos conhecidos antes de mandar um texto selecionado para a API.</summary>
public static class SecretScanner
{
    private static readonly (string Name, Regex Regex)[] Patterns =
    [
        ("chave da Anthropic", Pattern(@"sk-ant-[A-Za-z0-9_\-]{20,}")),
        // Sem o `(?!ant-)`, toda chave da Anthropic também seria apontada como da OpenAI.
        ("chave da OpenAI", Pattern(@"sk-(?!ant-)(?:proj-)?[A-Za-z0-9_\-]{32,}")),
        ("chave da AWS", Pattern(@"\b(?:AKIA|ASIA)[0-9A-Z]{16}\b")),
        ("token do GitHub", Pattern(@"\b(?:gh[pousr]_[A-Za-z0-9]{36,}|github_pat_[A-Za-z0-9_]{22,})")),
        ("token do Slack", Pattern(@"\bxox[abprs]-[A-Za-z0-9\-]{10,}")),
        ("chave do Google", Pattern(@"\bAIza[0-9A-Za-z_\-]{35}\b")),
        ("chave do Stripe", Pattern(@"\b(?:sk|rk)_live_[0-9A-Za-z]{20,}")),
        ("chave privada", Pattern(@"-----BEGIN [A-Z ]*PRIVATE KEY-----")),
        ("token JWT", Pattern(@"\beyJ[A-Za-z0-9_\-]{10,}\.eyJ[A-Za-z0-9_\-]{10,}\.[A-Za-z0-9_\-]{10,}")),
        // Sem `\b` antes do nome: em DATABASE_PASSWORD, o "_" não marca fronteira de palavra.
        ("senha ou token em configuração",
         Pattern(@"(?i)(?:password|passwd|senha|secret|api[_\-]?key|access[_\-]?token)\s*[:=]\s*[""']?[^\s""'`]{8,}")),
    ];

    /// <summary>Os tipos de segredo encontrados, sem repetir.</summary>
    public static IReadOnlyList<string> Findings(string text) =>
        Patterns.Where(p => p.Regex.IsMatch(text)).Select(p => p.Name).ToList();

    private static Regex Pattern(string pattern) => new(pattern, RegexOptions.CultureInvariant);
}
