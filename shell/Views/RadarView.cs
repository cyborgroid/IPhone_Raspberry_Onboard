using Avalonia;
using Avalonia.Controls;
using Avalonia.Media;
using CyborgroidDashboard.Services;

namespace CyborgroidDashboard.Views;

/// <summary>
/// Plots access points by signal strength: nearer the centre is stronger. RSSI
/// has no direction, so the angle only keeps each AP's dot in a stable place.
/// </summary>
public sealed class RadarView : Control
{
    public static readonly StyledProperty<IReadOnlyList<AccessPointInfo>?> AccessPointsProperty =
        AvaloniaProperty.Register<RadarView, IReadOnlyList<AccessPointInfo>?>(nameof(AccessPoints));

    private const float StrongestDbm = -30;
    private const float WeakestDbm = -95;

    private static readonly Pen RingPen = new(SolidColorBrush.Parse("#3300FF7F"), 1);
    private static readonly IBrush Band24 = SolidColorBrush.Parse("#00FF7F");
    private static readonly IBrush Band5 = SolidColorBrush.Parse("#4FC3F7");
    private static readonly IBrush Band6 = SolidColorBrush.Parse("#C792EA");

    static RadarView() => AffectsRender<RadarView>(AccessPointsProperty);

    public IReadOnlyList<AccessPointInfo>? AccessPoints
    {
        get => GetValue(AccessPointsProperty);
        set => SetValue(AccessPointsProperty, value);
    }

    public override void Render(DrawingContext context)
    {
        var centre = new Point(Bounds.Width / 2, Bounds.Height / 2);
        var radius = Math.Min(Bounds.Width, Bounds.Height) / 2 - 8;
        if (radius <= 0)
        {
            return;
        }

        for (var ring = 1; ring <= 4; ring++)
        {
            context.DrawEllipse(null, RingPen, centre, radius * ring / 4, radius * ring / 4);
        }
        context.DrawEllipse(Band24, null, centre, 3, 3);

        foreach (var ap in AccessPoints ?? [])
        {
            var strength = Math.Clamp((StrongestDbm - ap.RssiDbm) / (StrongestDbm - WeakestDbm), 0f, 1f);
            var distance = radius * (0.12 + 0.88 * strength);
            var angle = (ap.Id % 360) * Math.PI / 180;
            var dot = new Point(centre.X + distance * Math.Cos(angle), centre.Y + distance * Math.Sin(angle));
            var brush = ap.FreqMhz < 3000 ? Band24 : ap.FreqMhz < 5900 ? Band5 : Band6;
            context.DrawEllipse(brush, null, dot, 4, 4);
        }
    }
}
