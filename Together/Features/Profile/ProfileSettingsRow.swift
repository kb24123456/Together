import SwiftUI

struct ProfileFlatSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.hierarchy.spacing.related) {
            Text(title)
                .font(AppTheme.typography.hierarchy(.supporting, weight: .semibold))
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

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(
            alignment: dynamicTypeSize.isAccessibilitySize ? .top : .center,
            spacing: AppTheme.hierarchy.spacing.component
        ) {
            Image(systemName: systemImage)
                .font(AppTheme.typography.sized(17, weight: .medium))
                .foregroundStyle(titleColor.opacity(0.66))
                .symbolEffect(.rotate.clockwise, isActive: rotatesSystemImage)
                .frame(width: 24, height: 24)

            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: AppTheme.hierarchy.spacing.inline) {
                    titleText
                    valueText
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                titleText

                Spacer(minLength: AppTheme.hierarchy.spacing.related)

                valueText
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

    private var titleText: some View {
        Text(title)
            .font(AppTheme.typography.hierarchy(.primary, weight: .medium))
            .foregroundStyle(titleColor)
            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var valueText: some View {
        if value.isEmpty == false {
            Text(value)
                .font(AppTheme.typography.hierarchy(.supporting, weight: .medium))
                .foregroundStyle(AppTheme.colors.body.opacity(0.58))
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct ProfileFlatToggleRow<Accessory: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let accessory: Accessory

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

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
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                HStack(alignment: .top, spacing: AppTheme.hierarchy.spacing.component) {
                    rowIcon

                    VStack(alignment: .leading, spacing: AppTheme.hierarchy.spacing.related) {
                        titleText

                        HStack {
                            Spacer(minLength: 0)
                            tintedAccessory
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                HStack(spacing: AppTheme.hierarchy.spacing.component) {
                    rowIcon
                    titleText
                    Spacer(minLength: AppTheme.hierarchy.spacing.related)
                    tintedAccessory
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 52)
    }

    private var rowIcon: some View {
        Image(systemName: systemImage)
            .font(AppTheme.typography.sized(17, weight: .medium))
            .foregroundStyle(AppTheme.colors.body.opacity(0.6))
            .frame(width: 24, height: 24)
    }

    private var titleText: some View {
        Text(title)
            .font(AppTheme.typography.hierarchy(.primary, weight: .medium))
            .foregroundStyle(AppTheme.colors.title)
            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var tintedAccessory: some View {
        accessory
            .tint(AppTheme.colors.sky)
    }
}

struct ProfileFlatOptionRow<MenuContent: View>: View {
    let title: String
    let value: String
    let systemImage: String
    @ViewBuilder let menuContent: MenuContent

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

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
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                HStack(alignment: .top, spacing: AppTheme.hierarchy.spacing.component) {
                    rowIcon

                    VStack(alignment: .leading, spacing: AppTheme.hierarchy.spacing.inline) {
                        titleText
                        menuButton
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                HStack(spacing: AppTheme.hierarchy.spacing.component) {
                    rowIcon
                    titleText
                    Spacer(minLength: AppTheme.hierarchy.spacing.related)
                    menuButton
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 52)
    }

    private var rowIcon: some View {
        Image(systemName: systemImage)
            .font(AppTheme.typography.sized(17, weight: .medium))
            .foregroundStyle(AppTheme.colors.body.opacity(0.6))
            .frame(width: 24, height: 24)
    }

    private var titleText: some View {
        Text(title)
            .font(AppTheme.typography.hierarchy(.primary, weight: .medium))
            .foregroundStyle(AppTheme.colors.title)
            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var menuButton: some View {
        Menu {
            menuContent
        } label: {
            HStack(spacing: AppTheme.hierarchy.spacing.inline) {
                Text(value)
                    .font(AppTheme.typography.hierarchy(.supporting, weight: .medium))
                    .foregroundStyle(AppTheme.colors.body.opacity(0.64))
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)

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
}

struct ProfileInlineNotice: View {
    let message: String
    let actionTitle: String
    let action: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: AppTheme.hierarchy.spacing.related) {
                    messageText
                    actionButton
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: AppTheme.hierarchy.spacing.related) {
                    messageText
                    Spacer(minLength: AppTheme.hierarchy.spacing.related)
                    actionButton
                }
            }
        }
        .padding(.leading, 40)
        .padding(.top, AppTheme.hierarchy.spacing.inline)
        .padding(.bottom, AppTheme.hierarchy.spacing.related)
    }

    private var messageText: some View {
        Text(message)
            .font(AppTheme.typography.hierarchy(.supporting, weight: .medium))
            .foregroundStyle(AppTheme.colors.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var actionButton: some View {
        Button(actionTitle, action: action)
            .font(AppTheme.typography.hierarchy(.supporting, weight: .semibold))
            .foregroundStyle(AppTheme.colors.sky)
            .frame(minHeight: 44)
            .buttonStyle(.plain)
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
