using Avalonia;
using Avalonia.Controls;
using Avalonia.Input;
using Avalonia.Interactivity;
using CyborgroidDashboard.ViewModels;

namespace CyborgroidDashboard.Views;

public partial class MainWindow : Window
{
    private const double SwipeThreshold = 80;

    private Point? _swipeStart;

    public MainWindow()
    {
        InitializeComponent();
        // Tunnelling, so a swipe that starts on a tile still turns the page.
        AddHandler(PointerPressedEvent, OnPressed, RoutingStrategies.Tunnel);
        AddHandler(PointerReleasedEvent, OnReleased, RoutingStrategies.Tunnel);
        SizeChanged += (_, e) =>
        {
            if (DataContext is MainViewModel vm)
            {
                var landscape = e.NewSize.Width >= e.NewSize.Height;
                vm.GridColumns = landscape ? 4 : 3;
                vm.CardColumns = landscape ? 2 : 1;
            }
        };
    }

    private void OnPressed(object? sender, PointerPressedEventArgs e) => _swipeStart = e.GetPosition(this);

    private void OnReleased(object? sender, PointerReleasedEventArgs e)
    {
        if (_swipeStart is not { } start || DataContext is not MainViewModel vm)
        {
            return;
        }
        _swipeStart = null;
        var delta = e.GetPosition(this) - start;
        if (Math.Abs(delta.X) >= SwipeThreshold && Math.Abs(delta.X) > Math.Abs(delta.Y))
        {
            vm.Page += delta.X < 0 ? 1 : -1;
        }
    }
}
