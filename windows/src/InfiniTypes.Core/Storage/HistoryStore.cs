using Microsoft.Data.Sqlite;

namespace InfiniTypes.Core.Storage;

/// <summary>Um ditado salvo no histórico.</summary>
public sealed class DictationRecord
{
    public long Id { get; set; }
    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.Now;
    /// <summary>Texto entregue: o prompt refinado ou, se o refinamento falhou, a transcrição bruta.</summary>
    public string Text { get; set; } = "";
    public string RawTranscript { get; set; } = "";
    public string? AppName { get; set; }
    public string? AppId { get; set; }
    public string? WindowTitle { get; set; }
    public string? ProjectName { get; set; }
    public DictationMode Mode { get; set; }
    /// <summary>Na revisão: o texto que estava selecionado antes de ser substituído.</summary>
    public string? OriginalText { get; set; }
    public string? ModelId { get; set; }
    public bool Refined { get; set; }
    public bool Pasted { get; set; }
    public string? ErrorMessage { get; set; }
    public double AudioSeconds { get; set; }
    public double TranscriptionSeconds { get; set; }
    public double? RefinementSeconds { get; set; }
    public int? InputTokens { get; set; }
    public int? OutputTokens { get; set; }
    /// <summary>Marcado no histórico para entrar no conjunto de avaliação do refinador.</summary>
    public bool InEvalSet { get; set; }
}

/// <summary>Histórico em SQLite, em <c>%LOCALAPPDATA%\InfiniTypes\History.db</c> no Windows.</summary>
public sealed class HistoryStore : IDisposable
{
    private readonly SqliteConnection _connection;

    private const string Columns =
        "created_at, text, raw_transcript, app_name, app_id, window_title, project_name, mode, original_text, " +
        "model_id, refined, pasted, error_message, audio_seconds, transcription_seconds, refinement_seconds, " +
        "input_tokens, output_tokens, in_eval_set";

