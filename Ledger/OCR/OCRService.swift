import Foundation
import UIKit
import Vision

struct OCRLine {
    let text: String
    /// Vision 坐标系下的高度，用来判断哪一行是「大字金额」
    let height: CGFloat
}

enum OCRService {
    /// 本地识别，不上传图片。completion 在主线程回调。
    static func recognize(_ image: UIImage, completion: @escaping ([OCRLine]) -> Void) {
        guard let cgImage = image.cgImage else {
            completion([])
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["zh-Hans", "en-US"]
            // 金额不能被"纠错"，否则 10.00 可能变成 1000
            request.usesLanguageCorrection = false

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                DispatchQueue.main.async { completion([]) }
                return
            }

            let observations = request.results ?? []
            let lines: [OCRLine] = observations.compactMap { observation in
                guard let candidate = observation.topCandidates(1).first else { return nil }
                return OCRLine(text: candidate.string, height: observation.boundingBox.height)
            }

            DispatchQueue.main.async { completion(lines) }
        }
    }
}
