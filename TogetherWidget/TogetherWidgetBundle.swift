import SwiftUI
import WidgetKit

@main
struct TogetherWidgetBundle: WidgetBundle {
    var body: some Widget {
        TodayFocusWidget()
        TodayListWidget()
    }
}
