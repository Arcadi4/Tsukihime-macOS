import Foundation
import TsukiApp

var args: AppArgs?
var error: String?
let argv = Array(CommandLine.arguments.dropFirst())
if !AppArgs.tryParse(argv, result: &args, error: &error) {
    if let error = error {
        if let data = "\(error)\n".data(using: .utf8) {
            FileHandle.standardError.write(data)
        }
    }
    if let data = "\(AppArgs.usage)\n".data(using: .utf8) {
        FileHandle.standardError.write(data)
    }
    exit(64)
}

guard let appArgs = args else {
    exit(64)
}

let code = GameApp.run(args: appArgs)
exit(Int32(code))
