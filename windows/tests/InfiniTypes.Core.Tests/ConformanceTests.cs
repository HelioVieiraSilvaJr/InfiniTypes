using System.Text.Json;
using System.Text.Json.Nodes;
using InfiniTypes.Core.Refinement;
using InfiniTypes.Core.Storage;
using InfiniTypes.Core.Transcription;

namespace InfiniTypes.Core.Tests;

// Casos de `shared/conformance/`. Os testes das outras plataformas leem os mesmos arquivos.

public sealed class SecretConformanceTests
{
    public static TheoryData<string> Cases => Conformance.Names("secrets");

    [Theory, MemberData(nameof(Cases))]
    public void FindsTheSameSecrets(string name)
    {
        var testCase = Conformance.Case("secrets", name);
        // Pedaços juntados sem separador: assim as chaves falsas não disparam os detectores de segredos.
        var text = string.Concat(Conformance.Strings(testCase["text"]));
        Assert.Equal(Conformance.Strings(testCase["findings"]), SecretScanner.Findings(text));
    }
}

public sealed class HallucinationConformanceTests
{
    public static TheoryData<string> Cases => Conformance.Names("hallucinations");

    [Theory, MemberData(nameof(Cases))]
    public void CleansTheSameWay(string name)
    {
        var testCase = Conformance.Case("hallucinations", name);
        Assert.Equal(testCase["output"]!.GetValue<string>(), HallucinationFilter.Clean(testCase["input"]!.GetValue<string>()));
    }
}

public sealed class ProjectConformanceTests
{
    public static TheoryData<string> Cases => Conformance.Names("projects");

    [Theory, MemberData(nameof(Cases))]
    public void PicksTheSameProject(string name)
    {
        var glossary = Conformance.File("projects")["glossary"].Deserialize<Glossary>()!;
        var testCase = Conformance.Case("projects", name);
        var match = glossary.Match(testCase["window_title"]?.GetValue<string>());
        Assert.Equal(testCase["project"]?.GetValue<string>(), match.ProjectName);
        Assert.Equal(Conformance.Strings(testCase["terms"]), match.Terms);
    }
}

public sealed class RevisionEditsConformanceTests
{
    public static TheoryData<string> Cases => Conformance.Names("revision-edits");

    [Theory, MemberData(nameof(Cases))]
    public void AppliesTheSameEdits(string name)
    {
        var testCase = Conformance.Case("revision-edits", name);
        var edits = testCase["edits"].Deserialize<List<RevisionEdit>>()!;
        var text = testCase["text"]!.GetValue<string>();
        if (testCase["error"]?.GetValue<string>() is { } error)
        {
            var failure = Assert.Throws<RevisionPatchException>(() => RevisionPatcher.Apply(edits, text));
            Assert.Equal(error, Code(failure.Error));
        }
        else
        {
            Assert.Equal(testCase["result"]!.GetValue<string>(), RevisionPatcher.Apply(edits, text));
        }
    }

    /// <summary>Nome do erro nos arquivos de conformidade.</summary>
    private static string Code(RevisionPatchError error) => error switch
    {
        RevisionPatchError.NotFound => "not_found",
        RevisionPatchError.Ambiguous => "ambiguous",
        _ => "overlapping",
    };
}

public sealed class RequestConformanceTests
{
    public static TheoryData<string> Cases => Conformance.Names("requests");

    [Fact]
    public void UsesTheSameEndpointAndVersion()
    {
        var api = Conformance.File("requests")["api"]!;
        Assert.Equal($"{AnthropicClient.BaseUrl}/messages", api["messages_url"]!.GetValue<string>());
        Assert.Equal(AnthropicClient.ApiVersion, api["anthropic_version"]!.GetValue<string>());
    }

    [Theory, MemberData(nameof(Cases))]
    public void BuildsTheSameRequest(string name)
    {
        var testCase = Conformance.Case("requests", name);
        string Text(string key) => testCase[key]!.GetValue<string>();
        string? Optional(JsonNode? node, string key) => node?[key]?.GetValue<string>();

        var model = ModelCatalog.Model(Text("model"));
        var effort = EffortExtensions.ParseEffort(Text("effort"));
        var contextNode = testCase["context"];
        var context = new DictationContext(Optional(contextNode, "app"), null, Optional(contextNode, "window_title"),
            Optional(contextNode, "project"));
        var vocabulary = Conformance.Strings(testCase["vocabulary"]);

        var request = Text("kind") switch
        {
            "refinement" => ClaudeRefiner.MakeRequest(model, effort, Text("system_prompt"), Text("transcript"), context,
                vocabulary),
            "revision" => ClaudeRefiner.MakeRevisionRequest(model, effort, Text("system_prompt"),
                Text("format") == "edits" ? RevisionFormat.Edits : RevisionFormat.FullText, Text("selection"),
                Text("transcript"), context, vocabulary),
            var kind => throw new InvalidDataException($"tipo de caso desconhecido: {kind}"),
        };

        var body = JsonNode.Parse(AnthropicClient.Serialize(request));
        var expected = testCase["expected_body"];
        Assert.True(JsonNode.DeepEquals(expected, body), $"esperado:\n{expected}\n\nrecebido:\n{body}");
        Assert.Equal(testCase["expected_beta"]?.GetValue<string>(), AnthropicClient.BetaHeader(request));
    }
}

/// <summary>Leitura dos arquivos, copiados para <c>conformance/</c> ao lado dos testes.</summary>
internal static class Conformance
{
    public static JsonNode File(string name) =>
        JsonNode.Parse(System.IO.File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "conformance", $"{name}.json")))!;

    public static TheoryData<string> Names(string name) =>
        new(File(name)["cases"]!.AsArray().Select(c => c!["name"]!.GetValue<string>()));

    public static JsonNode Case(string file, string name) =>
        File(file)["cases"]!.AsArray().Single(c => c!["name"]!.GetValue<string>() == name)!;

    public static List<string> Strings(JsonNode? node) =>
        node!.AsArray().Select(item => item!.GetValue<string>()).ToList();
}
