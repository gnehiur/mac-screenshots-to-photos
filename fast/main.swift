// screenshot-sync — fast mode of mac-screenshots-to-photos.
// The moment a screenshot lands on disk: put the image on the clipboard,
// then import it into Photos and delete the source file.
// Watches the folder with FSEvents (no polling delay) instead of Folder Actions.
// Optional: --sound <file> plays an extra cue per screenshot, e.g. to tell two Macs apart.
import AppKit
import AVFoundation
import CoreServices
import Photos

let version = "0.3.3"
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

func option(_ name: String) -> String? {
    let a = CommandLine.arguments
    guard let i = a.firstIndex(of: name), i + 1 < a.count else { return nil }
    return (a[i + 1] as NSString).expandingTildeInPath
}

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

// MARK: Sound cue

// Fired as early as possible. macOS writes a screenshot in three steps
// (measured with tools/fsevents-probe):
//   +0 ms    create  "..Screenshot ….png-XXXXXX"   (atomic-write temp, being written)
//   +180 ms  rename  ".Screenshot ….png"
//   +182 ms  rename  "Screenshot ….png"            (final)
// The temp file appears only ~10 ms after the shutter starts (coreaudiod log),
// so firing right there lands the cue on the shutter's attack while the speaker is
// still powering up from idle — its start gets swallowed. --sound-delay <ms>
// (default 140) pushes it to ~150 ms after the shutter, where it is heard whole.
// Played on its own queue so audio can never hold up the clipboard.
var cue: AVAudioPlayer?
var cueDelay = 0.14
var cued = Set<String>()   // final file names already cued (main queue)
let audioQueue = DispatchQueue(label: "audio", qos: .userInteractive)

func loadCue(_ path: String) {
    guard let p = try? AVAudioPlayer(contentsOf: URL(fileURLWithPath: path)) else {
        log("cannot load sound: \(path)"); return
    }
    cue = p
    // Warm up CoreAudio once at launch: the first play in a process costs
    // ~2-3 s of HAL / plug-in setup, which would otherwise hit the first screenshot.
    audioQueue.async {
        p.volume = 0
        p.play()
        Thread.sleep(forTimeInterval: 0.3)
        p.stop()
        p.volume = 1
        p.currentTime = 0
        p.prepareToPlay()
    }
    log("sound cue: \(path), \(Int(cueDelay * 1000)) ms after detection")
}

func playCue(for name: String, early: Bool) {
    guard cue != nil, !cued.contains(name) else { return }
    cued.insert(name)
    audioQueue.asyncAfter(deadline: .now() + cueDelay) {
        guard let p = cue else { return }
        p.stop()            // rapid screenshots: restart instead of overlapping
        p.currentTime = 0
        p.play()
    }
    log("cue (\(early ? "temp file" : "final file")): \(name)")
}

/// "..Screenshot x.png-nIhk4R" or ".Screenshot x.png" -> "Screenshot x.png"; nil if not a screenshot temp.
func finalName(ofTemp name: String) -> String? {
    guard name.hasPrefix(".") else { return nil }
    var n = Substring(name)
    while n.hasPrefix(".") { n = n.dropFirst() }
    if let r = n.range(of: ".png", options: [.caseInsensitive, .backwards]) { n = n[..<r.upperBound] } else { return nil }
    return n.isEmpty ? nil : String(n)
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
    DispatchQueue.main.async {
        handled.remove(path)
        cued.remove((path as NSString).lastPathComponent)
    }
}

// MARK: FSEvents

func watch(_ dir: String) {
    let cb: FSEventStreamCallback = { _, _, n, paths, flags, _ in
        let list = unsafeBitCast(paths, to: NSArray.self) as! [String]
        for i in 0..<n {
            let f = Int(flags[i])
            let p = list[i]
            let name = (p as NSString).lastPathComponent
            if let final = finalName(ofTemp: name) {
                if f & kFSEventStreamEventFlagItemCreated != 0, FileManager.default.fileExists(atPath: p) {
                    playCue(for: final, early: true)
                }
                continue
            }
            guard f & kFSEventStreamEventFlagItemIsFile != 0,
                  f & (kFSEventStreamEventFlagItemCreated | kFSEventStreamEventFlagItemRenamed | kFSEventStreamEventFlagItemModified) != 0,
                  isScreenshot(p), !handled.contains(p),
                  FileManager.default.fileExists(atPath: p) else { continue }
            // Only new files: leave anything that was already there at startup alone.
            if let c = (try? FileManager.default.attributesOfItem(atPath: p))?[.creationDate] as? Date,
               c < startTime { continue }
            handled.insert(p)
            playCue(for: name, early: false)   // only if the temp file was missed
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

if let ms = option("--sound-delay").flatMap(Double.init) { cueDelay = max(0, ms) / 1000 }
if let path = option("--sound") { loadCue(path) }

watch(dir)
log("screenshot-sync \(version) watching: \(dir)")
NSApplication.shared.setActivationPolicy(.prohibited)
NSApplication.shared.run()
