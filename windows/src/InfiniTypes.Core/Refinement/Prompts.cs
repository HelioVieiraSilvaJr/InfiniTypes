namespace InfiniTypes.Core.Refinement;

/// <summary>Prompts de <c>shared/prompts/</c>, embutidos na DLL.</summary>
public static class Prompts
{
    public static string Load(string resource)
    {
        using var stream = typeof(Prompts).Assembly.GetManifestResourceStream($"Prompts.{resource}.md")
            ?? throw new InvalidOperationException($"{resource}.md não foi embutido na DLL");
        using var reader = new StreamReader(stream);
        return reader.ReadToEnd();
    }
}
