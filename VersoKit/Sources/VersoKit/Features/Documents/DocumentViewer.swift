import PDFKit
import PencilKit
import SwiftUI

/// Reading and marking up a document.
///
/// Pages are rendered to images with the annotation layers as ordinary views on
/// top, rather than reaching into `PDFView`'s scroll hierarchy — which is a far
/// more fragile way to get the same result, and would not let the Phase 10 ink
/// canvas be reused as-is.
///
/// **Coordinates.** `NormalisedRect` and stored ink are both in *PDF page
/// space*, whose origin is the bottom left. Everything on screen has its origin
/// at the top left. The flip happens once, here, in `displayRect` — getting it
/// wrong mirrors every annotation vertically, which is the classic PDF bug.
struct DocumentViewer: View {
    @Binding var payload: AttachmentPayload

    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme
    @Environment(\.motion) private var motion

    enum Mode: String, CaseIterable {
        case read
        case highlight
        case ink

        var displayName: LocalizedStringResource {
            switch self {
            case .read: "Read"
            case .highlight: "Highlight"
            case .ink: "Draw"
            }
        }

        var systemImage: String {
            switch self {
            case .read: "book"
            case .highlight: "highlighter"
            case .ink: "pencil.tip"
            }
        }
    }

    @State private var document: PDFDocument?
    @State private var pageIndex = 0
    @State private var mode: Mode = .read
    @State private var highlightColor: DocumentAnnotations.HighlightColor = .accent
    @State private var dragStart: CGPoint?
    @State private var dragEnd: CGPoint?
    @State private var isExporting = false

    private var page: PDFPage? { document?.page(at: pageIndex) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let document, document.pageCount > 0 {
                    pageView
                    PageThumbnailStrip(
                        document: document,
                        selection: $pageIndex,
                        annotatedPages: payload.annotations.annotatedPages
                    )
                } else {
                    ContentUnavailableView(
                        "Not on this device",
                        systemImage: "doc.questionmark",
                        description: Text("This document was added on another device. Documents stay on the device they were imported to.")
                    )
                }
            }
            .background(theme.stock.ignoresSafeArea())
            .navigationTitle(payload.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .sheet(isPresented: $isExporting) {
                DocumentExportSheet(payload: payload)
            }
            .task {
                document = DocumentStore.document(for: payload)
            }
        }
    }

    // MARK: - Page

    private var pageView: some View {
        GeometryReader { proxy in
            let pageSize = page.map(DocumentStore.pageSize) ?? CGSize(width: 612, height: 792)
            let scale = proxy.size.width / pageSize.width
            let displaySize = CGSize(width: proxy.size.width, height: pageSize.height * scale)

            ScrollView {
                ZStack(alignment: .topLeading) {
                    if let page, let image = DocumentStore.image(of: page, fittingWidth: proxy.size.width) {
                        Image(uiImage: image)
                            .resizable()
                            .frame(width: displaySize.width, height: displaySize.height)
                    }

                    highlightLayer(pageSize: pageSize, displaySize: displaySize)

                    if mode == .ink {
                        inkLayer(pageSize: pageSize, scale: scale, displaySize: displaySize)
                    }

                    if let rect = pendingHighlightRect {
                        Rectangle()
                            .fill(color(for: highlightColor).opacity(0.25))
                            .frame(width: rect.width, height: rect.height)
                            .offset(x: rect.minX, y: rect.minY)
                            .allowsHitTesting(false)
                    }
                }
                .frame(width: displaySize.width, height: displaySize.height)
                .contentShape(.rect)
                .gesture(mode == .highlight ? highlightGesture(pageSize: pageSize, scale: scale) : nil)
            }
            .scrollDisabled(mode == .ink)
        }
    }

    private func highlightLayer(pageSize: CGSize, displaySize: CGSize) -> some View {
        ForEach(payload.annotations.highlights(onPage: pageIndex)) { highlight in
            ForEach(Array(highlight.rects.enumerated()), id: \.offset) { _, rect in
                let frame = displayRect(rect, pageSize: pageSize, displaySize: displaySize)
                Rectangle()
                    .fill(color(for: highlight.color).opacity(0.3))
                    .frame(width: frame.width, height: frame.height)
                    .offset(x: frame.minX, y: frame.minY)
                    .onTapGesture {
                        motion.run(.snap) { payload.annotations.removeHighlight(id: highlight.id) }
                    }
                    .accessibilityLabel(Text("Highlight"))
                    .accessibilityValue(Text(highlight.text))
                    .accessibilityHint(Text("Double tap to remove"))
            }
        }
    }

    /// Ink is stored in page space, so it lands identically at any width.
    private func inkLayer(pageSize: CGSize, scale: CGFloat, displaySize: CGSize) -> some View {
        InkCanvasView(
            drawing: Binding(
                get: { scaled(payload.annotations.drawing(onPage: pageIndex) ?? Data(), by: scale) },
                set: { payload.annotations.setDrawing(scaled($0, by: 1 / scale), onPage: pageIndex) }
            ),
            theme: theme,
            isEditable: true,
            onChange: { _ in },
            onStrokeTapped: nil
        )
        .frame(width: displaySize.width, height: displaySize.height)
    }

    // MARK: - Highlighting

    /// Drag across text and the highlight follows the *lines*, not the
    /// rectangle — `selectionsByLine` is what makes a highlight across a
    /// paragraph break stop at the end of each line instead of swallowing the
    /// margin.
    private func highlightGesture(pageSize: CGSize, scale: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                if dragStart == nil { dragStart = value.startLocation }
                dragEnd = value.location
            }
            .onEnded { value in
                defer {
                    dragStart = nil
                    dragEnd = nil
                }
                guard let page else { return }

                let from = pagePoint(value.startLocation, pageSize: pageSize, scale: scale)
                let to = pagePoint(value.location, pageSize: pageSize, scale: scale)

                guard let selection = page.selection(from: from, to: to) else { return }
                let lines = selection.selectionsByLine()
                let rects = lines
                    .map { NormalisedRect($0.bounds(for: page), in: pageSize) }
                    .filter(\.isMeaningful)
                guard !rects.isEmpty else { return }

                motion.run(.snap) {
                    payload.annotations.add(
                        DocumentAnnotations.Highlight(
                            page: pageIndex,
                            rects: rects,
                            color: highlightColor,
                            text: selection.string ?? ""
                        )
                    )
                }
            }
    }

    private var pendingHighlightRect: CGRect? {
        guard mode == .highlight, let start = dragStart, let end = dragEnd else { return nil }
        return CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )
    }

    // MARK: - Coordinates

    /// Screen point to PDF page point: undo the display scale, then flip.
    private func pagePoint(_ point: CGPoint, pageSize: CGSize, scale: CGFloat) -> CGPoint {
        CGPoint(x: point.x / scale, y: pageSize.height - point.y / scale)
    }

    /// Page rect to screen rect: scale, then flip.
    private func displayRect(_ rect: NormalisedRect, pageSize: CGSize, displaySize: CGSize) -> CGRect {
        let inPage = rect.rect(in: pageSize)
        let scale = displaySize.width / pageSize.width
        return CGRect(
            x: inPage.minX * scale,
            y: displaySize.height - (inPage.maxY * scale),
            width: inPage.width * scale,
            height: inPage.height * scale
        )
    }

    private func scaled(_ data: Data, by scale: CGFloat) -> Data {
        guard !data.isEmpty, let drawing = try? PKDrawing(data: data) else { return Data() }
        return drawing.transformed(using: CGAffineTransform(scaleX: scale, y: scale)).dataRepresentation()
    }

    private func color(for role: DocumentAnnotations.HighlightColor) -> Color {
        switch role {
        case .accent: theme.accent
        case .gilt: theme.gilt
        case .ink: theme.ink
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Done") { dismiss() }
        }

        ToolbarItem(placement: .principal) {
            Picker("Mode", selection: $mode) {
                ForEach(Mode.allCases, id: \.self) { mode in
                    Label(mode.displayName, systemImage: mode.systemImage)
                        .labelStyle(.iconOnly)
                        .tag(mode)
                }
            }
            .pickerStyle(.segmented)
        }

        ToolbarItem(placement: .primaryAction) {
            Menu {
                if mode == .highlight {
                    Picker("Colour", selection: $highlightColor) {
                        ForEach(DocumentAnnotations.HighlightColor.allCases, id: \.self) { role in
                            Text(role.displayName).tag(role)
                        }
                    }
                    Divider()
                }
                Button {
                    isExporting = true
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
            } label: {
                Label("Options", systemImage: "ellipsis.circle")
            }
        }
    }
}

