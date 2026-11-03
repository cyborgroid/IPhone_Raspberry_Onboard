using System.Windows.Input;

namespace CyborgroidDashboard.ViewModels;

public sealed class RelayCommand(Action execute, bool enabled = true) : ICommand
{
    public event EventHandler? CanExecuteChanged { add { } remove { } }

    public bool CanExecute(object? parameter) => enabled;

    public void Execute(object? parameter) => execute();
}
