import Darwin
import Foundation

/// The full paths of the native images (libraries and the executable) mapped into this process.
public enum NativeImages {
    /// The images, one entry per file, in load order (the executable first).
    public static func enumerate() -> [String] {
        let count = _dyld_image_count()
        var images: [String] = []
        var seen = Set<String>()
        images.reserveCapacity(Int(count))
        for i in 0..<count {
            if let ptr = _dyld_get_image_name(i) {
                let path = String(cString: ptr)
                if !path.isEmpty && seen.insert(path).inserted {
                    images.append(path)
                }
            }
        }
        return images
    }
}
