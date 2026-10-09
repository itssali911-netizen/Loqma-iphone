import Foundation
import CoreGraphics
import ImageIO
import CryptoKit
import OnnxRuntimeBindings

actor PhotoAnalyzer {
    static let shared=PhotoAnalyzer()
    // LFS file SHA-256 from Hugging Face x-linked-etag, not the Xet storage hash.
    private let globalHash="583fd1110a514667812fee7d684952aaf82a99b959760c8d7dca7e0ab9839299"
    private let detailHash="44eece4fe5fe4e0359a88268a327adf758633a1aade3917690b952bef1501f96"
    private var verified=Set<String>()
    private var analyzing=false
    func foods() throws -> [PhotoFood] {
        guard let url=Bundle.main.url(forResource:"photo-foods",withExtension:"json") else { throw AppError.invalid("ملف الأطعمة مفقود.", "Food references are missing.") }
        return try JSONDecoder().decode([PhotoFood].self,from:Data(contentsOf:url))
    }
    private func model(_ name:String,revision:String,hash:String,progress:@Sendable (String)->Void) async throws -> URL {
        var folder=FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("PhotoModels",isDirectory:true)
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        var rv=URLResourceValues();rv.isExcludedFromBackup=true;try folder.setResourceValues(rv)
        let dest=folder.appendingPathComponent(hash+".onnx")
        func correct(_ url:URL) throws -> Bool {
            let file=try FileHandle(forReadingFrom:url);defer {try? file.close()};var digest=SHA256()
            while let chunk=try file.read(upToCount:1024*1024),!chunk.isEmpty {digest.update(data:chunk)}
            return digest.finalize().map{String(format:"%02x",$0)}.joined()==hash
        }
        if FileManager.default.fileExists(atPath:dest.path) {
            if verified.contains(hash) {return dest}
            progress("verify");if try correct(dest) {verified.insert(hash);return dest}
            try FileManager.default.removeItem(at:dest)
        }
        progress("download")
        let url=URL(string:"https://huggingface.co/\(name)/resolve/\(revision)/onnx/vision_model_quantized.onnx")!
        var req=URLRequest(url:url);req.timeoutInterval=300
        let (temp,response)=try await URLSession.shared.download(for:req)
        defer {try? FileManager.default.removeItem(at:temp)}
        guard let http=response as? HTTPURLResponse,http.statusCode==200,try correct(temp) else {throw AppError.invalid("تعذّر تنزيل نموذج سليم. اتصل بالإنترنت وأعد المحاولة.", "The model download failed verification. Connect to the internet and retry.")}
        try FileManager.default.moveItem(at:temp,to:dest);verified.insert(hash);return dest
    }
    static func image(_ data:Data) throws -> CGImage {
        guard data.count<=40*1024*1024,let source=CGImageSourceCreateWithData(data as CFData,nil),let image=CGImageSourceCreateThumbnailAtIndex(source,0,[kCGImageSourceCreateThumbnailFromImageAlways:true,kCGImageSourceCreateThumbnailWithTransform:true,kCGImageSourceThumbnailMaxPixelSize:2048] as CFDictionary) else { throw AppError.invalid("تعذّر فتح الصورة. اختر صورة JPEG أو PNG أو HEIC أصغر.", "The image could not be opened. Choose a smaller JPEG, PNG or HEIC image.") }; return image
    }
    private func pixels(_ image:CGImage,box:PhotoBox) throws -> [Float] {
        let rect=CGRect(x:box.x*Double(image.width),y:box.y*Double(image.height),width:box.width*Double(image.width),height:box.height*Double(image.height)).integral
        guard let crop=image.cropping(to:rect),let color=CGColorSpace(name:CGColorSpace.sRGB) else{throw AppError.invalid("تعذّر تجهيز الصورة.","Image preprocessing failed.")}
        var rgba=[UInt8](repeating:0,count:224*224*4)
        let ok=rgba.withUnsafeMutableBytes { bytes -> Bool in
            guard let context=CGContext(data:bytes.baseAddress,width:224,height:224,bitsPerComponent:8,bytesPerRow:224*4,space:color,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else{return false}
            let scale=224/max(1,Double(min(crop.width,crop.height))),w=Double(crop.width)*scale,h=Double(crop.height)*scale
            context.interpolationQuality = .high
            // CG bitmap rows are read top-first for ONNX's image coordinate system.
            context.translateBy(x:0,y:224);context.scaleBy(x:1,y:-1)
            context.draw(crop,in:CGRect(x:(224-w)/2,y:(224-h)/2,width:w,height:h));return true
        }
        guard ok else{throw AppError.invalid("تعذّر تجهيز الصورة.","Image preprocessing failed.")}
        let mean:[Float]=[0.48145466,0.4578275,0.40821073],std:[Float]=[0.26862954,0.26130258,0.27577711]
        var input=[Float](repeating:0,count:3*224*224)
        for channel in 0..<3 {for i in 0..<224*224 {input[channel*224*224+i]=(Float(rgba[i*4+channel])/255-mean[channel])/std[channel]}}
        return input
    }
    private func run(_ path:URL,image:CGImage,boxes:[PhotoBox],labels:[PhotoLabel],progress:@Sendable(String)->Void) throws -> [PhotoRegion] {
        let env=try ORTEnv(loggingLevel:.warning),options=try ORTSessionOptions();try options.setIntraOpNumThreads(2);try options.setGraphOptimizationLevel(.all)
        let session=try ORTSession(env:env,modelPath:path.path,sessionOptions:options)
        var output:[PhotoRegion]=[]
        for (index,box) in boxes.enumerated() {
            try Task.checkCancellation();progress("analyze:\(index+1)/\(boxes.count)")
            let floats=try pixels(image,box:box)
            let buffer=floats.withUnsafeBytes {NSMutableData(bytes:$0.baseAddress!,length:$0.count)}
            let value=try ORTValue(tensorData:buffer,elementType:.float,shape:[1,3,224,224])
            let values=try session.run(withInputs:["pixel_values":value],outputNames:["image_embeds"],runOptions:nil)
            guard let tensor=values["image_embeds"] else {throw AppError.invalid("مخرجات النموذج غير مكتملة.","The model output is incomplete.")}
            let bytes=try tensor.tensorData();guard bytes.length==512*MemoryLayout<Float>.size else{throw AppError.invalid("أبعاد النموذج غير صحيحة.","Unexpected model dimensions.")}
            let vector=Array(UnsafeBufferPointer(start:bytes.bytes.assumingMemoryBound(to:Float.self),count:512))
            output.append(try PhotoMeal.rank(vector,labels:labels,box:box))
        };return output
    }
    func analyze(_ data:Data,description:String,progress:@escaping @Sendable (String)->Void) async throws -> PhotoResult {
        guard !analyzing else{throw AppError.invalid("انتظر انتهاء التحليل الحالي.","Wait for the current analysis.")};analyzing=true;defer{analyzing=false}
        guard let url=Bundle.main.url(forResource:"food-labels",withExtension:"json") else{throw AppError.invalid("ملف التحليل مفقود.","Image labels are missing.")}
        let labels=try JSONDecoder().decode(PhotoLabels.self,from:Data(contentsOf:url)),foods=try foods(),image=try Self.image(data)
        let global=try await model(labels.modelId,revision:labels.revision,hash:globalHash,progress:progress)
        let detail=try await model(labels.regional.modelId,revision:labels.regional.revision,hash:detailHash,progress:progress)
        try Task.checkCancellation()
        var regions=try run(global,image:image,boxes:[PhotoBox(x:0,y:0,width:1,height:1)],labels:labels.labels,progress:progress)
        var boxes:[PhotoBox]=[PhotoBox(x:0,y:0,width:1,height:1)]
        for y in [0.0,0.275,0.55] {for x in [0.0,0.275,0.55] {boxes.append(PhotoBox(x:x,y:y,width:0.45,height:0.45))}}
        for y in [0.0,0.5] {for x in [0.0,0.5] {boxes.append(PhotoBox(x:x,y:y,width:0.5,height:0.5))}}
        regions += try run(detail,image:image,boxes:boxes,labels:labels.regional.labels,progress:progress)
        return try PhotoMeal.estimate(regions,description:description,foods:foods)
    }
}
