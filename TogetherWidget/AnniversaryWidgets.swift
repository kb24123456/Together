import SwiftUI
import WidgetKit
import OSLog

#if canImport(UIKit)
import UIKit
#endif

struct AnniversaryWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: TodayWidgetConstants.anniversaryWidgetKind, provider: AnniversaryWidgetProvider()) { entry in
            AnniversaryWidgetView(entry: entry)
                .widgetURL(TodayWidgetConstants.todayDeepLink)
        }
        .configurationDisplayName("双人纪念日")
        .description("查看你们在一起的天数和下一个纪念节点。")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}

struct AnniversaryWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: AnniversaryWidgetSnapshot
    let isPlaceholder: Bool
}

private struct AnniversaryWidgetProvider: TimelineProvider {
    private static let logger = Logger(subsystem: "com.pigdog.Together", category: "AnniversaryWidget")

    func placeholder(in context: Context) -> AnniversaryWidgetEntry {
        let now = Date.now
        let snapshot = readSnapshot(for: now, source: "placeholder", family: context.family)
        if snapshot.hasAnniversaryWidgetContent {
            return AnniversaryWidgetEntry(
                date: now,
                snapshot: snapshot,
                isPlaceholder: false
            )
        }

        return AnniversaryWidgetEntry(
            date: now,
            snapshot: .placeholder,
            isPlaceholder: true
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (AnniversaryWidgetEntry) -> Void) {
        let now = Date.now
        let snapshot = context.isPreview
            ? AnniversaryWidgetSnapshot.previewDemo.resolved(for: now)
            : readSnapshot(for: now, source: "snapshot", family: context.family)
        completion(AnniversaryWidgetEntry(date: now, snapshot: snapshot, isPlaceholder: false))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<AnniversaryWidgetEntry>) -> Void) {
        let now = Date.now
        completion(Timeline(
            entries: [
                AnniversaryWidgetEntry(
                    date: now,
                    snapshot: readSnapshot(for: now, source: "timeline", family: context.family),
                    isPlaceholder: false
                )
            ],
            policy: .after(now.addingTimeInterval(60 * 60))
        ))
    }

    private func readSnapshot(
        for date: Date,
        source: String,
        family: WidgetFamily
    ) -> AnniversaryWidgetSnapshot {
        let store = AnniversaryWidgetSnapshotStore()
        do {
            let snapshot = try store.read().resolved(for: date)
            return snapshot
        } catch {
            Self.logger.error(
                "[AnniversaryWidget] read snapshot failed source=\(source, privacy: .public) family=\(String(describing: family), privacy: .public) error=\(error.localizedDescription, privacy: .public)"
            )
            return .empty
        }
    }
}

