import AVFoundation
import CoreGraphics

/// Stills out of a screen recording, for the OCR that names and indexes it.
///
/// Two by default: a beat in, and the middle. A recording's first frame is
/// often the desktop before the thing happened, and its last is the cursor
/// heading for the stop button; the middle is the point of it. Synchronous on
/// purpose — everything that reads a capture's text is — so these are the
/// older AVFoundation calls, which the 13 floor still ships.
public enum Frames {
    public static func stills(of url: URL, at fractions: [Double] = [0.1, 0.5]) -> [CGImage] {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        let duration = CMTimeGetSeconds(asset.duration)
        guard duration.isFinite, duration > 0 else { return [] }
        return fractions.compactMap { fraction in
            let seconds = max(0, min(duration * fraction, duration - 0.05))
            let time = CMTime(seconds: seconds, preferredTimescale: 600)
            return try? generator.copyCGImage(at: time, actualTime: nil)
        }
    }
}
