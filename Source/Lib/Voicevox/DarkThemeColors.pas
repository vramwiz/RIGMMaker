unit DarkThemeColors;

// Syncroh2基準の共通ダーク配色を定義し、画面ごとの色定義重複を防ぐ。
interface

uses
  Vcl.Graphics;

const
  DarkThemeAccent = TColor($00B03C3C);

  DarkThemePanelBackground = TColor($002B2B2B);
  DarkThemePanelBorder = TColor($004A4A4A);
  DarkThemePanelText = TColor($00DCDCDC);

  DarkThemeControlBackground = TColor($00353535);
  DarkThemeControlBorder = TColor($00505050);
  DarkThemeControlText = clWhite;
  DarkThemeControlHot = TColor($00454545);
  DarkThemeControlPressed = TColor($00282828);
  DarkThemeControlDisabled = TColor($002A2A2A);
  DarkThemeControlDisabledText = TColor($00888888);

  DarkThemeEditBackground = TColor($003A3A3A);
  DarkThemeEditBorder = TColor($00505050);
  DarkThemeEditText = clWhite;
  DarkThemeEditBackgroundFocus = TColor($00404040);
  DarkThemeEditBorderFocus = TColor($006A6A6A);
  DarkThemeEditDisabled = TColor($002A2A2A);
  DarkThemeEditDisabledText = TColor($00888888);

  DarkThemeMemoBackground = TColor($003A3A3A);
  DarkThemeMemoBorder = TColor($00505050);
  DarkThemeMemoText = clWhite;
  DarkThemeMemoBackgroundFocus = TColor($00404040);
  DarkThemeMemoBorderFocus = TColor($006A6A6A);
  DarkThemeMemoDisabled = TColor($002A2A2A);
  DarkThemeMemoDisabledText = TColor($00888888);
  DarkThemeMemoSelection = TColor($001F3C70);
  DarkThemeMemoSelectionText = clWhite;
  DarkThemeMemoCaret = clWhite;
  DarkThemeMemoLineNumberBack = TColor($002F2F2F);
  DarkThemeMemoLineNumberText = TColor($00AAAAAA);
  DarkThemeMemoCurrentLine = TColor($00333333);

  DarkThemeComboBackground = TColor($003A3A3A);
  DarkThemeComboText = clWhite;
  DarkThemeComboButton = TColor($00505050);
  DarkThemeComboHighlight = TColor($002D5AA7);

  DarkThemeListBackground = TColor($001E1E1E);
  DarkThemeListAltBackground = TColor($00323232);
  DarkThemeListAltBackground2 = TColor($00464646);
  DarkThemeListText = TColor($00DCDCDC);
  DarkThemeListHot = DarkThemeAccent;
  DarkThemeListSelection = TColor($00FF6666);
  DarkThemeListSelectionText = clWhite;

  DarkThemeListViewAltBackground = TColor($002A2A2A);
  DarkThemeListViewFixedBackground = TColor($002B2B2B);
  DarkThemeListViewBorderLight = TColor($00505050);
  DarkThemeListViewBorderDark = TColor($002C2C2C);

  DarkThemeTabBackground = TColor($002B2B2B);
  DarkThemeTabNormal = TColor($003A3A3A);
  DarkThemeTabHot = TColor($00444444);
  DarkThemeTabActive = clBlue;
  DarkThemeTabText = TColor($00DCDCDC);
  DarkThemeTabActiveText = clWhite;
  DarkThemeTabBorder = TColor($004A4A4A);

  DarkThemeTextNormal = TColor($00DCDCDC);
  DarkThemeTextDisabled = TColor($00828282);
  DarkThemeBorder = DarkThemeAccent;
  DarkThemeHighlight = TColor($00627DE7);
  DarkThemeHover = TColor($00464646);

  DarkThemeToolBarBackground = TColor($002B2B2B);
  DarkThemeToolBarHot = DarkThemeAccent;
  DarkThemeToolBarPressed = TColor($001F1F1F);
  DarkThemeToolBarChecked = TColor($00FF6666);
  DarkThemeToolBarFont = clWhite;

  DarkThemeTreeBackground = TColor($001E1E1E);
  DarkThemeTreeText = TColor($00DCDCDC);
  DarkThemeTreeSelection = clBlue;
  DarkThemeTreeSelectionText = clWhite;
  DarkThemeTreeLine = DarkThemeAccent;
  DarkThemeTreeExpand = TColor($00C0C0C0);

  DarkThemePreviewBackground = TColor($002A2A2A);
  DarkThemePreviewBorder = DarkThemeAccent;
  DarkThemePreviewChecker1 = TColor($004A4A4A);
  DarkThemePreviewChecker2 = TColor($003A3A3A);

implementation

end.
