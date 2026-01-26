import SwiftUI

struct HUDView: View {
    let icon: String
    let title: String
    let subtitle: String
    let isSuccess: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            // Icon
            Image(systemName: icon)
                .font(.system(size: 24, weight: .semibold))
                .foregroundColor(isSuccess ? .green : .red)
            
            // Text content
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primary)
                
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow)
        )
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
    }
}

// MARK: - Visual Effect Blur for macOS
struct VisualEffectBlur: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

// MARK: - Preview
#if DEBUG
struct HUDView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            HUDView(
                icon: "checkmark.circle.fill",
                title: "Fixed!",
                subtitle: "⌘Z to undo",
                isSuccess: true
            )

            HUDView(
                icon: "checkmark.circle.fill",
                title: "No Changes",
                subtitle: "Your text looks good!",
                isSuccess: true
            )

            HUDView(
                icon: "xmark.circle.fill",
                title: "Error",
                subtitle: "Could not replace text",
                isSuccess: false
            )
        }
        .padding(40)
        .background(Color.gray.opacity(0.3))
    }
}
#endif
