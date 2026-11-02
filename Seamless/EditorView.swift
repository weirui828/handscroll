import SwiftUI

/// The canvas and the controls sit in two separate panes. When the window is wide
/// (iPad, landscape, or an unfolded screen) the panes sit side by side, so a fold
/// falls between them and never across the canvas. When it is narrow they stack.
struct EditorView: View {
    @Bindable var model: EditorModel
    var batch: BatchModel?              // nil while adjusting one batch photo
    @Binding var showBatch: Bool
    @Binding var shareRequest: ShareRequest?
    @Environment(HingeState.self) private var hinge

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Seamless")
                    .font(.system(size: 17, weight: .semibold))
                    .tracking(0.3)
                    .foregroundStyle(DS.text)
                Spacer()
            }
            .padding(.horizontal, 16).padding(.top, 6).padding(.bottom, 2)

            Picker("Mode", selection: $model.mode) {
                ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(DS.bar)
            Divider().overlay(DS.stroke)

            GeometryReader { geo in
                let wide = geo.size.width >= 640 && (hinge.splitAtFold || geo.size.width > geo.size.height * 0.9)
                let controlsWidth = min(400, geo.size.width * 0.42)
                let controls = VStack(spacing: 0) {
                    ScrollView {
                        Controls(model: model).padding(12)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    Divider().overlay(DS.stroke)
                    ExportActions(model: model, batch: batch,
                                  showBatch: $showBatch, shareRequest: $shareRequest)
                }
                .background(DS.bg)

                if #available(iOS 27.1, *), hinge.splitAtFold {
                    ArrangementView {
                        CanvasView(model: model)
                    } secondary: {
                        controls
                    }
                    .arrangementViewStyle(.split)
                } else if wide {
                    HStack(spacing: 0) {
                        CanvasView(model: model)
                        Divider().overlay(DS.stroke)
                        controls.frame(width: controlsWidth)
                    }
                } else {
                    VStack(spacing: 0) {
                        CanvasView(model: model)
                            .frame(height: max(180, min(360, geo.size.height * 0.44)))
                        Divider().overlay(DS.stroke)
                        controls
                    }
                }
            }
        }
        .background(DS.bg)
        .toolbarBackground(DS.bar, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar(.visible, for: .navigationBar)
    }
}

struct CanvasView: View {
    @Bindable var model: EditorModel
    @State private var dragStart: Layout?
    @State private var pinchStart: CGFloat?

    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { geo in
                if let img = model.preview, let frame = model.currentFrame {
                    let isReel = model.mode == .reel
                    let aw = isReel ? reelSize.width : frame.fw
                    let ah = isReel ? reelSize.height : frame.fh
                    let fit = max(0.001, min(max(1, geo.size.width - 24) / aw, max(1, geo.size.height - 12) / ah))
                    let w = aw * fit, h = ah * fit
                    ZStack {
                        Image(uiImage: img).resizable().frame(width: w, height: h)
                        if isReel {
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
                        if !isReel {
                            Canvas { ctx, size in
                                for i in 1..<max(frame.n, 1) {
                                    let x = size.width * CGFloat(i) / CGFloat(frame.n)
                                    var p = Path()
                                    p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: size.height))
                                    ctx.stroke(p, with: .color(.white.opacity(0.9)), style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
                                }
                            }
                            .frame(width: w, height: h)
                            .allowsHitTesting(false)
                        }
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
                    .contentShape(Rectangle())
                    .gesture(drag(w: w, h: h), including: isReel ? .none : .all)
                    .simultaneousGesture(pinch, including: isReel ? .none : .all)
                    .onTapGesture(count: 2) { if !isReel { model.resetPosition() } }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Photo preview")
                    .accessibilityValue(model.info)
                    .accessibilityHint("Use the position controls to adjust the photo.")
                }
            }
            .clipped()
            if model.mode == .reel {
                GeometryReader { bar in
                    ZStack(alignment: .leading) {
                        Capsule().fill(DS.stroke)
                        Capsule().fill(DS.secondary)
                            .frame(width: bar.size.width * (model.reel.dur > 0 ? min(1, model.reelT / model.reel.dur) : 0))
                    }
                }
                .frame(height: 2)
                .padding(.horizontal, 24)
                .padding(.top, 6)
                .allowsHitTesting(false)
            }
            VStack(spacing: 2) {
                Text(model.sizeText).font(.footnote).foregroundStyle(DS.secondary).multilineTextAlignment(.center)
                if model.tallWarning {
                    Text("Too tall for scheduling tools. Post from the Instagram app.")
                        .font(.caption).foregroundStyle(.orange).multilineTextAlignment(.center)
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

    private var pinch: some Gesture {
        MagnifyGesture()
            .onChanged { v in
                if pinchStart == nil { pinchStart = model.layout.zoom }
                if let z = pinchStart { model.setZoom(z * v.magnification) }
            }
            .onEnded { _ in pinchStart = nil }
    }
}

struct LabeledSlider: View {
    var title: String
    @Binding var value: Double
    var range: ClosedRange<Double>
    var format: (Double) -> String
    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text(format(value)).monospacedDigit().foregroundStyle(.secondary)
            }
            Slider(value: $value, in: range)
                .accessibilityLabel(title)
                .accessibilityValue(format(value))
        }
    }
}

