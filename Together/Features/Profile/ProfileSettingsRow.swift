import SwiftUI

struct ProfileFlatSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing.sm) {
            Text(title)
                .font(AppTheme.typography.sized(15, weight: .semibold))
                .foregroundStyle(AppTheme.colors.textTertiary)
                .padding(.leading, 40)

            VStack(spacing: 0) {
                content
            }
        }
    }
}

struct ProfileFlatValueRow: View {
    let title: String
    let value: String
    let systemImage: String
    var trailingSymbol: String = "chevron.right"
    var titleColor: Color = AppTheme.colors.title
    var rotatesSystemImage = false

    var body: some View {
        HStack(spacing: AppTheme.spacing.md) {
            Image(systemName: systemImage)
                .font(AppTheme.typography.sized(17, weight: .medium))
                .foregroundStyle(titleColor.opacity(0.66))
                .symbolEffect(.rotate.clockwise, isActive: rotatesSystemImage)
                .frame(width: 24, height: 24)

            Text(title)
                .font(AppTheme.typography.sized(17, weight: .medium))
                .foregroundStyle(titleColor)
                .lineLimit(2)

            Spacer(minLength: AppTheme.spacing.sm)

            if value.isEmpty == false {
                Text(value)
                    .font(AppTheme.typography.sized(15, weight: .medium))
                    .foregroundStyle(AppTheme.colors.body.opacity(0.58))
                    .lineLimit(1)
            }

            if trailingSymbol.isEmpty == false {
                Image(systemName: trailingSymbol)
                    .font(AppTheme.typography.sized(11, weight: .bold))
                    .foregroundStyle(AppTheme.colors.body.opacity(0.34))
            }
        }
        .frame(maxWidth: .infinity, minHeight: 52)
        .contentShape(Rectangle())
    }
}

struct ProfileFlatToggleRow<Accessory: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let accessory: Accessory

    init(
        title: String,
        systemImage: String,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.title = title
        self.systemImage = systemImage
        self.accessory = accessory()
    }

    var body: some View {
        HStack(spacing: AppTheme.spacing.md) {
            Image(systemName: systemImage)
                .font(AppTheme.typography.sized(17, weight: .medium))
                .foregroundStyle(AppTheme.colors.body.opacity(0.6))
                .frame(width: 24, height: 24)

            Text(title)
                .font(AppTheme.typography.sized(17, weight: .medium))
                .foregroundStyle(AppTheme.colors.title)
                .lineLimit(2)

            Spacer(minLength: AppTheme.spacing.sm)

            accessory
                .tint(AppTheme.colors.sky)
        }
        .frame(maxWidth: .infinity, minHeight: 52)
    }
}

struct ProfileFlatOptionRow<MenuContent: View>: View {
    let title: String
    let value: String
    let systemImage: String
    @ViewBuilder let menuContent: MenuContent

    init(
        title: String,
        value: String,
        systemImage: String,
        @ViewBuilder menuContent: () -> MenuContent
    ) {
        self.title = title
        self.value = value
        self.systemImage = systemImage
        self.menuContent = menuContent()
    }

    var body: some View {
        HStack(spacing: AppTheme.spacing.md) {
            Image(systemName: systemImage)
                .font(AppTheme.typography.sized(17, weight: .medium))
                .foregroundStyle(AppTheme.colors.body.opacity(0.6))
                .frame(width: 24, height: 24)

            Text(title)
                .font(AppTheme.typography.sized(17, weight: .medium))
                .foregroundStyle(AppTheme.colors.title)
                .lineLimit(2)

            Spacer(minLength: AppTheme.spacing.sm)

            Menu {
                menuContent
            } label: {
                HStack(spacing: AppTheme.spacing.xs) {
                    Text(value)
                        .font(AppTheme.typography.sized(15, weight: .medium))
                        .foregroundStyle(AppTheme.colors.body.opacity(0.64))
                        .lineLimit(1)

                    Image(systemName: "chevron.up.chevron.down")
                        .font(AppTheme.typography.sized(10, weight: .bold))
                        .foregroundStyle(AppTheme.colors.body.opacity(0.34))
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(title)，\(value)")
            .accessibilityHint("轻点选择")
        }
        .frame(maxWidth: .infinity, minHeight: 52)
    }
}

struct ProfileInlineNotice: View {
    let message: String
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: AppTheme.spacing.sm) {
            Text(message)
                .font(AppTheme.typography.sized(14, weight: .medium))
                .foregroundStyle(AppTheme.colors.textTertiary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: AppTheme.spacing.sm)

            Button(actionTitle, action: action)
                .font(AppTheme.typography.sized(14, weight: .semibold))
                .foregroundStyle(AppTheme.colors.sky)
                .buttonStyle(.plain)
        }
        .padding(.leading, 40)
        .padding(.top, AppTheme.spacing.xs)
        .padding(.bottom, AppTheme.spacing.sm)
    }
}

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
    private let titleColor: Color?

    init(
        title: String,
        value: String,
        isEnabled: Bool = true,
        showsChevron: Bool = false,
        chevronSystemName: String = "chevron.right",
        titleColor: Color? = nil
    ) {
        self.title = title
        self.style = .value(value)
        self.isEnabled = isEnabled
        self.showsChevron = showsChevron
        self.chevronSystemName = chevronSystemName
        self.titleColor = titleColor
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
        self.titleColor = nil
    }

    var body: some View {
        rowShell {
            switch style {
            case let .value(value):
                valueAccessory(value: value)
            case let .toggle(isOn):
                Toggle("", isOn: isOn)
                    .labelsHidden()
                    .tint(AppTheme.colors.selectionTint)
                    .sensoryFeedback(.selection, trigger: isOn.wrappedValue)
            }
        }
    }

    private func valueAccessory(value: String) -> some View {
        HStack(spacing: AppTheme.spacing.xs) {
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
        HStack(alignment: .center, spacing: AppTheme.spacing.md) {
            Text(title)
                .font(AppTheme.typography.textStyle(.body, weight: .medium))
                .foregroundStyle((titleColor ?? AppTheme.colors.title).opacity(isEnabled ? 1 : 0.42))
                .lineLimit(2)

            Spacer(minLength: AppTheme.spacing.md)

            accessory()
        }
        .padding(.vertical, AppTheme.spacing.sm)
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .contentShape(Rectangle())
        .opacity(isEnabled ? 1 : 0.76)
    }
}
