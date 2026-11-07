import SwiftUI

/// One chapter of Help, listed in this order on the home screen.
enum HelpTopic: String, CaseIterable, Identifiable {
    case basics = "Basics"
    case photo = "Photo"
    case drift = "Video"
    case batch = "Batch"
    case settings = "Settings"

    var id: String { rawValue }
    var title: String { rawValue }

    var summary: String {
        switch self {
        case .basics: "Move, zoom, shape, fill and export"
        case .photo: "One image or up to five slides"
        case .drift: "A slow pan as a short video"
        case .batch: "The same steps on up to 10 photos"
        case .settings: "Accent colour and gesture hints"
        }
    }

    var symbol: String {
        switch self {
        case .basics: "hand.draw"
        case .photo: "rectangle.split.3x1"
        case .drift: "play.rectangle"
        case .batch: "rectangle.stack"
        case .settings: "slider.horizontal.3"
        }
    }

    /// The editor mode a chapter is about, when it has one.
    var mode: Mode? {
        switch self {
        case .photo: .split
        case .drift: .drift
        default: nil
        }
    }
}

/// The manual: an index of topics that pushes into a chapter.
struct HelpView: View {
    let open: HelpTopic?
    let anchor: String?
    @Binding var accentHex: String
    let onOpenMode: (Mode) -> Void
    let onOpenBatch: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var topic: HelpTopic?

    init(open: HelpTopic? = nil,
         anchor: String? = nil,
         accentHex: Binding<String>,
         onOpenMode: @escaping (Mode) -> Void,
         onOpenBatch: @escaping () -> Void) {
        self.open = open
        self.anchor = anchor
        _accentHex = accentHex
        self.onOpenMode = onOpenMode
        self.onOpenBatch = onOpenBatch
        _topic = State(initialValue: open)
    }

    var body: some View {
        VStack(spacing: 0) {
                bar
                if let topic {
                    HelpChapterView(topic: topic, anchor: anchor,
                                    accentHex: $accentHex,
                                    onOpenMode: onOpenMode,
                                    onOpenBatch: onOpenBatch)
                } else {
                    HelpHome(onSelect: { picked in
                        withAnimation(.easeOut(duration: 0.18)) { self.topic = picked }
                    })
                }
            }
            .background(DS.bg)
        .tint(Color(UIColor(hex: accentHex)))
    }

