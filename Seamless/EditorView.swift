import SwiftUI
import PhotosUI
import UIKit

/// The canvas and the controls sit in two separate panes. A wide, clearly landscape
/// window puts them side by side; anything narrower stacks the canvas above the
/// controls, so the photo never has to share a row with the inspector.
struct EditorView: View {
    @Bindable var model: EditorModel
    var batch: BatchModel?              // nil while adjusting one batch photo
    @Binding var showBatch: Bool
    @Binding var shareRequest: ShareRequest?
    var pick: Binding<PhotosPickerItem?>? = nil
    var accent: Color = DS.ink
    var onHelp: (() -> Void)?
    var onExplain: (() -> Void)?
    /// False while adjusting one batch photo: that screen has its own Done/Cancel bar.
    var showsExportActions = true
    @State private var controlsHeight: CGFloat = 0
    @State private var showResult = false
    @State private var note: String?
    @State private var noteTask: Task<Void, Never>?
    @Environment(HingeState.self) private var hinge

    /// The folded Duo runs on its outer display. The system puts the bars on the side
    /// there, so the mode switch floats over the canvas instead of taking a row.
    private var onOuterDisplay: Bool { hinge.openness == .closed }

    private var modePicker: some View {
        Picker("Mode", selection: $model.mode) {
            ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
    }

    private var currentStep: Step? { model.captureStep() }
    private var currentStepAdded: Bool {
        guard let batch, let step = currentStep else { return false }
        return batch.steps.contains { $0.sameAs(step) }
    }

    private func addCurrentStep() {
        guard let batch, let step = currentStep, !currentStepAdded else { return }
        flash(batch.add(step))
    }

    private func flash(_ text: String) {
        noteTask?.cancel()
        withAnimation(.easeOut(duration: 0.15)) { note = text }
        noteTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            withAnimation(.easeIn(duration: 0.25)) { note = nil }
        }
    }

    private func shareFiles() {
        Task {
            let urls = await model.exportFiles()
            if urls.isEmpty { showResult = true }
            else { shareRequest = ShareRequest(items: urls) }
        }
    }

    private func saveFiles() {
        model.status = nil
        Task {
            let urls = await model.exportFiles()
            if !urls.isEmpty { await model.saveToPhotos(urls) }
            showResult = true
        }
    }

