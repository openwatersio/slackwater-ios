// Slackwater — GPL v3. Printable tables: the schedule card's last row, the Week/Month sheet
// it opens, and the PDF that sheet previews, prints and shares (docs/detail.md §8.6).
import PDFKit
import SwiftUI
import UIKit

/// The page as a PDF: the HTML through `UIMarkupTextPrintFormatter`, paginated by
/// `UIPrintPageRenderer`, so a saved file and a printed sheet break at the same rows.
/// Letter where Locale.current.measurementSystem == .us, else A4; 36 pt margins.
/// `paper` overrides the locale's choice; tests use it to print both sizes.
@MainActor func printablePDF(html: String, paper size: CGSize? = nil) -> Data {
    let paper = size.map { CGRect(origin: .zero, size: $0) }
        ?? (Locale.current.measurementSystem == .us
            ? CGRect(x: 0, y: 0, width: 612, height: 792)
            : CGRect(x: 0, y: 0, width: 595.28, height: 841.89))
    let formatter = UIMarkupTextPrintFormatter(markupText: html)
    let renderer = UIPrintPageRenderer()
    renderer.addPrintFormatter(formatter, startingAtPageAt: 0)
    // UIPrintPageRenderer only exposes these read-only; KVC is the standard way to set them off a print job.
    renderer.setValue(NSValue(cgRect: paper), forKey: "paperRect")
    renderer.setValue(NSValue(cgRect: paper.insetBy(dx: 36, dy: 36)), forKey: "printableRect")
    return UIGraphicsPDFRenderer(bounds: paper).pdfData { context in
        // Lay the formatter out against the rects above before counting its pages.
        renderer.prepare(forDrawingPages: NSRange(location: 0, length: 1))
        let pages = renderer.numberOfPages
        renderer.prepare(forDrawingPages: NSRange(location: 0, length: pages))
        for page in 0..<pages {
            context.beginPage()
            renderer.drawPage(at: page, in: context.pdfContextBounds)
        }
    }
}

/// The printed header's unit, written out: "kn" becomes "knots".
func printableUnitName(_ label: String) -> String {
    switch label {
    case "kn": String(localized: "printable.unit.kn", defaultValue: "knots", comment: "Printed tide or current table header: the speed unit, written out.")
    case "km/h": String(localized: "printable.unit.kmh", defaultValue: "kilometres per hour", comment: "Printed tide or current table header: the speed unit, written out.")
    case "m/s": String(localized: "printable.unit.ms", defaultValue: "metres per second", comment: "Printed tide or current table header: the speed unit, written out.")
    case "ft": String(localized: "printable.unit.ft", defaultValue: "feet", comment: "Printed tide or current table header: the height unit, written out.")
    case "m": String(localized: "printable.unit.m", defaultValue: "metres", comment: "Printed tide or current table header: the height unit, written out.")
    default: label
    }
}

/// The schedule card's last row. Premium is checked on every tap.
struct PrintableTablesRow: View {
    let config: PrintableConfig
    let anchor: Date
    let tz: TimeZone
    @State private var showSheet = false
    @State private var showPremium = false

    init(config: PrintableConfig, anchor: Date, tz: TimeZone) {
        self.config = config
        self.anchor = anchor
        self.tz = tz
    }

    var body: some View {
        Button {
            if PremiumStore.shared.isPremium { showSheet = true } else { showPremium = true }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "printer")
                    .font(.footnote)
                    .foregroundStyle(SN.foam.opacity(0.7))
                Text("Printable tables", comment: "Row at the end of a place's schedule that opens printable week and month tables. Premium feature.")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Image(systemName: "sparkles")
                    .font(.footnote)
                    .foregroundStyle(SN.leaf)
                    .accessibilityLabel(Text(String(localized: "printable.premium", defaultValue: "Premium",
                                                    comment: "Spoken marker beside the Printable tables row: it is a Premium feature.")))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(SN.foam.opacity(0.5))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("printable-tables-row")
        .sheet(isPresented: $showSheet) { PrintableSheet(config: config, anchor: anchor, tz: tz) }
        .sheet(isPresented: $showPremium) { PremiumView(opening: .print) }
    }
}

/// Week or month, previewed as the PDF itself so preview, print and file match.
struct PrintableSheet: View {
    let config: PrintableConfig
    let anchor: Date
    let tz: TimeZone
    @AppStorage(setFormatKey, store: AppGroup.defaults) private var setFormat = "compass"
    @Environment(\.dismiss) private var dismiss
    @State private var span: PrintSpan = .week
    /// Each span's PDF once built; the sheet builds a span once while it is open.
    @State private var pdfs: [PrintSpan: Data] = [:]
    @State private var sharing: URL?