/// The page strip. Pages carrying annotations are marked, so finding the one
/// you wrote on does not mean scrolling through fifty.
struct PageThumbnailStrip: View {
    let document: PDFDocument
    @Binding var selection: Int
    let annotatedPages: Set<Int>

    @Environment(\.theme) private var theme

    private static let thumbnailWidth: CGFloat = 56

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: Layout.Space.snug) {
                    ForEach(0..<document.pageCount, id: \.self) { index in
                        thumbnail(index)
                            .id(index)
                    }
                }
                .padding(.horizontal, Layout.Space.regular)
                .padding(.vertical, Layout.Space.snug)
            }
            .scrollIndicators(.hidden)
            .background(.bar)
            .onChange(of: selection) { _, index in
                withAnimation { proxy.scrollTo(index, anchor: .center) }
            }
        }
    }

    private func thumbnail(_ index: Int) -> some View {
        Button {
            selection = index
        } label: {
            VStack(spacing: Layout.Space.hair) {
                ZStack(alignment: .topTrailing) {
                    if let page = document.page(at: index),
                       let image = DocumentStore.image(of: page, fittingWidth: Self.thumbnailWidth, scale: 1) {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: Self.thumbnailWidth)
                    } else {
                        Rectangle()
                            .fill(theme.inset)
                            .frame(width: Self.thumbnailWidth, height: Self.thumbnailWidth * 1.4)
                    }

                    if annotatedPages.contains(index) {
                        Circle()
                            .fill(theme.accent)
                            .frame(width: Layout.Space.snug, height: Layout.Space.snug)
                            .padding(Layout.Space.hair)
                    }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: Layout.Radius.tight / 2)
                        .strokeBorder(
                            selection == index ? theme.accent : theme.rule,
                            lineWidth: selection == index ? 2 : Layout.hairline
                        )
                }

                Text("\(index + 1)")
                    .versoText(.metadata)
                    .foregroundStyle(selection == index ? theme.accent : theme.inkSecondary)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Page \(index + 1)"))
        .accessibilityAddTraits(selection == index ? [.isSelected] : [])
        .accessibilityHint(annotatedPages.contains(index) ? Text("Has annotations") : Text(""))
    }
}
