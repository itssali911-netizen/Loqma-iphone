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
    var language:AppLanguage = .ar
    var completion:(String)->Void;var failed:(String)->Void
    func makeUIViewController(context:Context) -> ScannerController {let c=ScannerController();c.language=language;c.completion=completion;c.failed=failed;return c}
    func updateUIViewController(_ controller:ScannerController,context:Context) {controller.language=language;controller.completion=completion;controller.failed=failed}
    static func dismantleUIViewController(_ controller:ScannerController,coordinator:()){controller.stop()}
}

// The Simulator preview and physical scanner render this same guide. It creates
// no capture session and requests no permission when shown on its own.
struct BarcodeScanGuide:UIViewRepresentable {
    var language:AppLanguage
    func makeUIView(context:Context)->BarcodeScanGuideView {let view=BarcodeScanGuideView();view.language=language;return view}
    func updateUIView(_ view:BarcodeScanGuideView,context:Context) {view.language=language}
}

final class BarcodeScanGuideView:UIView {
    var language:AppLanguage = .ar {didSet{updateInstruction()}}
    private(set) var targetRect=CGRect.zero
    var onTargetRectChange:((CGRect)->Void)?
    private let shade=CAShapeLayer(),border=CAShapeLayer(),corners=CAShapeLayer()
    private let instruction=UILabel()

    override init(frame:CGRect) {
        super.init(frame:frame)
        isUserInteractionEnabled=false;isAccessibilityElement=true;accessibilityTraits = .staticText
        backgroundColor = .clear
        shade.fillRule = .evenOdd;shade.fillColor=UIColor.black.withAlphaComponent(0.6).cgColor
        border.fillColor=UIColor.clear.cgColor;border.strokeColor=UIColor(Theme.accent).withAlphaComponent(0.35).cgColor;border.lineWidth=1
        corners.fillColor=UIColor.clear.cgColor;corners.strokeColor=UIColor(Theme.accent).cgColor;corners.lineWidth=4;corners.lineCap = .round;corners.lineJoin = .round
        [shade,border,corners].forEach{layer.addSublayer($0)}
        instruction.numberOfLines=0;instruction.textAlignment = .center;instruction.textColor = .white
        instruction.backgroundColor=UIColor(Theme.background).withAlphaComponent(0.92)
        instruction.layer.cornerRadius=16;instruction.clipsToBounds=true;instruction.isAccessibilityElement=false
        addSubview(instruction);updateInstruction()
    }
    required init?(coder:NSCoder){fatalError("init(coder:) has not been implemented")}
    private func updateInstruction() {
        instruction.text=language.text("ضع الباركود داخل الإطار\nثبّت المنتج حتى تتم قراءته تلقائيًا","Place the barcode inside the frame\nHold still to scan automatically")
        instruction.font=LTypography.uiFont(size:16,weight:.medium,relativeTo:.body)
        accessibilityLabel=language.text("إطار مسح الباركود","Barcode scanning frame")
        accessibilityHint=language.text("ضع باركود المنتج في منتصف الكاميرا داخل الإطار البرتقالي، ثم ثبّته قليلًا.","Center the product barcode inside the orange camera frame, then hold it still.")
        setNeedsLayout()
    }
    override func traitCollectionDidChange(_ previousTraitCollection:UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if previousTraitCollection?.preferredContentSizeCategory != traitCollection.preferredContentSizeCategory {updateInstruction()}
    }
    override func safeAreaInsetsDidChange(){super.safeAreaInsetsDidChange();setNeedsLayout()}
    override func layoutSubviews() {
        super.layoutSubviews()
        let safe=bounds.inset(by:safeAreaInsets),available=safe.insetBy(dx:24,dy:20)
        guard available.width>0,available.height>0 else{return}
        let textWidth=max(1,available.width-24)
        let textHeight=instruction.sizeThatFits(CGSize(width:textWidth,height:.greatestFiniteMagnitude)).height
        let labelHeight=min(textHeight+24,max(44,available.height-104))
        let width=min(360,available.width),height=min(width*0.55,max(64,available.height-labelHeight-32))
        let groupHeight=height+24+labelHeight
        let top=max(available.minY,available.midY-groupHeight/2)
        let rect=CGRect(x:available.midX-width/2,y:top,width:width,height:height).integral
        instruction.frame=CGRect(x:available.minX,y:rect.maxY+24,width:available.width,height:labelHeight).integral
        let hole=UIBezierPath(roundedRect:rect,cornerRadius:18),mask=UIBezierPath(rect:bounds)
        mask.append(hole)
        let path=UIBezierPath(),length:CGFloat=30,radius:CGFloat=16
        path.move(to:CGPoint(x:rect.minX,y:rect.minY+length));path.addLine(to:CGPoint(x:rect.minX,y:rect.minY+radius));path.addQuadCurve(to:CGPoint(x:rect.minX+radius,y:rect.minY),controlPoint:rect.origin);path.addLine(to:CGPoint(x:rect.minX+length,y:rect.minY))
        path.move(to:CGPoint(x:rect.maxX-length,y:rect.minY));path.addLine(to:CGPoint(x:rect.maxX-radius,y:rect.minY));path.addQuadCurve(to:CGPoint(x:rect.maxX,y:rect.minY+radius),controlPoint:CGPoint(x:rect.maxX,y:rect.minY));path.addLine(to:CGPoint(x:rect.maxX,y:rect.minY+length))
        path.move(to:CGPoint(x:rect.maxX,y:rect.maxY-length));path.addLine(to:CGPoint(x:rect.maxX,y:rect.maxY-radius));path.addQuadCurve(to:CGPoint(x:rect.maxX-radius,y:rect.maxY),controlPoint:CGPoint(x:rect.maxX,y:rect.maxY));path.addLine(to:CGPoint(x:rect.maxX-length,y:rect.maxY))
        path.move(to:CGPoint(x:rect.minX+length,y:rect.maxY));path.addLine(to:CGPoint(x:rect.minX+radius,y:rect.maxY));path.addQuadCurve(to:CGPoint(x:rect.minX,y:rect.maxY-radius),controlPoint:CGPoint(x:rect.minX,y:rect.maxY));path.addLine(to:CGPoint(x:rect.minX,y:rect.maxY-length))
        // Layer geometry changes immediately, without implicit animation loops.
        CATransaction.begin();CATransaction.setDisableActions(true)
        shade.frame=bounds;border.frame=bounds;corners.frame=bounds
        shade.path=mask.cgPath;border.path=hole.cgPath;corners.path=path.cgPath
        CATransaction.commit()
        if targetRect != rect{targetRect=rect;onTargetRectChange?(rect)}
    }
}