    var body: some View {
        GeometryReader { geo in
            let sideBySide = !onOuterDisplay && fitsTwoPanes(width: geo.size.width, height: geo.size.height)
            let compact = !sideBySide && geo.size.height < 620
            let controlsWidth = min(400, geo.size.width * 0.42)

            let header = VStack(spacing: 0) {
                modePicker
                    .padding(.horizontal, 12)
                    .padding(.top, sideBySide ? 44 : 10)
                    .padding(.bottom, 6)
                Divider().overlay(DS.stroke)
            }
            .background(DS.bar)

            let controls = ScrollView {
                Controls(model: model, compact: compact, accent: accent,
                         roomy: sideBySide, onExplain: onExplain)
                    .padding(12)
                    .background(GeometryReader { proxy in
                        Color.clear.preference(key: ControlsHeightKey.self, value: proxy.size.height)
                    })
            }
            .scrollBounceBehavior(.basedOnSize)
            .onPreferenceChange(ControlsHeightKey.self) { controlsHeight = $0 }

            if sideBySide {
                HStack(spacing: 0) {
                    CanvasView(model: model, inset: 20, onExplain: onExplain,
                               showsInfoRow: model.mode == .drift)
                    Divider().overlay(DS.stroke)
                    VStack(spacing: 0) { header; controls }
                        .frame(width: controlsWidth)
                        .background(DS.bg)
                }
            } else if onOuterDisplay {
                // Folded: the system puts its bars on the side, so the mode switch
                // floats over the canvas and the photo keeps the full height.
                VStack(spacing: 0) {
                    ZStack(alignment: .bottom) {
                        CanvasView(model: model, onExplain: onExplain, bottomInset: 84)
                        modePicker
                            .padding(6)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                            .padding(.horizontal, 20)
                            .padding(.bottom, 60)
                    }
                    .frame(maxHeight: .infinity)
                    Divider().overlay(DS.stroke)
                    controls
                        .frame(height: min(max(controlsHeight, 0), geo.size.height * (compact ? 0.45 : 0.55)))
                }
            } else {
                VStack(spacing: 0) {
                    header
                    CanvasView(model: model, onExplain: onExplain)
                        .frame(maxHeight: .infinity)
                    Divider().overlay(DS.stroke)
                    controls
                        .frame(height: min(max(controlsHeight, 0), geo.size.height * (compact ? 0.45 : 0.55)))
                }
            }
        }
        .background(DS.bg)
        // The actions live in the bottom bar, so the top bar has nothing to say.
        .toolbar(showsExportActions ? .hidden : .visible, for: .navigationBar)
        .overlay(alignment: .bottom) {
            if let message = model.progress ?? (model.busy ? "Working…" : note) {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(DS.text)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.bottom, 14)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .bottomBar) {
                // Help leads: the system puts the first item at the top of a
                // vertical bar, and at the leading edge of a horizontal one.
                if let onHelp {
                    Button(action: onHelp) {
                        Label("Help", systemImage: "questionmark.circle")
                    }
                }
                if let pick {
                    PhotosPicker(selection: pick, matching: .images, photoLibrary: .shared()) {
                        Label("New photo", systemImage: "photo.badge.plus")
                    }
                }
                if let batch {
                    Button { addCurrentStep() } label: {
                        Label("Add to batch", systemImage: "plus.circle")
                    }
                    .disabled(currentStepAdded || model.busy || batch.steps.count >= maxSteps)

                    Button { showBatch = true } label: {
                        Label(batch.steps.isEmpty ? "Batch" : "Batch, \(batch.steps.count) steps",
                              systemImage: "rectangle.stack")
                            .symbolEffect(.bounce, value: batch.steps.count)
                    }
                    .accessibilityValue("\(batch.steps.count) steps")
                }
                if showsExportActions {
                    Button { saveFiles() } label: {
                        Label("Save", systemImage: "square.and.arrow.down")
                    }
                    .disabled(model.busy)

                    Button { shareFiles() } label: {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    .disabled(model.busy)
                }
            }
        }
        .alert("Export", isPresented: $showResult) {
            if model.status?.hasPrefix("Photos access is off") == true {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                    model.status = nil
                }
            }
            Button("OK", role: .cancel) { model.status = nil }
        } message: {
            Text(model.status ?? "No files were saved.")
        }
        .task {
            #if DEBUG
            // -demoSave exercises the save flow without a tap, for testing.
            if ProcessInfo.processInfo.arguments.contains("-demoSave") {
                try? await Task.sleep(for: .seconds(2))
                saveFiles()
                if ProcessInfo.processInfo.arguments.contains("-demoDismiss") {
                    try? await Task.sleep(for: .seconds(3))
                    showResult = false
                }
            }
            #endif
        }
        .onChange(of: showResult) { _, showing in
            if !showing { model.status = nil }
        }
    }
}