    init(config: PrintableConfig, anchor: Date, tz: TimeZone) {
        self.config = config
        self.anchor = anchor
        self.tz = tz
    }

    private var ready: Data? { pdfs[span] }

    private var coverageNote: String? {
        guard case .fetched(let covered, _) = config.source else { return nil }
        return printCoverageNote(range: printRange(span, anchor: anchor, tz: tz), covered: covered, tz: tz)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Picker(selection: $span) {
                    Text("Week", comment: "Printable tables switch: print the seven days the schedule shows.")
                        .tag(PrintSpan.week)
                    Text("Month", comment: "Printable tables switch: print the calendar month the schedule's week starts in.")
                        .tag(PrintSpan.month)
                } label: {
                    Text("Printable tables", comment: "Row at the end of a place's schedule that opens printable week and month tables. Premium feature.")
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("printable-span")
                .padding(.horizontal, 16)

                if let note = coverageNote {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(note)
                            .font(.footnote.weight(.semibold))
                            .accessibilityIdentifier("printable-coverage")
                        if let hint = config.moreHint {
                            Text(hint).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                }

                ZStack {
                    Color.white
                    if let ready {
                        PDFPreview(data: ready)
                            .accessibilityIdentifier("printable-preview")
                    } else {
                        ProgressView()
                            .tint(.gray)
                            .accessibilityIdentifier("printable-loading")
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
            .padding(.top, 8)
            .navigationTitle(Text("Printable tables", comment: "Row at the end of a place's schedule that opens printable week and month tables. Premium feature."))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("printable-done")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        if let ready { sharing = writeShareFile(ready) }
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel("Share")
                    .accessibilityIdentifier("printable-share")
                    .disabled(ready == nil)
                }
            }
            .background(ActivityPresenter(item: $sharing))
        }
        .task(id: span) { await build(span) }
    }

    /// Month timelines are built off the main actor; the HTML and its PDF need UIKit.
    /// A result for a span the switch has already left is dropped.
    private func build(_ requested: PrintSpan) async {
        guard pdfs[requested] == nil else { return }
        let source = config.source, tz = tz, now = appNow()
        let range = printRange(requested, anchor: anchor, tz: tz)
        let timelines = await Task.detached(priority: .userInitiated) {
            printTimelines(source, range: range, tz: tz, now: now)
        }.value
        guard !Task.isCancelled, requested == span else { return }
        let page = printablePage(config, span: requested, anchor: anchor, tz: tz,
                                 timelines: timelines, printedAt: now)
        let data = printablePDF(html: printableHTML(page, setFormat: setFormat))
        guard !Task.isCancelled, requested == span else { return }
        pdfs[requested] = data
    }

    /// `<name> – <Week|Month>.pdf` in its own temporary folder, so Save to Files gets a sensible name.
    private func writeShareFile(_ data: Data) -> URL? {
        let label = span == .week
            ? String(localized: "Week", comment: "Printable tables switch: print the seven days the schedule shows.")
            : String(localized: "Month", comment: "Printable tables switch: print the calendar month the schedule's week starts in.")
        let safeName = config.facts.name.replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("printable-\(UUID().uuidString)", isDirectory: true)
        let url = folder.appendingPathComponent("\(safeName) – \(label).pdf")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }
}

/// The PDF on a white page, scaled to the sheet's width.
private struct PDFPreview: UIViewRepresentable {
    let data: Data

    final class Coordinator { var shown: Data? }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.backgroundColor = .white
        view.pageShadowsEnabled = false
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        guard context.coordinator.shown != data else { return }
        context.coordinator.shown = data
        view.document = PDFDocument(data: data)
    }
}

/// Presents `UIActivityViewController` for a file URL from the sheet's own controller,
/// anchored at its top trailing corner for the iPad popover.
private struct ActivityPresenter: UIViewControllerRepresentable {
    @Binding var item: URL?

    func makeUIViewController(context: Context) -> UIViewController { UIViewController() }

    func updateUIViewController(_ host: UIViewController, context: Context) {
        guard let url = item, host.presentedViewController == nil else { return }
        let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        if let popover = activity.popoverPresentationController {
            popover.sourceView = host.view
            popover.sourceRect = CGRect(x: host.view.bounds.maxX - 44, y: 0, width: 44, height: 1)
        }
        activity.completionWithItemsHandler = { _, _, _, _ in
            item = nil
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
        }
        DispatchQueue.main.async { host.present(activity, animated: true) }
    }
}
