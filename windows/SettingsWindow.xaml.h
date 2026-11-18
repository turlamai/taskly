#pragma once

#include "pch.h"
#include "SettingsWindow.g.h"

namespace winrt::RivetHost::implementation {

// PRODUCT-SPEC §8 + §2a: the settings window (⌘,/Ctrl+,). Presentational
// only — the preference state, application (ApplyLanguage/ApplyTheme) and
// persistence (SaveSettingAsync) stay in MainWindow, which subscribes to
// the Committed/DataAction events raised by the user acting on a control.
// The §2a database/lists snapshot is pushed in through SyncDatabaseState.
struct SettingsWindow : SettingsWindowT<SettingsWindow> {
  SettingsWindow();

  void Initialize(hstring const& language, hstring const& theme,
                  bool auto_check);
  void SyncAutoCheck(bool auto_check);
  void ApplyAppLanguage();
  void ApplyAppTheme(hstring const& theme);

  // §2a: push the current database identity + lists (no events fire; the
  // caller keeps ownership of persistence).
  void SyncDatabaseState(
      hstring const& database_name, hstring const& database_path,
      bool connected,
      winrt::Windows::Foundation::Collections::IVectorView<std::int64_t> const&
          list_ids,
      winrt::Windows::Foundation::Collections::IVectorView<hstring> const&
          list_names,
      std::int64_t default_list_id, hstring const& quick_add);
  // Status line under the 数据 group (export/restore/migrate outcomes).
  void SetDataFeedback(hstring const& message);
  // §2a restore step 2: explicit replacement confirmation hosted here; true
  // only for the confirm button.
  winrt::Windows::Foundation::IAsyncOperation<bool> ConfirmRestoreAsync(
      hstring const& body);

  // Non-const: the generated XAML accessors are non-const, and these
  // read the live controls.
  hstring SelectedLanguage();
  hstring SelectedTheme();
  bool AutoCheckUpdatesOn();

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
  winrt::event_token DataActionRequested(
      winrt::Windows::Foundation::TypedEventHandler<
          winrt::RivetHost::SettingsWindow, winrt::Windows::Foundation::IInspectable> const&
          handler);
  void DataActionRequested(winrt::event_token token);
  winrt::event_token DefaultListCommitted(
      winrt::Windows::Foundation::TypedEventHandler<
          winrt::RivetHost::SettingsWindow, winrt::Windows::Foundation::IInspectable> const&
          handler);
  void DefaultListCommitted(winrt::event_token token);
  winrt::event_token QuickAddCommitted(
      winrt::Windows::Foundation::TypedEventHandler<
          winrt::RivetHost::SettingsWindow, winrt::Windows::Foundation::IInspectable> const&
          handler);
  void QuickAddCommitted(winrt::event_token token);

  void OnLanguageSelected(winrt::Windows::Foundation::IInspectable const&,
                          winrt::Microsoft::UI::Xaml::Controls::SelectionChangedEventArgs const&);
  void OnThemeSelected(winrt::Windows::Foundation::IInspectable const&,
                       winrt::Microsoft::UI::Xaml::Controls::SelectionChangedEventArgs const&);
  void OnAutoCheckToggled(winrt::Windows::Foundation::IInspectable const&,
                          winrt::Microsoft::UI::Xaml::RoutedEventArgs const&);
  // §2a handlers (新任务 + 数据 groups).
  void OnDataActionClicked(winrt::Windows::Foundation::IInspectable const&,
                           winrt::Microsoft::UI::Xaml::RoutedEventArgs const&);
  void OnDefaultListSelected(winrt::Windows::Foundation::IInspectable const&,
                             winrt::Microsoft::UI::Xaml::Controls::SelectionChangedEventArgs const&);
  void OnQuickAddRecorderClicked(winrt::Windows::Foundation::IInspectable const&,
                                 winrt::Microsoft::UI::Xaml::RoutedEventArgs const&);
  void OnQuickAddResetClicked(winrt::Windows::Foundation::IInspectable const&,
                              winrt::Microsoft::UI::Xaml::RoutedEventArgs const&);
  void OnQuickAddClearClicked(winrt::Windows::Foundation::IInspectable const&,
                              winrt::Microsoft::UI::Xaml::RoutedEventArgs const&);

 private:
  void FillLanguageBox(hstring const& language);
  void FillThemeBox(hstring const& theme);
  void FillDefaultListComboBox();
  void RenderQuickAdd();
  void StartQuickAddRecording();
  void StopQuickAddRecording();
  void HandleRecorderKey(winrt::Microsoft::UI::Xaml::Input::KeyRoutedEventArgs const& args);
  static std::wstring RecorderKeyName(
      winrt::Windows::System::VirtualKey key);

  winrt::event<winrt::Windows::Foundation::TypedEventHandler<
      winrt::RivetHost::SettingsWindow, winrt::Windows::Foundation::IInspectable>>
      language_committed_;
  winrt::event<winrt::Windows::Foundation::TypedEventHandler<
      winrt::RivetHost::SettingsWindow, winrt::Windows::Foundation::IInspectable>>
      theme_committed_;
  winrt::event<winrt::Windows::Foundation::TypedEventHandler<
      winrt::RivetHost::SettingsWindow, winrt::Windows::Foundation::IInspectable>>
      auto_check_committed_;
  winrt::event<winrt::Windows::Foundation::TypedEventHandler<
      winrt::RivetHost::SettingsWindow, winrt::Windows::Foundation::IInspectable>>
      data_action_requested_;
  winrt::event<winrt::Windows::Foundation::TypedEventHandler<
      winrt::RivetHost::SettingsWindow, winrt::Windows::Foundation::IInspectable>>
      default_list_committed_;
  winrt::event<winrt::Windows::Foundation::TypedEventHandler<
      winrt::RivetHost::SettingsWindow, winrt::Windows::Foundation::IInspectable>>
      quick_add_committed_;
  // Guards the SelectionChanged/Toggled handlers while Initialize, the
  // Apply* methods and SyncDatabaseState sync visuals to state.
  bool updating_visuals_{false};
  // §2a 新任务 group state (mirrors what MainWindow pushed in).
  std::vector<std::int64_t> default_list_ids_;
  std::vector<std::wstring> default_list_names_;
  std::int64_t default_list_id_{0};
  bool database_connected_{false};
  std::wstring quick_add_;
  bool quick_add_recording_{false};
};

}  // namespace winrt::RivetHost::implementation

namespace winrt::RivetHost::factory_implementation {

struct SettingsWindow : SettingsWindowT<SettingsWindow, implementation::SettingsWindow> {};

}  // namespace winrt::RivetHost::factory_implementation
