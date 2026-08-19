import SwiftUI
import SwiftData
import PhotosUI
import AVFoundation
import UniformTypeIdentifiers

/// The camera badge on a profile photo: take a photo, pick one from Photos,
/// or pick an image file. Every route lands in the crop circle before it's
/// saved, the same path the editor's photos take.
struct ProfilePhotoEditButton: View {
    let person: Person

    @Environment(\.modelContext) private var context

    @State private var showingOptions = false
    @State private var showingCamera = false
    @State private var showingPhotos = false
    @State private var showingFiles = false
    @State private var photoItem: PhotosPickerItem?
    // The camera's capture is staged until its cover finishes dismissing.
    // Presenting the crop sheet while the cover is still animating away
    // drops the sheet.
    @State private var capturedImage: UIImage?
    @State private var pendingCropImage: UIImage?
    @State private var showingCameraDenied = false

    var body: some View {
        Button {
            showingOptions = true
        } label: {
            Image(systemName: "camera.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(person.workspace.accent)
                .padding(7)
                .background(.white, in: Circle())
                .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Change profile photo")
        .confirmationDialog("Change Photo", isPresented: $showingOptions, titleVisibility: .visible) {
            if CameraCapture.isAvailable {
                Button("Take Photo") {
                    // A denied permission presents as a black, dead capture
                    // screen, so explain instead. (.notDetermined is fine:
                    // the picker raises the system prompt itself.)
                    switch AVCaptureDevice.authorizationStatus(for: .video) {
                    case .denied, .restricted: showingCameraDenied = true
                    default: showingCamera = true
                    }
                }
            }
            Button("Choose from Photos") { showingPhotos = true }
            Button("Choose from Files") { showingFiles = true }
        }
        .alert("Camera Access Is Off", isPresented: $showingCameraDenied) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Turn on Camera access for Memento in \(ProcessInfo.processInfo.isiOSAppOnMac ? "System Settings" : "the iOS Settings app"), then try again. You can also choose a photo from Photos or Files instead.")
        }
        .photosPicker(isPresented: $showingPhotos, selection: $photoItem, matching: .images)
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task { @MainActor in
                if let data = try? await item.loadTransferable(type: Data.self),
                   let uiImage = UIImage(data: data) {
                    pendingCropImage = uiImage
                }
                photoItem = nil
            }
        }
        .fullScreenCover(isPresented: $showingCamera) {
            CameraCapture { image in
                capturedImage = image
            }
            .ignoresSafeArea()
        }
        .onChange(of: showingCamera) { _, isShowing in
            guard !isShowing, let image = capturedImage else { return }
            capturedImage = nil
            pendingCropImage = image
        }
        .fileImporter(isPresented: $showingFiles, allowedContentTypes: [.image]) { result in
            guard let url = try? result.get() else { return }
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            if let data = try? Data(contentsOf: url), let uiImage = UIImage(data: data) {
                pendingCropImage = uiImage
            }
        }
        .sheet(isPresented: Binding(
            get: { pendingCropImage != nil },
            set: { if !$0 { pendingCropImage = nil } }
        )) {
            if let image = pendingCropImage {
                PhotoCropperView(image: image) { data in
                    person.profilePhotoData = data
                    try? context.save()
                }
            }
        }
    }
}

// MARK: - Camera

/// UIImagePickerController's camera, the system capture screen. SwiftUI has
/// no native equivalent short of an AVFoundation viewfinder.
struct CameraCapture: UIViewControllerRepresentable {
    var onCapture: (UIImage) -> Void

    @Environment(\.dismiss) private var dismiss

    /// False on Macs without a camera and on the Simulator. The Take Photo
    /// option hides rather than presenting a black screen.
    static var isAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ picker: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        private let parent: CameraCapture
        init(_ parent: CameraCapture) { self.parent = parent }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                parent.onCapture(image)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
