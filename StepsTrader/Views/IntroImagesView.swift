import SwiftUI

/// 8 full-screen onboarding images (onboarding1...onboarding8). Slide 8 has a "YES" button to continue.
struct IntroImagesView: View {
    let onYes: () -> Void


    private static let imageNames = (1...8).map { "onboarding\($0)" }
    @State private var index: Int = 0

    var body: some View {
        GeometryReader { geo in
            ZStack {
                TabView(selection: $index) {
                    ForEach(Array(Self.imageNames.enumerated()), id: \.offset) { idx, name in
                        Image(name)
                            .resizable()
                            .scaledToFill()
                            .frame(width: geo.size.width, height: geo.size.height)
                            .clipped()
                            .ignoresSafeArea(.all)
                            .tag(idx)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.none, value: index)
                .transaction { $0.animation = nil }
                .ignoresSafeArea(.all)

            VStack(spacing: 0) {
                progressBar
                    .padding(.top, 60)
                    .padding(.bottom, 24)
                Spacer()
                HStack(spacing: 12) {
                    if index > 0 {
                        Button(action: { index -= 1 }) {
                            Text("Back")
                                .font(.systemSerif(16, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 12)
                                .background(Capsule().fill(.ultraThinMaterial))
                                .overlay(Capsule().strokeBorder(.white.opacity(0.25), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer(minLength: 0)
                    Button(action: {
                        if index < 7 {
                            index += 1
                        } else {
                            onYes()
                        }
                    }) {
                        Text(index == 7 ? "YES" : "Next")
                            .font(.systemSerif(16, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                            .background(Capsule().fill(.ultraThinMaterial))
                            .overlay(Capsule().strokeBorder(.white.opacity(0.25), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea(.all)
    }

    private var progressBar: some View {
        HStack(spacing: 4) {
            ForEach(0..<Self.imageNames.count, id: \.self) { i in
                Capsule()
                    .fill(i == index ? AppColors.brandAccent : AppColors.brandAccent.opacity(0.3))
                    .frame(height: 4)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 24)
    }
}
