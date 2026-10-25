// screenshot-sync — fast mode of mac-screenshots-to-photos.
// The moment a screenshot lands on disk: put the image on the clipboard,
// then import it into Photos and delete the source file.
// Watches the folder with FSEvents (no polling delay) instead of Folder Actions.
import AppKit
import CoreServices
import Photos

let version = "0.2.0"
let pngTail: [UInt8] = [0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82] // end of the IEND chunk

// MARK: Logging

let logFmt: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
    return f
}()

func log(_ s: String) {
    FileHandle.standardError.write("\(logFmt.string(from: Date())) \(s)\n".data(using: .utf8)!)
}

// MARK: Screenshot folder

func screenshotDir() -> String {
    if CommandLine.arguments.count > 1, !CommandLine.arguments[1].hasPrefix("-") {
        return (CommandLine.arguments[1] as NSString).expandingTildeInPath
    }
    let d = UserDefaults(suiteName: "com.apple.screencapture")
    let loc = d?.string(forKey: "location-screenshot") ?? d?.string(forKey: "location") ?? "~/Desktop"
    return (loc as NSString).expandingTildeInPath
}

// macOS writes a hidden ".Screenshot…" temp file first, then renames it.
func isScreenshot(_ path: String) -> Bool {
    let name = (path as NSString).lastPathComponent
    return !name.hasPrefix(".") && name.lowercased().hasSuffix(".png")
}

/// Returns the PNG only once it is complete (ends with IEND), else nil.
func readCompletePNG(_ path: String) -> Data? {
    guard let data = FileManager.default.contents(atPath: path), data.count > pngTail.count else { return nil }
    return Array(data.suffix(pngTail.count)) == pngTail ? data : nil
}

// MARK: Handling

var handled = Set<String>()
let photosQueue = DispatchQueue(label: "photos")

func handle(_ path: String, attempt: Int = 0) {
    guard FileManager.default.fileExists(atPath: path) else { handled.remove(path); return }
    guard let data = readCompletePNG(path) else {
        if attempt < 100 { // wait up to 5 s for the write to finish
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { handle(path, attempt: attempt + 1) }
        } else {
            log("gave up (file never completed): \(path)")
            handled.remove(path)
        }
        return
    }
    // Image bytes, not a file URL: still pastes after the file is deleted,
    // and survives remote-desktop clipboard sync to another Mac.
    let pb = NSPasteboard.general
    pb.clearContents()
    pb.setData(data, forType: .png)
    log("clipboard \(data.count / 1024)KB: \((path as NSString).lastPathComponent)")
    photosQueue.async { importToPhotos(path) }
}

func importToPhotos(_ path: String) {
    let url = URL(fileURLWithPath: path)
    let sem = DispatchSemaphore(value: 0)
    var err: Error?
    // PhotoKit always copies into the library, so there is no reference-mode dead-link risk.
    PHPhotoLibrary.shared().performChanges({
        let opt = PHAssetResourceCreationOptions()
        opt.originalFilename = url.lastPathComponent
        PHAssetCreationRequest.forAsset().addResource(with: .photo, fileURL: url, options: opt)
    }) { ok, e in
        if !ok { err = e ?? NSError(domain: "screenshot-sync", code: 1) }
        sem.signal()
    }
    sem.wait()
    if let err {
        log("Photos import failed, file kept: \(url.lastPathComponent) — \(err.localizedDescription)")
    } else {
        try? FileManager.default.removeItem(at: url) // reached only after a successful import
        log("imported + deleted: \(url.lastPathComponent)")
    }
    DispatchQueue.main.async { handled.remove(path) }
}

// MARK: FSEvents

func watch(_ dir: String) {
    let cb: FSEventStreamCallback = { _, _, n, paths, flags, _ in
        let list = unsafeBitCast(paths, to: NSArray.self) as! [String]
        for i in 0..<n {
            let f = Int(flags[i])
            let p = list[i]
            guard f & kFSEventStreamEventFlagItemIsFile != 0,
                  f & (kFSEventStreamEventFlagItemCreated | kFSEventStreamEventFlagItemRenamed | kFSEventStreamEventFlagItemModified) != 0,
                  isScreenshot(p), !handled.contains(p),
                  FileManager.default.fileExists(atPath: p) else { continue }
            // Only new files: leave anything that was already there at startup alone.
            if let c = (try? FileManager.default.attributesOfItem(atPath: p))?[.creationDate] as? Date,
               c < startTime { continue }
            handled.insert(p)
            handle(p)
        }
    }
    let flags = UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer | kFSEventStreamCreateFlagUseCFTypes)
    guard let stream = FSEventStreamCreate(nil, cb, nil, [dir] as CFArray,
                                           FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.0, flags) else {
        log("cannot create FSEvents stream: \(dir)"); exit(1)
    }
    FSEventStreamSetDispatchQueue(stream, .main)
    FSEventStreamStart(stream)
}

// MARK: Entry

if CommandLine.arguments.contains("--version") { print(version); exit(0) }

let startTime = Date().addingTimeInterval(-2)
let dir = screenshotDir()
try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

PHPhotoLibrary.requestAuthorization(for: .addOnly) { s in
    log(s == .authorized ? "Photos access: allowed"
                         : "Photos access: NOT allowed (\(s.rawValue)) — clipboard only, files kept")
}

watch(dir)
log("screenshot-sync \(version) watching: \(dir)")
NSApplication.shared.setActivationPolicy(.prohibited)
NSApplication.shared.run()