struct CanvasView: View {
    @Bindable var model: EditorModel
    var inset: CGFloat = 0
    var onExplain: (() -> Void)? = nil
    var showsInfoRow = true
    /// Room under the photo, so a control floating above it (the mode switch on the
    /// folded Duo) never sits on the slide grip.
    var bottomInset: CGFloat = 0
    @AppStorage("seamless.hint.slides") private var slidesHintDone = false
    @AppStorage("seamless.hint.shape") private var shapeHintDone = false
    @State private var hintPulse = false
    @State private var dragStart: Layout?
    @State private var pinchStart: CGFloat?
    @State private var countStart: Int?
    @State private var shapeStart: CGFloat?

    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { geo in
                if let img = model.preview, let frame = model.currentFrame {
                    let isDrift = model.mode == .drift
                    let aw = isDrift ? driftSize.width : frame.fw
                    let ah = isDrift ? driftSize.height : frame.fh
                    // the grips sit 10 pt past the photo edges, so leave that much room
                    let verticalMargin: CGFloat = isDrift ? 12 : 44
                    let fit = max(0.001, min(max(1, geo.size.width - 24) / aw, max(1, geo.size.height - verticalMargin) / ah))
                    let w = aw * fit, h = ah * fit
                    let photoTop = (geo.size.height - h) / 2
                    let photoLeft = (geo.size.width - w) / 2
                    ZStack {
                        Image(uiImage: img).resizable().frame(width: w, height: h)
                            .overlay(alignment: .bottom) {
                                if isDrift && model.playing {
                                    let progress = model.drift.dur > 0 ? min(1, max(0, model.driftT / model.drift.dur)) : 0
                                    let barWidth = min(132, max(0, w - 24))
                                    ZStack(alignment: .leading) {
                                        Capsule()
                                            .fill(.white.opacity(0.12))
                                            .background(.ultraThinMaterial, in: Capsule())
                                        Capsule()
                                            .fill(.white.opacity(0.55))
                                            .frame(width: barWidth * progress)
                                    }
                                    .frame(width: barWidth, height: 3)
                                    .padding(.bottom, 8)
                                    .animation(.linear(duration: 0.08), value: progress)
                                    .allowsHitTesting(false)
                                    .transition(.opacity)
                                }
                            }
                        if isDrift {
                            Button { model.togglePlay() } label: {
                                Image(systemName: model.playing ? "pause.fill" : "play.fill")
                                    .font(.system(size: 24, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.92))
                                    .frame(width: 62, height: 62)
                                    .background(.black.opacity(0.18), in: Circle())
                                    .overlay(Circle().stroke(.white.opacity(0.22), lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(model.playing ? "Pause" : "Play")
                        }
                        if !isDrift {
                            // the dashed cuts run a little past the photo and end in a grip
                            Canvas { ctx, size in
                                let n = max(frame.n, 1)
                                let top = (size.height - h) / 2       // where the photo starts
                                let bottom = top + h
                                for i in 1..<n {
                                    let x = size.width * CGFloat(i) / CGFloat(n)
                                    // inside the photo the cut is white
                                    var inside = Path()
                                    inside.move(to: CGPoint(x: x, y: top + 4))
                                    inside.addLine(to: CGPoint(x: x, y: bottom - 4))
                                    ctx.stroke(inside, with: .color(.white.opacity(0.9)),
                                               style: StrokeStyle(lineWidth: 1, dash: [6, 4]))

                                    // outside it sits on paper, so it turns ink
                                    for range in [(CGFloat(8), top - 2), (bottom + 2, size.height - 8)] {
                                        var outside = Path()
                                        outside.move(to: CGPoint(x: x, y: range.0))
                                        outside.addLine(to: CGPoint(x: x, y: range.1))
                                        ctx.stroke(outside, with: .color(DS.secondary.opacity(0.6)),
                                                   style: StrokeStyle(lineWidth: 1, dash: [4, 4]))

                                        let y = range.0 < top ? range.0 : range.1
                                        let grip = CGRect(x: x - 9, y: y - 2, width: 18, height: 4)
                                        ctx.fill(Path(roundedRect: grip, cornerRadius: 2),
                                                 with: .color(DS.secondary))
                                    }
                                }
                            }
                            .frame(width: w, height: h + 36)
                            .allowsHitTesting(false)

                            // drag the stubs above or below the photo to change the slide count
                            if frame.n > 1 {
                                VStack(spacing: 0) {
                                    dividerBand(w: w, n: frame.n)
                                    Spacer(minLength: 0)
                                    dividerBand(w: w, n: frame.n)
                                }
                                .frame(width: w, height: h + 36)
                            }

                            // both hints sit next to the handle they talk about
                            if frame.n > 1, !slidesHintDone {
                                hintCapsule("Drag for slides", icon: "arrow.left.and.right") {
                                    slidesHintDone = true
                                }
                                .position(x: min(max(photoLeft + w / CGFloat(max(frame.n, 1)), 80), geo.size.width - 80),
                                          y: max(24, photoTop - 22))
                            }
                            if !shapeHintDone {
                                hintCapsule("Drag for shape", icon: "arrow.up.left.and.arrow.down.right") {
                                    shapeHintDone = true
                                }
                                .position(x: min(max(photoLeft + w - 92, 92), geo.size.width - 92),
                                          y: photoTop + h + 26 <= geo.size.height - 46
                                            ? photoTop + h + 26
                                            : photoTop + h - 64)
                            }

                            // and the bottom-right corner sets the shape
                            cornerHandle(frame: frame, h: h)
                                .frame(width: w, height: h, alignment: .bottomTrailing)
                        }
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
                    .contentShape(Rectangle())
                    .gesture(drag(w: w, h: h), including: isDrift ? .none : .all)
                    .simultaneousGesture(pinch, including: isDrift ? .none : .all)
                    .onTapGesture(count: 2) { if !isDrift { model.resetPosition() } }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Photo preview")
                    .accessibilityValue(model.info)
                    .accessibilityHint("Use the position controls to adjust the photo.")
                }
            }
            .clipped()
            .padding(.bottom, bottomInset)
            if showsInfoRow {
                VStack(spacing: 2) {
                    HStack(spacing: 12) {
                            if model.tallWarning {
                                Button { onExplain?() } label: {
                                    Image(systemName: "exclamationmark.circle")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(.orange)
                                        .frame(width: 24, height: 44)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("4:5 warning")
                                .accessibilityHint("Opens Help")
                            }

                        if model.mode == .drift {
                            Text(model.sizeText).font(.footnote).foregroundStyle(DS.secondary)
                        } else {
                            SizeControl(model: model)
                            FrameControl(model: model, style: .menu)
                            if model.leavesGap {
                                FillControl(model: model)
                            }
                        }
                    }
                }
                .padding(.horizontal, 12).padding(.bottom, 6)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(inset)
        .background(DS.bg)
        .clipped()
    }

    private func drag(w: CGFloat, h: CGFloat) -> some Gesture {
        DragGesture()
            .onChanged { v in
                if dragStart == nil { dragStart = model.layout }
                if let s = dragStart { model.pan(dx: v.translation.width / w, dy: v.translation.height / h, from: s) }
            }
            .onEnded { _ in dragStart = nil }
    }

    private func hintCapsule(_ text: String, icon: String, dismiss: @escaping () -> Void) -> some View {
        Button(action: dismiss) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 10, weight: .semibold))
                Text(text).font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(DS.onInk)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(DS.ink.opacity(0.82), in: Capsule())
            .scaleEffect(hintPulse ? 1.06 : 1)
            .opacity(hintPulse ? 1 : 0.82)
        }
        .buttonStyle(.plain)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                hintPulse = true
            }
        }
        .accessibilityLabel(text)
    }

