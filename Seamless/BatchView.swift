import SwiftUI
import PhotosUI

struct BatchView: View {
    @Bindable var batch: BatchModel
    @Binding var shareRequest: ShareRequest?
    @State private var picks: [PhotosPickerItem] = []
    @State private var fix: FixContext?
    @State private var showSaveResult = false
    @Environment(HingeState.self) private var hinge

    var body: some View {
        GeometryReader { geo in
            let wide = geo.size.width >= 700 && (hinge.splitAtFold || geo.size.width > geo.size.height * 0.9)
            Group {
                if wide {
                    // steps on the left, the photos and the run button on the right, so a fold
                    // never cuts through a thumbnail row
                    HStack(alignment: .top, spacing: 0) {
                        ScrollView {
                            stepsSection.padding().frame(maxWidth: 420, alignment: .leading)
                        }
                        Divider()
                        ScrollView {
                            VStack(alignment: .leading, spacing: 20) { photosSection; runSection }
                                .padding()
                                .frame(maxWidth: 620, alignment: .leading)
                        }
                        .scrollBounceBehavior(.basedOnSize)
                    }
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            stepsSection
                            photosSection
                            runSection
                        }
                        .padding()
                        .frame(maxWidth: 900)
                        .frame(maxWidth: .infinity)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                }
            }
        }
        .navigationTitle("Batch")
        .navigationBarTitleDisplayMode(.inline)
        .background(DS.bg)
        .alert("Save to Photos", isPresented: $showSaveResult) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(batch.status ?? "No files were saved.")
        }
        .onChange(of: picks) { _, items in
            guard !items.isEmpty else { return }
            Task { await batch.add(items); picks = [] }
        }
        .fullScreenCover(item: $fix) { ctx in
            FixView(ctx: ctx, batch: batch) { fix = nil }
        }
    }

    private func card<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(DS.secondary)
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.card, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(DS.stroke, lineWidth: 1))
    }

    private var stepsSection: some View {
        card("Steps") {
            if batch.steps.isEmpty {
                Text("No steps yet. Add some from the editor.").foregroundStyle(DS.secondary)
            }
            ForEach(Array(batch.steps.enumerated()), id: \.element.id) { i, step in
                HStack {
                    Text("\(i + 1)").bold().frame(width: 24, height: 24).background(DS.stroke, in: Circle())
                    Text(step.label)
                    Spacer()
                    Button { batch.remove(step) } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                            .frame(minWidth: 44, minHeight: 44)
                    }
                        .accessibilityLabel("Remove step \(i + 1)")
                }
            }
        }
    }

    private var photosSection: some View {
        card("Photos · \(batch.photos.count) of \(maxPhotos)") {
            HStack {
                Spacer()
                PhotosPicker(selection: $picks, maxSelectionCount: max(1, maxPhotos - batch.photos.count),
                             matching: .images, photoLibrary: .shared()) {
                    Label("Add photos", systemImage: "plus").frame(minHeight: 32)
                }
                .buttonStyle(.bordered)
                .disabled(batch.photos.count >= maxPhotos)
            }
            if let w = batch.warning { Text(w).font(.footnote).foregroundStyle(.orange) }
            ForEach(batch.photos) { photo in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(photo.base).font(.subheadline.weight(.semibold)).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Button { batch.removePhoto(photo.id) } label: {
                            Image(systemName: "trash").foregroundStyle(.secondary).frame(minWidth: 44, minHeight: 44)
                        }
                            .accessibilityLabel("Remove \(photo.base)")
                    }
                    if photo.failed {
                        Text("This photo could not be opened.").font(.footnote).foregroundStyle(.red)
                    } else if photo.thumb == nil {
                        ProgressView()
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(alignment: .top, spacing: 10) {
                                ForEach(Array(batch.steps.enumerated()), id: \.element.id) { i, step in
                                    cell(photo, step, i)
                                }
                            }
                        }
                    }
                }
                .padding(10)
                .background(DS.bg, in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private func cell(_ photo: BatchPhoto, _ step: Step, _ i: Int) -> some View {
        Button {
            Task { fix = await batch.fixContext(photo: photo.id, step: step) }
        } label: {
            VStack(spacing: 4) {
                if let img = batch.cell(photo, step) {
                    Image(uiImage: img).resizable().scaledToFit().frame(height: 130)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                Text(photo.overrides[step.id] != nil ? "Step \(i + 1) · Adjusted" : "Step \(i + 1)")
                    .font(.caption2).foregroundStyle(photo.overrides[step.id] != nil ? DS.text : DS.secondary)
            }
        }
        .buttonStyle(.plain)
    }

    private var runSection: some View {
        card("Export") {
            Text(batch.estimateText).font(.footnote).foregroundStyle(DS.secondary)
            HStack(spacing: 2) {
                Spacer(minLength: 8)
                if !batch.results.isEmpty && !batch.busy {
                    Button { Task {
                        await batch.saveToPhotos()
                        showSaveResult = true
                    } } label: {
                        Label("Save to Photos", systemImage: "square.and.arrow.down").labelStyle(.iconOnly)
                    }
                    .buttonStyle(QuietBarButton())
                    .accessibilityLabel("Save to Photos")
                    Button { shareRequest = ShareRequest(items: batch.results) } label: {
                        Label("Share", systemImage: "square.and.arrow.up").labelStyle(.iconOnly)
                    }
                    .buttonStyle(QuietBarButton())
                    .accessibilityLabel("Share")
                }
                Button { Task { await batch.run() } } label: {
                    Text(batch.progress ?? "Make files")
                }
                .buttonStyle(PrimaryButton())
                .disabled(!batch.canRun)
            }
            if let s = batch.status { Text(s).font(.footnote).foregroundStyle(DS.secondary) }
        }
    }
}

/// The editor for one batch photo and one step.
struct FixView: View {
    let ctx: FixContext
    var batch: BatchModel
    var done: () -> Void
    @State private var model: EditorModel
    @State private var showBatch = false
    @State private var shareRequest: ShareRequest?

    init(ctx: FixContext, batch: BatchModel, done: @escaping () -> Void) {
        self.ctx = ctx; self.batch = batch; self.done = done
        _model = State(initialValue: EditorModel(fix: ctx))
    }

    private var stepNumber: Int { (batch.steps.firstIndex { $0.id == ctx.step.id } ?? 0) + 1 }

    var body: some View {
        NavigationStack {
            EditorView(model: model, batch: nil, showBatch: $showBatch, shareRequest: $shareRequest,
                       showsWordmark: false, showsExportBar: false, hidesNavigationBar: false)
                .navigationTitle("\(ctx.base) · step \(stepNumber)")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: done) }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Apply") {
                            batch.setOverride(model.currentOverride(), photo: ctx.photoID, step: ctx.step.id)
                            done()
                        }
                    }
                    if ctx.existing != nil {
                        ToolbarItem(placement: .bottomBar) {
                            Button("Go back to the step's settings") {
                                batch.setOverride(nil, photo: ctx.photoID, step: ctx.step.id)
                                done()
                            }
                        }
                    }
                }
        }
        .tint(DS.ink)
    }
}