private struct AnniversaryWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetContentMargins) private var widgetContentMargins
    @Environment(\.colorScheme) private var colorScheme

    let entry: AnniversaryWidgetEntry

    var body: some View {
        Group {
            if entry.snapshot.isPaired, entry.snapshot.startDate != nil {
                content
            } else {
                emptyState
            }
        }
        .padding(contentInsets)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .containerBackground(for: .widget) {
            AnniversaryMaterialBackground(avatars: entry.snapshot.avatars, family: family)
        }
        .unredacted()
    }

    private var contentInsets: EdgeInsets {
        let minimum: CGFloat = switch family {
        case .systemSmall: 12
        case .systemMedium: 18
        case .systemLarge: 20
        default: 16
        }

        return EdgeInsets(
            top: max(widgetContentMargins.top, minimum),
            leading: max(widgetContentMargins.leading, minimum),
            bottom: max(widgetContentMargins.bottom, minimum),
            trailing: max(widgetContentMargins.trailing, minimum)
        )
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .systemSmall:
            smallContent
        case .systemMedium:
            mediumContent
        default:
            largeContent
        }
    }

    private var smallContent: some View {
        VStack(spacing: 5) {
            AnniversaryAvatarPair(
                avatars: entry.snapshot.avatars,
                size: 44,
                overlap: 14,
                allowsImageData: smallAvatarImageDataIsWidgetSafe
            )
                .frame(height: 48)

            Text(entry.snapshot.title)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.76)

            daysText(size: 26)

            Text(entry.snapshot.startDateText)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.76)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var mediumContent: some View {
        HStack(spacing: 16) {
            AnniversaryAvatarPair(avatars: entry.snapshot.avatars, size: 70, overlap: 22)
                .frame(width: 126)

            VStack(alignment: .leading, spacing: 7) {
                Text(entry.snapshot.title)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)

                daysText(size: 31)

                Text("从 \(entry.snapshot.startDateText) 开始")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)

                countdownPill
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var largeContent: some View {
        VStack(spacing: 0) {
            AnniversaryAvatarPair(avatars: entry.snapshot.avatars, size: 86, overlap: 24)
                .frame(height: 94)

            Text(entry.snapshot.title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(.top, 4)

            daysText(size: 36)
                .padding(.top, 8)

            Text("从 \(entry.snapshot.startDateLongText) 开始")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(.top, 8)

            countdownPill
                .padding(.top, 14)

            Spacer(minLength: 10)

            HStack {
                Label("下一个节点", systemImage: "calendar")
                    .labelStyle(.titleAndIcon)

                Spacer()

                if let nextMilestoneDays = entry.snapshot.nextMilestoneDays {
                    Text(verbatim: "\(nextMilestoneDays) 天")
                        .foregroundStyle(.primary)
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary.opacity(0.55))
            }
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(.secondary)
            .padding(.top, 16)
            .overlay(alignment: .top) {
                Divider()
                    .overlay(WidgetTheme.divider(for: colorScheme))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 9) {
            AnniversaryAvatarPair(
                avatars: entry.snapshot.avatars,
                size: family == .systemSmall ? 42 : 56,
                overlap: 14,
                allowsImageData: family != .systemSmall || smallAvatarImageDataIsWidgetSafe
            )
                .opacity(0.72)

            Text(emptyTitle)
                .font(.system(size: family == .systemLarge ? 17 : 14, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)

            Text(emptySubtitle)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyTitle: String {
        if entry.isPlaceholder {
            return "双人纪念日"
        }
        if entry.snapshot.isPaired {
            return "还没有纪念日"
        }
        return "开启双人纪念日"
    }

    private var emptySubtitle: String {
        if entry.isPlaceholder {
            return "打开 App 查看"
        }
        if entry.snapshot.isPaired {
            return "进入 App 添加日期"
        }
        return "进入 App 完成设置"
    }

    private var smallAvatarImageDataIsWidgetSafe: Bool {
        entry.snapshot.avatars.reduce(0) { partialResult, avatar in
            partialResult + (avatar.imageData?.count ?? 0)
        } <= 180_000
    }

    private func daysText(size: CGFloat) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(verbatim: "\(entry.snapshot.daysTogether)")
                .font(.system(size: size, weight: .bold, design: .rounded))
            Text("天")
                .font(.system(size: max(14, size * 0.52), weight: .semibold, design: .rounded))
        }
        .foregroundStyle(WidgetTheme.accent(for: colorScheme))
        .lineLimit(1)
        .minimumScaleFactor(family == .systemSmall ? 0.62 : 0.78)
    }

    @ViewBuilder
    private var countdownPill: some View {
        if let countdownDays = entry.snapshot.countdownDays {
            Text(verbatim: "♥ 距离周年纪念还有 \(countdownDays) 天")
                .font(.system(size: family == .systemMedium ? 11 : 12, weight: .semibold, design: .rounded))
                .foregroundStyle(WidgetTheme.accentText(for: colorScheme))
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .padding(.horizontal, family == .systemMedium ? 9 : 10)
                .padding(.vertical, family == .systemMedium ? 6 : 7)
                .background(
                    Capsule(style: .continuous)
                        .fill(WidgetTheme.accentFill(for: colorScheme, opacity: colorScheme == .dark ? 0.18 : 0.12))
                )
        }
    }
}

private struct AnniversaryAvatarPair: View {
    let avatars: [AnniversaryWidgetAvatarSnapshot]
    let size: CGFloat
    let overlap: CGFloat
    var allowsImageData = true

    var body: some View {
        HStack(spacing: -overlap) {
            ForEach(Array(resolvedAvatars.enumerated()), id: \.element.id) { index, avatar in
                AnniversaryAvatarView(avatar: avatar, size: size, allowsImageData: allowsImageData)
                    .zIndex(Double(resolvedAvatars.count - index))
            }
        }
    }

    private var resolvedAvatars: [AnniversaryWidgetAvatarSnapshot] {
        if avatars.isEmpty {
            return AnniversaryWidgetSnapshot.neutralAvatars
        }
        return Array(avatars.prefix(2))
    }
}

private struct AnniversaryAvatarView: View {
    @Environment(\.colorScheme) private var colorScheme

    let avatar: AnniversaryWidgetAvatarSnapshot
    let size: CGFloat
    let allowsImageData: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(fallbackFill)

            avatarImage
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay {
            Circle().stroke(WidgetTheme.avatarStroke(for: colorScheme), lineWidth: max(3, size * 0.055))
        }
        .shadow(color: WidgetTheme.avatarShadow(for: colorScheme), radius: 12, x: 0, y: 8)
        .accessibilityLabel(avatar.displayName)
    }

    @ViewBuilder
    private var avatarImage: some View {
        #if canImport(UIKit)
        if allowsImageData, let imageData = avatar.imageData, let uiImage = UIImage(data: imageData) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
        } else {
            fallbackSymbol
        }
        #else
        fallbackSymbol
        #endif
    }

    private var fallbackSymbol: some View {
        Image(systemName: avatar.systemName)
            .font(.system(size: size * 0.42, weight: .semibold, design: .rounded))
            .foregroundStyle(WidgetTheme.avatarSymbol(for: colorScheme))
    }

    private var fallbackFill: LinearGradient {
        let colors = WidgetTheme.avatarFallbackColors(tintIndex: avatar.tintIndex, colorScheme: colorScheme)
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

private struct AnniversaryMaterialBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    let avatars: [AnniversaryWidgetAvatarSnapshot]
    let family: WidgetFamily

    var body: some View {
        ZStack {
            fallbackGradient

            if shouldRenderAvatarBlur {
                HStack(spacing: -40) {
                    ForEach(Array(avatars.prefix(2).enumerated()), id: \.element.id) { index, avatar in
                        blurredAvatar(avatar, index: index)
                            .frame(width: blurredAvatarSize, height: blurredAvatarSize)
                            .clipped()
                    }
                }
                .scaleEffect(blurredAvatarScale)
                .blur(radius: blurredAvatarRadius)
                .opacity(0.42)
            }

            WidgetTheme.materialOverlay(for: colorScheme)
        }
        .clipped()
    }

    private var shouldRenderAvatarBlur: Bool {
        family != .systemSmall && avatars.isEmpty == false
    }

    private var blurredAvatarSize: CGFloat {
        family == .systemLarge ? 190 : 140
    }

    private var blurredAvatarScale: CGFloat {
        family == .systemLarge ? 2.2 : 2.0
    }

    private var blurredAvatarRadius: CGFloat {
        family == .systemLarge ? 26 : 22
    }

    private var fallbackGradient: LinearGradient {
        WidgetTheme.anniversaryBackground(for: colorScheme)
    }

    @ViewBuilder
    private func blurredAvatar(_ avatar: AnniversaryWidgetAvatarSnapshot, index: Int) -> some View {
        #if canImport(UIKit)
        if let imageData = avatar.imageData, let uiImage = UIImage(data: imageData) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
        } else {
            Circle()
                .fill(WidgetTheme.blurredAvatarFallback(index: index, colorScheme: colorScheme))
        }
        #else
        Circle()
            .fill(WidgetTheme.blurredAvatarFallback(index: index, colorScheme: colorScheme))
        #endif
    }
}

private extension AnniversaryWidgetSnapshot {
    var hasAnniversaryWidgetContent: Bool {
        isPaired || avatars.isEmpty == false || startDate != nil
    }

    static var placeholder: AnniversaryWidgetSnapshot {
        AnniversaryWidgetSnapshot(
            generatedAt: .now,
            isPaired: false,
            title: "双人纪念日",
            startDate: nil,
            daysTogether: 0,
            startDateText: "",
            startDateLongText: "",
            countdownDays: nil,
            nextMilestoneDays: nil,
            avatars: neutralAvatars
        )
    }

    static var previewDemo: AnniversaryWidgetSnapshot {
        AnniversaryWidgetSnapshot(
            generatedAt: .now,
            isPaired: true,
            title: "在一起",
            startDate: Calendar.current.date(from: DateComponents(year: 2024, month: 12, day: 1)),
            daysTogether: 520,
            startDateText: "2024.12.01",
            startDateLongText: "2024年12月1日",
            countdownDays: 32,
            nextMilestoneDays: 600,
            avatars: neutralAvatars
        )
    }

    static var neutralAvatars: [AnniversaryWidgetAvatarSnapshot] {
        [
            AnniversaryWidgetAvatarSnapshot(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000101") ?? UUID(),
                displayName: "我",
                systemName: "person.crop.circle.fill",
                imageData: nil,
                tintIndex: 0
            ),
            AnniversaryWidgetAvatarSnapshot(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000102") ?? UUID(),
                displayName: "对方",
                systemName: "person.crop.circle.fill",
                imageData: nil,
                tintIndex: 1
            )
        ]
    }
}
