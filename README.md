# Tsukihime macOS Native Port

<p align="center"><img width="520" alt="Tsukihime logo" src="assets/branding/tsukihime-logo.png" /></p>

A native macOS port of *TSUKIHIME -A piece of blue glass moon-* written entirely in **Swift**.
It plays your own extracted PS4 game files (`CUSA47999`) directly on macOS without emulation, conversion, or virtual machines.

## Architecture

- **100% Swift 6**: Modular architecture comprising `TsukiCore`, `TsukiEngine`, `TsukiData`, `TsukiRender`, `TsukiMedia`, `TsukiUi`, `TsukiPlatform`, and `TsukiApp`.
- **Metal Compositor**: Hardware-accelerated 2D projection and compositor written directly in Metal Shading Language (MSL), matching PS4 draw commands, alpha masking, blur, and colour-grading filters bit-for-bit.
- **Native macOS Audio & Video**: Low-latency audio mixing with `AVAudioEngine`, native HE-VAG ADPCM hardware decoding, and `AVFoundation` / `VideoToolbox` video streaming for H.264 chapter cards and opening movies.
- **Native AppKit & SwiftUI**: Pure AppKit window and input pipeline supporting Apple Silicon ProMotion displays, Retina rendering, trackpad gestures, keyboard shortcuts, and Apple GameController framework. A dedicated SwiftUI launcher (`TsukihimeLauncher`) provides settings, folder picking, and save management.

## Requirements

- macOS 14.0 (Sonoma) or later.
- Apple Silicon (M1/M2/M3/M4) or Intel Mac with Metal support.
- Extracted PS4 game folder (`CUSA47999`) containing `eboot.bin`, `image/`, `data/`, and `sce_sys/` (~44 GB).
- Xcode 16+ or Swift 6 toolchain.

## Building and Running

### Build from Source

```bash
# Clone the repository and enter the native worktree
cd Tsukihime-macOS-native

# Build all targets in release mode
swift build -c release

# Run the SwiftUI Launcher
./.build/release/TsukihimeLauncher

# Or run the game directly
./.build/release/Tsukihime --game /path/to/CUSA47999

# Run the developer / inspection CLI
./.build/release/tsuki verify --game /path/to/CUSA47999
```

### Running Tests

```bash
swift test
```

## Features

- **Languages**: Japanese, English, Simplified Chinese, and Traditional Chinese.
- **Audio & Video**: Original voices, high-efficiency VAG sound effects, BGM, and movies with zero latency.
- **Saves**: 140 save slots with rendered thumbnails, auto-saves, quick-saves, and seamless rollback / history rewind.
- **Flowchart & Extras**: Interactive flowchart, bad end guidance, and full CG / Music / Movie gallery.
- **macOS Native Integration**: Retina scaling, full-screen switching, button prompt customization, and text hooker clipboard integration.

## License

Source code is licensed under the Mozilla Public License, v. 2.0 (**MPL-2.0**). See [LICENSE](LICENSE).

*This is an unofficial fan program, unaffiliated with TYPE-MOON, Aniplex, HuneX, or Sony. TSUKIHIME and its assets belong to their respective rights holders.*
