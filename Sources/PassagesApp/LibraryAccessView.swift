import SwiftUI
import AppKit

private typealias AccessState<Value> = SwiftUI.State<Value>

struct LibraryAccessView: View {
    let isChecking: Bool
    let chooseFolder: () -> Void
    let accessMessage: String?
    @AccessState private var hasAttemptedConnection: Bool = false

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 24) {
                    header
                    actions
                }
                .frame(maxWidth: 460)
                .padding(.horizontal, 32)
                .padding(.vertical, 40)
                .frame(maxWidth: .infinity, minHeight: geometry.size.height)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        VStack(spacing: 12) {
            Image(systemName: "books.vertical")
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .frame(width: 68, height: 68)
                .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 18))
                .accessibilityHidden(true)
            Text("Connect your Apple Books library")
                .font(.system(size: 25, weight: .semibold))
                .multilineTextAlignment(.center)
            Text("Allow access to Apple Books folder to browse and export your highlights.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var actions: some View {
        VStack(spacing: 12) {
            Button {
                hasAttemptedConnection = true
                chooseFolder()
            } label: {
                HStack(spacing: 6) {
                    if isChecking { ProgressView().controlSize(.mini) }
                    Text(isChecking ? "Connecting…" : (hasAttemptedConnection ? "Retry" : "Allow access"))
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isChecking)
            .controlSize(.large)
            if let accessMessage {
                Label(accessMessage, systemImage: "info.circle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

}
