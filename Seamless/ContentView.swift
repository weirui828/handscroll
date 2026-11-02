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
    #if DEBUG
    private var debugSettings: Bool { ProcessInfo.processInfo.arguments.contains("-demoSettings") }
    #else
    private var debugSettings: Bool { false }
    #endif
    @State private var shareRequest: ShareRequest?
    var body: some View {
        NavigationStack {
            Group {
                if editor.photo == nil {
                    StartView(pick: $pick, status: editor.status, onHelp: { showHelp = true })
                } else {
                    EditorView(model: editor, batch: batch, showBatch: $showBatch,
                               shareRequest: $shareRequest,
                               showsWordmark: true,
                               pick: $pick,
                               accent: Color(UIColor(hex: accentHex)),
                               onHelp: { showHelp = true })
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
               let mode = Mode(rawValue: args[i + 1]) { editor.mode = mode }
            if args.contains("-demoBatch") { showBatch = true }
            if args.contains("-demoPlay") { editor.togglePlay() }
            if args.contains("-demoSettings") { showHelp = true }
            if args.contains("-demoHelp") { showHelp = true }
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
        .sheet(isPresented: $showHelp) {
            HelpView(startTab: debugSettings ? .settings
                        : showBatch ? .batch : editor.photo == nil ? .carousel : HelpTab(editor.mode),
                     accentHex: $accentHex)
        }
    }
}

struct StartView: View {
    @Binding var pick: PhotosPickerItem?
    var status: String?
    var onHelp: () -> Void = {}

    var body: some View {
        ScrollView {
        VStack(spacing: 20) {
            Text("Seamless")
                .font(.system(size: 30, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(DS.text)
            PhotosPicker(selection: $pick, matching: .images, photoLibrary: .shared()) {
                Text("Select a photo").frame(minWidth: 180)
            }
            .buttonStyle(PrimaryButton())
            Button("Help") { onHelp() }
                .font(.footnote)
                .foregroundStyle(DS.secondary)
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
