import SwiftUI
import AVFoundation
import UIKit

/// UI state belongs to MainActor; all session mutations and blocking operations
/// belong to MealCameraSession's serial queue. The preview layer is persistent.
@MainActor final class MealCamera: ObservableObject {
    enum State: Equatable { case idle, starting, ready, denied, restricted, unavailable, interrupted, failed }
    @Published private(set) var state: State = .idle
    @Published private(set) var capturing = false
    let driver = MealCameraSession()
    private var wanted = false
    private var permissionTask: Task<Void, Never>?
    private var captureGeneration = UUID()

    init() {
        driver.onState = { [weak self] state in
            Task { @MainActor [weak self] in
                guard let self, self.wanted else { return }
                self.state = state
            }
        }
    }

    func setActive(_ active: Bool) {
        guard wanted != active else { return }
        wanted = active
        if !active {
            permissionTask?.cancel(); permissionTask = nil
            captureGeneration = UUID(); capturing = false
            driver.setActive(false)
            return
        }
        state = .starting
        permissionTask = Task { [weak self] in
            let available = await Task.detached {
                AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) != nil
            }.value
            guard !Task.isCancelled, let self, self.wanted else { return }
            guard available else { self.state = .unavailable; self.permissionTask = nil; return }
            let authorized = await CameraAccess.request()
            guard !Task.isCancelled, self.wanted else { return }
            self.permissionTask = nil
            guard authorized else {
                self.state = AVCaptureDevice.authorizationStatus(for: .video) == .restricted ? .restricted : .denied
                return
            }
            self.driver.setActive(true)
        }
    }

    func capture(_ completion: @escaping (Data?) -> Void) {
        guard wanted, state == .ready, !capturing else { return }
        capturing = true
        let generation = UUID(); captureGeneration = generation
        driver.capture { [weak self] data in
            Task { @MainActor [weak self] in
                guard let self, self.wanted, self.captureGeneration == generation else { return }
                self.capturing = false
                completion(data)
            }
        }
    }
}

/// Queue-confined AVFoundation state. Only `session` is exposed, exclusively for
/// AVCaptureVideoPreviewLayer. Delegates hop back onto the same serial queue.
final class MealCameraSession: NSObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {
    let session = AVCaptureSession()
    var onState: ((MealCamera.State) -> Void)?
    private let queue = DispatchQueue(label: "luqma.meal-camera", qos: .userInitiated)
    private let output = AVCapturePhotoOutput()
    private var configured = false, wanted = false, interrupted = false
    private var orientation: AVCaptureVideoOrientation = .portrait
    private var completion: ((Data?) -> Void)?
    private var photoData: Data?
    private var captureID: Int64?
    private var observers: [NSObjectProtocol] = []

