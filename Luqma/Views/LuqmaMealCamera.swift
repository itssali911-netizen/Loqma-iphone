import SwiftUI
import UIKit
import AVFoundation

/// Real inline capture surface. Permission is handled by the existing camera
/// access flow; this view never requests it or supplies synthetic frames.
struct LuqmaMealCamera:UIViewControllerRepresentable {
    let captureID:Int
    let active:Bool
    let onCapture:(Data)->Void
    let onFailure:()->Void
    func makeUIViewController(context:Context)->LuqmaMealCameraController {
        let controller=LuqmaMealCameraController()
        controller.onCapture=onCapture;controller.onFailure=onFailure
        controller.update(active:active,captureID:captureID)
        return controller
    }
    func updateUIViewController(_ controller:LuqmaMealCameraController,context:Context){
        controller.onCapture=onCapture;controller.onFailure=onFailure
        controller.update(active:active,captureID:captureID)
    }
    static func dismantleUIViewController(_ controller:LuqmaMealCameraController,coordinator:()){controller.dispose()}
}

final class LuqmaMealCameraController:UIViewController,AVCapturePhotoCaptureDelegate {
    var onCapture:((Data)->Void)?
    var onFailure:(()->Void)?
    private let session=AVCaptureSession()
    private let output=AVCapturePhotoOutput()
    private let queue=DispatchQueue(label:"luqma.meal-camera")
    private let lock=NSLock()
    // Only requestedRunning crosses queues, guarded by lock. Capture session
    // configuration and photo output remain confined to the serial queue.
    private var requestedRunning=false
    private var configured=false
    private var capturing=false
    private var visible=false
    private var active=false
    private var disposed=false
    private var captureID=0
    private var preview:AVCaptureVideoPreviewLayer?
    private var observers:[NSObjectProtocol]=[]
    override func viewDidLoad(){
        super.viewDidLoad();view.backgroundColor=UIColor(Theme.background)
        let layer=AVCaptureVideoPreviewLayer(session:session);layer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(layer);preview=layer
        observers.append(NotificationCenter.default.addObserver(forName:AVCaptureSession.runtimeErrorNotification,object:session,queue:.main){[weak self]_ in
            guard let self,self.visible,self.active,!self.disposed else{return};self.onFailure?()
        })
        observers.append(NotificationCenter.default.addObserver(forName:AVCaptureSession.interruptionEndedNotification,object:session,queue:.main){[weak self]_ in self?.refresh()})
    }
    deinit{observers.forEach{NotificationCenter.default.removeObserver($0)}}
    override func viewDidLayoutSubviews(){
        super.viewDidLayoutSubviews();preview?.frame=view.bounds
        if let connection=preview?.connection,connection.isVideoOrientationSupported{connection.videoOrientation = .portrait}
    }
    override func viewDidAppear(_ animated:Bool){super.viewDidAppear(animated);visible=true;refresh()}
    override func viewWillDisappear(_ animated:Bool){super.viewWillDisappear(animated);visible=false;refresh()}
    func update(active:Bool,captureID:Int){
        self.active=active;refresh()
        guard self.captureID != captureID else{return};self.captureID=captureID
        queue.async{[self] in
            guard wantsRunning(),configured,session.isRunning,!capturing else{return}
            capturing=true
            if let connection=output.connection(with:.video),connection.isVideoOrientationSupported{connection.videoOrientation = .portrait}
            let settings=AVCapturePhotoSettings(format:[AVVideoCodecKey:AVVideoCodecType.jpeg])
            output.capturePhoto(with:settings,delegate:self)
        }
    }
    func dispose(){disposed=true;visible=false;refresh()}
    private func wantsRunning()->Bool{lock.lock();defer{lock.unlock()};return requestedRunning}
    private func refresh(){
        lock.lock();requestedRunning=visible && active && !disposed;lock.unlock()
        queue.async{[self] in
            guard wantsRunning() else{if session.isRunning{session.stopRunning()};return}
            do{
                if !configured{try configure();configured=true}
                guard wantsRunning() else{return}
                if !session.isRunning{session.startRunning()}
                if !wantsRunning(),session.isRunning{session.stopRunning()}
                DispatchQueue.main.async{[weak self] in self?.view.setNeedsLayout()}
            }catch{DispatchQueue.main.async{[weak self] in
                guard let self,self.visible,self.active,!self.disposed else{return};self.onFailure?()
            }}
        }
    }
    private func configure() throws {
        guard AVCaptureDevice.authorizationStatus(for:.video) == .authorized,
              let camera=AVCaptureDevice.default(.builtInWideAngleCamera,for:.video,position:.back) else{throw CocoaError(.featureUnsupported)}
        let input=try AVCaptureDeviceInput(device:camera)
        session.beginConfiguration();defer{session.commitConfiguration()}
        session.sessionPreset = .photo
        guard session.canAddInput(input),session.canAddOutput(output) else{throw CocoaError(.featureUnsupported)}
        session.addInput(input);session.addOutput(output)
    }
    func photoOutput(_ output:AVCapturePhotoOutput,didFinishProcessingPhoto photo:AVCapturePhoto,error:Error?){
        let data=error == nil ? photo.fileDataRepresentation():nil
        queue.async{[self] in
            capturing=false
            guard wantsRunning() else{return}
            DispatchQueue.main.async{[weak self] in
                guard let self,self.visible,self.active,!self.disposed else{return}
                if let data{self.onCapture?(data)}else{self.onFailure?()}
            }
        }
    }
}