    /// A clear band that turns a horizontal drag into +-1 slide, starting from the nearest cut.
    private func dividerBand(w: CGFloat, n: Int) -> some View {
        Color.clear
            .frame(height: 26)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 6)
                    .onChanged { value in
                        slidesHintDone = true
                        if countStart == nil { countStart = n }
                        guard let start = countStart else { return }
                        let steps = Int((value.translation.width / 46).rounded())
                        model.setCount(min(maxSlides, max(2, start + steps)))
                    }
                    .onEnded { _ in countStart = nil }
            )
    }

    /// The crop-style corner: drag down for a taller slide, up for a wider one.
    private func cornerHandle(frame: Frame, h: CGFloat) -> some View {
        ZStack(alignment: .bottomTrailing) {
            Color.clear.frame(width: 64, height: 64)

            // a bigger bracket, so the corner reads as a handle, not as a speck
            Path { p in
                p.move(to: CGPoint(x: 34, y: 4))
                p.addLine(to: CGPoint(x: 34, y: 34))
                p.addLine(to: CGPoint(x: 4, y: 34))
            }
            .stroke(.white.opacity(0.95), style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
            .shadow(color: .black.opacity(0.45), radius: 1.6, y: 0.5)
            .frame(width: 38, height: 38)
            .padding(6)

            // the ratio sits inside the bracket
            Text(shapeLabel)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.95))
                .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
                .padding(.trailing, 14).padding(.bottom, 12)
        }
        .contentShape(Rectangle())
        .onTapGesture { cycleShape() }
        .gesture(
            DragGesture(minimumDistance: 6)
                .onChanged { value in
                    shapeHintDone = true
                    if shapeStart == nil { shapeStart = frame.a }
                    guard let start = shapeStart else { return }
                    let taller = start * h / max(60, h + value.translation.height * 1.8)
                    let target: Shape
                    if taller > 0.9 { target = .r11 }
                    else if taller > 0.775 { target = .r45 }
                    else { target = .r34 }
                    model.setShape(target)
                }
                .onEnded { _ in shapeStart = nil }
        )
        .accessibilityLabel("Slide shape")
        .accessibilityValue(shapeLabel)
        .accessibilityHint("Tap to change, drag to adjust")
    }

    private var shapeLabel: String {
        model.layout.shape.rawValue
    }

    private func cycleShape() {
        let order: [Shape] = model.mode == .split ? [.auto, .r45, .r34, .r11] : [.r45, .r34, .r11]
        let i = order.firstIndex(of: model.layout.shape) ?? 0
        model.setShape(order[(i + 1) % order.count])
    }

    private var pinch: some Gesture {
        MagnifyGesture()
            .onChanged { v in
                if pinchStart == nil { pinchStart = model.layout.zoom }
                if let z = pinchStart { model.setZoom(z * v.magnification) }
            }
            .onEnded { _ in pinchStart = nil }
    }
}

