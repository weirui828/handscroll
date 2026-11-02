import SwiftUI

/// The canvas and the controls sit in two separate panes. When the window is wide
/// (iPad, landscape, or an unfolded screen) the panes sit side by side, so a fold
/// falls between them and never across the canvas. When it is narrow they stack.
struct EditorView: View {
    @Bindable var model: EditorModel
    var batch: BatchModel?              // nil while adjusting one batch photo
    @Binding var showBatch: Bool
    @Binding var shareRequest: ShareRequest?
    var showsWordmark = true
    var accent: Color = DS.ink
    @Environment(HingeState.self) private var hinge
    @State private var controlsHeight: CGFloat = 0

    var onHelp: (() -> Void)?
    var showsExportBar = true
    var hidesNavigationBar = true

    var body: some View {
        GeometryReader { geo in
            // a wide, on-purpose window gets two panes; everything else stacks with the
            // header at the top, so the wordmark never floats in the middle of the screen
            let sideBySide = geo.size.width >= 520 && geo.size.width > geo.size.height * 1.05
            let compact = !sideBySide && geo.size.height < 620
            let controlsWidth = min(400, geo.size.width * 0.42)

            let header = VStack(spacing: 0) {
                if showsWordmark && !compact {
                    HStack(spacing: 0) {
                        Text("Seamless")
                            .font(.system(size: 17, weight: .semibold))
                            .tracking(0.3)
                            .foregroundStyle(DS.text)
                        Spacer()
                        if let onHelp {
                            Button(action: onHelp) {
                                Image(systemName: "questionmark.circle")
                            }
                            .buttonStyle(QuietBarButton())
                            .accessibilityLabel("Help")
                        }
                    }
                    .padding(.horizontal, 12).padding(.top, 4)
                }
                Picker("Mode", selection: $model.mode) {
                    ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 12).padding(.vertical, 6)
                Divider().overlay(DS.stroke)
            }
            .background(DS.bar)

            let controls = VStack(spacing: 0) {
                ScrollView {
                    Controls(model: model, compact: compact, accent: accent).padding(12)
                }
                .scrollBounceBehavior(.basedOnSize)
                if showsExportBar {
                    Divider().overlay(DS.stroke)
                    ExportActions(model: model, batch: batch,
                                  showBatch: $showBatch, shareRequest: $shareRequest)
                }
            }

            if sideBySide {
                HStack(spacing: 0) {
                    CanvasView(model: model, inset: 20)
                    Divider().overlay(DS.stroke)
                    VStack(spacing: 0) { header; controls }
                        .frame(width: controlsWidth)
                        .background(DS.bg)
                }
            } else {
                VStack(spacing: 0) {
                    header
                    // the photo sits in the middle of whatever is left above the controls
                    CanvasView(model: model)
                        .frame(maxHeight: .infinity)
                    Divider().overlay(DS.stroke)
                    ScrollView {
                        Controls(model: model, compact: compact, accent: accent)
                            .padding(12)
                            .background(GeometryReader { proxy in
                                Color.clear.preference(key: ControlsHeightKey.self, value: proxy.size.height)
                            })
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    .frame(height: min(max(controlsHeight, 0), geo.size.height * (compact ? 0.45 : 0.55)))
                    .onPreferenceChange(ControlsHeightKey.self) { controlsHeight = $0 }
                    if showsExportBar {
                        Divider().overlay(DS.stroke)
                        ExportActions(model: model, batch: batch,
                                      showBatch: $showBatch, shareRequest: $shareRequest)
                    }
                }
            }
        }
        .background(DS.bg)
        .toolbar(hidesNavigationBar ? .hidden : .visible, for: .navigationBar)
    }
}

struct CanvasView: View {
    @Bindable var model: EditorModel
    var inset: CGFloat = 0
    @AppStorage("seamless.hint.slides") private var slidesHintDone = false
    @AppStorage("seamless.hint.shape") private var shapeHintDone = false
    @State private var hintPulse = false
    @State private var dragStart: Layout?
    @State private var pinchStart: CGFloat?
    @State private var countStart: Int?
    @State private var shapeStart: CGFloat?
    @State private var showFill: Bool = {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-demoFill")
        #else
        return false
        #endif
    }()

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
                            .overlay(alignment: .bottom) {
                                if isReel && model.playing {
                                    let progress = model.reel.dur > 0 ? min(1, max(0, model.reelT / model.reel.dur)) : 0
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

                            if frame.n > 1, !slidesHintDone {
                                hintCapsule("Drag for slides", icon: "arrow.left.and.right") {
                                    slidesHintDone = true
                                }
                                .position(x: min(max(w / CGFloat(max(frame.n, 1)), 60), w - 60), y: 30)
                            }
                            if !shapeHintDone {
                                hintCapsule("Drag for shape", icon: "arrow.up.left.and.arrow.down.right") {
                                    shapeHintDone = true
                                }
                                .frame(width: w, height: h, alignment: .bottomTrailing)
                                .padding(.trailing, 52).padding(.bottom, 46)
                            }

                            // and the bottom-right corner sets the shape
                            cornerHandle(frame: frame, h: h)
                                .frame(width: w, height: h, alignment: .bottomTrailing)
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
            VStack(spacing: 2) {
                HStack(spacing: 20) {
                    if model.mode == .reel {
                        Text(model.sizeText).font(.footnote).foregroundStyle(DS.secondary)
                    } else {
                        Menu {
                            Picker("Size", selection: $model.outW) {
                                ForEach(model.sizeChoices, id: \.width) { c in
                                    Text("\(c.width) × \(c.height) px").tag(CGFloat(c.width))
                                }
                            }
                        } label: {
                            HStack(spacing: 3) {
                                Text(model.sizeText)
                                Image(systemName: "chevron.up.chevron.down").font(.system(size: 8, weight: .semibold))
                            }
                            .font(.footnote)
                            .foregroundStyle(DS.secondary)
                        }
                        .accessibilityLabel("Output size")

                        Menu {
                            Button("Fit") { model.wholePhoto() }
                            Button("Fill") { model.fillFrame() }
                        } label: {
                            HStack(spacing: 3) {
                                Text(model.showsWholePhoto ? "Fit" : "Fill")
                                Image(systemName: "chevron.up.chevron.down").font(.system(size: 8, weight: .semibold))
                            }
                            .font(.footnote)
                            .foregroundStyle(DS.secondary)
                            .frame(minHeight: 44)
                        }
                        .accessibilityLabel("Frame")

                        if model.leavesGap {
                            Button { showFill = true } label: {
                                HStack(spacing: 3) {
                                    Text(model.look.fill.rawValue)
                                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 8, weight: .semibold))
                                }
                                .font(.footnote)
                                .foregroundStyle(DS.secondary)
                                .frame(minHeight: 44)
                            }
                            .accessibilityLabel("Fill")
                        }
                    }
                }
                if model.tallWarning {
                    Text("Too tall for scheduling tools. Post from the Instagram app.")
                        .font(.caption).foregroundStyle(.orange).multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 12).padding(.bottom, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(inset)
        .background(DS.bg)
        .clipped()
        .sheet(isPresented: $showFill) {
            FillSheet(model: model)
                .presentationDetents([.height(190)])
                .presentationCornerRadius(22)
                .presentationDragIndicator(.visible)
        }
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
        let order: [Shape] = model.mode == .carousel ? [.auto, .r45, .r34, .r11] : [.r45, .r34, .r11]
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
    var compact = false
    var accent: Color = DS.ink
    @ScaledMetric(relativeTo: .body) private var slideWidth = 72.0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let geo = model.geo {
                if model.mode == .reel { reelControls }
            }

            if let s = model.status { Text(s).font(.footnote).foregroundStyle(.secondary) }
        }
    }

