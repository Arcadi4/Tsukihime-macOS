import Foundation
import TsukiCore
import TsukiEngine

/// Finds the image MZPs inside a container the way `oracle.image.census` does
/// (`tsuki.sniff.classify_mzp`): a container that is an image is reported, any other container is
/// searched through its nested sections. An allpac3 entry is a set whose sections are the pictures;
/// a font file is a list of pages whose sections hold the pictures.
public enum PictureWalker {
    /// Calls `visit` for every image MZP in `container` in section order, with the section path from
    /// `container` to the image (empty when the container itself is the image).
    public static func walk(
        _ container: MzpContainer, _ visit: ([Int], MzpContainer) -> Void
    ) throws {
        try walk(container, path: [], visit)
    }

    private static func walk(
        _ container: MzpContainer, path: [Int], _ visit: ([Int], MzpContainer) -> Void
    ) throws {
        if ImageMzp.isImage(container) {
            visit(path, container)
            return
        }

        for i in 0..<container.count {
            if container.isNested(i) {
                try walk(container.child(i), path: path + [i], visit)
            }
        }
    }

    /// The label the oracle gives a picture: `source#entry` and `/section` for every nested level
    /// (`allpac0#12`, `allpac3#5/17`, `ft_en.mrg#4/1`).
    public static func label(_ source: String, entry: Int, path: [Int]) -> String {
        var text = "\(source)#\(entry)"
        text.reserveCapacity(text.count + 12)
        for p in path {
            text += "/\(p)"
        }
        return text
    }
}
