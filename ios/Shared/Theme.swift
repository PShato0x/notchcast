import SwiftUI

/// Design tokens matching the cream / terracotta / ink mockups.
enum Theme {
    static let cream = Color(red: 0.957, green: 0.945, blue: 0.918)      // #F4F1EA card background
    static let creamDeep = Color(red: 0.925, green: 0.910, blue: 0.878)  // subtle fills
    static let terracotta = Color(red: 0.773, green: 0.443, blue: 0.310) // #C5714F primary action
    static let ink = Color(red: 0.173, green: 0.161, blue: 0.145)        // #2C2925 dark action / text
    static let inkSoft = Color(red: 0.173, green: 0.161, blue: 0.145).opacity(0.55)
    static let stone = Color(red: 0.878, green: 0.863, blue: 0.831)      // #E0DCD4 quiet action
    static let paper = Color(red: 0.980, green: 0.973, blue: 0.957)      // light text on dark
}

struct WidgetActionButtonStyle: ButtonStyle {
    var background: Color
    var foreground: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.subheadline, design: .serif).weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .foregroundStyle(foreground)
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