    override init() {
        super.init()
        observe(AVCaptureSession.wasInterruptedNotification) { camera in
            camera.interrupted = true
            camera.finishCapture(nil)
            if camera.wanted { camera.onState?(.interrupted) }
        }
        observe(AVCaptureSession.interruptionEndedNotification) { camera in
            camera.interrupted = false
            camera.reconcile()
        }
        observers.append(NotificationCenter.default.addObserver(forName: AVCaptureSession.runtimeErrorNotification, object: session, queue: nil) { [weak self] note in
            let code = (note.userInfo?[AVCaptureSessionErrorKey] as? AVError)?.code
            self?.queue.async { [weak self] in
                guard let self else { return }
                self.finishCapture(nil)
                if code == .mediaServicesWereReset { self.reconcile() }
                else if self.wanted { self.onState?(.failed) }
            }
        })
    }
    deinit {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        let captureSession = session
        queue.async { if captureSession.isRunning { captureSession.stopRunning() } }
    }
    private func observe(_ name: Notification.Name, action: @escaping (MealCameraSession) -> Void) {
        observers.append(NotificationCenter.default.addObserver(forName: name, object: session, queue: nil) { [weak self] _ in
            self?.queue.async { [weak self] in if let self { action(self) } }
        })
    }
    func setActive(_ active: Bool) {
        queue.async { [self] in
            wanted = active
            if !active { finishCapture(nil) }
            reconcile()
        }
    }
    func setOrientation(_ value: AVCaptureVideoOrientation) { queue.async { [self] in orientation = value } }
    private func reconcile() {
        guard wanted else { if session.isRunning { session.stopRunning() }; return }
        // A background stop may end an interruption before its queued notice.
        // Re-read AVFoundation's current state when returning to the feature.
        interrupted = session.isInterrupted
        guard !interrupted else { onState?(.interrupted); return }
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else { onState?(.denied); return }
        if !configured {
            guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else { onState?(.unavailable); return }
            do {
                let input = try AVCaptureDeviceInput(device: camera)
                session.beginConfiguration()
                session.sessionPreset = .photo
                guard session.canAddInput(input), session.canAddOutput(output) else {
                    session.commitConfiguration(); onState?(.failed); return
                }
                session.addInput(input); session.addOutput(output)
                // Prefer a full-resolution photo up to 24 MP to bound transient
                // codec memory. Devices with other formats use their largest size.
                let sizes = camera.activeFormat.supportedMaxPhotoDimensions
                let bounded = sizes.filter { Int64($0.width) * Int64($0.height) <= 24_000_000 }
                if let largest = (bounded.isEmpty ? sizes : bounded).max(by: { Int64($0.width) * Int64($0.height) < Int64($1.width) * Int64($1.height) }) {
                    output.maxPhotoDimensions = largest
                }
                output.maxPhotoQualityPrioritization = .quality
                session.commitConfiguration(); configured = true
            } catch { onState?(.failed); return }
        }
        if !session.isRunning { session.startRunning() }
        onState?(session.isRunning ? .ready : .failed)
    }
    func capture(_ callback: @escaping (Data?) -> Void) {
        queue.async { [self] in
            guard wanted, !interrupted, session.isRunning, completion == nil else { callback(nil); return }
            completion = callback; photoData = nil
            if let connection = output.connection(with: .video), connection.isVideoOrientationSupported { connection.videoOrientation = orientation }
            let settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
            settings.maxPhotoDimensions = output.maxPhotoDimensions
            settings.photoQualityPrioritization = .quality
            settings.flashMode = .off
            captureID = settings.uniqueID
            output.capturePhoto(with: settings, delegate: self)
        }
    }
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let data = error == nil ? photo.fileDataRepresentation() : nil
        let identifier = photo.resolvedSettings.uniqueID
        queue.async { [self] in if captureID == identifier { photoData = data } }
    }
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings, error: Error?) {
        let identifier = resolvedSettings.uniqueID
        queue.async { [self] in if captureID == identifier { finishCapture(error == nil ? photoData : nil) } }
    }
    private func finishCapture(_ data: Data?) {
        let callback = completion; completion = nil; photoData = nil; captureID = nil
        callback?(data)
    }
}

struct MealCameraPreview: UIViewRepresentable {
    let driver: MealCameraSession
    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = driver.session
        view.previewLayer.videoGravity = .resizeAspectFill
        view.orientationChanged = { driver.setOrientation($0) }
        return view
    }
    func updateUIView(_ view: PreviewView, context: Context) { view.setNeedsLayout() }
    static func dismantleUIView(_ view: PreviewView, coordinator: ()) { view.previewLayer.session = nil }

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
        var orientationChanged: ((AVCaptureVideoOrientation) -> Void)?
        override func layoutSubviews() {
            super.layoutSubviews()
            let orientation: AVCaptureVideoOrientation
            switch window?.windowScene?.interfaceOrientation {
            case .landscapeLeft: orientation = .landscapeLeft
            case .landscapeRight: orientation = .landscapeRight
            case .portraitUpsideDown: orientation = .portraitUpsideDown
            default: orientation = .portrait
            }
            if let connection = previewLayer.connection, connection.isVideoOrientationSupported { connection.videoOrientation = orientation }
            orientationChanged?(orientation)
        }
    }
}
