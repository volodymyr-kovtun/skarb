import SwiftUI

/// Single-use codes, shown once — the server only keeps hashes, so there is no second chance to
/// read them. Copying or saving them is the only thing that matters here, so the buttons that do
/// it sit right under them.
struct RecoveryCodesView: View {
    let codes: [String]
    @State private var copied = false

    private var asText: String { codes.joined(separator: "\n") + "\n" }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Each code signs you in once if you lose your authenticator. Store them somewhere safe — this is the only time they are shown.")
                .font(.system(size: 13))
                .foregroundStyle(Palette.muted)
                .lineSpacing(2)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(codes, id: \.self) { code in
                    Text(code)
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Palette.ink)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(Palette.surface2, in: .rect(cornerRadius: 8))
                        .textSelection(.enabled)
                }
            }

            HStack(spacing: 18) {
                Button {
                    UIPasteboard.general.string = asText
                    copied = true
                } label: {
                    Label(copied ? "Copied" : "Copy all", systemImage: copied ? "checkmark" : "doc.on.doc")
                }
                // The web's "Download": into Files, a password manager, or a note.
                ShareLink(item: asText, subject: Text("Skarb recovery codes")) {
                    Label("Save…", systemImage: "square.and.arrow.down")
                }
            }
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Palette.accent)
            .sensoryFeedback(.success, trigger: copied)
        }
    }
}