    // MARK: Reel

    @ViewBuilder
    private var reelControls: some View {
        group {
            HStack(spacing: 10) {
                rowLabel("Pan").frame(width: 58, alignment: .leading)
                RangeSlider(lower: $model.reel.p0, upper: $model.reel.p1, accent: accent)
                    .frame(height: 34)
            }

            inlineSlider("Zoom to", value: Binding(get: { model.reel.z1 },
                                                  set: { model.reel.z1 = $0; model.reel.z0 = 1 }),
                         range: 1...1.6,
                         text: "\(Int((model.reel.z1 * 100).rounded()))%")

            inlineSlider("Length", value: Binding(get: { model.reel.dur },
                                                 set: { model.reel.dur = $0.rounded(); model.reelT = min(model.reelT, model.reel.dur) }),
                         range: 3...30,
                         text: "\(Int(model.reel.dur)) s")

            Toggle("Ease in and out", isOn: $model.reel.ease)
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

    private func group<Content: View>(_ title: String, trailing: AnyView? = nil,
                                     @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: compact ? 6 : 8) {
            if !compact {
                HStack {
                    Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(DS.secondary)
                    Spacer()
                    trailing
                }
            } else if trailing != nil {
                HStack { Spacer(); trailing }
            }
            content()
        }
        .padding(compact ? 10 : 14)
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

private struct ControlsHeightKey: PreferenceKey {
    nonisolated(unsafe) static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// Two knobs on one track: the start and the end of the reel pan.
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
                            Circle()
                                .fill(Color(UIColor(hex: swatch.hex)))
                                .frame(width: 28, height: 28)
                                .overlay {
                                    Circle().strokeBorder(DS.ink,
                                                          lineWidth: model.look.colorHex.uppercased() == swatch.hex ? 2 : 0)
                                }
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

private struct ExportActions: View {
    @Bindable var model: EditorModel
    var batch: BatchModel?
    @Binding var showBatch: Bool
    @Binding var shareRequest: ShareRequest?
    @State private var showResult = false
    @State private var note: String?
    @State private var noteTask: Task<Void, Never>?
    @State private var flying = false
    @State private var flyFilled = false
    @State private var flyX: CGFloat = -154
    @State private var flyScale: CGFloat = 1
    @State private var flyAlpha: CGFloat = 1
    @State private var badgeBump = false

    private var currentStep: Step? { model.captureStep() }

    /// Adds the current settings, then lets a little count travel from the plus to the
    /// batch icon so the two controls read as one thing.
    private func addToBatch(added: Bool) {
        guard let batch, !added, let step = currentStep else { return }
        let text = batch.add(step)
        flash(text)
        // the plus sits one slot left of the batch icon; the step slides across and fills in
        flying = true
        flyFilled = false
        flyX = -154
        flyScale = 1
        flyAlpha = 1
        withAnimation(.easeInOut(duration: 0.36)) {
            flyX = -110
            flyScale = 0.9
        }
        Task {
            try? await Task.sleep(for: .seconds(0.37))
            withAnimation(.spring(response: 0.22, dampingFraction: 0.55)) {
                flyFilled = true
                flyScale = 1.12
            }
            badgeBump = true
            try? await Task.sleep(for: .seconds(0.22))
            withAnimation(.easeIn(duration: 0.12)) { flyAlpha = 0; flyScale = 0.7 }
            try? await Task.sleep(for: .seconds(0.14))
            flying = false
            flyFilled = false
            flyX = -154
            badgeBump = false
        }
    }

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

    var body: some View {
        VStack(spacing: 4) {
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

            HStack(spacing: 0) {
                Spacer(minLength: 0)

                if let batch {
                    let added = currentStep.map { step in batch.steps.contains { $0.sameAs(step) } } ?? false
                    Button {
                        addToBatch(added: added)
                    } label: {
                        Image(systemName: "plus.circle")
                    }
                    .buttonStyle(QuietBarButton())
                    .accessibilityLabel("Add to batch")
                    .opacity(added || model.busy || batch.steps.count >= maxSteps ? 0.35 : 1)
                    .disabled(added || model.busy || batch.steps.count >= maxSteps)

                    Button { showBatch = true } label: {
                        Image(systemName: "rectangle.stack")
                            .overlay(alignment: .topTrailing) {
                                if !batch.steps.isEmpty {
                                    Text("\(batch.steps.count)")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(DS.onInk)
                                        .frame(minWidth: 15, minHeight: 15)
                                        .background(DS.ink, in: Circle())
                                        .offset(x: 4, y: -2)
                                        .scaleEffect(badgeBump ? 1.35 : 1)
                                        .animation(.spring(response: 0.25, dampingFraction: 0.5), value: badgeBump)
                                }
                            }
                    }
                    .buttonStyle(QuietBarButton())
                    .accessibilityLabel("Batch")
                    .accessibilityValue("\(batch.steps.count) steps")
                }

                Button {
                    Task {
                        let urls = await model.exportFiles()
                        if urls.isEmpty { showResult = true }
                        else { shareRequest = ShareRequest(items: urls) }
                    }
                } label: {
                    Label("Share", systemImage: "square.and.arrow.up").labelStyle(.iconOnly)
                }
                .buttonStyle(QuietBarButton())
                .accessibilityLabel("Share")

                Button { Task {
                    let urls = await model.exportFiles()
                    if !urls.isEmpty { await model.saveToPhotos(urls) }
                    showResult = true
                } } label: {
                    Label("Save", systemImage: "square.and.arrow.down").labelStyle(.iconOnly)
                }
                .buttonStyle(QuietBarButton())
                .accessibilityLabel("Save")
            }
            .overlay(alignment: .trailing) {
                if flying {
                    // an empty slide leaves the plus and lands as a filled one: the step is stored
                    RoundedRectangle(cornerRadius: 3)
                        .fill(flyFilled ? DS.ink : Color.clear)
                        .frame(width: 9, height: 13)
                        .overlay(RoundedRectangle(cornerRadius: 3).stroke(DS.ink, lineWidth: 1.2))
                        .scaleEffect(flyScale)
                        .opacity(flyAlpha)
                        .offset(x: flyX, y: -14)
                        .allowsHitTesting(false)
                }
            }

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
