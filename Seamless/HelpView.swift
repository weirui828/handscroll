import SwiftUI

enum HelpTab: String, CaseIterable, Identifiable {
    case carousel = "Carousel", fit = "Fit", crop = "Crop", reel = "Reel", batch = "Batch", settings = "Accent"
    var id: String { rawValue }
    init(_ m: Mode) { self = HelpTab(rawValue: m.rawValue) ?? .carousel }
}

private enum Block {
    case p(String), h(String), ul([String]), ol([String]), note(String)
}

struct HelpView: View {
    @State var tab: HelpTab
    @Binding var accentHex: String
    @Environment(\.dismiss) private var dismiss

    init(startTab: HelpTab, accentHex: Binding<String>) {
        _tab = State(initialValue: startTab)
        _accentHex = accentHex
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
        }
    }

    private func swatch(_ name: String, _ hex: String) -> some View {
        Button { accentHex = hex } label: {
            VStack(spacing: 6) {
                Circle()
                    .fill(Color(UIColor(hex: hex)))
                    .frame(width: 30, height: 30)
                    .overlay {
                        Circle().strokeBorder(DS.ink, lineWidth: accentHex.uppercased() == hex ? 2 : 0)
                    }
                Text(name).font(.caption2).foregroundStyle(DS.secondary)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func view(_ b: Block) -> some View {
        switch b {
        case .h(let t): Text(t).font(.headline).padding(.top, 6)
        case .p(let t): Text(.init(t))
        case .note(let t): Text(.init("**NOTE:** " + t)).padding(10).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
        case .ul(let items):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, t in HStack(alignment: .firstTextBaseline) { Text("•"); Text(.init(t)) } }
            }
        case .ol(let items):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.offset) { i, t in HStack(alignment: .firstTextBaseline) { Text("\(i + 1)."); Text(.init(t)) } }
            }
        }
    }

    private func blocks(_ tab: HelpTab) -> [Block] {
        switch tab {
        case .carousel: [
            .h("What it does"),
            .p("Carousel cuts one wide photo into slides. On Instagram, people swipe through the slides and see one continuous photo."),
            .h("Add or remove slides"),
            .ol(["Find the dashed line that runs past the top and the bottom of the photo.",
                 "Drag the small handle at the end of that line to the right to add a slide.",
                 "Drag it to the left to remove a slide. You can have 2 to 5 slides."]),
            .p("The line below the photo shows the number of slides and the size of each slide."),
            .h("Change the shape"),
            .ol(["Find the corner marks at the bottom right of the photo.",
                 "Drag the corner down for a taller slide, or up for a wider slide.",
                 "Tap the corner to step through **Auto**, **4:5**, **3:4** and **1:1**."]),
            .p("**Auto** keeps all of the photo. **4:5** is the safe shape for scheduling tools."),
            .note("**3:4** works only when you post from the Instagram app. Scheduling tools accept up to 4:5."),
            .h("Move and zoom"),
            .ul(["Drag the photo to move it.", "Pinch to zoom.", "Double-tap the photo to go back to the start."]),
            .h("Empty space"),
            .p("If the photo does not fill the frame, the space around it needs a fill. Tap **Blur** below the photo, then choose **Blur**, **Black**, **White** or **Color**."),
            .p("With **Blur**, the **Darken** slider makes the fill darker."),
            .h("Size and export"),
            .ul(["Tap the size line to change the output size.",
                 "Tap **Fit** to show the whole photo, or **Fill** to fill the frame.",
                 "Tap the download icon to save the slides to Photos, or the share icon to send them to another app."]),
            .p("File names follow the photo and the slide number: `DSC_0420_01.jpg`, `DSC_0420_02.jpg`."),
            .p("On Instagram, post the slides as one carousel, in order."),
        ]
        case .fit: [
            .p("Fit puts the whole photo on a tall frame, so it uses more of the screen in the Instagram feed."),
            .h("Shape"),
            .p("Tap the corner at the bottom right to step through **4:5**, **3:4** and **1:1**. Drag the corner to change the shape continuously."),
            .note("**4:5** is safe for scheduling tools. **3:4** works only in the Instagram app."),
            .h("Move and zoom"),
            .p("Drag the photo to move it. Pinch to zoom. Double-tap to go back to the start. For a margin on all sides, zoom out a small amount."),
            .h("Fill"),
            .p("Tap **Blur** below the photo to choose how the space around the photo is filled."),
            .h("Export"),
            .p("Tap the download icon to save the image to Photos, or the share icon to send it to another app."),
        ]
        case .crop: [
            .p("Crop makes a tall version of the photo for Instagram. You keep the full photo for your website."),
            .ol(["Tap the corner at the bottom right to choose a shape.",
                 "Drag and pinch the photo until the frame shows the part that you want.",
                 "Tap the download icon to save, or the share icon to send."]),
        ]
        case .reel: [
            .p("Reel makes a short video that moves slowly across the photo."),
            .h("Play"),
            .p("Tap the play button in the middle of the photo. While the video plays, a thin bar at the bottom of the photo shows the position. Tap again to pause."),
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
