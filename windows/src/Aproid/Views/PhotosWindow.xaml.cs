using Aproid.Model;
using Aproid.Shell;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using Windows.System;

namespace Aproid.Views;

/// The phone's gallery, in its own window, with a viewer for one photo at a time. Closing it only hides it.
public sealed partial class PhotosWindow : Window
{
    public PhotosWindow(PhotosStore store)
    {
        Store = store;
        InitializeComponent();

        SystemBackdrop = new MicaBackdrop();
        AppWindow.SetIcon(AppPaths.WindowIcon);
        AppWindow.Resize(new Windows.Graphics.SizeInt32(1040, 720));
        AppWindow.Closing += (_, args) =>
        {
            args.Cancel = true;
            Store.CloseViewer();
            AppWindow.Hide();
        };
        if (AppWindow.Presenter is OverlappedPresenter presenter)
        {
            presenter.PreferredMinimumWidth = 560;
            presenter.PreferredMinimumHeight = 420;
        }

        MonthsSource.Source = Store.Months;
        Gallery.ItemsSource = MonthsSource.View;
    }

    public PhotosStore Store { get; }

    public void Present()
    {
        AppWindow.Show(true);
        Activate();

        if (Store.IsEmpty) Store.LoadMore();
    }

    // Bound helpers

    public static ImageSource? Thumb(string? base64) => Pictures.FromBase64(base64, 264);

    /// The full photo once it arrived; until then, and for videos, the thumbnail.
    public ImageSource? Preview(string? file, PhotoItem? viewed)
    {
        if (viewed is null) return null;

        return !viewed.IsVideo && Pictures.FromFile(file) is { } full ? full : Pictures.FromBase64(viewed.Thumbnail);
    }

    public Visibility IsPlayableVideo(string? file, PhotoItem? viewed) =>
        viewed?.IsVideo == true && file is not null ? Visibility.Visible : Visibility.Collapsed;

    public string ViewedName(PhotoItem? viewed) => viewed?.Name ?? "";

    public string ViewedDate(PhotoItem? viewed) => viewed is null ? "" : $"{viewed.Date:dddd d MMMM yyyy}, {viewed.Date.ToShortTimeString()}";

    // Gallery

    private void Gallery_ContainerContentChanging(ListViewBase sender, ContainerContentChangingEventArgs args)
    {
        if (args.Item is PhotoItem item && Store.IsNearEnd(item)) Store.LoadMore();
    }

    private void Gallery_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        var count = Gallery.SelectedItems.Count;

        DownloadButton.IsEnabled = count > 0;
        DownloadLabel.Text = count > 1 ? $"Download {count}" : "Download";
    }

    private void Gallery_DoubleTapped(object sender, DoubleTappedRoutedEventArgs e)
    {
        if ((e.OriginalSource as FrameworkElement)?.DataContext is PhotoItem item) Store.Open(item.Id);
    }

    private void Download_Click(object sender, RoutedEventArgs e)
    {
        Store.Download(Gallery.SelectedItems.OfType<PhotoItem>().ToList());
        Gallery.SelectedItems.Clear();
    }

    private void Refresh_Click(object sender, RoutedEventArgs e) => Store.Refresh();

    private void OpenDownloads_Click(object sender, RoutedEventArgs e) => Explorer.Open(AppPaths.Downloads);

    // Viewer

    private void Root_KeyDown(object sender, KeyRoutedEventArgs e)
    {
        if (!Store.IsViewing) return;

        switch (e.Key)
        {
            case VirtualKey.Left:
                Store.Step(-1);
                break;
            case VirtualKey.Right:
                Store.Step(1);
                break;
            case VirtualKey.Escape:
                Store.CloseViewer();
                break;
            default:
                return;
        }

        e.Handled = true;
    }

    private void CloseViewer_Click(object sender, RoutedEventArgs e) => Store.CloseViewer();

    private void Previous_Click(object sender, RoutedEventArgs e) => Store.Step(-1);

    private void Next_Click(object sender, RoutedEventArgs e) => Store.Step(1);

    private void Retry_Click(object sender, RoutedEventArgs e) => Store.RetryPreview();

    private void DownloadViewed_Click(object sender, RoutedEventArgs e)
    {
        if (Store.Viewed is PhotoItem item) Store.Download([item]);
    }

    private void PlayVideo_Click(object sender, RoutedEventArgs e)
    {
        if (Store.ViewedFile is string file) Explorer.Open(file);
    }
}
