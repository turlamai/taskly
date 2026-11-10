#pragma once

#include "pch.h"
#include "SettingsWindow.g.h"

namespace winrt::RivetHost::implementation {

// PRODUCT-SPEC §8: the settings window (⌘,/Ctrl+,). Presentational only —
// the preference state, application (ApplyLanguage/ApplyTheme) and
// persistence (SaveSettingAsync) stay in MainWindow, which subscribes to
// the Committed events raised by the user acting on a control.
struct SettingsWindow : SettingsWindowT<SettingsWindow> {
  SettingsWindow();

  void Initialize(hstring const& language, hstring const& theme,
                  bool auto_check);
  void SyncAutoCheck(bool auto_check);
  void ApplyAppLanguage();
  void ApplyAppTheme(hstring const& theme);

  hstring SelectedLanguage() const;
  hstring SelectedTheme() const;
  bool AutoCheckUpdatesOn() const;

  winrt::event_token LanguageCommitted(
      winrt::Windows::Foundation::TypedEventHandler<
          winrt::RivetHost::SettingsWindow, winrt::Windows::Foundation::IInspectable> const&
          handler);
  void LanguageCommitted(winrt::event_token token);
  winrt::event_token ThemeCommitted(
      winrt::Windows::Foundation::TypedEventHandler<
          winrt::RivetHost::SettingsWindow, winrt::Windows::Foundation::IInspectable> const&
          handler);
  void ThemeCommitted(winrt::event_token token);
  winrt::event_token AutoCheckCommitted(
      winrt::Windows::Foundation::TypedEventHandler<
          winrt::RivetHost::SettingsWindow, winrt::Windows::Foundation::IInspectable> const&
          handler);
  void AutoCheckCommitted(winrt::event_token token);

  void OnLanguageSelected(winrt::Windows::Foundation::IInspectable const&,
                          winrt::Microsoft::UI::Xaml::Controls::SelectionChangedEventArgs const&);
  void OnThemeSelected(winrt::Windows::Foundation::IInspectable const&,
                       winrt::Microsoft::UI::Xaml::Controls::SelectionChangedEventArgs const&);
  void OnAutoCheckToggled(winrt::Windows::Foundation::IInspectable const&,
                          winrt::Microsoft::UI::Xaml::RoutedEventArgs const&);

 private:
  void FillLanguageBox(hstring const& language);
  void FillThemeBox(hstring const& theme);

  winrt::event<winrt::Windows::Foundation::TypedEventHandler<
      winrt::RivetHost::SettingsWindow, winrt::Windows::Foundation::IInspectable>>
      language_committed_;
  winrt::event<winrt::Windows::Foundation::TypedEventHandler<
      winrt::RivetHost::SettingsWindow, winrt::Windows::Foundation::IInspectable>>
      theme_committed_;
  winrt::event<winrt::Windows::Foundation::TypedEventHandler<
      winrt::RivetHost::SettingsWindow, winrt::Windows::Foundation::IInspectable>>
      auto_check_committed_;
  // Guards the SelectionChanged/Toggled handlers while Initialize and the
  // Apply* methods sync visuals to state.
  bool updating_visuals_{false};
};

}  // namespace winrt::RivetHost::implementation

namespace winrt::RivetHost::factory_implementation {

struct SettingsWindow : SettingsWindowT<SettingsWindow, implementation::SettingsWindow> {};

}  // namespace winrt::RivetHost::factory_implementation
