using System.Windows.Input;
using Avalonia.Media;
using Avalonia.Threading;
using CyborgroidDashboard.Services;

namespace CyborgroidDashboard.ViewModels;

public sealed class MainViewModel : ViewModelBase
{
    public const int PageCount = 3;

    // gnome-control-center refuses to start outside a session that says it is GNOME.
    private const string SettingsCommand = "env XDG_CURRENT_DESKTOP=GNOME gnome-control-center";

    private static readonly IBrush Good = SolidColorBrush.Parse("#00FF7F");
    private static readonly IBrush Warn = SolidColorBrush.Parse("#FFB020");
    private static readonly IBrush Bad = SolidColorBrush.Parse("#FF5A5A");
    private static readonly IBrush Muted = SolidColorBrush.Parse("#888888");
    private static readonly IBrush Faint = SolidColorBrush.Parse("#44FFFFFF");

    private readonly CoreClient _core = new();
    private bool _polling;

    public MainViewModel()
    {
        ShowDashboard = new RelayCommand(() => Page = 1);
        ShowRadar = new RelayCommand(() => Page = 2);
        OpenSettings = Launcher(SettingsCommand);
        var terminal = First("ptyxis", "gnome-terminal");
        Tiles =
        [
            Tile("전화", "#2FB457", Icons.Phone, $"{terminal} -- baresip"),
            Tile("브라우저", "#FFFFFF", Icons.Globe, "firefox"),
            Tile("파일", "#2F74D0", Icons.Folder, "nautilus"),
            Tile("갤러리", "#5A4FB5", Icons.Image, First("loupe", "eog")),
            Tile("메모", "#2AA3C7", Icons.Note, First("gnome-text-editor", "gedit")),
            Tile("계산기", "#4A4F57", Icons.Calculator, "gnome-calculator"),
            Tile("터미널", "#3A3D42", Icons.Terminal, terminal),
            Tile("Wi-Fi", "#2F74D0", Icons.Wifi, $"{terminal} -- nmtui"),
            new AppTile("토큰", "#0F9D6B", Icons.Token, ShowDashboard),
            new AppTile("VPN", "#4A4F57", Icons.Shield, ShowDashboard),
            new AppTile("레이더", "#7A4FC0", Icons.Radar, ShowRadar),
            Tile("설정", "#E95420", Icons.Gear, SettingsCommand),
        ];

        var timer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(2) };
        timer.Tick += (_, _) => _ = RefreshAsync();
        timer.Start();
        _ = RefreshAsync();
    }

    public IReadOnlyList<AppTile> Tiles { get; }
    public ICommand ShowDashboard { get; }
    public ICommand ShowRadar { get; }
    public ICommand OpenSettings { get; }

    private static ICommand Launcher(string command) =>
        new RelayCommand(() => AppLauncher.Launch(command), IsAvailable(command));

    /// <summary>A tile whose app is missing stays visible but dimmed and inert.</summary>
    private static AppTile Tile(string title, string color, string icon, string command)
    {
        var available = IsAvailable(command);
        return new AppTile(title, color, icon, new RelayCommand(() => AppLauncher.Launch(command), available), available);
    }

    /// <summary>Ubuntu's default app differs by release; a PC run may have the older one.</summary>
    private static string First(params string[] apps) => apps.FirstOrDefault(AppLauncher.IsInstalled, apps[0]);

    /// <summary>Wrappers such as "ptyxis -- baresip" need both programs present.</summary>
    private static bool IsAvailable(string command) =>
        AppLauncher.IsInstalled(command) && AppLauncher.IsInstalled(command.Split(' ').Last());

    private int _page;
    public int Page
    {
        get => _page;
        set
        {
            var clamped = Math.Clamp(value, 0, PageCount - 1);
            Set(ref _page, clamped);
            Raise(nameof(IsHomePage), nameof(IsDashboardPage), nameof(IsRadarPage), nameof(Dot0), nameof(Dot1), nameof(Dot2));
        }
    }

    public bool IsHomePage => Page == 0;
    public bool IsDashboardPage => Page == 1;
    public bool IsRadarPage => Page == 2;
    public IBrush Dot0 => Page == 0 ? Brushes.White : Faint;
    public IBrush Dot1 => Page == 1 ? Brushes.White : Faint;
    public IBrush Dot2 => Page == 2 ? Brushes.White : Faint;

    private int _gridColumns = 3;
    public int GridColumns { get => _gridColumns; set => Set(ref _gridColumns, value); }

    private int _cardColumns = 1;
    public int CardColumns { get => _cardColumns; set => Set(ref _cardColumns, value); }

    private string _clock = DateTime.Now.ToString("HH:mm");
    public string Clock { get => _clock; private set => Set(ref _clock, value); }

    // Bindings named in the architecture spec's dashboard.
    private string _vpnStatus = "코어 엔진 연결 대기 중";
    public string VpnStatus { get => _vpnStatus; private set => Set(ref _vpnStatus, value); }

    private string _mintedTokens = "-";
    public string MintedTokens { get => _mintedTokens; private set => Set(ref _mintedTokens, value); }

    private string _trafficStatus = "-";
    public string TrafficStatus { get => _trafficStatus; private set => Set(ref _trafficStatus, value); }

    private IBrush _vpnBrush = Muted;
    public IBrush VpnBrush { get => _vpnBrush; private set => Set(ref _vpnBrush, value); }

    private string _batteryText = "--";
    public string BatteryText { get => _batteryText; private set => Set(ref _batteryText, value); }

    private double _batteryFraction;
    public double BatteryFraction { get => _batteryFraction; private set => Set(ref _batteryFraction, value); }

    private bool _batteryCharging;
    public bool BatteryCharging { get => _batteryCharging; private set => Set(ref _batteryCharging, value); }

    private string _spatialSummary = "-";
    public string SpatialSummary { get => _spatialSummary; private set => Set(ref _spatialSummary, value); }

    private IReadOnlyList<AccessPointInfo> _accessPoints = [];
    public IReadOnlyList<AccessPointInfo> AccessPoints { get => _accessPoints; private set => Set(ref _accessPoints, value); }

    private async Task RefreshAsync()
    {
        Clock = DateTime.Now.ToString("HH:mm");
        if (_polling)
        {
            return;
        }
        _polling = true;
        try
        {
            Apply(await _core.GetStatusAsync());
        }
        finally
        {
            _polling = false;
        }
    }

    private void Apply(CoreStatus? s)
    {
        if (s is null)
        {
            VpnStatus = "코어 엔진에 연결할 수 없음";
            VpnBrush = Bad;
            MintedTokens = "-";
            TrafficStatus = "cyborgroid-core 데몬 응답 없음";
            SpatialSummary = "-";
            AccessPoints = [];
            BatteryText = "--";
            BatteryFraction = 0;
            BatteryCharging = false;
            return;
        }

        (VpnStatus, VpnBrush) = DescribeVpn(s.Vpn);
        MintedTokens = s.Tokens.ToString("F4");
        TrafficStatus = s.RxError is null
            ? $"수신 {FormatBytes(s.TotalRxBytes)} · {ModeName(s.Mode)} · 공간: {DensityName(s.Spatial.Density)}"
            : $"트래픽 카운터 오류: {s.RxError}";
        SpatialSummary = s.ScanError is { } error
            ? $"스캔 실패: {error}"
            : DescribeSpatial(s.Spatial);
        AccessPoints = s.Spatial.AccessPoints;

        // No fuel gauge means no number: never show a made-up percentage.
        BatteryText = s.Battery is { } b ? $"{b.Percent}%" : "--";
        BatteryFraction = (s.Battery?.Percent ?? 0) / 100.0;
        BatteryCharging = s.Battery?.Charging ?? false;
    }

    private static (string, IBrush) DescribeVpn(VpnInfo v)
    {
        var killswitch = v.Killswitch ? "킬스위치 켜짐" : "킬스위치 꺼짐";
        if (v.Connected)
        {
            return ($"VPN 연결됨 · {killswitch}", Good);
        }
        if (v.InterfaceUp)
        {
            return ($"VPN 핸드셰이크 없음 · {killswitch}", Warn);
        }
        return v.Killswitch
            ? ("VPN 끊김 · 외부 통신 차단 중", Warn)
            : ("VPN 미설정 · 트래픽 보호되지 않음", Bad);
    }

    private static string DescribeSpatial(SpatialInfo s) =>
        s.Environment.Length == 0
            ? "첫 스캔 대기 중"
            : $"AP {s.ApCount}개 · {DensityName(s.Density)} · 평균 {s.MeanRssiDbm?.ToString("F0") ?? "-"} dBm · {EnvironmentName(s.Environment)}";

    private static string ModeName(string mode) => mode == "desktop" ? "데스크톱 모드" : "모바일 모드";

    private static string DensityName(string density) => density switch
    {
        "none" => "신호 없음",
        "sparse" => "한산함",
        "moderate" => "보통",
        "dense" => "밀집",
        _ => "측정 전",
    };

    private static string EnvironmentName(string environment) => environment switch
    {
        "stationary" => "제자리",
        "changing" => "변화 중",
        "moved" => "이동함",
        _ => "비교 대기",
    };

    private static string FormatBytes(long bytes) => bytes switch
    {
        >= 1L << 30 => $"{bytes / (double)(1L << 30):F2} GiB",
        >= 1L << 20 => $"{bytes / (double)(1L << 20):F1} MiB",
        >= 1L << 10 => $"{bytes / (double)(1L << 10):F0} KiB",
        _ => $"{bytes} B",
    };

    private void Raise(params string[] names)
    {
        foreach (var name in names)
        {
            RaiseChanged(name);
        }
    }
}
