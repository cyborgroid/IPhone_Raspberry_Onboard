using System.ComponentModel;
using System.Runtime.CompilerServices;

namespace CyborgroidDashboard.ViewModels;

public abstract class ViewModelBase : INotifyPropertyChanged
{
    public event PropertyChangedEventHandler? PropertyChanged;

    protected void Set<T>(ref T field, T value, [CallerMemberName] string? name = null)
    {
        if (!EqualityComparer<T>.Default.Equals(field, value))
        {
            field = value;
            RaiseChanged(name);
        }
    }

    protected void RaiseChanged(string? name) => PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
}
