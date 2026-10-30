#!/usr/bin/env python3
"""Build the screenshot-sound picker: pick candidate macOS sounds, filter out
ones the system / iPhone already use a lot, convert to m4a for the browser,
measure pitch (spectral centroid), write sounds.js for index.html.

Audio files are Apple's; they are converted locally into sounds/ (git-ignored).
"""
import json, os, subprocess, wave
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "sounds")
WAV = os.path.join(HERE, "sounds", "wav")
TONES = "/System/Library/PrivateFrameworks/ToneLibrary.framework/Versions/A/Resources/AlertTones"
SHUTTER = "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/system/Screen Capture.aif"
MAX_SEC = 2.0

# name -> why it is excluded (already heard often elsewhere)
COMMON = {
    "Basso": "系统和很多 App 的报错声",
    "Tink": "老版 macOS 默认提示音，很多 App 还在用",
    "Glass": "很多 App 的「完成」提示音",
    "Hero": "Xcode 等开发工具的成功提示",
    "Pop": "你自己的 fireworks 工具在用",
    "Tri-Tone": "iPhone 经典短信音",
    "Ding": "旧版 iPhone 新邮件音",
    "Swoosh": "邮件「已发送」音",
    "Tweet": "旧版推特发推音",
    "Note": "iPhone 旧默认短信音",
    "Chord": "iPhone 日历 / 提醒常用",
    "Rebound": "iPhone 现默认短信音",
}

def sources():
    for d, ext in (("/System/Library/Sounds", ".aiff"), (f"{TONES}/Classic", ".m4r"),
                   (f"{TONES}/Modern", ".m4r"), (f"{TONES}/EncoreInfinitum", ".caf")):
        group = {"/System/Library/Sounds": "Mac 提示音"}.get(d, "iPhone 提示音（" + os.path.basename(d) + "）")
        for f in sorted(os.listdir(d)):
            if f.endswith(ext):
                name = f[: -len(ext)].replace("-EncoreInfinitum", "")
                yield name, os.path.join(d, f), group

def duration(path):
    out = subprocess.run(["afinfo", path], capture_output=True, text=True).stdout
    for line in out.splitlines():
        if "estimated duration" in line:
            return float(line.split()[2])
    return 0.0

def centroid(path, key):
    w = os.path.join(WAV, key + ".wav")
    subprocess.run(["afconvert", "-f", "WAVE", "-d", "LEI16@22050", "-c", "1", path, w], check=True)
    with wave.open(w) as f:
        x = np.frombuffer(f.readframes(f.getnframes()), dtype=np.int16).astype(np.float64)
        sr = f.getframerate()
    mag = np.abs(np.fft.rfft(x * np.hanning(len(x))))
    hz = np.fft.rfftfreq(len(x), 1 / sr)
    band = (hz >= 60) & (hz <= 8000)
    mag, hz = mag[band], hz[band]
    peak = float(hz[np.argmax(mag)])
    return float((hz * mag).sum() / mag.sum()), peak

def m4a(path, key):
    dst = os.path.join(OUT, key + ".m4a")
    subprocess.run(["afconvert", "-f", "m4af", "-d", "aac", "-b", "192000", path, dst], check=True)
    return "sounds/" + key + ".m4a"

def main():
    os.makedirs(WAV, exist_ok=True)
    keep, dropped = [], []
    for name, path, group in sources():
        sec = duration(path)
        key = name.replace(" ", "_")
        why = COMMON.get(name) or (f"太长（{sec:.1f} 秒）" if sec > MAX_SEC else None)
        item = {"name": name, "key": key, "path": path, "group": group, "sec": round(sec, 2)}
        if why:
            dropped.append({**item, "why": why})
            continue
        c, p = centroid(path, key)
        keep.append({**item, "hz": round(c), "peak": round(p), "src": m4a(path, key)})
    keep.sort(key=lambda s: s["hz"])
    mid = float(np.median([s["hz"] for s in keep]))
    for s in keep:
        s["band"] = "low" if s["hz"] < mid else "high"
    data = {"shutter": m4a(SHUTTER, "_shutter"), "split": round(mid), "keep": keep, "dropped": dropped}
    with open(os.path.join(HERE, "sounds.js"), "w") as f:
        f.write("window.SOUNDS = " + json.dumps(data, ensure_ascii=False, indent=1) + ";\n")
    print(f"keep {len(keep)}, dropped {len(dropped)}, split at {mid:.0f} Hz")

main()
