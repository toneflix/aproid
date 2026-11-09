using System.Collections.ObjectModel;
using Aproid.Core;

namespace Aproid.Model;

/// One photo in the grid. Its thumbnail stays as base64 so the grid can decode it only while it is on screen.
public sealed class PhotoItem(PhonePhoto photo) : Observable
{
    private bool downloading;

    public PhonePhoto Photo { get; } = photo;

    public long Id => Photo.Id;

    public string Name => Photo.Name;

    public string? Thumbnail => Photo.Thumbnail;

    public bool IsVideo => Photo.IsVideo;

    public DateTime Date => MessageTime.Local(Photo.Date);

    public bool IsDownloading
    {
        get => downloading;
        set => Set(ref downloading, value);
    }
}

/// One month of photos, under its own heading in the grid.
public sealed class PhotoMonth(DateTime month) : ObservableCollection<PhotoItem>
{
    public DateTime Month { get; } = month;

    public string Title => Month.ToString("MMMM yyyy");
}

/// The phone's gallery, loaded a page at a time for the Photos window. Use on the UI thread.
public sealed class PhotosStore : Observable
{
    private readonly Dictionary<long, PhotoItem> byId = [];
    private readonly List<PhotoItem> ordered = [];
    private readonly HashSet<long> requestedPreviews = [];
    private readonly HashSet<long> failedPreviews = [];
    private readonly Dictionary<long, string> previews = [];
    private string? deviceId;
    private bool hasPhone;
    private bool loading;
    private bool more = true;
    private long? viewing;

    /// Sends a packet to the phone the photos come from. Set by the app model.
    internal Func<NetworkPacket, bool>? Send { get; set; }

    public ObservableCollection<PhotoMonth> Months { get; } = [];

    public bool HasPhone
    {
        get => hasPhone;
        private set
        {
            if (Set(ref hasPhone, value)) RaiseStatus();
        }
    }

    public bool IsLoading
    {
        get => loading;
        private set
        {
            if (Set(ref loading, value)) RaiseStatus();
        }
    }

    public bool IsEmpty => ordered.Count == 0;

    public string EmptyText => !HasPhone ? "Connect your phone to see its photos" : IsLoading ? "Loading your photos…" : "No photos on your phone";

    public PhotoItem? Viewed => viewing is long id ? byId.GetValueOrDefault(id) : null;

    public bool IsViewing => Viewed is not null;

    /// The full photo for the viewer, once it arrived.
    public string? ViewedFile => viewing is long id ? previews.GetValueOrDefault(id) : null;

    public bool ViewedFailed => viewing is long id && failedPreviews.Contains(id);

    public bool ViewedLoading => IsViewing && ViewedFile is null && !ViewedFailed;

    public bool CanGoBack => viewing is long id && Neighbour(id, -1) is not null;

    public bool CanGoForward => viewing is long id && Neighbour(id, 1) is not null;

    /// A phone connected: start over with its gallery.
    public void Attach(string id)
    {
        HasPhone = true;
        if (deviceId == id) return;

        deviceId = id;
        Reset();
    }

    public void Detach(string id)
    {
        if (deviceId != id) return;

        HasPhone = false;
        IsLoading = false;
        failedPreviews.UnionWith(requestedPreviews);
        requestedPreviews.Clear();
        RaiseViewer();
    }

    /// Loads from the newest photo again.
    public void Refresh()
    {
        Reset();
        LoadMore();
    }

    /// Asks for the next, older page. Does nothing while one is on its way.
    public void LoadMore()
    {
        if (!HasPhone || !more || IsLoading) return;

        IsLoading = Send?.Invoke(Photos.RequestPacket(ordered.LastOrDefault()?.Photo.Date)) == true;
    }

    public void Ingest(Photos.Page page, string fromDevice)
    {
        if (fromDevice != deviceId) return;

        var fresh = page.Items.Where(p => !byId.ContainsKey(p.Id)).ToList();
        foreach (var item in fresh.Select(photo => new PhotoItem(photo)))
        {
            byId[item.Id] = item;
            ordered.Add(item);

            var month = new DateTime(item.Date.Year, item.Date.Month, 1);
            if (Months.LastOrDefault() is { } last && last.Month == month) last.Add(item);
            else Months.Add(new PhotoMonth(month) { item });
        }

        more = page.More && fresh.Count > 0;
        IsLoading = false;
        RaiseStatus();
    }

    /// Opens a photo in the viewer and fetches it in full, with the next one so stepping through is quick.
    public void Open(long id)
    {
        viewing = id;
        FetchPreview(id);

        if (Neighbour(id, 1) is { IsVideo: false } next) FetchPreview(next.Id);
        if (ordered.FindIndex(p => p.Id == id) >= ordered.Count - 5) LoadMore();

        RaiseViewer();
    }

    /// Moves the viewer to the previous (-1) or next (1) photo.
    public void Step(int offset)
    {
        if (viewing is long id && Neighbour(id, offset) is PhotoItem photo) Open(photo.Id);
    }

    public void CloseViewer()
    {
        viewing = null;
        RaiseViewer();
    }

    public void RetryPreview()
    {
        if (viewing is not long id) return;

        failedPreviews.Remove(id);
        requestedPreviews.Remove(id);
        FetchPreview(id);
        RaiseViewer();
    }

    public void IngestPreview(long id, string? file, string fromDevice)
    {
        if (fromDevice != deviceId) return;

        requestedPreviews.Remove(id);
        if (file is not null) previews[id] = file;
        else failedPreviews.Add(id);

        if (id == viewing) RaiseViewer();
    }

    /// The grid is showing one of the last photos loaded, so the next page should come.
    public bool IsNearEnd(PhotoItem item) => ordered.Count - ordered.IndexOf(item) <= 12;

    /// Asks the phone to send these in full. They arrive in Downloads like any shared file.
    public void Download(IEnumerable<PhotoItem> items)
    {
        foreach (var item in items.Where(i => !i.IsDownloading))
        {
            if (Send?.Invoke(Photos.DownloadPacket(item.Id)) == true) item.IsDownloading = true;
        }
    }

    private void FetchPreview(long id)
    {
        if (previews.ContainsKey(id) || failedPreviews.Contains(id) || requestedPreviews.Contains(id)) return;

        if (Send?.Invoke(Photos.DownloadPacket(id, preview: true)) == true) requestedPreviews.Add(id);
        else failedPreviews.Add(id);
    }

    private PhotoItem? Neighbour(long id, int offset)
    {
        var index = ordered.FindIndex(p => p.Id == id);
        if (index < 0) return null;

        index += offset;

        return index >= 0 && index < ordered.Count ? ordered[index] : null;
    }

    private void Reset()
    {
        byId.Clear();
        ordered.Clear();
        Months.Clear();
        previews.Clear();
        failedPreviews.Clear();
        requestedPreviews.Clear();
        viewing = null;
        more = true;
        IsLoading = false;
        RaiseStatus();
        RaiseViewer();
    }

    private void RaiseStatus()
    {
        Raise(nameof(IsEmpty));
        Raise(nameof(EmptyText));
    }

    private void RaiseViewer()
    {
        Raise(nameof(Viewed));
        Raise(nameof(IsViewing));
        Raise(nameof(ViewedFile));
        Raise(nameof(ViewedFailed));
        Raise(nameof(ViewedLoading));
        Raise(nameof(CanGoBack));
        Raise(nameof(CanGoForward));
    }
}
