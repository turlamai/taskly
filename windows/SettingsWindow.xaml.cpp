#include "pch.h"

#include "SettingsWindow.xaml.h"
#if __has_include("SettingsWindow.g.cpp")
#include "SettingsWindow.g.cpp"
#endif

#include "MainWindow.xaml.h"

using namespace winrt;
using namespace winrt::Microsoft::UI::Xaml;
using namespace winrt::Microsoft::UI::Xaml::Controls;

namespace mx = winrt::Microsoft::UI::Xaml;

namespace winrt::RivetHost::implementation {

// Same host-wide i18n table as MainWindow (defined in MainWindow.xaml.cpp).
std::wstring t(char const* key);

namespace {
constexpr wchar_t const* kLanguages[] = {L"zh", L"en"};
constexpr wchar_t const* kThemes[] = {L"system", L"light", L"dark"};
}

SettingsWindow::SettingsWindow() {
  InitializeComponent();
  Title(hstring(t("menuSettings")));
  // The branded icon rides the EXE resource (RT_GROUP_ICON ID 1); WinUI 3
  // does not propagate it to secondary windows. Same pattern as MainWindow.
  if (HICON const icon =
          ::LoadIconW(::GetModuleHandleW(nullptr), MAKEINTRESOURCEW(1))) {
    AppWindow().SetIcon(winrt::Microsoft::UI::IconId{
        static_cast<std::uint64_t>(reinterpret_cast<UINT_PTR>(icon))});
  }
  ApplyAppLanguage();
}

void SettingsWindow::Initialize(hstring const& language, hstring const& theme,
                                bool auto_check) {
  updating_visuals_ = true;
  FillLanguageBox(language);
  FillThemeBox(theme);
  AutoCheckSwitch().IsOn(auto_check);
  updating_visuals_ = false;
}

void SettingsWindow::SyncAutoCheck(bool auto_check) {
  updating_visuals_ = true;
  AutoCheckSwitch().IsOn(auto_check);
  updating_visuals_ = false;
}

void SettingsWindow::ApplyAppLanguage() {
  Title(hstring(t("menuSettings")));
  LanguageCaption().Text(t("menuLanguage"));
  ThemeCaption().Text(t("menuTheme"));
  AutoCheckCaption().Text(t("settingsAutoCheckUpdates"));
  // The row's TextBlock carries the caption; the switch renders bare.
  AutoCheckSwitch().OnContent(winrt::box_value(hstring(L"")));
  AutoCheckSwitch().OffContent(winrt::box_value(hstring(L"")));
  // Rebuild the combo labels for the new language, keeping the selections.
  updating_visuals_ = true;
  FillLanguageBox(SelectedLanguage());
  FillThemeBox(SelectedTheme());
  updating_visuals_ = false;
}

void SettingsWindow::ApplyAppTheme(hstring const& theme) {
  if (theme == L"light") {
    RootGrid().RequestedTheme(mx::ElementTheme::Light);
  } else if (theme == L"dark") {
    RootGrid().RequestedTheme(mx::ElementTheme::Dark);
  } else {
    RootGrid().RequestedTheme(mx::ElementTheme::Default);
  }
}

hstring SettingsWindow::SelectedLanguage() const {
  auto const index = LanguageBox().SelectedIndex();
  return hstring(index >= 0 && index < 2 ? kLanguages[index] : L"zh");
}

hstring SettingsWindow::SelectedTheme() const {
  auto const index = ThemeBox().SelectedIndex();
  return hstring(index >= 0 && index < 3 ? kThemes[index] : L"system");
}

bool SettingsWindow::AutoCheckUpdatesOn() const {
  return AutoCheckSwitch().IsOn();
}

void SettingsWindow::FillLanguageBox(hstring const& language) {
  auto box = LanguageBox();
  box.Items().Clear();
  constexpr char const* kKeys[] = {"menuLangZh", "menuLangEn"};
  int selected = 0;
  for (std::size_t i = 0; i < 2; ++i) {
    ComboBoxItem item;
    item.Content(winrt::box_value(hstring(t(kKeys[i]))));
    box.Items().Append(item);
    if (language == kLanguages[i]) selected = static_cast<int>(i);
  }
  box.SelectedIndex(selected);
}

void SettingsWindow::FillThemeBox(hstring const& theme) {
  auto box = ThemeBox();
  box.Items().Clear();
  constexpr char const* kKeys[] = {"themeFollowSystem", "themeLight",
                                   "themeDark"};
  int selected = 0;
  for (std::size_t i = 0; i < 3; ++i) {
    ComboBoxItem item;
    item.Content(winrt::box_value(hstring(t(kKeys[i]))));
    box.Items().Append(item);
    if (theme == kThemes[i]) selected = static_cast<int>(i);
  }
  box.SelectedIndex(selected);
}

winrt::event_token SettingsWindow::LanguageCommitted(
    winrt::Windows::Foundation::TypedEventHandler<
        winrt::RivetHost::SettingsWindow,
        winrt::Windows::Foundation::IInspectable> const& handler) {
  return language_committed_.add(handler);
}

void SettingsWindow::LanguageCommitted(winrt::event_token token) {
  language_committed_.remove(token);
}

winrt::event_token SettingsWindow::ThemeCommitted(
    winrt::Windows::Foundation::TypedEventHandler<
        winrt::RivetHost::SettingsWindow,
        winrt::Windows::Foundation::IInspectable> const& handler) {
  return theme_committed_.add(handler);
}

void SettingsWindow::ThemeCommitted(winrt::event_token token) {
  theme_committed_.remove(token);
}

winrt::event_token SettingsWindow::AutoCheckCommitted(
    winrt::Windows::Foundation::TypedEventHandler<
        winrt::RivetHost::SettingsWindow,
        winrt::Windows::Foundation::IInspectable> const& handler) {
  return auto_check_committed_.add(handler);
}

void SettingsWindow::AutoCheckCommitted(winrt::event_token token) {
  auto_check_committed_.remove(token);
}

void SettingsWindow::OnLanguageSelected(
    winrt::Windows::Foundation::IInspectable const&,
    SelectionChangedEventArgs const&) {
  if (updating_visuals_) return;
  language_committed_(*this, nullptr);
}

void SettingsWindow::OnThemeSelected(
    winrt::Windows::Foundation::IInspectable const&,
    SelectionChangedEventArgs const&) {
  if (updating_visuals_) return;
  theme_committed_(*this, nullptr);
}

void SettingsWindow::OnAutoCheckToggled(
    winrt::Windows::Foundation::IInspectable const&,
    RoutedEventArgs const&) {
  if (updating_visuals_) return;
  auto_check_committed_(*this, nullptr);
}

}  // namespace winrt::RivetHost::implementation
