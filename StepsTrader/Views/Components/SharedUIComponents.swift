import SwiftUI

struct ResistanceTag: View {
    let text: String
    let theme: AppTheme
    
    var body: some View {
        Text(text)
            .font(.caption.weight(.medium))
            .foregroundColor(theme.accentColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .stroke(theme.accentColor, lineWidth: 1)
            )
    }
}

struct PinkUnderline: View {
    let width: CGFloat
    let theme: AppTheme
    
    var body: some View {
        Path { path in
            path.move(to: CGPoint(x: 0, y: 0))
            path.addQuadCurve(
                to: CGPoint(x: width, y: 2),
                control: CGPoint(x: width * 0.5, y: -1)
            )
        }
        .stroke(theme.accentColor, lineWidth: 2)
        .frame(width: width, height: 4)
    }
}

struct ThemedDivider: View {
    let theme: AppTheme
    
    var body: some View {
        Rectangle()
            .fill(theme.stroke.opacity(theme.strokeOpacity))
            .frame(height: 1)
    }
}

struct EmptyStateView: View {
    let message: String
    let theme: AppTheme
    var subMessage: String? = nil
    
    var body: some View {
        VStack(spacing: 8) {
            Text(message)
                .font(.subheadline)
                .foregroundColor(theme.textSecondary)
            
            if let sub = subMessage {
                Text(sub)
                    .font(.caption)
                    .foregroundColor(theme.textSecondary.opacity(0.7))
                    .italic()
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}
