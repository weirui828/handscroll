import SwiftUI
import PhotosUI
import UIKit

/// The Photo/Video switch on top, the canvas, then the controls. The app runs in
/// portrait only, so this is the one layout, on every iPhone and the folded Duo.
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

    private var modePicker: some View {
        Picker("Output", selection: $model.mode) {
            Text("Photo").tag(Mode.split)
            Text("Video").tag(Mode.drift)
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
            let compact = geo.size.height < 620

            let header = VStack(spacing: 0) {
                modePicker
                    .padding(.horizontal, 12)
                    // No status bar above it (the folded Duo keeps it at the side): clear the rounded corner.
                    .padding(.top, geo.safeAreaInsets.top < 20 ? 24 : 10)
                    .padding(.bottom, 6)
                Divider().overlay(DS.stroke)
            }
            .background(DS.bar)

            let controls = ScrollView {
                Controls(model: model, compact: compact, accent: accent, onExplain: onExplain)
                    .padding(12)
                    .background(GeometryReader { proxy in
                        Color.clear.preference(key: ControlsHeightKey.self, value: proxy.size.height)
                    })
            }
            .scrollBounceBehavior(.basedOnSize)
            .onPreferenceChange(ControlsHeightKey.self) { controlsHeight = $0 }

            // Every iPhone, the folded Duo included: the Photo/Video switch on top.
            VStack(spacing: 0) {
                header
                CanvasView(model: model, onExplain: onExplain)
                    .frame(maxHeight: .infinity)
                Divider().overlay(DS.stroke)
                controls
                    .frame(height: min(max(controlsHeight, 0), geo.size.height * (compact ? 0.45 : 0.55)))
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

/// The slide grips: how far they sit past the photo edge, their size, and the band
/// above and below the photo that holds them.
private let gripGap: CGFloat = 18
private let gripSize = CGSize(width: 28, height: 10)
private let gripBand: CGFloat = gripGap + 12

struct CanvasView: View {
    @Bindable var model: EditorModel
    var onExplain: (() -> Void)? = nil
    /// Room under the photo, so a control floating above it (the mode switch on the
    /// folded Duo) never sits on the slide grip.
    var bottomInset: CGFloat = 0
    @AppStorage("seamless.hint.slides") private var slidesHintDone = false
    @AppStorage("seamless.hint.shape") private var shapeHintDone = false
    @AppStorage("seamless.hint.doubletap") private var doubleTapHintDone = false
    @State private var hintPulse = false
    @State private var dragStart: Layout?
    @State private var pinchStart: CGFloat?
    @State private var fitHapticSent = false
    @State private var showFitCue = false
    @State private var fitCueTask: Task<Void, Never>?
    @State private var countStart: Int?
    /// How far the slide dials have turned, in radians; dragging rolls their ridges.
    @State private var dialPhase: CGFloat = 0
    @State private var dialPhaseStart: CGFloat?
    @State private var shapeStart: CGFloat?

    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { geo in
                if let img = model.preview, let frame = model.currentFrame {
                    let isDrift = model.mode == .drift
                    let aw = isDrift ? driftSize.width : frame.fw
                    let ah = isDrift ? driftSize.height : frame.fh
                    // the grips sit gripGap pt past the photo edges, so leave room for them
                    let verticalMargin: CGFloat = isDrift ? 12 : 2 * gripBand + 8
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
                            // Read the state here: the Canvas closure runs off the main actor.
                            let phase = dialPhase
                            // An unsplit photo keeps both grips, but has no cut line.
                            Canvas { ctx, size in
                                let n = max(frame.n, 1)
                                let top = (size.height - h) / 2       // where the photo starts
                                let bottom = top + h
                                let gripTop = top - gripGap, gripBottom = bottom + gripGap
                                // A small crown-like wheel seen from the side: ridges bunch up
                                // toward its edges and roll past as it turns.
                                func grip(at x: CGFloat, _ y: CGFloat) {
                                    let r = CGRect(x: x - gripSize.width / 2, y: y - gripSize.height / 2,
                                                   width: gripSize.width, height: gripSize.height)
                                    let body = Path(roundedRect: r, cornerRadius: 3)
                                    ctx.fill(body, with: .linearGradient(
                                        Gradient(colors: [DS.secondary.opacity(0.55), DS.secondary.opacity(0.18),
                                                          DS.secondary.opacity(0.55)]),
                                        startPoint: CGPoint(x: r.minX, y: y), endPoint: CGPoint(x: r.maxX, y: y)))
                                    ctx.stroke(body, with: .color(DS.secondary.opacity(0.7)), lineWidth: 0.75)

                                    let radius = r.width / 2 - 2
                                    let spacing = CGFloat.pi / 8
                                    let offset = phase.truncatingRemainder(dividingBy: spacing)
                                    for k in -9...9 {
                                        let angle = offset + CGFloat(k) * spacing
                                        guard abs(angle) < .pi / 2 * 0.92 else { continue }
                                        let facing = cos(angle)               // 1 at the front, 0 at the edge
                                        let rx = x + radius * sin(angle)
                                        var ridge = Path()
                                        ridge.move(to: CGPoint(x: rx, y: r.minY + 2.5))
                                        ridge.addLine(to: CGPoint(x: rx, y: r.maxY - 2.5))
                                        ctx.stroke(ridge, with: .color(DS.secondary.opacity(0.35 + 0.6 * facing)),
                                                   lineWidth: 0.5 + 0.7 * facing)
                                    }
                                }
                                if n == 1 {
                                    grip(at: size.width / 2, gripTop)
                                    grip(at: size.width / 2, gripBottom)
                                }
                                for i in 1..<n {
                                    let x = size.width * CGFloat(i) / CGFloat(n)
                                    // inside the photo the cut is white
                                    var inside = Path()
                                    inside.move(to: CGPoint(x: x, y: top + 4))
                                    inside.addLine(to: CGPoint(x: x, y: bottom - 4))
                                    ctx.stroke(inside, with: .color(.white.opacity(0.9)),
                                               style: StrokeStyle(lineWidth: 1, dash: [6, 4]))

                                    // outside it sits on paper, so it turns ink
                                    for range in [(gripTop, top - 2), (bottom + 2, gripBottom)] {
                                        var outside = Path()
                                        outside.move(to: CGPoint(x: x, y: range.0))
                                        outside.addLine(to: CGPoint(x: x, y: range.1))
                                        ctx.stroke(outside, with: .color(DS.secondary.opacity(0.6)),
                                                   style: StrokeStyle(lineWidth: 1, dash: [4, 4]))

                                        grip(at: x, range.0 < top ? range.0 : range.1)
                                    }
                                }
                            }
                            .frame(width: w, height: h + 2 * gripBand)
                            .allowsHitTesting(false)

                            // Drag either grip to move between no cuts and 2–5 slides.
                            VStack(spacing: 0) {
                                dividerBand(w: w, n: frame.n)
                                Spacer(minLength: 0)
                                dividerBand(w: w, n: frame.n)
                            }
                            .frame(width: w, height: h + 2 * gripBand)

                            // both hints sit next to the handle they talk about
                            if !slidesHintDone {
                                hintCapsule("Drag for slides", icon: "arrow.left.and.right") {
                                    slidesHintDone = true
                                }
                                .position(x: min(max(photoLeft + w / CGFloat(frame.n == 1 ? 2 : frame.n), 80), geo.size.width - 80),
                                          y: max(24, photoTop - gripGap - 16))
                            }
                            if !shapeHintDone {
                                hintCapsule("Drag for shape", icon: "arrow.up.left.and.arrow.down.right") {
                                    shapeHintDone = true
                                }
                                .position(x: min(max(photoLeft + w - 92, 92), geo.size.width - 92),
                                          y: photoTop + h + gripGap + 16 <= geo.size.height - 46
                                            ? photoTop + h + gripGap + 16
                                            : photoTop + h - 64)
                            }
                            // one image only: that is where double-tap switches fit and crop
                            if frame.n == 1, !doubleTapHintDone {
                                hintCapsule("Double-tap: fit or crop", icon: "hand.tap") {
                                    doubleTapHintDone = true
                                }
                                .position(x: photoLeft + w / 2, y: photoTop + h / 2)
                            }

                            // and the bottom-right corner sets the shape
                            cornerHandle(frame: frame, h: h)
                                .frame(width: w, height: h, alignment: .bottomTrailing)

                            if showFitCue {
                                Text(pinchStart == nil ? "Fit · whole photo" : "Release to fit")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(DS.text)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                    .background(.regularMaterial, in: Capsule())
                                    .position(x: photoLeft + w / 2, y: photoTop + h - 32)
                                    .allowsHitTesting(false)
                                    .accessibilityHidden(true)
                            }
                        }
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
                    .contentShape(Rectangle())
                    .gesture(drag(w: w, h: h), including: isDrift ? .none : .all)
                    .simultaneousGesture(pinch, including: isDrift ? .none : .all)
                    // One image: double-tap switches between the whole photo and a crop
                    // centred where you tapped. Slides: back to filling the frame.
                    .onTapGesture(count: 2) { location in
                        guard !isDrift else { return }
                        // the ratio corner (its 64 pt square) keeps its own taps
                        let inCorner = location.x > photoLeft + w - 64 && location.x < photoLeft + w
                            && location.y > photoTop + h - 64 && location.y < photoTop + h
                        guard !inCorner else { return }
                        doubleTapHintDone = true
                        fitCueTask?.cancel()
                        showFitCue = false
                        let tap = CGPoint(x: (location.x - photoLeft) / w, y: (location.y - photoTop) / h)
                        if model.toggleFit(at: tap) {
                            announceFit(haptic: true)
                        } else {
                            UISelectionFeedbackGenerator().selectionChanged()
                        }
                    }
                    // VoiceOver gets what the gestures do: slides by swiping, the rest as actions.
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Photo preview")
                    .accessibilityValue(model.info)
                    .accessibilityHint(isDrift ? "Use the actions to play or pause."
                                               : "Swipe up or down to change the number of slides. More in the actions.")
                    .accessibilityAdjustableAction { direction in
                        guard !isDrift else { return }
                        switch direction {
                        case .increment: model.setCount(model.layout.n + 1)
                        case .decrement: model.setCount(model.layout.n - 1)
                        @unknown default: break
                        }
                    }
                    .accessibilityActions {
                        if isDrift {
                            Button(model.playing ? "Pause" : "Play") { model.togglePlay() }
                        } else {
                            if model.layout.n == 1 {
                                Button("Whole photo or crop") {
                                    if model.toggleFit(at: CGPoint(x: 0.5, y: 0.5)) { announceFit(haptic: false) }
                                }
                            }
                            Button("Change shape") { cycleShape() }
                        }
                    }
                }
            }
            .clipped()
            .padding(.bottom, bottomInset)
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
                        if model.leavesGap {
                            FillControl(model: model)
                        }
                    }
                }
            }
            .padding(.horizontal, 12).padding(.bottom, 6)

        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            .frame(height: gripBand + 8)
            .contentShape(Rectangle())
            .onTapGesture(count: 2) {}   // the grips only drag; keep double-tap off the photo
            .gesture(
                // Global space: the band moves as the slide count reshapes the photo.
                DragGesture(minimumDistance: 6, coordinateSpace: .global)
                    .onChanged { value in
                        slidesHintDone = true
                        if countStart == nil { countStart = n; dialPhaseStart = dialPhase }
                        guard let start = countStart else { return }
                        // the ridges roll with the finger, like turning a crown
                        dialPhase = (dialPhaseStart ?? 0) + value.translation.width / (gripSize.width / 2)
                        let steps = Int((value.translation.width / 46).rounded())
                        let next = min(maxSlides, max(1, start + steps))
                        if next != model.layout.n {
                            UISelectionFeedbackGenerator().selectionChanged()   // one detent per slide
                            model.setCount(next)
                        }
                    }
                    .onEnded { _ in countStart = nil; dialPhaseStart = nil }
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
                if pinchStart == nil {
                    fitCueTask?.cancel()
                    pinchStart = model.layout.zoom
                    fitHapticSent = model.isNearFit
                }
                if let z = pinchStart { model.setZoom(z * v.magnification) }
                let nearFit = model.isNearFit
                if nearFit && !fitHapticSent {
                    UISelectionFeedbackGenerator().selectionChanged()
                    fitHapticSent = true
                }
                showFitCue = nearFit
            }
            .onEnded { _ in
                let snapped = model.snapToFitIfClose()
                pinchStart = nil
                showFitCue = false
                if snapped { announceFit(haptic: false) }   // the haptic already fired on approach
            }
    }

    /// The "Fit · whole photo" cue for a second, shared by the pinch snap and double-tap.
    private func announceFit(haptic: Bool) {
        fitCueTask?.cancel()
        if haptic { UISelectionFeedbackGenerator().selectionChanged() }
        showFitCue = true
        UIAccessibility.post(notification: .announcement, argument: "Fit. Whole photo visible.")
        fitCueTask = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            showFitCue = false
        }
    }
}