struct Controls: View {
    @Bindable var model: EditorModel
    var compact = false
    var accent: Color = DS.ink
    /// True in the two-pane layout, where the pane takes the controls the narrow
    /// layout keeps in the line under the photo.
    var roomy = false
    var onExplain: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if model.geo != nil, model.mode == .drift { driftControls }
            if roomy, model.geo != nil, model.mode != .drift {
                slideGroup
            }

            if let s = model.status { Text(s).font(.footnote).foregroundStyle(.secondary) }
        }
    }

    // MARK: Slide and photo

    @ViewBuilder
    private var slideGroup: some View {
        group {
            if model.mode == .split {
                controlRow("Slides") {
                    Picker("Slides", selection: Binding(get: { model.layout.n },
                                                        set: { model.setCount($0) })) {
                        ForEach(2...maxSlides, id: \.self) { n in Text("\(n)").tag(n) }
                    }
                    .pickerStyle(.segmented)
                    .fixedSize(horizontal: true, vertical: false)
                    .accessibilityLabel("Slides")
                }
            }
            controlRow("Shape") {
                AdaptivePicker("Shape", selection: Binding(get: { model.layout.shape },
                                                           set: { model.setShape($0) })) {
                    ForEach(shapeChoices) { Text($0.rawValue).tag($0) }
                }
            }
            controlRow("Size") {
                SizeControl(model: model)
            }
            controlRow("Frame") {
                FrameControl(model: model)
            }
            if model.leavesGap {
                controlRow("Empty") {
                    FillControl(model: model)
                }
            }
            if model.tallWarning {
                Button { onExplain?() } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundStyle(.orange)
                        Text("Taller than 4:5. It may be cropped when you post.")
                            .font(.footnote)
                            .foregroundStyle(DS.secondary)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var shapeChoices: [Shape] {
        model.mode == .split ? [.auto, .r45, .r34, .r11] : [.r45, .r34, .r11]
    }

    // MARK: Drift

    @ViewBuilder
    private var driftControls: some View {
        group {
            HStack(spacing: 10) {
                rowLabel("Pan").frame(width: 58, alignment: .leading)
                RangeSlider(lower: $model.drift.p0, upper: $model.drift.p1, accent: accent)
                    .frame(height: 34)
            }

            inlineSlider("Zoom to", value: Binding(get: { model.drift.z1 },
                                                  set: { model.drift.z1 = $0; model.drift.z0 = 1 }),
                         range: 1...1.6,
                         text: "\(Int((model.drift.z1 * 100).rounded()))%")

            inlineSlider("Length", value: Binding(get: { model.drift.dur },
                                                 set: { model.drift.dur = $0.rounded(); model.driftT = min(model.driftT, model.drift.dur) }),
                         range: 3...30,
                         text: "\(Int(model.drift.dur)) s")

            Toggle("Ease in and out", isOn: $model.drift.ease)
                .font(.footnote)
                .foregroundStyle(DS.secondary)
        }
    }

    private func inlineSlider(_ label: String, value: Binding<Double>,
                              range: ClosedRange<Double>, text: String) -> some View {
        HStack(spacing: 10) {
            rowLabel(label).frame(width: 58, alignment: .leading)
            Slider(value: value, in: range)
            rowValue(text).frame(width: 42, alignment: .trailing)
        }
    }

    private func rowLabel(_ text: String) -> some View {
        Text(text).font(.footnote).foregroundStyle(DS.secondary)
    }

    /// Label, then the control, all flush left: the controls line up on one edge.
    private func controlRow<Content: View>(_ label: String,
                                           @ViewBuilder _ control: () -> Content) -> some View {
        HStack(spacing: 10) {
            rowLabel(label).frame(width: 58, alignment: .leading)
            control()
            Spacer(minLength: 0)
        }
    }

    private func rowValue(_ text: String) -> some View {
        Text(text).font(.footnote).foregroundStyle(DS.secondary).monospacedDigit()
    }

    // MARK: Export and batch

    private func group<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: compact ? 6 : 8) {
            content()
        }
            .padding(compact ? 10 : 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DS.card, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(DS.stroke, lineWidth: 1))
    }

}

