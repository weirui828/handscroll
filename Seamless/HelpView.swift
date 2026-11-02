import SwiftUI

enum HelpTab: String, CaseIterable, Identifiable {
    case carousel = "Carousel", fit = "Fit", crop = "Crop", reel = "Reel", batch = "Batch"
    var id: String { rawValue }
    init(_ m: Mode) { self = HelpTab(rawValue: m.rawValue) ?? .carousel }
}

private enum Block {
    case p(String), h(String), ul([String]), ol([String]), note(String)
}

struct HelpView: View {
    @State var tab: HelpTab
    @Environment(\.dismiss) private var dismiss

    init(startTab: HelpTab) {
        _tab = State(initialValue: startTab)
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
                        ForEach(Array(blocks(tab).enumerated()), id: \.offset) { _, b in view(b) }
                        Text("Seamless works only on your device. It does not send your photos to a server.")
                            .font(.footnote).foregroundStyle(.secondary).padding(.top, 8)
                    }
                    .padding()
                    .frame(maxWidth: 700, alignment: .leading)
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("Help")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .tint(DS.ink)
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
            .p("Use Carousel to cut a wide photo into slides. On Instagram, people swipe through the slides and see one continuous photo."),
            .h("Slides"),
            .p("Select the number of slides. The text below each number gives this data:"),
            .ul(["With the **Auto** shape, the text shows the shape of each slide, for example `4:5` or `0.89:1`.",
                 "If the text shows a percentage, the photo is too wide for that number of slides. The percentage shows how much of the photo stays.",
                 "With a fixed shape, the text shows the percentage of the photo that the slides show.",
                 "The dot shows the largest number of slides that keeps all of the photo."]),
            .h("Slide shape"),
            .p("Choose the shape from the menu at the right of **Slides**."),
            .p("**Auto** keeps all of the photo. It selects a shape between 1.91:1 (wide) and 3:4 (tall)."),
            .p("**4:5**, **3:4** and **1:1** fill each slide fully. Seamless removes the parts of the photo that are outside the slides."),
            .note("Instagram accepts slides up to 3:4 only when you post from the Instagram app. Tools that schedule posts accept slides up to 4:5. If the slides are taller than 4:5, a warning shows below the photo."),
            .h("Position"),
            .ul(["To move the photo, drag it.", "To zoom, pinch or use the **Zoom** slider.",
                 "To go back to the initial position, double-tap the photo.",
                 "To show all of the photo, choose **Fit**.",
                 "To fill the frame with no gaps, choose **Fill**.",
                 "To put the photo back in the center, double-tap the photo."]),
            .h("Empty space"),
            .p("If the photo does not fill the frame, Seamless fills the empty space. Select **Blur** (a blurred copy of the photo), **Black**, **White** or **Color**."),
            .p("With **Blur**, use **Darken** to make the fill darker."),
            .h("Export"),
            .p("The images are 1080 px wide unless you change the width in the bar below the controls. Instagram keeps images at this width."),
            .p("Each file has the name of your photo and the slide number, for example `DSC_0420_01.jpg` and `DSC_0420_02.jpg`."),
            .ol(["Tap **Save** to put the images in Photos. To use another app, tap **Share**.",
                 "On Instagram, post the slides as one carousel, in the sequence of their numbers."]),
        ]
        case .fit: [
            .p("Use Fit to put all of the photo on a tall frame. The photo then uses more of the screen in the Instagram feed."),
            .h("Shape"),
            .ul(["**4:5**: All tools accept this shape.", "**3:4**: The tallest shape. Use it only when you post from the Instagram app.", "**1:1**: A square."]),
            .h("Border"),
            .p("Seamless fills the space around the photo. Select **Blur**, **Black**, **White** or **Color**."),
            .p("To get a margin on all sides, decrease the zoom a small amount."),
            .h("Export"),
            .p("Tap **Save** or **Share**. Seamless makes one image, for example `DSC_0420_01.jpg`."),
        ]
        case .crop: [
            .p("Use Crop to make a tall version of the photo for Instagram. Keep the full photo for your website."),
            .ol(["Select a shape.", "Drag and zoom the photo until the frame shows the part that you want.", "Tap **Save** or **Share**."]),
            .p("The text below the photo shows the percentage of the photo that the crop keeps."),
        ]
        case .reel: [
            .p("Use Reel to make a video that moves slowly across the photo. Instagram usually shows Reels to more people than other posts."),
            .h("Pan"),
            .p("**Start** and **End** set the position at the start and at the end of the video. 0% is the left edge of the photo. 100% is the right edge."),
            .ul(["To move in the opposite direction, set **Start** to a value that is larger than **End**.",
                 "If the photo is tall, use **Up/down** to select the part of the photo that the video shows."]),
            .h("Zoom and timing"),
            .ul(["Zoom **Start** and **End** set the zoom at the start and at the end of the video. Use different values to move slowly in or out.",
                 "**Length** sets the duration of the video, from 3 to 30 seconds.",
                 "**Ease in and out** makes the movement start and stop slowly.",
                 "To examine the video, tap **Play** or move the slider."]),
            .h("Export"),
            .p("Tap **Save** or **Share**. Seamless makes an MP4 video, 1080 × 1920 px, at 30 frames per second. The file name is, for example, `DSC_0420_reel.mp4`."),
            .note("The video has no sound. When you post on Instagram, add music or your voice."),
        ]
        case .batch: [
            .p("Use Batch to apply the same settings to a maximum of 10 photos."),
            .h("1. Add steps"),
            .ol(["Open a photo in **Carousel**, **Fit**, **Crop** or **Reel**.", "Set the controls as you want them.",
                 "Tap **Add to batch**. Seamless keeps the current settings as one step.",
                 "To add more steps, change the settings and tap **Add to batch** again. You can add a maximum of 5 steps."]),
            .p("Example: a carousel, a 4:5 fit with a blurred border and a 10-second Reel."),
            .p("The steps show on the **Batch** screen. Seamless keeps the steps on this device."),
            .ul(["To apply the settings of a step to your photo, tap the step.", "To remove a step, tap the **x**."]),
            .h("How the settings apply to other photos"),
            .ul(["Seamless applies zoom and position in proportion to each photo. For example, if you zoom in and move one photo up, all photos get the same change.",
                 "If a carousel step uses the **Auto** shape, Seamless selects the best number of slides for each photo.",
                 "If you selected a number of slides, all photos get that number of slides."]),
            .h("2. Apply the steps to your photos"),
            .ol(["Tap **Run on photos…**. You can also tap the batch button at the top of the screen.", "Tap **Add photos** and select a maximum of 10 photos.",
                 "Examine the results. Each row shows one photo. Each result shows one step."]),
            .p("Above the buttons, Seamless shows the approximate number of files, their size and the time to make them."),
            .h("3. Adjust one photo"),
            .ol(["Tap the result that you want to change. The editor opens for that photo and that step only.", "Change the settings.",
                 "Tap **Apply**. The result shows the label **Adjusted**."]),
            .p("To remove your changes, tap the result again. Then tap **Go back to the step's settings**."),
            .h("4. Export"),
            .ol(["Tap **Make files**.", "Tap **Save to Photos**. To use another app or to save in Files, tap **Share**."]),
            .p("Each file name shows the photo, the step and the slide. For example, `DSC_0420_2-carousel_01.jpg` is photo DSC_0420, step 2 (Carousel), slide 1."),
        ]
        }
    }
}
