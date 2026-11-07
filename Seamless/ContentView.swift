import SwiftUI
import PhotosUI

struct ContentView: View {
    @State private var editor = EditorModel()
    @State private var batch = BatchModel()
    @State private var hinge = HingeState()
    @AppStorage("seamless.accent.v2") private var accentHex = "#111317"
    @State private var pick: PhotosPickerItem?
    @State private var showBatch = false
    @State private var showHelp = false
    @State private var helpOpen: HelpTopic?
    @State private var helpAnchor: String?
    @State private var shareRequest: ShareRequest?
    var body: some View {
        NavigationStack {
            Group {
                if editor.photo == nil {
                    StartView(pick: $pick, status: editor.status)
                } else {
                    EditorView(model: editor, batch: batch, showBatch: $showBatch,
                               shareRequest: $shareRequest,
                               pick: $pick,
                               accent: Color(UIColor(hex: accentHex)),
                               onHelp: { helpOpen = nil; helpAnchor = nil; showHelp = true },
                               onExplain: { helpOpen = .basics; helpAnchor = "4-5-warning"; showHelp = true })
                }
            }
            .navigationTitle("")
        .toolbarBackground(DS.bar, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(isPresented: $showBatch) {
                BatchView(batch: batch, shareRequest: $shareRequest)
            }
        }
        .tint(Color(UIColor(hex: accentHex)))
        .background(DS.bg)
        .environment(hinge)
        .background(HingeReader(state: hinge))
        .task {
            #if DEBUG
            let args = ProcessInfo.processInfo.arguments
            if editor.photo == nil, args.contains("-demoPhoto") { editor.loadDemo() }
            if let i = args.firstIndex(of: "-demoMode"), i + 1 < args.count,
               let mode = args[i + 1] == "Video" ? Mode.drift : Mode(rawValue: args[i + 1]) {
                editor.mode = mode == .drift ? .drift : .split
                if mode == .fit || mode == .crop {
                    editor.setCount(1)
                    if mode == .fit, let geo = editor.geo, let frame = editor.currentFrame {
                        editor.setZoom(geo.fitZoom(frame))
                    }
                }
            }
            if args.contains("-demoBatch") { showBatch = true }
            if args.contains("-demoPlay") { editor.togglePlay() }
            if args.contains("-demoSettings") { helpOpen = .settings; showHelp = true }
            if let i = args.firstIndex(of: "-demoTopic"), i + 1 < args.count,
               let topic = HelpTopic(rawValue: args[i + 1]) { helpOpen = topic; showHelp = true }
            if args.contains("-demoHelp") { helpOpen = nil; showHelp = true }
            if args.contains("-demoBasics") { helpOpen = .basics; showHelp = true }
            if args.contains("-demoWarning") { editor.setShape(.r34) }
            if let i = args.firstIndex(of: "-demoSlides"), i + 1 < args.count,
               let count = Int(args[i + 1]) { editor.setCount(count) }
            if let i = args.firstIndex(of: "-demoShape"), i + 1 < args.count,
               let shape = Shape(rawValue: args[i + 1]) { editor.setShape(shape) }
            if args.contains("-demoColor") {
                editor.look.fill = .color
                editor.look.colorHex = "#A78BFA"
            }
            #endif
        }
        .onChange(of: showBatch) { _, showing in
            // the photo open in the editor belongs in the batch, so take it along
            guard showing, let item = editor.sourceItem, !batch.contains(item) else { return }
            Task { await batch.add([item]) }
        }
        .onChange(of: pick) { _, item in
            guard let item else { return }
            Task { await editor.load(item); pick = nil }
        }
        .sheet(item: $shareRequest) { request in ShareSheet(items: request.items) }
        // Full screen, so the manual gets the width it needs on a Duo and a phone
        // alike; a centred sheet stayed phone-width in landscape.
        .fullScreenCover(isPresented: $showHelp, onDismiss: { helpAnchor = nil }) {
            HelpView(open: helpOpen, anchor: helpAnchor, accentHex: $accentHex,
                     onOpenMode: { mode in
                         editor.mode = mode
                         showHelp = false
                     },
                     onOpenBatch: {
                         showHelp = false
                         DispatchQueue.main.async { showBatch = true }
                     })
        }
    }
}


struct StartView: View {
    @Binding var pick: PhotosPickerItem?
    var status: String?

    var body: some View {
        ScrollView {
        VStack(spacing: 20) {
            Text("handscroll")
                .font(.system(size: 30, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(DS.text)
            PhotosPicker(selection: $pick, matching: .images, photoLibrary: .shared()) {
                Text("Select a photo").frame(minWidth: 180)
            }
            .buttonStyle(PrimaryButton())
            if let status { Text(status).foregroundStyle(.red).font(.footnote) }
        }
        .padding()
        .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .defaultScrollAnchor(.center)
        .background(DS.bg)
        .toolbar(.hidden, for: .navigationBar)
    }
}

struct ShareRequest: Identifiable {
    let id = UUID()
    let items: [URL]
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [URL]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