struct Controls: View {
    @Bindable var model: EditorModel
    @ScaledMetric(relativeTo: .body) private var slideWidth = 72.0

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let geo = model.geo {
                if model.mode == .reel { reelControls } else { imageControls(geo) }
            }

            if let s = model.status { Text(s).font(.footnote).foregroundStyle(.secondary) }
        }
    }

    // MARK: Carousel, Fit, Crop

    @ViewBuilder
    private func imageControls(_ geo: Geometry) -> some View {
        if model.mode == .carousel {
            countGrid(geo)
        } else {
            group("Shape") {
                AdaptivePicker("Shape", selection: shapeBinding) {
                    ForEach(Shape.allCases.filter { $0 != .auto }) { Text($0.rawValue).tag($0) }
                }
            }
        }

        group("Position") {
            if let f = model.currentFrame {
                HStack {
                    Text("Zoom")
                    Slider(value: Binding(get: { model.layout.zoom }, set: { model.setZoom($0) }), in: geo.zoomRange(f))
                }
            }
            Picker("Fit", selection: Binding(get: { model.showsWholePhoto },
                                            set: { whole in whole ? model.wholePhoto() : model.fillFrame() })) {
                Text("Fit").tag(true)
                Text("Fill").tag(false)
            }
            .pickerStyle(.segmented)
        }

        if model.leavesGap {
            group("Empty space") {
                AdaptivePicker("Fill", selection: $model.look.fill) {
                    ForEach(Fill.allCases) { Text($0.rawValue).tag($0) }
                }
                if model.look.fill == .blur {
                    LabeledSlider(title: "Darken", value: Binding(get: { Double(model.look.dim) }, set: { model.look.dim = CGFloat($0) }),
                                  range: 0...0.7) { "\(Int($0 * 100))%" }
                }
                if model.look.fill == .color {
                    ColorPicker("Color", selection: Binding(
                        get: { Color(UIColor(hex: model.look.colorHex)) },
                        set: { model.look.colorHex = UIColor($0).hexString }))
                }
            }

        }


    }

    private var shapeBinding: Binding<Shape> {
        Binding(get: { model.layout.shape }, set: { model.setShape($0) })
    }

    private var shapeMenu: some View {
        Menu {
            Picker("Shape", selection: shapeBinding) {
                ForEach(Shape.allCases) { Text($0.rawValue).tag($0) }
            }
        } label: {
            HStack(spacing: 4) {
                Text(model.layout.shape.rawValue).font(.footnote.weight(.medium))
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .semibold))
            }
            .foregroundStyle(DS.secondary)
            // a full 44 pt target, so it is easy to hit on purpose and never a near miss
            .frame(minWidth: 44, minHeight: 44, alignment: .trailing)
            .contentShape(Rectangle())
        }
        .accessibilityLabel("Slide shape")
        .disabled(model.busy)
    }

    private func countGrid(_ geo: Geometry) -> some View {
        let best = geo.bestN
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Slides").font(.subheadline.weight(.semibold)).foregroundStyle(DS.secondary)
                Spacer()
                shapeMenu
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: slideWidth), spacing: 8)], spacing: 8) {
                ForEach(2...maxSlides, id: \.self) { n in
                    Button { model.setCount(n) } label: {
                        VStack(spacing: 2) {
                            HStack(spacing: 3) {
                                Text("\(n)").bold()
                                if n == best && model.layout.shape == .auto { Circle().fill(DS.secondary).frame(width: 5, height: 5) }
                            }
                            Text(geo.chipText(n: n, shape: model.layout.shape)).font(.caption2)
                        }
                        .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                    .tint(model.layout.n == n ? DS.ink : .gray)
                    .accessibilityLabel("\(n) slides")
                    .accessibilityValue(geo.chipText(n: n, shape: model.layout.shape))
                    .accessibilityAddTraits(model.layout.n == n ? .isSelected : [])
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.card, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(DS.stroke, lineWidth: 1))
    }

    // MARK: Reel

    @ViewBuilder
    private var reelControls: some View {
        group("Pan") {
            LabeledSlider(title: "Start", value: $model.reel.p0, range: 0...1) { "\(Int($0 * 100))%" }
            LabeledSlider(title: "End", value: $model.reel.p1, range: 0...1) { "\(Int($0 * 100))%" }
        }
        group("Frame") {
            LabeledSlider(title: "Vertical", value: $model.reel.v, range: 0...1) {
                $0 < 0.34 ? "top" : $0 > 0.66 ? "bottom" : "middle"
            }
        }
        group("Zoom") {
            LabeledSlider(title: "Start", value: $model.reel.z0, range: 1...1.6) { "\(Int(($0 * 100).rounded()))%" }
            LabeledSlider(title: "End", value: $model.reel.z1, range: 1...1.6) { "\(Int(($0 * 100).rounded()))%" }
        }
        group("Timing") {
            LabeledSlider(title: "Length", value: Binding(get: { model.reel.dur }, set: { model.reel.dur = $0.rounded(); model.reelT = min(model.reelT, model.reel.dur) }),
                          range: 3...30) { "\(Int($0)) s" }
            Toggle("Ease in and out", isOn: $model.reel.ease)
        }
    }

    // MARK: Export and batch

    private func group<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(DS.secondary)
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.card, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(DS.stroke, lineWidth: 1))
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
        .frame(maxWidth: .infinity)
    }
}