    public HistoryStore(string path)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(path))!);
        _connection = new SqliteConnection(new SqliteConnectionStringBuilder { DataSource = path }.ToString());
        _connection.Open();
        Execute("""
            CREATE TABLE IF NOT EXISTS dictations (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                created_at TEXT NOT NULL,
                text TEXT NOT NULL,
                raw_transcript TEXT NOT NULL,
                app_name TEXT,
                app_id TEXT,
                window_title TEXT,
                project_name TEXT,
                mode TEXT NOT NULL,
                original_text TEXT,
                model_id TEXT,
                refined INTEGER NOT NULL,
                pasted INTEGER NOT NULL,
                error_message TEXT,
                audio_seconds REAL NOT NULL,
                transcription_seconds REAL NOT NULL,
                refinement_seconds REAL,
                input_tokens INTEGER,
                output_tokens INTEGER,
                in_eval_set INTEGER NOT NULL DEFAULT 0
            );
            CREATE INDEX IF NOT EXISTS dictations_created_at ON dictations (created_at);
            """);
    }

    public event Action? Changed;

    public void Insert(DictationRecord record)
    {
        using var command = _connection.CreateCommand();
        command.CommandText = $"INSERT INTO dictations ({Columns}) VALUES " +
            "($created_at, $text, $raw_transcript, $app_name, $app_id, $window_title, $project_name, $mode, " +
            "$original_text, $model_id, $refined, $pasted, $error_message, $audio_seconds, $transcription_seconds, " +
            "$refinement_seconds, $input_tokens, $output_tokens, $in_eval_set); SELECT last_insert_rowid();";
        Bind(command, record);
        record.Id = (long)command.ExecuteScalar()!;
        Changed?.Invoke();
    }

    public void Update(DictationRecord record)
    {
        using var command = _connection.CreateCommand();
        command.CommandText = "UPDATE dictations SET pasted = $pasted, in_eval_set = $in_eval_set WHERE id = $id";
        command.Parameters.AddWithValue("$pasted", record.Pasted);
        command.Parameters.AddWithValue("$in_eval_set", record.InEvalSet);
        command.Parameters.AddWithValue("$id", record.Id);
        command.ExecuteNonQuery();
        Changed?.Invoke();
    }

    public void Delete(long id)
    {
        using var command = _connection.CreateCommand();
        command.CommandText = "DELETE FROM dictations WHERE id = $id";
        command.Parameters.AddWithValue("$id", id);
        command.ExecuteNonQuery();
        Changed?.Invoke();
    }

    /// <summary>Do mais novo para o mais antigo. A busca olha o texto entregue, a transcrição e o app.</summary>
    public IReadOnlyList<DictationRecord> Records(string? search = null, int limit = 500)
    {
        using var command = _connection.CreateCommand();
        var filter = string.IsNullOrWhiteSpace(search)
            ? ""
            : "WHERE text LIKE $search OR raw_transcript LIKE $search OR app_name LIKE $search OR project_name LIKE $search";
        command.CommandText = $"SELECT id, {Columns} FROM dictations {filter} ORDER BY created_at DESC, id DESC LIMIT $limit";
        if (filter.Length > 0) command.Parameters.AddWithValue("$search", $"%{search!.Trim()}%");
        command.Parameters.AddWithValue("$limit", limit);
        using var reader = command.ExecuteReader();
        var records = new List<DictationRecord>();
        while (reader.Read()) records.Add(Read(reader));
        return records;
    }

    public IReadOnlyList<DictationRecord> EvalSet() =>
        Records(limit: int.MaxValue).Where(r => r.InEvalSet).ToList();

    public void Dispose() => _connection.Dispose();

    private void Execute(string sql)
    {
        using var command = _connection.CreateCommand();
        command.CommandText = sql;
        command.ExecuteNonQuery();
    }

    private static void Bind(SqliteCommand command, DictationRecord record)
    {
        void Add(string name, object? value) => command.Parameters.AddWithValue(name, value ?? DBNull.Value);
        Add("$created_at", record.CreatedAt.ToString("O"));
        Add("$text", record.Text);
        Add("$raw_transcript", record.RawTranscript);
        Add("$app_name", record.AppName);
        Add("$app_id", record.AppId);
        Add("$window_title", record.WindowTitle);
        Add("$project_name", record.ProjectName);
        Add("$mode", record.Mode.RawValue());
        Add("$original_text", record.OriginalText);
        Add("$model_id", record.ModelId);
        Add("$refined", record.Refined);
        Add("$pasted", record.Pasted);
        Add("$error_message", record.ErrorMessage);
        Add("$audio_seconds", record.AudioSeconds);
        Add("$transcription_seconds", record.TranscriptionSeconds);
        Add("$refinement_seconds", record.RefinementSeconds);
        Add("$input_tokens", record.InputTokens);
        Add("$output_tokens", record.OutputTokens);
        Add("$in_eval_set", record.InEvalSet);
    }

    private static DictationRecord Read(SqliteDataReader reader)
    {
        string? Text(int i) => reader.IsDBNull(i) ? null : reader.GetString(i);
        return new DictationRecord
        {
            Id = reader.GetInt64(0),
            CreatedAt = DateTimeOffset.Parse(reader.GetString(1)),
            Text = reader.GetString(2),
            RawTranscript = reader.GetString(3),
            AppName = Text(4),
            AppId = Text(5),
            WindowTitle = Text(6),
            ProjectName = Text(7),
            Mode = DictationModeExtensions.ParseMode(reader.GetString(8)),
            OriginalText = Text(9),
            ModelId = Text(10),
            Refined = reader.GetBoolean(11),
            Pasted = reader.GetBoolean(12),
            ErrorMessage = Text(13),
            AudioSeconds = reader.GetDouble(14),
            TranscriptionSeconds = reader.GetDouble(15),
            RefinementSeconds = reader.IsDBNull(16) ? null : reader.GetDouble(16),
            InputTokens = reader.IsDBNull(17) ? null : reader.GetInt32(17),
            OutputTokens = reader.IsDBNull(18) ? null : reader.GetInt32(18),
            InEvalSet = reader.GetBoolean(19),
        };
    }
}
