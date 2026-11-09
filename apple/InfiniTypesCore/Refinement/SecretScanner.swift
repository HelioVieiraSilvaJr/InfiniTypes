import Foundation

/// Procura chaves e segredos conhecidos antes de mandar um texto selecionado para a API.
enum SecretScanner {
    private static let patterns: [(name: String, regex: Regex<Substring>)] = [
        ("chave da Anthropic", /sk-ant-[A-Za-z0-9_\-]{20,}/),
        // Sem o `(?!ant-)`, toda chave da Anthropic também seria apontada como da OpenAI.
        ("chave da OpenAI", /sk-(?!ant-)(?:proj-)?[A-Za-z0-9_\-]{32,}/),
        ("chave da AWS", /\b(?:AKIA|ASIA)[0-9A-Z]{16}\b/),
        ("token do GitHub", /\b(?:gh[pousr]_[A-Za-z0-9]{36,}|github_pat_[A-Za-z0-9_]{22,})/),
        ("token do Slack", /\bxox[abprs]-[A-Za-z0-9\-]{10,}/),
        ("chave do Google", /\bAIza[0-9A-Za-z_\-]{35}\b/),
        ("chave do Stripe", /\b(?:sk|rk)_live_[0-9A-Za-z]{20,}/),
        ("chave privada", /-----BEGIN [A-Z ]*PRIVATE KEY-----/),
        ("token JWT", /\beyJ[A-Za-z0-9_\-]{10,}\.eyJ[A-Za-z0-9_\-]{10,}\.[A-Za-z0-9_\-]{10,}/),
        // Sem `\b` antes do nome: em DATABASE_PASSWORD, o "_" não marca fronteira de palavra.
        ("senha ou token em configuração",
         /(?i)(?:password|passwd|senha|secret|api[_\-]?key|access[_\-]?token)\s*[:=]\s*["']?[^\s"'`]{8,}/),
    ]

    /// Os tipos de segredo encontrados, sem repetir.
    static func findings(in text: String) -> [String] {
        patterns.filter { text.contains($0.regex) }.map(\.name)
    }
}
