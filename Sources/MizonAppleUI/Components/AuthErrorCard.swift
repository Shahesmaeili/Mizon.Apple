#if !os(watchOS)
import SwiftUI

struct AuthErrorCard: View {
    let title: String
    let message: String
    private var localization = AuthLocalization()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        HStack(spacing: 11) {
            FluentIcon(symbol: .dismissCircle, size: 20)
                .foregroundStyle(AuthAppearance.errorAccent)
                .frame(width: 34, height: 34)
                .background(AuthAppearance.errorWash, in: .rect(cornerRadius: 11))
                .overlay { RoundedRectangle(cornerRadius: 11).strokeBorder(AuthAppearance.errorBorder) }
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(localization.font(12, weight: .semibold))
                    .foregroundStyle(MizonPalette.negative)
                Text(message).font(localization.font(11))
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(AuthAppearance.errorFill, in: .rect(cornerRadius: 14))
        .overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(AuthAppearance.errorBorder) }
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2)
                .fill(AuthAppearance.errorAccent)
                .frame(width: 3)
                .padding(.vertical, 12)
                .allowsHitTesting(false)
        }
        .opacity(appeared || reduceMotion ? 1 : 0)
        .offset(y: appeared || reduceMotion ? 0 : 6)
        .onAppear {
            withAnimation(reduceMotion ? nil : .timingCurve(0.16, 0.8, 1, 1, duration: 0.22)) {
                appeared = true
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title). \(message)")
        .accessibilityIdentifier("auth.error")
    }
}
#endif
