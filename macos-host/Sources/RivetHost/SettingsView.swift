import SwiftUI

/// The Settings window (⌘,) General pane (PRODUCT-SPEC §8): the same three
/// preferences as the Windows 设置 menu — language, theme, auto-check
/// updates — in the macOS-native home for persistent app preferences.
/// Every control applies immediately through the same AppModel setters the
/// old menu items used, so persistence semantics are unchanged.
struct SettingsPaneView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            Section {
                Picker(model.t("menuLanguage"), selection: Binding(
                    get: { model.i18n.language },
                    set: { model.setLanguage($0) })) {
                    Text(model.t("menuLangZh")).tag("zh")
                    Text(model.t("menuLangEn")).tag("en")
                }
                .pickerStyle(.menu)

                Picker(model.t("menuTheme"), selection: Binding(
                    get: { model.themeValue },
                    set: { model.setTheme($0) })) {
                    Text(model.t("themeFollowSystem")).tag("system")
                    Text(model.t("themeLight")).tag("light")
                    Text(model.t("themeDark")).tag("dark")
                }
                .pickerStyle(.menu)
            }

            Section {
                Toggle(model.t("settingsAutoCheckUpdates"), isOn: Binding(
                    get: { model.autoCheckUpdates },
                    set: { model.setAutoCheckUpdates($0) }))
            }
        }
        .formStyle(.grouped)
        .frame(width: 420, height: 230)
        // Live language switch works without extra wiring: every label comes
        // from model.t(), whose read of languageChangedToken keeps the pane
        // observed on it.
    }
}
