import SwiftUI
import ShopCore

struct UndoBanner: View {
    @ObservedObject var undoCoordinator: UndoCoordinator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var undoError: String?

    var body: some View {
        if let action = undoCoordinator.currentAction {
            HStack(spacing: ShopTheme.spacingSM) {
                Text(action.message)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Spacer(minLength: ShopTheme.spacingSM)

                Button(ShopStrings.undo) {
                    performUndo()
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ShopTheme.naturalGreen)
                .frame(minWidth: ShopTheme.minTouchTarget, minHeight: ShopTheme.minTouchTarget)
                .accessibilityLabel(ShopStrings.undo)
                .accessibilityHint(action.message)
            }
            .padding(.horizontal, ShopTheme.spacingMD)
            .padding(.vertical, ShopTheme.spacingSM)
            .shopGlassSurface(in: RoundedRectangle(cornerRadius: ShopTheme.rowCornerRadius, style: .continuous))
            .padding(.horizontal, ShopTheme.spacingMD)
            .padding(.bottom, ShopTheme.spacingSM)
            .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isModal)
            .onAppear {
                UIAccessibility.post(notification: .announcement, argument: action.message)
            }
            .alert(ShopStrings.undo, isPresented: Binding(
                get: { undoError != nil },
                set: { if !$0 { undoError = nil } }
            )) {
                Button(ShopStrings.undo, role: .cancel) {}
            } message: {
                Text(undoError ?? "")
            }
        }
    }

    private func performUndo() {
        do {
            try undoCoordinator.undo()
        } catch {
            undoError = error.localizedDescription
        }
    }
}