    private var bar: some View {
        HStack(spacing: 8) {
            if topic != nil {
                Button { withAnimation(.easeOut(duration: 0.18)) { topic = nil } } label: {
                    Label("All topics", systemImage: "chevron.left")
                        .font(.subheadline)
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("All topics")
            } else {
                Text("Help").font(.headline)
            }
            Spacer()
            Button("Done") { dismiss() }
                .font(.subheadline.weight(.semibold))
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
        .background(DS.bar)
        .overlay(alignment: .bottom) { Rectangle().fill(DS.stroke).frame(height: 1) }
    }
}

// MARK: - Home

private struct HelpHome: View {
    let onSelect: (HelpTopic) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(HelpTopic.allCases) { topic in
                    Button { onSelect(topic) } label: { row(topic) }
                        .buttonStyle(.plain)
                }
            }
            .padding(16)
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    private func row(_ topic: HelpTopic) -> some View {
        HStack(spacing: 12) {
            Image(systemName: topic.symbol)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(DS.text)
                .frame(width: 32, height: 32)
                .background(DS.stroke.opacity(0.55), in: RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 2) {
                Text(topic.title).font(.body.weight(.semibold)).foregroundStyle(DS.text)
                Text(topic.summary).font(.footnote).foregroundStyle(DS.secondary)
            }
            Spacer(minLength: 6)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(DS.secondary)
        }
        .padding(14)
        .background(DS.card, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(DS.stroke, lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - Chapter

private struct HelpChapterView: View {
    let topic: HelpTopic
    let anchor: String?
    @Binding var accentHex: String
    let onOpenMode: (Mode) -> Void
    let onOpenBatch: () -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text(topic.title).font(.title2.weight(.semibold))
                    if topic == .settings {
                        HelpSettings(accentHex: $accentHex)
                    } else {
                        content
                        openButton
                    }
                }
                .padding(20)
                .frame(maxWidth: 640, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .onAppear {
                guard let anchor else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    withAnimation { proxy.scrollTo(anchor, anchor: .top) }
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch topic {
        case .basics: basics
        case .photo: photo
        case .drift: drift
        case .batch: batch
        case .settings: EmptyView()
        }
    }

    private var basics: some View {
        VStack(alignment: .leading, spacing: 20) {
            paragraph("Photo makes one image or a set of slides. Video makes a slow pan across the photo.")

            section("Move and zoom") {
                bullets(["Drag the photo to move it.",
                         "Pinch to zoom.",
                         "Double-tap to switch between the whole photo and a crop around the spot you tap. With slides, double-tap fills the frame again."])
            }

            section("Shape") {
                HelpDiagram(kind: .corner)
                paragraph("The bottom-right corner sets the shape. Drag it up or down; tap it to step through **Auto**, **4:5**, **3:4** and **1:1**.")
                paragraph("**4:5** is the safe ratio. Most apps and scheduling tools accept it.")
            }

            section("The 4:5 warning", anchor: "4-5-warning") {
                paragraph("A frame taller than **4:5** shows a warning under the photo. Some apps accept 3:4, but scheduling tools stop at 4:5, so a 3:4 post cannot be scheduled.")
            }

            section("Empty space") {
                paragraph("If the photo does not fill the frame, tap **Blur** under the photo and pick a swatch: blur, black, white, a colour, or your own.")
                paragraph("With **Blur**, the **Darken** slider makes the fill darker.")
            }

            section("Size and export") {
                bullets(["Tap the size line to change the output size.",
                         "Save with the download icon; share with the share icon."])
                paragraph("Exported files are named photo_01.jpg, photo_02.jpg…")
            }
        }
    }

    private var photo: some View {
        VStack(alignment: .leading, spacing: 20) {
            paragraph("Choose 1–5 slides. One slide makes a single image; two to five make a set that lines up across a post.")
            HelpDiagram(kind: .slides)
            section("Choose the number of slides") {
                steps(["Turn either dial right to add slides, or left to remove them.",
                       "At one slide, the dials stay centered and the dashed line disappears.",
                       "One slide starts with the whole photo on a blur. Double-tap to switch between the whole photo and a crop around the spot you tap, or spread two fingers to crop."])
                paragraph("The line under the photo shows the size of each slide.")
            }
            section("Frame the image") {
                paragraph("Tap or drag the bottom-right corner to choose a shape. Drag the photo to move it. If zooming out leaves empty space, choose Blur, Black, White or Color for the background.")
                paragraph("When a pinch gets close to showing the whole photo, the Fit cue appears. Release to snap the photo into place.")
            }
        }
    }

    private var drift: some View {
        VStack(alignment: .leading, spacing: 20) {
            paragraph("Video makes a short clip that moves slowly across the photo.")
            HelpDiagram(kind: .pan)
            section("Play") {
                paragraph("Tap the play button in the middle of the photo. A thin bar at the bottom shows the position; tap again to pause.")
            }
            section("Length and ease") {
                bullets(["The video moves across the whole photo, left to right, with a gentle zoom in.",
                         "**Length** sets 3 to 30 seconds.",
                         "**Ease in and out** makes the movement start and stop slowly."])
            }
            section("Export") {
                paragraph("The video is 1080 × 1920 px, 30 frames per second, and has no sound. Add music in the app you post from.")
            }
        }
    }

    private var batch: some View {
        VStack(alignment: .leading, spacing: 20) {
            paragraph("Batch applies the same steps to up to 10 photos.")
            HelpDiagram(kind: .batch)
            section("Add a step") {
                steps(["Open a photo in Photo or Video and set it up.",
                       "Tap the plus icon in the bar below the photo.",
                       "Change the settings and tap plus again. Up to 5 steps."])
            }
            section("Open Batch") {
                paragraph("Tap the stack icon. The number on it is the number of steps. The photo you are editing joins the batch automatically.")
            }
            section("Run") {
                steps(["Tap **Add photos** and pick up to 10 photos.",
                       "Each photo shows one result for each step.",
                       "Tap **Run**."])
            }
            section("Adjust one photo") {
                steps(["Tap a result.",
                       "Change it and tap **Apply**. It is marked **Adjusted**.",
                       "To undo, open it again and choose **Go back to the step's settings**."])
            }
            section("Save") {
                paragraph("Download or share all files. Names include the photo, the step and the slide.")
            }
        }
    }

    @ViewBuilder
    private var openButton: some View {
        if let mode = topic.mode {
            Button { onOpenMode(mode) } label: {
                HStack(spacing: 8) {
                    Text("Open \(topic.title)")
                    Image(systemName: "arrow.up.right")
                }
                .font(.body.weight(.semibold))
                .foregroundStyle(DS.onInk)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(DS.ink, in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
        } else if topic == .batch {
            Button { onOpenBatch() } label: {
                HStack(spacing: 8) {
                    Text("Open Batch")
                    Image(systemName: "arrow.up.right")
                }
                .font(.body.weight(.semibold))
                .foregroundStyle(DS.onInk)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(DS.ink, in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
        }
    }

    private func paragraph(_ text: String) -> some View {
        Text(.init(text))
            .font(.body)
            .foregroundStyle(DS.text)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func section<Content: View>(_ title: String,
                                        anchor id: String? = nil,
                                        @ViewBuilder _ body: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundStyle(DS.text)
                .id(id ?? title)
            body()
        }
    }

    private func bullets(_ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("•").foregroundStyle(DS.secondary)
                    Text(.init(item)).foregroundStyle(DS.text)
                }
            }
        }
    }

    private func steps(_ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("\(index + 1)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(DS.text)
                        .frame(width: 20, height: 20)
                        .background(DS.stroke.opacity(0.55), in: Circle())
                    Text(.init(item)).foregroundStyle(DS.text)
                }
            }
        }
    }
}

// MARK: - Settings

private struct HelpSettings: View {
    @Binding var accentHex: String
    @AppStorage("seamless.hint.slides") private var slidesHintDone = false
    @AppStorage("seamless.hint.shape") private var shapeHintDone = false
    @AppStorage("seamless.hint.doubletap") private var doubleTapHintDone = false
    @State private var hintsReset = false

    private var swatches: [Palette.Swatch] {
        [Palette.Swatch(name: "Ink", hex: "#111317")] + Palette.all
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Accent").font(.headline)
            Text("Sliders, switches and the selected chip use this colour. The background and the cards stay paper.")
                .font(.footnote)
                .foregroundStyle(DS.secondary)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 14) {
                ForEach(swatches, id: \.hex) { swatch in
                    Button { accentHex = swatch.hex } label: {
                        VStack(spacing: 6) {
                            PaletteDot(hex: swatch.hex,
                                       selected: accentHex.uppercased() == swatch.hex.uppercased(),
                                       size: 30)
                            Text(swatch.name).font(.caption2).foregroundStyle(DS.secondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(swatch.name)
                }

                // The custom picker is the twelfth cell: three rows of four.
                VStack(spacing: 6) {
                    ColorPicker("Custom colour", selection: Binding(
                        get: { Color(UIColor(hex: accentHex)) },
                        set: { accentHex = UIColor($0).hexString }),
                        supportsOpacity: false)
                        .labelsHidden()
                        .frame(width: 30, height: 30)
                    Text("Custom").font(.caption2).foregroundStyle(DS.secondary)
                }
                .frame(maxWidth: .infinity)
                .accessibilityLabel("Custom colour")
            }

            Divider().overlay(DS.stroke)

            Text("Tutorial").font(.headline)
            Text("The gesture hints show once on a new photo. You can show them again.")
                .font(.footnote)
                .foregroundStyle(DS.secondary)

            Button {
                slidesHintDone = false
                shapeHintDone = false
                doubleTapHintDone = false
                hintsReset = true
                Task {
                    try? await Task.sleep(for: .seconds(2))
                    hintsReset = false
                }
            } label: {
                Text(hintsReset ? "Hints will show again" : "Show the hints again")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(DS.text)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(DS.card, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(DS.stroke, lineWidth: 1))
            }
            .buttonStyle(.plain)

            Divider().overlay(DS.stroke)

            Text("About").font(.headline)
            Text("Handscroll 1.0")
                .font(.footnote)
                .foregroundStyle(DS.secondary)
        }
    }
}

// MARK: - Diagrams

/// A small copy of the editor's slide dial for the diagrams: shaded body, vertical ridges.
private struct HelpDial: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 2.5)
                .fill(LinearGradient(colors: [DS.secondary.opacity(0.75), DS.secondary.opacity(0.35),
                                              DS.secondary.opacity(0.75)],
                                     startPoint: .leading, endPoint: .trailing))
            RoundedRectangle(cornerRadius: 2.5).stroke(DS.secondary.opacity(0.8), lineWidth: 0.5)
            HStack(spacing: 2.2) {
                ForEach(0..<6, id: \.self) { _ in
                    Rectangle().fill(DS.secondary).frame(width: 0.8, height: 4)
                }
            }
        }
        .frame(width: 22, height: 8)
    }
}

private struct HelpDiagram: View {
    enum Kind { case slides, corner, pan, batch }
    let kind: Kind

