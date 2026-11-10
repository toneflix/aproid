using Aproid.Icons;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace Aproid.Views;

/// One action in the grid: an icon chip with a title and a hint.
public sealed class ActionTile : Button
{
    public static readonly DependencyProperty IconProperty =
        DependencyProperty.Register(nameof(Icon), typeof(Lucide), typeof(ActionTile), new PropertyMetadata(Lucide.File, (d, _) => ((ActionTile)d).Update()));

    public static readonly DependencyProperty TitleProperty =
        DependencyProperty.Register(nameof(Title), typeof(string), typeof(ActionTile), new PropertyMetadata("", (d, _) => ((ActionTile)d).Update()));

    public static readonly DependencyProperty SubtitleProperty =
        DependencyProperty.Register(nameof(Subtitle), typeof(string), typeof(ActionTile), new PropertyMetadata("", (d, _) => ((ActionTile)d).Update()));

    public static readonly DependencyProperty IsOnProperty =
        DependencyProperty.Register(nameof(IsOn), typeof(bool), typeof(ActionTile), new PropertyMetadata(true, (d, _) => ((ActionTile)d).Update()));

    private readonly LucideIcon icon = new() { Size = 15 };
    private readonly Border chip = new() { Width = 34, Height = 34, CornerRadius = new CornerRadius(9) };
    private readonly TextBlock title = new() { FontSize = 13, FontWeight = Microsoft.UI.Text.FontWeights.SemiBold, TextTrimming = TextTrimming.CharacterEllipsis };
    private readonly TextBlock subtitle = new() { FontSize = 11, TextTrimming = TextTrimming.CharacterEllipsis };

    public ActionTile()
    {
        Style = (Style)Application.Current.Resources["AproidTileButton"];
        chip.Child = icon;
        subtitle.SetValue(TextBlock.ForegroundProperty, Application.Current.Resources["AproidSubBrush"]);

        var text = new StackPanel { VerticalAlignment = VerticalAlignment.Center, Spacing = 1, Children = { title, subtitle } };
        var row = new Grid { ColumnSpacing = 10 };
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        Grid.SetColumn(text, 1);
        row.Children.Add(chip);
        row.Children.Add(text);
        Content = row;

        Update();
    }

    public Lucide Icon
    {
        get => (Lucide)GetValue(IconProperty);
        set => SetValue(IconProperty, value);
    }

    public string Title
    {
        get => (string)GetValue(TitleProperty);
        set => SetValue(TitleProperty, value);
    }

    public string Subtitle
    {
        get => (string)GetValue(SubtitleProperty);
        set => SetValue(SubtitleProperty, value);
    }

    public bool IsOn
    {
        get => (bool)GetValue(IsOnProperty);
        set => SetValue(IsOnProperty, value);
    }

    private void Update()
    {
        icon.Icon = Icon;
        title.Text = Title;
        subtitle.Text = Subtitle;
        subtitle.Visibility = string.IsNullOrEmpty(Subtitle) ? Visibility.Collapsed : Visibility.Visible;
        chip.SetValue(Border.BackgroundProperty, Application.Current.Resources[IsOn ? "AproidTintBrush" : "AproidThumbBrush"]);
        icon.SetValue(ForegroundProperty, Application.Current.Resources[IsOn ? "AproidAccentBrush" : "AproidSubBrush"]);
        Microsoft.UI.Xaml.Automation.AutomationProperties.SetName(this, string.IsNullOrEmpty(Subtitle) ? Title : $"{Title}, {Subtitle}");
    }
}
