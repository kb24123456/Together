import SwiftUI

struct ProfileSettingsRow<MenuContent: View>: View {
    private enum Style {
        case value(String)
        case toggle(Binding<Bool>)
        case menu(String)
    }

    private let title: String
    private let style: Style
    private let isEnabled: Bool
    private let showsChevron: Bool
    @ViewBuilder private let menuContent: MenuContent

    init(
        title: String,
        value: String,
        isEnabled: Bool = true,
        showsChevron: Bool = true,
        @ViewBuilder menuContent: () -> MenuContent
    ) {
        self.title = title
        self.style = .menu(value)
        self.isEnabled = isEnabled
        self.showsChevron = showsChevron
        self.menuContent = menuContent()
    }

    init(
        title: String,
        value: String,
        isEnabled: Bool = true,
        showsChevron: Bool = false
    ) where MenuContent == EmptyView {
        self.title = title
        self.style = .value(value)
        self.isEnabled = isEnabled
        self.showsChevron = showsChevron
        self.menuContent = EmptyView()
    }

    init(
        title: String,
        isOn: Binding<Bool>,
        isEnabled: Bool = true
    ) where MenuContent == EmptyView {
        self.title = title
        self.style = .toggle(isOn)
        self.isEnabled = isEnabled
        self.showsChevron = false
        self.menuContent = EmptyView()
    }

    var body: some View {
        switch style {
        case let .value(value):
            rowShell {
                valueAccessory(value: value)
            }
        case let .toggle(isOn):
            rowShell {
                Toggle("", isOn: isOn)
                    .labelsHidden()
                    .tint(AppTheme.colors.accent)
            }
        case let .menu(value):
            Menu {
                menuContent
            } label: {
                rowShell {
                    valueAccessory(value: value)
                }
            }
            .disabled(!isEnabled)
        }
    }

    private func valueAccessory(value: String) -> some View {
        HStack(spacing: 8) {
            Text(value)
                .font(AppTheme.typography.textStyle(.subheadline, weight: .medium))
                .foregroundStyle(AppTheme.colors.body.opacity(isEnabled ? 0.64 : 0.42))
                .lineLimit(1)

            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(AppTheme.typography.sized(12, weight: .bold))
                    .foregroundStyle(AppTheme.colors.body.opacity(isEnabled ? 0.36 : 0.22))
            }
        }
    }

    private func rowShell<Accessory: View>(@ViewBuilder accessory: () -> Accessory) -> some View {
        HStack(alignment: .center, spacing: 14) {
            Text(title)
                .font(AppTheme.typography.textStyle(.body, weight: .medium))
                .foregroundStyle(AppTheme.colors.title.opacity(isEnabled ? 1 : 0.42))
                .lineLimit(2)

            Spacer(minLength: 12)

            accessory()
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .contentShape(Rectangle())
        .opacity(isEnabled ? 1 : 0.76)
    }
}