/// The output-size menu, shared by the line under the photo and the pane.
struct SizeControl: View {
    @Bindable var model: EditorModel

    var body: some View {
        Menu {
            Picker("Size", selection: $model.outW) {
                ForEach(model.sizeChoices, id: \.width) { c in
                    Text("\(c.width) × \(c.height) px").tag(CGFloat(c.width))
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(model.sizeText)
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 8, weight: .semibold))
            }
            .font(.footnote)
            .foregroundStyle(DS.secondary)
            .frame(minHeight: 32)
        }
        .accessibilityLabel("Output size")
    }
}

/// Fit/Fill: a menu in the line under the photo, a segment in the pane.
struct FrameControl: View {
    enum Style { case menu, segmented }

    @Bindable var model: EditorModel
    var style: Style = .segmented

    var body: some View {
        switch style {
        case .menu:
            Menu {
                Button("Fit") { model.wholePhoto() }
                Button("Fill") { model.fillFrame() }
            } label: {
                HStack(spacing: 4) {
                    Text(model.showsWholePhoto ? "Fit" : "Fill")
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 8, weight: .semibold))
                }
                .font(.footnote)
                .foregroundStyle(DS.secondary)
                .frame(minHeight: 44)
            }
            .accessibilityLabel("Frame")
        case .segmented:
            Picker("Frame", selection: Binding(get: { model.showsWholePhoto },
                                               set: { whole in whole ? model.wholePhoto() : model.fillFrame() })) {
                Text("Fit").tag(true)
                Text("Fill").tag(false)
            }
            .pickerStyle(.segmented)
            .fixedSize(horizontal: true, vertical: false)
            .accessibilityLabel("Frame")
        }
    }
}

/// The empty-space picker: shows the current fill and opens the fill sheet.
struct FillControl: View {
    @Bindable var model: EditorModel
    @State private var shows = false

    var body: some View {
        Button { shows = true } label: {
            HStack(spacing: 4) {
                Text(model.look.fill.rawValue)
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 8, weight: .semibold))
            }
            .font(.footnote)
            .foregroundStyle(DS.secondary)
            .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Empty space")
        .sheet(isPresented: $shows) {
            FillSheet(model: model)
                .presentationDetents([.height(190)])
                .presentationCornerRadius(22)
                .presentationDragIndicator(.visible)
        }
    }
}

/// Keeps all choices visible when they fit, and uses a native menu on narrow screens or larger text sizes.
struct AdaptivePicker<Selection: Hashable, Choices: View>: View {
    let title: String
    @Binding var selection: Selection
    @ViewBuilder var choices: () -> Choices
    @Environment(\.dynamicTypeSize) private var typeSize

