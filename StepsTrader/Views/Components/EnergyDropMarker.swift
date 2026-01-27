import SwiftUI
import MapKit
import CoreLocation

struct EnergyDropMarker: View {
    let drop: EnergyDrop
    let userLocation: CLLocationCoordinate2D?
    let dropNumber: Int
    let maxDropsPerDay: Int
    @State private var isAnimating = false
    
    private var distanceToUser: CLLocationDistance? {
        guard let userLoc = userLocation else { return nil }
        let dropLoc = CLLocation(latitude: drop.coordinate.latitude, longitude: drop.coordinate.longitude)
        let userLocation = CLLocation(latitude: userLoc.latitude, longitude: userLoc.longitude)
        return dropLoc.distance(from: userLocation)
    }
    
    private var isWithinRange: Bool {
        guard let distance = distanceToUser else { return false }
        return distance <= 50
    }
    
    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                // Glow
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        RadialGradient(
                            colors: [Color.green.opacity(0.5), .clear],
                            center: .center,
                            startRadius: 5,
                            endRadius: 35
                        )
                    )
                    .frame(width: 60, height: 70)
                    .scaleEffect(isAnimating ? 1.15 : 0.85)
                
                // Range indicator
                if isWithinRange {
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.green, lineWidth: 3)
                        .frame(width: 44, height: 52)
                        .scaleEffect(isAnimating ? 1.08 : 0.92)
                }
                
                // Battery body
                VStack(spacing: 0) {
                    // Battery cap
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.white.opacity(0.9))
                        .frame(width: 14, height: 5)
                    
                    // Battery main body
                    ZStack {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(
                                LinearGradient(
                                    colors: [Color.green, Color.green.opacity(0.7)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .frame(width: 32, height: 40)
                        
                        // Bolt icon
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
                .shadow(color: Color.green.opacity(0.5), radius: 8)
                
                // Drop ordinal number
                Text("\(dropNumber)")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(Color.black.opacity(0.6))
                    )
                    .offset(y: -32)
            }
            
            // Energy amount + distance badge
            VStack(spacing: 2) {
                Text(shortEnergy)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white)
                
                if let distance = distanceToUser {
                    Text(formatDistance(distance))
                        .font(.system(size: 8, weight: .medium))
                        .foregroundColor(isWithinRange ? .green : .white.opacity(0.8))
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(Color.black.opacity(0.6))
            )
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                isAnimating = true
            }
        }
    }
    
    private var shortEnergy: String {
        let value = max(0, drop.energy)
        if value < 1000 { return "\(value)" }
        if value < 10_000 {
            let v = (Double(value) / 1000.0 * 10).rounded() / 10
            let s = String(format: "%.1f", v)
            return (s.hasSuffix(".0") ? String(s.dropLast(2)) : s) + "K"
        }
        if value < 1_000_000 {
            return "\(Int((Double(value) / 1000.0).rounded()))K"
        }
        let v = (Double(value) / 1_000_000.0 * 10).rounded() / 10
        let s = String(format: "%.1f", v)
        return (s.hasSuffix(".0") ? String(s.dropLast(2)) : s) + "M"
    }
    
    private func formatDistance(_ meters: CLLocationDistance) -> String {
        if meters < 1000 {
            return "\(Int(meters))m"
        } else {
            return String(format: "%.1fkm", meters / 1000)
        }
    }
}

#Preview {
    OuterWorldView(model: DIContainer.shared.makeAppModel())
}
