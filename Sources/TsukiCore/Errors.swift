import Foundation

/// Every failure the port reports. Malformed game data, missing files and unsupported builds are
/// distinct cases so callers can decide between "this dump is damaged" and "this build is not
/// supported".
public enum TsukiError: Error, CustomStringConvertible, Equatable {
    /// Bytes that do not follow the documented layout.
    case format(String)
    /// A known-shape file whose build or variant the port does not support.
    case unsupported(String)
    /// A read outside the bounds of a buffer or file.
    case bounds(String)
    /// The file system failed.
    case io(String)
    /// An operation is invalid in the current engine state.
    case state(String)

    public var description: String {
        switch self {
        case let .format(message): return message
        case let .unsupported(message): return message
        case let .bounds(message): return message
        case let .io(message): return message
        case let .state(message): return message
        }
    }
}
