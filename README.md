# Slim4K - Hardware-Accelerated 10x 4K Video Compressor

**Slim4K** is a high-performance cross-platform Flutter application built to ingest massive 4K camera streams (typically 100+ Mbps) and compress them to **1/10th the file size (~10 Mbps)** while preserving visual 4K fidelity.

---

## 🚀 Key Features

1. **Hardware-Accelerated Encoding (60–120+ FPS)**:
   - **Android**: `hevc_mediacodec` (Qualcomm Snapdragon / MediaTek VPU).
   - **macOS**: `hevc_videotoolbox` (Apple Silicon M1/M2/M3/M4 & Intel T2).
   - **Windows**: `hevc_nvenc` (NVIDIA) / `hevc_qsv` (Intel) / `hevc_amf` (AMD).
   - **Linux**: `hevc_vaapi` / `hevc_nvenc`.
   - **CPU Fallback**: `libx265` with multi-threaded fast CRF encoding.
2. **10x Size Reduction**:
   - Reduces a 10 GB camera 4K video file down to **~1.0 GB** in just 1–3 minutes.
3. **Interactive Quality Inspector**:
   - Built-in video player with a **"Press & Hold to Compare"** feature to visually inspect the original vs compressed video side-by-side.
4. **Compression Presets**:
   - **10x Slim (Recommended)**: 10 Mbps HEVC VBR (90% space saved, visually lossless).
   - **15x Ultra Slim**: 6.5 Mbps HEVC VBR (93% space saved).
   - **20x Extreme Slim**: 4.5 Mbps HEVC VBR (95% space saved).
   - **Custom Bitrate**: Adjustable slider from 2 Mbps to 30 Mbps.
5. **Real-Time Progress Dashboard**:
   - Live FPS, transcoding speed multiplier (e.g., `2.5x Real-Time`), and accurate ETA countdown.

---

## 🔒 Permissions & Platform Entitlements (All Configured)

### Android (`android/app/src/main/AndroidManifest.xml`)
- `READ_EXTERNAL_STORAGE` & `WRITE_EXTERNAL_STORAGE`
- `READ_MEDIA_VIDEO` (Android 13+)
- `MANAGE_EXTERNAL_STORAGE` (Full file system access for 4K video imports)
- `WAKE_LOCK` (Prevents CPU sleep during heavy video transcoding)
- `FOREGROUND_SERVICE` (Ensures background batch tasks finish uninterrupted)
- `requestLegacyExternalStorage="true"`

### macOS (`macos/Runner/DebugProfile.entitlements` & `Release.entitlements`)
- `com.apple.security.files.user-selected.read-write` (User-selected file access)
- `com.apple.security.files.downloads.read-write` (Saving compressed output files)
- `com.apple.security.network.client` & `server` (Local socket and media streaming)

---

## 🛠️ How to Run

### Desktop (macOS / Windows / Linux)
```bash
cd slim4k
flutter run -d macos    # On macOS
flutter run -d windows  # On Windows
flutter run -d linux    # On Linux
```

### Android
```bash
cd slim4k
flutter run -d android
```

### Build Production Releases
```bash
# Build Android APK
flutter build apk --release

# Build macOS App
flutter build macos --release
```
