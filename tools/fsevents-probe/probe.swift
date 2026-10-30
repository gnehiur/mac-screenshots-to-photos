// fsevents-probe — log every file event whose name looks like a screenshot,
// with millisecond timestamps and decoded flags, to see how macOS writes it.
// Usage: probe <dir> [<dir> ...]
import CoreServices
import Foundation

let fmt = DateFormatter(); fmt.dateFormat = "HH:mm:ss.SSS"
let names: [(Int, String)] = [
    (kFSEventStreamEventFlagItemCreated, "Created"), (kFSEventStreamEventFlagItemRemoved, "Removed"),
    (kFSEventStreamEventFlagItemRenamed, "Renamed"), (kFSEventStreamEventFlagItemModified, "Modified"),
    (kFSEventStreamEventFlagItemInodeMetaMod, "InodeMeta"), (kFSEventStreamEventFlagItemChangeOwner, "Owner"),
    (kFSEventStreamEventFlagItemXattrMod, "Xattr"), (kFSEventStreamEventFlagItemFinderInfoMod, "FinderInfo"),
    (kFSEventStreamEventFlagItemIsFile, "File"), (kFSEventStreamEventFlagItemIsDir, "Dir"),
    (kFSEventStreamEventFlagItemCloned, "Cloned"), (kFSEventStreamEventFlagMustScanSubDirs, "MustScan"),
]
let pattern = try! NSRegularExpression(pattern: "截屏|Screenshot|Screen Shot|screencapture|\\.png$", options: [.caseInsensitive])

let cb: FSEventStreamCallback = { _, _, n, paths, flags, ids in
    let list = unsafeBitCast(paths, to: NSArray.self) as! [String]
    for i in 0..<n {
        let p = list[i]
        guard pattern.firstMatch(in: p, range: NSRange(p.startIndex..., in: p)) != nil else { continue }
        let f = Int(flags[i])
        let tags = names.filter { f & $0.0 != 0 }.map(\.1).joined(separator: ",")
        let size = (try? FileManager.default.attributesOfItem(atPath: p))?[.size] as? Int
        print("\(fmt.string(from: Date())) id=\(ids[i]) [\(tags)] size=\(size.map(String.init) ?? "-") \(p)")
        fflush(stdout)
    }
}
let dirs = Array(CommandLine.arguments.dropFirst())
let flags = UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer | kFSEventStreamCreateFlagUseCFTypes)
let s = FSEventStreamCreate(nil, cb, nil, dirs as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.0, flags)!
FSEventStreamSetDispatchQueue(s, .main)
FSEventStreamStart(s)
print("\(fmt.string(from: Date())) watching \(dirs)"); fflush(stdout)
dispatchMain()
