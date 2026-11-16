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
namespace mxc = winrt::Microsoft::UI::Xaml::Controls;

namespace winrt::RivetHost::implementation {

// Same host-wide i18n table as MainWindow (defined in MainWindow.xaml.cpp).
std::wstring t(char const* key);

namespace {
constexpr wchar_t const* kLanguages[] = {L"zh", L"en"};
constexpr wchar_t const* kThemes[] = {L"system", L"light", L"dark"};
// §2a recorder default (DATA-FORMAT §7 `global-quick-add`), reset value.
constexpr wchar_t const* kQuickAddDefault = L"ctrl+alt+space";
}  // namespace

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
  // §2a recorder: key events bubble from the focused control to the root;
  // while recording, every KeyDown lands in HandleRecorderKey.
  RootGrid().KeyDown(
      [this](winrt::Windows::Foundation::IInspectable const&,
             mx::Input::KeyRoutedEventArgs const& args) {
        HandleRecorderKey(args);
      });
  // Clicking elsewhere (or focus loss of any kind) cancels the recording
  // without changes, like the prototype's blur handler.
  QuickAddRecorderButton().LostFocus(
      [this](auto const&, auto const&) { StopQuickAddRecording(); });
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
  // §2a 新任务 group.
  NewTasksGroupHeader().Text(t("settingsGroupNewTasks"));
  DefaultListCaption().Text(t("defaultListLabel"));
  DefaultListHelpText().Text(t("defaultListHelp"));
  QuickAddCaption().Text(t("globalQuickAddLabel"));
  QuickAddHelpText().Text(t("globalQuickAddHelp"));
  QuickAddResetButton().Content(winrt::box_value(hstring(t("shortcutReset"))));
  QuickAddClearButton().Content(winrt::box_value(hstring(t("shortcutClear"))));
  RenderQuickAdd();
  // §2a 数据 group.
  DataGroupHeader().Text(t("settingsGroupData"));
  DbCurrentCaption().Text(t("dbCurrentLabel"));
  DbMigrateCaption().Text(t("dbLocationLabel"));
  DbMigrateHelpText().Text(t("dbLocationHelp"));
  DbOpenCaption().Text(t("dbSwitchLabel"));
  DbOpenHelpText().Text(t("dbSwitchHelp"));
  DbCreateCaption().Text(t("dbNewLabel"));
  DbCreateHelpText().Text(t("dbNewHelp"));
  DbExportCaption().Text(t("dbExportLabel"));
  DbExportHelpText().Text(t("dbExportHelp"));
  DbRestoreCaption().Text(t("dbRestoreLabel"));
  DbRestoreHelpText().Text(t("dbRestoreHelp"));
  DbRevealButton().Content(winrt::box_value(hstring(t("dbReveal"))));
  DbMigrateButton().Content(winrt::box_value(hstring(t("dbMigrateBtn"))));
  DbOpenButton().Content(winrt::box_value(hstring(t("dbOpenBtn"))));
  DbCreateButton().Content(winrt::box_value(hstring(t("dbCreateBtn"))));
  DbExportButton().Content(winrt::box_value(hstring(t("dbExportBtn"))));
  DbRestoreButton().Content(winrt::box_value(hstring(t("dbRestoreBtn"))));
  DataNoteText().Text(t("dbDataNote"));
  // Rebuild the combo labels for the new language, keeping the selections.
  updating_visuals_ = true;
  FillLanguageBox(SelectedLanguage());
  FillThemeBox(SelectedTheme());
  FillDefaultListComboBox();
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

hstring SettingsWindow::SelectedLanguage() {
  auto const index = LanguageBox().SelectedIndex();
  return hstring(index >= 0 && index < 2 ? kLanguages[index] : L"zh");
}

hstring SettingsWindow::SelectedTheme() {
  auto const index = ThemeBox().SelectedIndex();
  return hstring(index >= 0 && index < 3 ? kThemes[index] : L"system");
}

bool SettingsWindow::AutoCheckUpdatesOn() {
  return AutoCheckSwitch().IsOn();
}

// §2a: refresh the 数据 + 新任务 visuals from the snapshot MainWindow
// pushed in. Guarded like the preference fills — no events may fire.
void SettingsWindow::SyncDatabaseState(
    hstring const& database_name, hstring const& database_path,
    bool connected,
    winrt::Windows::Foundation::Collections::IVectorView<std::int64_t> const&
        list_ids,
    winrt::Windows::Foundation::Collections::IVectorView<hstring> const&
        list_names,
    std::int64_t default_list_id, hstring const& quick_add) {
  DbCurrentNameText().Text(database_name.empty() ? hstring(t("dbCurrentNone"))
                                                 : database_name);
  DbCurrentPathText().Text(database_path.empty() ? hstring(t("dbPathNone"))
                                                 : database_path);
  database_connected_ = connected;
  // Controls that need an open database stay disabled while none is open.
  DbRevealButton().IsEnabled(connected);
  DbMigrateButton().IsEnabled(connected);
  DbExportButton().IsEnabled(connected);
  DbRestoreButton().IsEnabled(connected);
  DefaultListComboBox().IsEnabled(connected);
  default_list_ids_.clear();
  default_list_names_.clear();
  for (std::uint32_t i = 0; i < list_ids.Size(); ++i) {
    default_list_ids_.push_back(list_ids.GetAt(i));
    default_list_names_.push_back(std::wstring(list_names.GetAt(i)));
  }
  default_list_id_ = default_list_id;
  quick_add_ = std::wstring(quick_add);
  updating_visuals_ = true;
  FillDefaultListComboBox();
  RenderQuickAdd();
  updating_visuals_ = false;
}

void SettingsWindow::SetDataFeedback(hstring const& message) {
  DataFeedbackText().Text(message);
}

// §2a restore step 2: the confirmation lives in the settings window (the
// surface the user acted on). Safe default: closing never confirms.
winrt::Windows::Foundation::IAsyncOperation<bool>
SettingsWindow::ConfirmRestoreAsync(hstring const& body) {
  auto content = mxc::StackPanel{};
  content.Spacing(8);
  auto text = mxc::TextBlock{};
  text.Text(body);
  text.TextWrapping(mx::TextWrapping::Wrap);
  text.MaxWidth(320);
  content.Children().Append(text);

  auto dialog = mxc::ContentDialog{};
  dialog.Title(winrt::box_value(hstring(t("dbRestorePreviewTitle"))));
  dialog.Content(content);
  dialog.PrimaryButtonText(hstring(t("dbRestoreApply")));
  dialog.CloseButtonText(hstring(t("dialogCancel")));
  dialog.DefaultButton(mxc::ContentDialogButton::Close);
  dialog.XamlRoot(Content().XamlRoot());

  auto const result = co_await dialog.ShowAsync();
  co_return result == mxc::ContentDialogResult::Primary;
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

// Default-list picker over the current lists, prefixed with the unset row
// (AppModel parity: "—" → id 0).
void SettingsWindow::FillDefaultListComboBox() {
  auto box = DefaultListComboBox();
  box.Items().Clear();
  auto unset = ComboBoxItem{};
  unset.Content(winrt::box_value(hstring(L"—")));
  box.Items().Append(unset);
  auto selected = 0;
  for (std::size_t i = 0; i < default_list_ids_.size(); ++i) {
    auto item = ComboBoxItem{};
    item.Content(winrt::box_value(hstring(default_list_names_[i])));
    box.Items().Append(item);
    if (default_list_ids_[i] == default_list_id_ && default_list_id_ != 0) {
      selected = static_cast<int>(i) + 1;
    }
  }
  box.SelectedIndex(default_list_id_ == 0 ? 0 : selected);
}

// §2a recorder display: recording prompt / Not Set / the recorded combo.
void SettingsWindow::RenderQuickAdd() {
  if (quick_add_recording_) {
    QuickAddRecorderButton().Content(
        winrt::box_value(hstring(t("shortcutRecording"))));
    return;
  }
  QuickAddRecorderButton().Content(winrt::box_value(
      hstring(quick_add_.empty() ? t("shortcutNone") : quick_add_)));
}

void SettingsWindow::StartQuickAddRecording() {
  if (quick_add_recording_) return;
  quick_add_recording_ = true;
  QuickAddHintText().Visibility(mx::Visibility::Collapsed);
  RenderQuickAdd();
  QuickAddRecorderButton().Focus(mx::FocusState::Keyboard);
}

void SettingsWindow::StopQuickAddRecording() {
  if (!quick_add_recording_) return;
  quick_add_recording_ = false;
  QuickAddHintText().Visibility(mx::Visibility::Collapsed);
  RenderQuickAdd();
}

// Captures the next modifier+key KeyDown (§2a: recorded, never registered).
// Escape cancels; bare modifiers keep the recording alive; a key without
// Win/Ctrl/Alt shows the actionable hint and keeps recording.
void SettingsWindow::HandleRecorderKey(
    mx::Input::KeyRoutedEventArgs const& args) {
  if (!quick_add_recording_) return;
  using winrt::Windows::System::VirtualKey;
  auto const key = args.Key();
  args.Handled(true);
  if (key == VirtualKey::Escape) {
    StopQuickAddRecording();
    return;
  }
  if (key == VirtualKey::Shift || key == VirtualKey::Control ||
      key == VirtualKey::Menu || key == VirtualKey::LeftWindows ||
      key == VirtualKey::RightWindows || key == VirtualKey::Tab ||
      key == VirtualKey::CapitalLock) {
    return;
  }
  // Modifier state via the classic Win32 API: the C++/WinRT projections
  // available to this host carry no InputKeyboardSource, and GetAsyncKeyState
  // is the dependable desktop reading of "held right now".
  auto const down = [](int virtual_key) {
    return (GetAsyncKeyState(virtual_key) & 0x8000) != 0;
  };
  bool const ctrl = down(VK_CONTROL);
  bool const alt = down(VK_MENU);
  bool const shift = down(VK_SHIFT);
  bool const win = down(VK_LWIN) || down(VK_RWIN);
  if (!ctrl && !alt && !win) {
    QuickAddHintText().Text(t("shortcutNeedModifier"));
    QuickAddHintText().Visibility(mx::Visibility::Visible);
    return;
  }
  auto const name = RecorderKeyName(key);
  if (name.empty()) {
    return;  // unmapped key: keep recording until a mappable one arrives
  }
  std::wstring combo;
  auto append = [&combo](std::wstring const& part) {
    if (!combo.empty()) combo += L"+";
    combo += part;
  };
  if (ctrl) append(L"ctrl");
  if (alt) append(L"alt");
  if (shift) append(L"shift");
  if (win) append(L"win");
  append(name);
  quick_add_ = combo;
  quick_add_recording_ = false;
  QuickAddHintText().Visibility(mx::Visibility::Collapsed);
  RenderQuickAdd();
  quick_add_committed_(*this, winrt::box_value(hstring(combo)));
}

// VirtualKey → normalized lowercase key name for the stored combo
// ("ctrl+alt+space" shape). Unmapped keys return empty.
std::wstring SettingsWindow::RecorderKeyName(
    winrt::Windows::System::VirtualKey key) {
  auto const code = static_cast<std::uint32_t>(key);
  if (code >= 0x44 && code <= 0x5A) {  // VirtualKey::A … VirtualKey::Z
    return std::wstring(1, static_cast<wchar_t>(L'a' + (code - 0x44)));
  }
  if (code >= 0x30 && code <= 0x39) {  // Number0 … Number9
    return std::wstring(1, static_cast<wchar_t>(L'0' + (code - 0x30)));
  }
  if (code >= 0x70 && code <= 0x87) {  // F1 … F24
    return L"f" + std::to_wstring(code - 0x70 + 1);
  }
  switch (key) {
    case winrt::Windows::System::VirtualKey::Space: return L"space";
    case winrt::Windows::System::VirtualKey::Comma: return L"comma";
    case winrt::Windows::System::VirtualKey::Period: return L"period";
    case winrt::Windows::System::VirtualKey::Semicolon: return L"semicolon";
    case winrt::Windows::System::VirtualKey::Minus: return L"minus";
    case winrt::Windows::System::VirtualKey::Slash: return L"slash";
    default: return L"";
  }
}

// The 数据 group's buttons stay presentational: the XAML Tag carries the
// action token and MainWindow runs the flow through DataActionRequested.
void SettingsWindow::OnDataActionClicked(
    winrt::Windows::Foundation::IInspectable const& sender,
    mx::RoutedEventArgs const&) {
  auto const action = winrt::unbox_value<hstring>(sender.as<Button>().Tag());
  data_action_requested_(*this, winrt::box_value(action));
}

void SettingsWindow::OnDefaultListSelected(
    winrt::Windows::Foundation::IInspectable const&,
    SelectionChangedEventArgs const&) {
  if (updating_visuals_) return;
  auto const index = DefaultListComboBox().SelectedIndex();
  // Index 0 is the unset row; every other entry maps through the snapshot.
  auto const id =
      index <= 0 ? std::int64_t{0}
                 : (static_cast<std::size_t>(index) <= default_list_ids_.size()
                        ? default_list_ids_[static_cast<std::size_t>(index) - 1]
                        : std::int64_t{0});
  default_list_id_ = id;
  default_list_committed_(*this,
                          winrt::box_value(static_cast<std::int64_t>(id)));
}

void SettingsWindow::OnQuickAddRecorderClicked(
    winrt::Windows::Foundation::IInspectable const&,
    mx::RoutedEventArgs const&) {
  if (quick_add_recording_) {
    StopQuickAddRecording();
  } else {
    StartQuickAddRecording();
  }
}

// Reset stores the family default ("ctrl+alt+space"); clear stores "".
void SettingsWindow::OnQuickAddResetClicked(
    winrt::Windows::Foundation::IInspectable const&,
    mx::RoutedEventArgs const&) {
  StopQuickAddRecording();
  quick_add_ = kQuickAddDefault;
  RenderQuickAdd();
  quick_add_committed_(*this, winrt::box_value(hstring(quick_add_)));
}

void SettingsWindow::OnQuickAddClearClicked(
    winrt::Windows::Foundation::IInspectable const&,
    mx::RoutedEventArgs const&) {
  StopQuickAddRecording();
  quick_add_.clear();
  RenderQuickAdd();
  quick_add_committed_(*this, winrt::box_value(hstring(L"")));
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

winrt::event_token SettingsWindow::DataActionRequested(
    winrt::Windows::Foundation::TypedEventHandler<
        winrt::RivetHost::SettingsWindow,
        winrt::Windows::Foundation::IInspectable> const& handler) {
  return data_action_requested_.add(handler);
}

void SettingsWindow::DataActionRequested(winrt::event_token token) {
  data_action_requested_.remove(token);
}

winrt::event_token SettingsWindow::DefaultListCommitted(
    winrt::Windows::Foundation::TypedEventHandler<
        winrt::RivetHost::SettingsWindow,
        winrt::Windows::Foundation::IInspectable> const& handler) {
  return default_list_committed_.add(handler);
}

void SettingsWindow::DefaultListCommitted(winrt::event_token token) {
  default_list_committed_.remove(token);
}

winrt::event_token SettingsWindow::QuickAddCommitted(
    winrt::Windows::Foundation::TypedEventHandler<
        winrt::RivetHost::SettingsWindow,
        winrt::Windows::Foundation::IInspectable> const& handler) {
  return quick_add_committed_.add(handler);
}

void SettingsWindow::QuickAddCommitted(winrt::event_token token) {
  quick_add_committed_.remove(token);
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
