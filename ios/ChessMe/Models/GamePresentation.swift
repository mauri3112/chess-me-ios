import SwiftUI
import ChessMeCore

enum DeviceAnalysisSchedule: String, Identifiable {
    case night, now
    var id: String { rawValue }
    var title: String { self == .night ? "Night analysis" : "Analyze now" }
    var symbol: String { self == .night ? "moon.fill" : "play.fill" }
}

extension PlayerGameOutcome {
    var color: Color {
        switch self {
        case .won: ChessMeStyle.green
        case .lost: Color(red: 0.72, green: 0.20, blue: 0.20)
        case .draw: ChessMeStyle.muted
        }
    }
    var title: String { rawValue.capitalized }
    var symbol: String { self == .won ? "arrow.up.right" : self == .lost ? "arrow.down.right" : "equal" }
}
