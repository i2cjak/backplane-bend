import SwiftUI

// Draws the markdown blocks Md.render made (p, h3-h5, ul/li, pre, code,
// strong) with native text styles.

private func inline(_ bs: [Block]) -> AttributedString {
    var out = AttributedString()
    for b in bs {
        if let t = b.text {
            out += AttributedString(t)
            continue
        }
        var part = inline(b.kids ?? [])
        switch b.tag {
        case "code":
            part.font = .body.monospaced()
            part.backgroundColor = Color(.secondarySystemFill)
        case "strong":
            part.font = .body.weight(.semibold)
        default:
            break
        }
        out += part
    }
    return out
}

struct MarkdownView: View {
    let blocks: [Block]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, b in
                BlockView(block: b)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct BlockView: View {
    let block: Block

    var body: some View {
        if let t = block.text {
            Text(t)
        } else {
            let kids = block.kids ?? []
            switch block.tag {
            case "p": Text(inline(kids))
            case "h3": Text(inline(kids)).font(.title3.bold())
            case "h4": Text(inline(kids)).font(.headline)
            case "h5": Text(inline(kids)).font(.subheadline.bold())
            case "ul":
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(kids.enumerated()), id: \.offset) { _, li in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("•")
                            Text(inline(li.kids ?? []))
                        }
                    }
                }
            case "pre":
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(block.plain).font(.callout.monospaced()).padding(12)
                }
                .background(Color(.secondarySystemBackground))
            // the web page's copy button: the message's context menu copies
            case "button": EmptyView()
            default: MarkdownView(blocks: kids)
            }
        }
    }
}