    init(_ title: String, selection: Binding<Selection>, @ViewBuilder choices: @escaping () -> Choices) {
        self.title = title
        _selection = selection
        self.choices = choices
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            if !typeSize.isAccessibilitySize {
                Picker(title, selection: $selection, content: choices)
                    .pickerStyle(.segmented)
                    .fixedSize(horizontal: true, vertical: false)
            }
            Picker(title, selection: $selection, content: choices)
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ControlsHeightKey: PreferenceKey {
    nonisolated(unsafe) static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// Two knobs on one track: the start and the end of the drift pan.
struct RangeSlider: View {
    @Binding var lower: Double
    @Binding var upper: Double
    var range: ClosedRange<Double> = 0...1
    var accent: Color = DS.ink
    var onEdit: (() -> Void)?

    private let knobWidth: CGFloat = 28
    private let knobHeight: CGFloat = 28

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let span = range.upperBound - range.lowerBound
            let usable = max(1, width - knobWidth)
            let lx = CGFloat((lower - range.lowerBound) / span) * usable
            let ux = CGFloat((upper - range.lowerBound) / span) * usable
            let lo = min(lx, ux), hi = max(lx, ux)

            ZStack(alignment: .leading) {
                Capsule().fill(DS.stroke)
                    .frame(height: 4)
                    .padding(.horizontal, knobWidth / 2)
                Capsule().fill(accent)
                    .frame(width: hi - lo, height: 4)
                    .offset(x: lo + knobWidth / 2)

                knobView(isStart: true)
                    .offset(x: lx)
                    .gesture(drag(width: usable, isLower: true))
                    .accessibilityLabel("Start")
                    .accessibilityValue("\(Int(lower * 100)) percent")

                knobView(isStart: false)
                    .offset(x: ux)
                    .gesture(drag(width: usable, isLower: false))
                    .accessibilityLabel("End")
                    .accessibilityValue("\(Int(upper * 100)) percent")
            }
        }
    }

    /// As close to the system thumb as a custom control gets: the same proportion,
    /// a glassy fill and the same soft shadow. The start one carries an accent dot.
    private func knobView(isStart: Bool) -> some View {
        Circle()
            .fill(.white.opacity(0.86))
            .background(.ultraThinMaterial, in: Circle())
            .frame(width: knobWidth, height: knobHeight)
            .shadow(color: .black.opacity(0.16), radius: 5, y: 1.5)
            .overlay {
                if isStart {
                    Circle().fill(accent).frame(width: 6, height: 6)
                }
            }
    }

    private func drag(width: CGFloat, isLower: Bool) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let span = range.upperBound - range.lowerBound
                let x = (isLower ? CGFloat((lower - range.lowerBound) / span) * width : CGFloat((upper - range.lowerBound) / span) * width)
                let next = (x + value.translation.width) / width
                let v = range.lowerBound + Double(min(max(next, 0), 1)) * span
                if isLower { lower = (v * 100).rounded() / 100 } else { upper = (v * 100).rounded() / 100 }
                onEdit?()
            }
    }
}

private struct FillSheet: View {
    @Bindable var model: EditorModel

    var body: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: 14) {
            Text("Empty space")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(DS.secondary)

            Picker("Fill", selection: $model.look.fill) {
                ForEach(Fill.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            if model.look.fill == .blur {
                HStack(spacing: 12) {
                    Text("Darken").font(.footnote).foregroundStyle(DS.secondary)
                    Slider(value: Binding(get: { Double(model.look.dim) }, set: { model.look.dim = CGFloat($0) }), in: 0...0.7)
                    Text("\(Int(model.look.dim * 100))%")
                        .font(.footnote).foregroundStyle(DS.secondary)
                        .frame(width: 34, alignment: .trailing)
                }
            }

            if model.look.fill == .color {
                HStack(spacing: 10) {
                    ForEach(Palette.all, id: \.hex) { swatch in
                        Button { model.look.colorHex = swatch.hex } label: {
                            PaletteDot(hex: swatch.hex,
                                       selected: model.look.colorHex.uppercased() == swatch.hex)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(swatch.name)
                    }
                    Spacer(minLength: 4)
                    ColorPicker("Custom", selection: Binding(
                        get: { Color(UIColor(hex: model.look.colorHex)) },
                        set: { model.look.colorHex = UIColor($0).hexString }))
                        .labelsHidden()
                }
            }
        }
        .padding(.horizontal, 18).padding(.top, 16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(DS.bg)
    }
}
