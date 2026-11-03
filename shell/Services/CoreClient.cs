using System.Net.Sockets;
using System.Text;
using System.Text.Json;

namespace CyborgroidDashboard.Services;

public sealed record BatteryInfo(int Percent, bool Charging);

public sealed record VpnInfo(bool InterfaceUp, long? HandshakeAgeSecs, bool Connected, bool Killswitch);

public sealed record AccessPointInfo(long Id, string Ssid, int FreqMhz, int Channel, float RssiDbm);

public sealed record SpatialInfo(
    int ApCount,
    float? MeanRssiDbm,
    string Density,
    double? Similarity,
    string Environment,
    Dictionary<string, int> Channels,
    List<AccessPointInfo> AccessPoints);

public sealed record CoreStatus(
    string Mode,
    bool ModeForced,
    double Tokens,
    long TotalRxBytes,
    string? RxError,
    BatteryInfo? Battery,
    VpnInfo Vpn,
    string? ScanError,
    SpatialInfo Spatial);

/// <summary>Client for the cyborgroid-core line-delimited JSON socket.</summary>
public sealed class CoreClient
{
    private static readonly JsonSerializerOptions Json = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.SnakeCaseLower,
    };

    private readonly string _socketPath =
        Environment.GetEnvironmentVariable("CYBORGROID_SOCKET") ?? "/run/cyborgroid/core.sock";

    /// <summary>Returns null while the daemon is unreachable.</summary>
    public async Task<CoreStatus?> GetStatusAsync()
    {
        try
        {
            using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(2));
            using var socket = new Socket(AddressFamily.Unix, SocketType.Stream, ProtocolType.Unspecified);
            await socket.ConnectAsync(new UnixDomainSocketEndPoint(_socketPath), timeout.Token);
            await using var stream = new NetworkStream(socket);
            await stream.WriteAsync(Encoding.UTF8.GetBytes("{\"cmd\":\"status\"}\n"), timeout.Token);
            using var reader = new StreamReader(stream, Encoding.UTF8);
            var line = await reader.ReadLineAsync(timeout.Token);
            return line is null ? null : JsonSerializer.Deserialize<CoreStatus>(line, Json);
        }
        catch (Exception e) when (e is SocketException or IOException or OperationCanceledException or JsonException)
        {
            return null;
        }
    }
}