    private var photo: LinearGradient {
        LinearGradient(colors: [Color(UIColor(hex: "#8E9BB2")), Color(UIColor(hex: "#D9C9AF"))],
                       startPoint: .top, endPoint: .bottom)
    }

    var body: some View {
        switch kind {
        case .slides: slides
        case .corner: corner
        case .pan: pan
        case .batch: batch
        }
    }

    private var slides: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(photo)
                ForEach([1, 2], id: \.self) { i in
                    Path { path in
                        let x = w * CGFloat(i) / 3
                        path.move(to: CGPoint(x: x, y: 10))
                        path.addLine(to: CGPoint(x: x, y: h - 10))
                    }
                    .stroke(.white.opacity(0.9), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    ForEach([CGFloat(7), h - 7], id: \.self) { y in
                        HelpDial().position(x: w * CGFloat(i) / 3, y: y)
                    }
                }
            }
        }
        .frame(height: 112)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(DS.stroke, lineWidth: 1))
    }

    private var corner: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(photo)
                Path { path in
                    path.move(to: CGPoint(x: w - 34, y: h - 8))
                    path.addLine(to: CGPoint(x: w - 8, y: h - 8))
                    path.addLine(to: CGPoint(x: w - 8, y: h - 34))
                }
                .stroke(.white.opacity(0.95), style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                Text("Auto")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.95))
                    .position(x: w - 30, y: h - 26)
                VStack(spacing: 2) {
                    Image(systemName: "arrow.up")
                    Image(systemName: "arrow.down")
                }
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white.opacity(0.9))
                .position(x: w - 56, y: h - 26)
            }
        }
        .frame(height: 130)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(DS.stroke, lineWidth: 1))
    }

    private var pan: some View {
        VStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 10).fill(photo)
                .frame(height: 76)
                .overlay {
                    HStack {
                        Image(systemName: "arrow.left")
                        Spacer()
                        Image(systemName: "arrow.right")
                    }
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(.horizontal, 16)
                }
            HStack(spacing: 0) {
                Circle().fill(DS.card).frame(width: 16, height: 16)
                    .overlay(Circle().stroke(DS.stroke, lineWidth: 1))
                    .overlay(Circle().fill(DS.ink).frame(width: 4, height: 4))
                Rectangle().fill(DS.ink.opacity(0.8)).frame(height: 2)
                Circle().fill(DS.card).frame(width: 16, height: 16)
                    .overlay(Circle().stroke(DS.stroke, lineWidth: 1))
            }
        }
    }

    private var batch: some View {
        HStack(spacing: 10) {
            ForEach(0..<3, id: \.self) { index in
                RoundedRectangle(cornerRadius: 6).fill(photo)
                    .frame(height: 60)
                    .overlay(alignment: .bottomTrailing) {
                        Text("\(index + 1)")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(DS.text)
                            .frame(width: 18, height: 18)
                            .background(DS.card, in: Circle())
                            .padding(6)
                    }
            }
        }
    }

}
