import SwiftUI

// MARK: - StatusRow Component
struct StatusRow: View {
    let icon: String
    let title: String
    let status: ConnectionStatus
    let description: String
    
    enum ConnectionStatus {
        case connected, disconnected, warning
        
        var color: Color {
            switch self {
            case .connected: return .green
            case .disconnected: return .red
            case .warning: return .orange
            }
        }
        
        var icon: String {
            switch self {
            case .connected: return "checkmark.circle.fill"
            case .disconnected: return "xmark.circle.fill"
            case .warning: return "exclamationmark.triangle.fill"
            }
        }
    }
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.blue)
                .font(.title3)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Image(systemName: status.icon)
                .foregroundColor(status.color)
                .font(.title3)
        }
        .padding(.vertical, 4)
    }
}
