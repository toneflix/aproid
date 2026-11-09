using System.ComponentModel;
using System.Runtime.CompilerServices;

namespace Aproid.Model;

/// Raises PropertyChanged so x:Bind can follow a property.
public abstract class Observable : INotifyPropertyChanged
{
    public event PropertyChangedEventHandler? PropertyChanged;

    protected void Raise([CallerMemberName] string? name = null) => PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));

    /// Sets the field and announces it when it changed.
    protected bool Set<T>(ref T field, T value, [CallerMemberName] string? name = null)
    {
        if (EqualityComparer<T>.Default.Equals(field, value)) return false;

        field = value;
        Raise(name);

        return true;
    }
}
