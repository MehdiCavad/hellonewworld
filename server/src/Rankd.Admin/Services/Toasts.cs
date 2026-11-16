namespace Rankd.Admin.Services;

public sealed record Toast(Guid Id, string Message, bool IsError);

/// <summary>Per-circuit toast queue rendered by the layout.</summary>
public sealed class Toasts
{
    private readonly List<Toast> _items = new();
    public IReadOnlyList<Toast> Items => _items;
    public event Action? Changed;

    public void Show(string message, bool error = false)
    {
        var toast = new Toast(Guid.NewGuid(), message, error);
        _items.Add(toast);
        Changed?.Invoke();
        _ = DismissLater(toast.Id);
    }

    private async Task DismissLater(Guid id)
    {
        await Task.Delay(3800);
        _items.RemoveAll(t => t.Id == id);
        Changed?.Invoke();
    }
}
