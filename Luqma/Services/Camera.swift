import SwiftUI
import AVFoundation
import Vision
import UIKit

struct CameraPhoto: UIViewControllerRepresentable {
    var completion: (Data?) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(completion) }
    func makeUIViewController(context:Context) -> UIImagePickerController { let vc=UIImagePickerController();vc.sourceType = .camera;vc.cameraDevice = .rear;vc.delegate=context.coordinator;return vc }
    func updateUIViewController(_ controller:UIImagePickerController,context:Context) {}
    final class Coordinator:NSObject,UIImagePickerControllerDelegate,UINavigationControllerDelegate {
        let completion:(Data?)->Void;init(_ c:@escaping(Data?)->Void){completion=c}
        func imagePickerControllerDidCancel(_ picker:UIImagePickerController){completion(nil)}
        func imagePickerController(_ picker:UIImagePickerController,didFinishPickingMediaWithInfo info:[UIImagePickerController.InfoKey:Any]) {completion((info[.originalImage] as? UIImage)?.jpegData(compressionQuality:0.85))}
    }
}

struct BarcodeCamera:UIViewControllerRepresentable {
    var completion:(String)->Void;var failed:(String)->Void
    func makeUIViewController(context:Context) -> ScannerController {let c=ScannerController();c.completion=completion;c.failed=failed;return c}
    func updateUIViewController(_ controller:ScannerController,context:Context) {}
    static func dismantleUIViewController(_ controller:ScannerController,coordinator:()){controller.stop()}
}
final class ScannerController:UIViewController,AVCaptureMetadataOutputObjectsDelegate {
    private let session=AVCaptureSession(),queue=DispatchQueue(label:"luqma.camera")
    private var preview:AVCaptureVideoPreviewLayer?,delivered=false
    var completion:((String)->Void)?,failed:((String)->Void)?
    override func viewDidLoad(){super.viewDidLoad();view.backgroundColor = .black
        let layer=AVCaptureVideoPreviewLayer(session:session);layer.videoGravity = .resizeAspectFill;view.layer.addSublayer(layer);preview=layer
        queue.async { [weak self] in self?.setup() }
    }
    override func viewDidLayoutSubviews(){super.viewDidLayoutSubviews();preview?.frame=view.bounds}
    private func setup(){
        do {try configure();session.startRunning()}
        catch {DispatchQueue.main.async{[weak self] in self?.failed?(error.localizedDescription)}}
    }
    private func configure() throws {
        guard let device=AVCaptureDevice.default(.builtInWideAngleCamera,for:.video,position:.back) else{throw AppError.invalid("لا توجد كاميرا متاحة.","No camera is available.")}
            let input=try AVCaptureDeviceInput(device:device),output=AVCaptureMetadataOutput()
            session.beginConfiguration();defer{session.commitConfiguration()}
            guard session.canAddInput(input),session.canAddOutput(output) else{throw AppError.invalid("تعذّر تشغيل الكاميرا.","The camera could not start.")}
            session.addInput(input);session.addOutput(output);output.setMetadataObjectsDelegate(self,queue:.main)
            output.metadataObjectTypes=[.ean13,.ean8,.upce,.code128,.code39,.itf14].filter{output.availableMetadataObjectTypes.contains($0)}
    }
    func stop(){queue.async{[weak self] in if self?.session.isRunning == true {self?.session.stopRunning()}}}
    override func viewWillDisappear(_ animated:Bool){super.viewWillDisappear(animated);stop()}
    func metadataOutput(_ output:AVCaptureMetadataOutput,didOutput metadataObjects:[AVMetadataObject],from connection:AVCaptureConnection){
        guard !delivered,let value=(metadataObjects.first as? AVMetadataMachineReadableCodeObject)?.stringValue else{return};delivered=true;stop();completion?(value)
    }
}
enum CameraAccess {
    static func request() async -> Bool { switch AVCaptureDevice.authorizationStatus(for:.video){case .authorized:return true;case .notDetermined:return await AVCaptureDevice.requestAccess(for:.video);default:return false} }
    static func barcode(in data:Data) async throws -> String? {
        try await Task.detached {
            let image=try PhotoAnalyzer.image(data),request=VNDetectBarcodesRequest();try VNImageRequestHandler(cgImage:image).perform([request]);return request.results?.compactMap(\.payloadStringValue).first
        }.value
    }
}