final class ScannerController:UIViewController,AVCaptureMetadataOutputObjectsDelegate {
    private let session=AVCaptureSession(),queue=DispatchQueue(label:"luqma.camera")
    private let guide=BarcodeScanGuideView(),lifecycleLock=NSLock()
    // Only these two requested values cross queues, under the short-lived lock.
    // Configuration/start/stop and output properties belong to the camera queue.
    private var requestedRunning=false,requestedRegion=CGRect.zero
    private var configured=false,metadata:AVCaptureMetadataOutput?
    private var preview:AVCaptureVideoPreviewLayer?,delivered=false,disposed=false,visible=false,appActive=true,interrupted=false
    private var observers:[NSObjectProtocol]=[]
    var language:AppLanguage = .ar {didSet{guide.language=language}}
    var completion:((String)->Void)?,failed:((String)->Void)?
    override func viewDidLoad(){super.viewDidLoad();view.backgroundColor = .black
        let layer=AVCaptureVideoPreviewLayer(session:session);layer.videoGravity = .resizeAspectFill;view.layer.addSublayer(layer);preview=layer
        guide.language=language;guide.onTargetRectChange={[weak self]_ in self?.updateRegionOfInterest()};view.addSubview(guide)
        appActive=UIApplication.shared.applicationState == .active
        observe(UIApplication.willResignActiveNotification){[weak self] in self?.appActive=false;self?.refreshRunning()}
        observe(UIApplication.didBecomeActiveNotification){[weak self] in self?.appActive=true;self?.refreshRunning()}
        // AVFoundation pauses/resumes interrupted capture itself. Stopping in
        // this notification can manufacture interruption-ended/restart loops.
        observe(AVCaptureSession.wasInterruptedNotification,object:session){[weak self] in self?.interrupted=true}
        observe(AVCaptureSession.interruptionEndedNotification,object:session){[weak self] in self?.interrupted=false;self?.refreshRunning()}
        observe(AVCaptureSession.runtimeErrorNotification,object:session){[weak self] in self?.finishFailure(AppError.invalid("تعذّر تشغيل الكاميرا. أغلق الماسح وحاول مجددًا.","The camera stopped. Close the scanner and try again."))}
    }
    deinit {observers.forEach{NotificationCenter.default.removeObserver($0)}}
    private func observe(_ name:Notification.Name,object:Any?=nil,action:@escaping()->Void) {
        observers.append(NotificationCenter.default.addObserver(forName:name,object:object,queue:.main){_ in action()})
    }
    override func viewDidAppear(_ animated:Bool){super.viewDidAppear(animated);visible=true;refreshRunning()}
    override func viewWillDisappear(_ animated:Bool){super.viewWillDisappear(animated);visible=false;refreshRunning()}
    override func viewDidLayoutSubviews(){super.viewDidLayoutSubviews()
        preview?.frame=view.bounds;guide.frame=view.bounds;guide.setNeedsLayout();guide.layoutIfNeeded()
        if let orientation=view.window?.windowScene?.interfaceOrientation,let connection=preview?.connection,connection.isVideoOrientationSupported {
            switch orientation{case .portrait:connection.videoOrientation = .portrait;case .portraitUpsideDown:connection.videoOrientation = .portraitUpsideDown;case .landscapeLeft:connection.videoOrientation = .landscapeLeft;case .landscapeRight:connection.videoOrientation = .landscapeRight;default:break}
        }
        updateRegionOfInterest()
    }
    private func updateRegionOfInterest() {
        guard let preview,guide.targetRect.width>0 else{return}
        let target=preview.convert(guide.targetRect,from:guide.layer)
        let converted=preview.metadataOutputRectConverted(fromLayerRect:target)
        let finite=[converted.origin.x,converted.origin.y,converted.width,converted.height].allSatisfy{$0.isFinite}
        let region=finite ? converted.intersection(CGRect(x:0,y:0,width:1,height:1)):CGRect.zero
        let checked=region.isNull || region.isEmpty ? CGRect.zero:region
        lifecycleLock.lock();let changed=requestedRegion != checked;requestedRegion=checked;lifecycleLock.unlock()
        if changed{queue.async{[self] in applyRegion()}}
    }
    private func refreshRunning() {
        let wanted=visible && appActive && !interrupted && !disposed && !delivered
        lifecycleLock.lock();requestedRunning=wanted;lifecycleLock.unlock()
        // Retain through queued teardown so dismissal cannot discard stopRunning.
        queue.async{[self] in reconcileCapture()}
    }
    private func wantsRunning()->Bool {lifecycleLock.lock();defer{lifecycleLock.unlock()};return requestedRunning}
    private func applyRegion(){lifecycleLock.lock();let region=requestedRegion;lifecycleLock.unlock();metadata?.rectOfInterest=region}
    private func reconcileCapture() {
        guard wantsRunning() else{if session.isRunning{session.stopRunning()};return}
        do {
            if !configured{try configure();configured=true}
            applyRegion()
            guard wantsRunning() else{return}
            if !session.isRunning{session.startRunning()}
            if !wantsRunning(),session.isRunning{session.stopRunning()}
            // The preview connection may not exist until configuration ends.
            // A layout now sets its actual interface orientation before ROI.
            DispatchQueue.main.async{[weak self] in self?.view.setNeedsLayout()}
        }catch{DispatchQueue.main.async{[weak self] in self?.finishFailure(error)}}
    }
    private func finishFailure(_ error:Error) {
        guard visible,appActive,!disposed,!delivered else{return}
        delivered=true;stop()
        failed?((error as? AppError)?.message(language) ?? language.text("تعذّر تشغيل الكاميرا. تحقق من إذن الكاميرا وأعد المحاولة.","The camera could not start. Check camera access and retry."))
    }
    private func configure() throws {
        guard let device=AVCaptureDevice.default(.builtInWideAngleCamera,for:.video,position:.back) else{throw AppError.invalid("لا توجد كاميرا متاحة.","No camera is available.")}
        let input=try AVCaptureDeviceInput(device:device),output=AVCaptureMetadataOutput()
        session.beginConfiguration();var success=false
        defer{if !success{if session.outputs.contains(where:{$0===output}){session.removeOutput(output)};if session.inputs.contains(where:{$0===input}){session.removeInput(input)}};session.commitConfiguration()}
        guard session.canAddInput(input),session.canAddOutput(output) else{throw AppError.invalid("تعذّر تشغيل الكاميرا.","The camera could not start.")}
        session.addInput(input);session.addOutput(output);output.setMetadataObjectsDelegate(self,queue:.main)
        let types:[AVMetadataObject.ObjectType]=[.ean13,.ean8,.upce,.code128,.code39,.itf14].filter{output.availableMetadataObjectTypes.contains($0)}
        guard !types.isEmpty else{throw AppError.invalid("مسح الباركود غير متاح على هذه الكاميرا.","Barcode scanning is unavailable on this camera.")}
        output.metadataObjectTypes=types;metadata=output;success=true
    }
    func stop(){disposed=true;visible=false;refreshRunning()}
    func metadataOutput(_ output:AVCaptureMetadataOutput,didOutput metadataObjects:[AVMetadataObject],from connection:AVCaptureConnection){
        guard visible,appActive,!interrupted,!disposed,!delivered,let preview,guide.targetRect.width>0 else{return}
        let target=preview.convert(guide.targetRect,from:guide.layer)
        for case let object as AVMetadataMachineReadableCodeObject in metadataObjects {
            guard let value=object.stringValue,!value.isEmpty,let transformed=preview.transformedMetadataObject(for:object),
                  target.contains(CGPoint(x:transformed.bounds.midX,y:transformed.bounds.midY)) else{continue}
            delivered=true;stop();completion?(value);return
        }
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
