import SwiftUI

struct ProfileSettingsRow: View {
    private enum Style {
        case value(String)
        case toggle(Binding<Bool>)
    }

    private let title: String
    private let style: Style
    private let isEnabled: Bool
    private let showsChevron: Bool
    private let chevronSystemName: String

    init(
        title: String,
        value: String,
        isEnabled: Bool = true,
        showsChevron: Bool = false,
        chevronSystemName: String = "chevron.right"
    ) {
        self.title = title
        self.style = .value(value)
        self.isEnabled = isEnabled
        self.showsChevron = showsChevron
        self.chevronSystemName = chevronSystemName
    }

    init(
        title: String,
        isOn: Binding<Bool>,
        isEnabled: Bool = true
    ) {
        self.title = title
        self.style = .toggle(isOn)
        self.isEnabled = isEnabled
        self.showsChevron = false
        self.chevronSystemName = "chevron.right"
    }

    var body: some View {
        rowShell {
            switch style {
            case let .value(value):
                valueAccessory(value: value)
            case let .toggle(isOn):
                Toggle("", isOn: isOn)
                    .labelsHidden()
                    .tint(AppTheme.colors.sky)
                    .sensoryFeedback(.selection, trigger: isOn.wrappedValue)
            }
        }
    }

    private func valueAccessory(value: String) -> some View {
        HStack(spacing: 8) {
            Text(value)
                .font(AppTheme.typography.textStyle(.subheadline, weight: .medium))
                .foregroundStyle(AppTheme.colors.body.opacity(isEnabled ? 0.64 : 0.42))
                .lineLimit(1)

            if showsChevron {
                Image(systemName: chevronSystemName)
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
