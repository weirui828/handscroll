import SwiftUI

enum HelpTab: String, CaseIterable, Identifiable {
    case basics = "Basics", carousel = "Carousel", fit = "Fit", crop = "Crop", reel = "Reel", batch = "Batch", settings = "Settings"
    var id: String { rawValue }
    init(_ m: Mode) { self = HelpTab(rawValue: m.rawValue) ?? .basics }
}

private enum Block {
    case p(String), h(String), ul([String]), ol([String]), note(String), img(String)
}

struct HelpView: View {
    @State var tab: HelpTab
    @Binding var accentHex: String
    var scrollTarget: String? = nil
    @AppStorage("seamless.hint.slides") private var slidesHintDone = false
    @AppStorage("seamless.hint.shape") private var shapeHintDone = false
    @State private var hintsReset = false
    @Environment(\.dismiss) private var dismiss

    init(startTab: HelpTab, accentHex: Binding<String>, scrollTarget: String? = nil) {
        _tab = State(initialValue: startTab)
        _accentHex = accentHex
        self.scrollTarget = scrollTarget
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    Text("Chapter")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Picker("Chapter", selection: $tab) {
                        ForEach(HelpTab.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(minHeight: 44)
                }
                .padding(.horizontal)
                Divider()
                ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if tab == .settings {
                            accentSettings
                        } else {
                            ForEach(Array(blocks(tab).enumerated()), id: \.offset) { _, b in view(b) }
                        }
                        Text("Seamless works only on your device. It does not send your photos to a server.")
                            .font(.footnote).foregroundStyle(.secondary).padding(.top, 8)
                    }
                    .padding()
                    .frame(maxWidth: 700, alignment: .leading)
                    .frame(maxWidth: .infinity)
                }
                .onAppear {
                    guard let target = scrollTarget else { return }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        withAnimation { proxy.scrollTo(target, anchor: .top) }
                    }
                }
                }
            }
            .tint(Color(UIColor(hex: accentHex)))
            .navigationTitle("Help")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    private var accentSettings: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Accent").font(.headline)
            Text("Sliders, switches and selected chips use this colour. The background and the cards stay paper.")
                .font(.footnote).foregroundStyle(DS.secondary)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 12)], alignment: .leading, spacing: 12) {
                swatch("Ink", "#111317")
                ForEach(Palette.all, id: \.hex) { s in swatch(s.name, s.hex) }
            }

            ColorPicker("Custom", selection: Binding(
                get: { Color(UIColor(hex: accentHex)) },
                set: { accentHex = UIColor($0).hexString }))
                .font(.footnote)

            Divider().overlay(DS.stroke).padding(.vertical, 4)

            Text("Tutorial").font(.headline)
            Text("The gesture hints show once on a new photo. You can show them again.")
                .font(.footnote).foregroundStyle(DS.secondary)

            Button {
                slidesHintDone = false
                shapeHintDone = false
                hintsReset = true
                Task {
                    try? await Task.sleep(for: .seconds(2))
                    hintsReset = false
                }
            } label: {
                Text(hintsReset ? "Hints will show again" : "Show the hints again")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(DS.text)
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .background(DS.card, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(DS.stroke, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
    }

    private func swatch(_ name: String, _ hex: String) -> some View {
        Button { accentHex = hex } label: {
            VStack(spacing: 6) {
                PaletteDot(hex: hex, selected: accentHex.uppercased() == hex, size: 30)
                Text(name).font(.caption2).foregroundStyle(DS.secondary)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func view(_ b: Block) -> some View {
        switch b {
        case .h(let t): Text(t).font(.headline).padding(.top, 6).id(t)
        case .p(let t): Text(.init(t))
        case .note(let t): Text(.init("**NOTE:** " + t)).padding(10).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
        case .ul(let items):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, t in HStack(alignment: .firstTextBaseline) { Text("•"); Text(.init(t)) } }
            }
        case .img(let name):
            Image(name)
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(DS.stroke, lineWidth: 1))
                .padding(.vertical, 4)
        case .ol(let items):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.offset) { i, t in HStack(alignment: .firstTextBaseline) { Text("\(i + 1)."); Text(.init(t)) } }
            }
        }
    }

    private func blocks(_ tab: HelpTab) -> [Block] {
        switch tab {
        case .basics: [
            .p("Carousel, Fit and Crop all start from one photo and end in image files. This chapter covers what they share."),
            .h("Move and zoom"),
            .ul(["Drag the photo to move it.", "Pinch to zoom.", "Double-tap the photo to go back to the start."]),
            .h("Shape"),
            .p("The corner marks at the bottom right set the shape of the frame."),
            .ul(["Drag the corner down for a taller frame, or up for a wider frame.",
                 "Tap the corner to step through **Auto**, **4:5**, **3:4** and **1:1**."]),
            .p("**4:5** is the safe shape. Instagram and scheduling tools all accept it."),
            .h("The 3:4 warning"),
            .p("If the frame is taller than 4:5, a warning shows below the photo: **Too tall for scheduling tools. Post from the Instagram app.**"),
            .p("The Instagram app accepts 3:4. Tools that schedule posts stop at 4:5, so a 3:4 post cannot be scheduled."),
            .h("Empty space"),
            .p("If the photo does not fill the frame, the space around it needs a fill. Tap **Blur** below the photo and choose **Blur**, **Black**, **White** or **Color**."),
            .p("With **Blur**, the **Darken** slider makes the fill darker."),
            .h("Size and export"),
            .ul(["Tap the size line to change the output size.",
                 "Tap **Fit** to switch between showing the whole photo and filling the frame.",
                 "Tap the download icon to save to Photos, or the share icon to send to another app."]),
            .p("File names follow the photo name and the number: `DSC_0420_01.jpg`, `DSC_0420_02.jpg`."),
        ]
        case .carousel: [
            .h("What it does"),
            .p("Carousel cuts one wide photo into slides. On Instagram, people swipe through the slides and see one continuous photo."),
            .h("Add or remove slides"),
            .ol(["Find the dashed line that runs past the top and the bottom of the photo.",
                 "Drag the small handle at the end of that line to the right to add a slide.",
                 "Drag it to the left to remove a slide. You can have 2 to 5 slides."]),
            .p("The line below the photo shows the size of each slide."),
            .img("help-carousel"),
            .p("For move, zoom, shape, the fill and export, see **Basics**."),
            .p("On Instagram, post the slides as one carousel, in order."),
        ]
        case .fit: [
            .p("Fit puts the whole photo on a tall frame, so it uses more of the screen in the Instagram feed."),
            .p("Tap the corner at the bottom right to choose a shape, or drag it. Use a small zoom out for a margin on all sides."),
            .p("For move, zoom, the fill and export, see **Basics**."),
        ]
        case .crop: [
            .p("Crop makes a tall version of the photo for Instagram. You keep the full photo for your website."),
            .ol(["Tap the corner at the bottom right to choose a shape.",
                 "Drag and pinch the photo until the frame shows the part that you want."]),
            .p("For the fill and export, see **Basics**."),
        ]
        case .reel: [
            .p("Reel makes a short video that moves slowly across the photo."),
            .h("Play"),
            .p("Tap the play button in the middle of the photo. While the video plays, a thin bar at the bottom of the photo shows the position. Tap again to pause."),
            .img("help-reel"),
            .h("Pan"),
            .ul(["The two ends set where the video starts and where it ends.",
                 "The start end has a small dot. Drag an end to move it.",
                 "Drag the start end past the other end to play in the opposite direction."]),
            .h("Zoom, length and ease"),
            .ul(["**Zoom to** sets the zoom at the end of the video. The video always starts at 100%.",
                 "**Length** sets the duration, from 3 to 30 seconds.",
                 "**Ease in and out** makes the movement start and stop slowly."]),
            .h("Export"),
            .p("Tap the download icon to save the video, or the share icon to send it. The video is 1080 × 1920 px, 30 frames per second, and has no sound. Add music in Instagram."),
        ]
        case .batch: [
            .p("Batch applies the same steps to a maximum of 10 photos."),
            .h("Add a step"),
            .ol(["Open a photo in **Carousel**, **Fit**, **Crop** or **Reel**.",
                 "Set the photo as you want it.",
                 "Tap the plus icon in the bar below the photo. The icon turns grey when the current settings are already a step.",
                 "To add another step, change the settings and tap the plus icon again. You can add up to 5 steps."]),
            .h("Open Batch"),
            .p("Tap the stack icon next to the plus icon. The number on the icon is the number of steps. The photo you are editing is added to the batch automatically."),
            .h("Add photos and run"),
            .ol(["Tap **Add photos** and select up to 10 photos.",
                 "Each photo shows one result for each step.",
                 "Tap **Make files**. The card shows the approximate number of files, their size and the time."]),
            .h("Adjust one photo"),
            .ol(["Tap a result to open it for that photo and that step.",
                 "Change the photo. Tap **Apply**. The result is marked **Adjusted**."]),
            .p("To remove the change, open the result again and tap **Go back to the step's settings**."),
            .h("Save"),
            .p("Tap the download icon to save all files to Photos, or the share icon to send them. File names include the photo, the step and the slide: `DSC_0420_2-carousel_01.jpg`."),
            .p("Seamless keeps the steps on this device."),
        ]
        case .settings: []
        }
    }
}
