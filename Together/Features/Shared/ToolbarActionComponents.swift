import SwiftUI

struct ToolbarTextActionLabel: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.body)
            .fontWeight(.regular)
            .lineLimit(1)
            .minimumScaleFactor(0.82)
    }
}