private struct ExportActions: View {
    @Bindable var model: EditorModel
    var batch: BatchModel?
    @Binding var showBatch: Bool
    @Binding var shareRequest: ShareRequest?
    @State private var showResult = false
    @State private var note: String?
    @State private var noteTask: Task<Void, Never>?

    /// Shows the result of a batch action for a moment, then takes it away again.
    private func flash(_ text: String) {
        noteTask?.cancel()
        withAnimation(.easeOut(duration: 0.15)) { note = text }
        noteTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            withAnimation(.easeIn(duration: 0.25)) { note = nil }
        }
    }

    /// The stored value is the pixel width; the menu speaks in quality names.
    private var qualityName: String {
        switch Int(model.outW) {
        case 1440: return "High"
        case 2160: return "Maximum"
        default: return "Standard"
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            if model.busy {
                HStack(spacing: 8) {
                    ProgressView()
                    Text(model.progress ?? "Saving…").font(.footnote).foregroundStyle(DS.secondary)
                }
            }
            if let note {
                Text(note)
                    .font(.footnote).foregroundStyle(DS.secondary)
                    .transition(.opacity)
            }
            HStack(spacing: 2) {
                Menu {
                    Section("Image quality") {
                        Picker("Image quality", selection: $model.outW) {
                            Text("Standard").tag(CGFloat(1080))
                            Text("High").tag(CGFloat(1440))
                            Text("Maximum").tag(CGFloat(2160))
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(qualityName)
                            .font(.footnote.weight(.medium))
                        Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .semibold))
                    }
                    .foregroundStyle(DS.secondary)
                    .frame(height: 44)
                    .padding(.trailing, 6)
                }
                .disabled(model.busy)

                Spacer(minLength: 8)

                if let batch {
                    Button {
                        if let step = model.captureStep() { flash(batch.add(step)) }
                    } label: {
                        Label("Add to batch", systemImage: "plus.square.on.square")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(QuietBarButton())
                    .accessibilityLabel("Add to batch")
                    .disabled(model.busy || batch.steps.count >= maxSteps)
                }

                Button {
                    Task {
                        let urls = await model.exportFiles()
                        if urls.isEmpty { showResult = true }
                        else { shareRequest = ShareRequest(items: urls) }
                    }
                } label: {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(QuietBarButton())
                .accessibilityLabel("Share")

                Button { Task {
                    let urls = await model.exportFiles()
                    if !urls.isEmpty { await model.saveToPhotos(urls) }
                    showResult = true
                } } label: {
                    Label("Save", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(PrimaryButton())

            }
            .disabled(model.busy)
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(DS.bar)
        .overlay(alignment: .top) { Rectangle().fill(DS.stroke).frame(height: 1) }
        .alert("Export", isPresented: $showResult) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.status ?? "No files were saved.")
        }
    }
}
