using System.Net.Http.Json;
using System.Text.Json.Serialization;

namespace Aproid.Shell;

/// An error from the licence server, such as "bad_code" or "computer_limit".
internal sealed class LicenceServerException(string code) : Exception(code)
{
    public string Code { get; } = code;
}

/// Talks to the licence API on the Aproid website.
internal sealed class LicenceServer
{
    public const string Site = "https://aproid.toneflix.com";

    private static readonly HttpClient Http = new() { BaseAddress = new Uri(Site), Timeout = TimeSpan.FromSeconds(20) };

    public sealed record Activation([property: JsonPropertyName("token")] string Token, [property: JsonPropertyName("secret")] string Secret);

    private sealed record TokenReply([property: JsonPropertyName("token")] string Token);

    private sealed record ErrorReply([property: JsonPropertyName("error")] string? Error);

    public async Task<string> TrialAsync(string machine) =>
        (await PostAsync<TokenReply>("/api/trial", new { machine })).Token;

    public async Task SendCodeAsync(string email) => await PostAsync<object>("/api/code", new { email });

    public Task<Activation> ActivateAsync(string email, string code, string machine, string name) =>
        PostAsync<Activation>("/api/activate", new { email, code, machine = new { id = machine, name, platform = "windows" } });

    public async Task<string> RefreshAsync(string machine, string secret) =>
        (await PostAsync<TokenReply>("/api/refresh", new { machine, secret })).Token;

    private static async Task<T> PostAsync<T>(string path, object body)
    {
        using var response = await Http.PostAsJsonAsync(path, body);

        if (!response.IsSuccessStatusCode)
        {
            var error = await response.Content.ReadFromJsonAsync<ErrorReply>().ConfigureAwait(false);
            throw new LicenceServerException(error?.Error ?? "server_error");
        }

        return response.StatusCode == System.Net.HttpStatusCode.NoContent ? default! : (await response.Content.ReadFromJsonAsync<T>())!;
    }
}
