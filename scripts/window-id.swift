// Prints the CGWindowID of the largest normal on-screen window of a process, for `screencapture -l`.
// Usage: swift scripts/window-id.swift <pid | owner name>
// Window numbers, owners and bounds are readable without Screen Recording permission.
import CoreGraphics
import Foundation

let arguments = CommandLine.arguments
guard arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: window-id.swift <pid | owner name>\n".utf8))
    exit(2)
}
let target = arguments[1]
let targetPID = Int(target)

let windows = (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]) ?? []

func area(_ window: [String: Any]) -> CGFloat {
    guard let dictionary = window[kCGWindowBounds as String] as? NSDictionary,
          let bounds = CGRect(dictionaryRepresentation: dictionary as CFDictionary)
    else { return 0 }
    return bounds.width * bounds.height
}

let matches = windows.filter { window in
    guard (window[kCGWindowLayer as String] as? Int) == 0 else { return false }
    if let targetPID {
        return (window[kCGWindowOwnerPID as String] as? Int) == targetPID
    }
    return (window[kCGWindowOwnerName as String] as? String) == target
}

guard let best = matches.max(by: { area($0) < area($1) }),
      let number = best[kCGWindowNumber as String] as? Int
else {
    FileHandle.standardError.write(Data("No on-screen window for \(target)\n".utf8))
    exit(1)
}
print(number)
