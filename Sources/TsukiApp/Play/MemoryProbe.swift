import Darwin
import Foundation

/// Memory diagnostics for the soak runs.
public enum MemoryProbe {
    /// The figures of the process right now, in MiB.
    public static func line() -> String {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / 4)
        let kerr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }

        let residentMiB = kerr == KERN_SUCCESS ? info.resident_size >> 20 : 0
        let virtualMiB = kerr == KERN_SUCCESS ? info.virtual_size >> 20 : 0
        return "mem: resident \(residentMiB) MiB, virtual \(virtualMiB) MiB"
    }
}
