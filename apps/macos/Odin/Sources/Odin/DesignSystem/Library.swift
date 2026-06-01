import SwiftUI

/// The Library strip — pinned and recent tasks. A single horizontal
/// strip of cards that scrolls when there are more than fit on screen.
/// The trailing fade is the affordance: it says "more in this direction"
/// without needing a button or a count.
struct LibraryStrip: View {
    let pinned: [String]
    let recents: [String]
    var onSelect: (String) -> Void
    var onPinToggle: (String) -> Void
    var onManage: (() -> Void)? = nil

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: OdinTokens.Space.s6) {
                ForEach(pinned, id: \.self) { item in
                    OdinLibraryCard(
                        title: display(item),
                        symbol: "pin.fill",
                        pinned: true,
                        onTap: { onSelect(item) },
                        onPinToggle: { onPinToggle(item) }
                    )
                }
                    ForEach(unpinnedRecents, id: \.self) { item in
                        OdinLibraryCard(
                            title: display(item),
                            symbol: nil,
                            pinned: false,
                            onTap: { onSelect(item) },
                            onPinToggle: { onPinToggle(item) }
                        )
                    }
                }
                .padding(.leading, OdinTokens.Space.s20)
                .padding(.trailing, OdinTokens.Space.s32)
            }
            .mask(
                HStack(spacing: 0) {
                    Rectangle()
                    LinearGradient(
                        colors: [.black, .clear],
                        startPoint: .leading, endPoint: .trailing
                    )
                    .frame(width: 32)
                }
            )
        .frame(height: OdinTokens.Size.libraryHeight)
    }

    private var unpinnedRecents: [String] {
        recents.filter { !pinned.contains($0) }
    }

    private func display(_ s: String) -> String {
        s.count <= 28 ? s : String(s.prefix(26)) + "…"
    }
}