struct Controls: View {
    @Bindable var model: EditorModel
    var compact = false
    var accent: Color = DS.ink
    var onExplain: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if model.geo != nil, model.mode == .drift { driftControls }

            if let s = model.status { Text(s).font(.footnote).foregroundStyle(.secondary) }
        }
    }

    // MARK: Drift

    @ViewBuilder
    private var driftControls: some View {
        // The pan always crosses the whole photo with a gentle push-in; only timing is set here.
        group {
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
                .presentationDetents([.height(230)])
                .presentationCornerRadius(22)
                .presentationDragIndicator(.visible)
        }
    }
}

private struct ControlsHeightKey: PreferenceKey {
    nonisolated(unsafe) static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

private struct FillSheet: View {
    @Bindable var model: EditorModel

    private var isCustom: Bool {
        model.look.fill == .color && !Palette.all.contains { $0.hex == model.look.colorHex.uppercased() }
    }

    var body: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: 14) {
            Text("Empty space")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(DS.secondary)

            // Every choice is a swatch: blur, black, white, the palette, then a custom colour.
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 7),
                      spacing: 14) {
                FillSwatch(name: "Blur", selected: model.look.fill == .blur) {
                    if let preview = model.preview {
                        Image(uiImage: preview).resizable().scaledToFill().blur(radius: 3)
                    } else {
                        LinearGradient(colors: [DS.secondary, DS.stroke], startPoint: .top, endPoint: .bottom)
                    }
                } action: { model.look.fill = .blur }

                FillSwatch(name: "Black", selected: model.look.fill == .black) {
                    Color.black
                } action: { model.look.fill = .black }

                FillSwatch(name: "White", selected: model.look.fill == .white) {
                    Color.white
                } action: { model.look.fill = .white }

                ForEach(Palette.all, id: \.hex) { swatch in
                    FillSwatch(name: swatch.name,
                               selected: model.look.fill == .color
                                   && model.look.colorHex.uppercased() == swatch.hex) {
                        Color(UIColor(hex: swatch.hex))
                    } action: {
                        model.look.colorHex = swatch.hex
                        model.look.fill = .color
                    }
                }

                ColorPicker("Custom", selection: Binding(
                    get: { Color(UIColor(hex: model.look.colorHex)) },
                    set: { model.look.colorHex = UIColor($0).hexString; model.look.fill = .color }))
                    .labelsHidden()
                    .padding(3)
                    .overlay { Circle().stroke(DS.ink, lineWidth: isCustom ? 2 : 0) }
            }

            if model.look.fill == .blur {
                HStack(spacing: 12) {
                    Text("Darken").font(.footnote).foregroundStyle(DS.secondary)
                    Slider(value: Binding(get: { Double(model.look.dim) }, set: { model.look.dim = CGFloat($0) }), in: 0...0.7)
                    Text("\(Int(model.look.dim * 100))%")
                        .font(.footnote).foregroundStyle(DS.secondary)
                        .frame(width: 34, alignment: .trailing)
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

/// One round choice in the fill sheet. The ring sits outside the dot, so it shows on
/// dark colours too; a hairline keeps white visible on the light sheet.
private struct FillSwatch<Content: View>: View {
    let name: String
    let selected: Bool
    @ViewBuilder let content: () -> Content
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            content()
                .frame(width: 30, height: 30)
                .clipShape(Circle())
                .overlay { Circle().strokeBorder(DS.stroke, lineWidth: 0.5) }
                .padding(3)
                .overlay { Circle().stroke(DS.ink, lineWidth: selected ? 2 : 0) }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
