# Architecture

A native macOS runtime for *TSUKIHIME -A piece of blue glass moon-*. It reads the user's own
extracted PS4 data (`CUSA47999`: `eboot.bin`, `image/`, `data/`, `sce_sys/`) directly and
interprets the game's 549 HuneX scripts. No conversion step, no emulator, no game data in the
repository.

Swift 6 package, macOS 14+, no third-party Swift dependencies.

## Layers

| target | depends on | holds |
|---|---|---|
| `TsukiCore` | — | bytes, memory mapping, display list, input, errors, maths, text, concurrency |
| `TsukiEngine` | `TsukiCore` | data contracts and the deterministic engine: VM, stage, text layout, sound model, saves, game host |
| `TsukiData` | `TsukiCore`, `TsukiEngine` | game-folder access, containers, images, eboot tables; implements the engine's data contracts |
| `TsukiMedia` | `TsukiCore`, `TsukiEngine` | ATRAC9 (FFmpeg via dlopen) and HE-VAG decoding, mixer, movie playback |
| `TsukiRender` | `TsukiCore`, `TsukiEngine` | Metal renderer for display lists, textures and screen effects |
| `TsukiUI` | `TsukiCore`, `TsukiEngine`, `TsukiData` | title, config, save/load, backlog, gallery, flowchart screens |
| `TsukiApp` | all of the above | AppKit shell: window, input, main loop, services (executable `Tsukihime`) |
| `TsukiCLI` | `TsukiCore`, `TsukiEngine`, `TsukiData` | headless verification and exploration (executable `tsuki`) |
| `TsukiLauncher` | `TsukiCore`, `TsukiData` | SwiftUI launcher (executable `TsukihimeLauncher`) |

`TsukiEngine` owns the game vocabulary (`Language`, `Picture`, `ScriptImage`, audio banks, UI sets)
and the protocols the data layer fulfils (`GameData`, `EbootTables`, `AudioDecoder`), so the engine
never imports the data layer. `TsukiData` imports `TsukiEngine`, never the reverse. The application
wires a `GameData` implementation into the engine host.

## Rules

- **Bytes are views.** `ByteSpan` wraps an array, shared storage or a memory mapping and slices
  in O(1). Archives up to 24 GB are mapped, never read whole. `ByteWindow` is the writable
  counterpart for fixed-size state records.
- **Value types first.** Decoded data, tables and state are structs. Classes are reserved for
  mapped files, caches and shared services.
- **Explicit encoding.** Save/system/history state is written and read field by field against the
  documented PS4 byte layouts. No generated accessor descriptors and no reflection.
- **Errors carry meaning.** Throw `TsukiError.format` for malformed bytes, `.unsupported` for a
  build the port does not understand, `.io` and `.bounds` for the rest.
- **Float32 where the engine uses float.** Layout, motion and compositing maths stay in `Float`
  so results match the PS4 bit for bit.
- **No incidental abstractions.** Protocols exist only where a module boundary needs them
  (`GameData`, `EbootTables`, `AudioDecoder`, the media sinks). No dev-only data source, no golden
  fixtures in shipping code. Synthetic builders in tests cover parsers.

## Platform mapping

| C# / Windows route | Swift / macOS |
|---|---|
| SDL3 window, input, gamepads | AppKit window; NSEvent; GameController |
| OpenGL 3.3 + GLSL | Metal + Metal Shading Language |
| FFmpeg.AutoGen (ATRAC9, H.264, AAC) | FFmpeg dylibs via `dlopen` for ATRAC9; AVFoundation/VideoToolbox for movies |
| WPF launcher | SwiftUI launcher |
| .NET file mapping | `mmap` (`MappedFile`) |

FFmpeg is needed only for ATRAC9, which macOS has no system decoder for. The program loads the
installed FFmpeg dylibs at run time and reports clearly when they are missing.

## Verification

- `swift test` — parsers on synthetic byte fixtures, deterministic engine units.
- `tsuki verify <folder>` — build identity, archive structure and table reads on the user's copy.
- `tsuki explore <folder>` — walks every script choice headless.

The C# implementation in the parent checkout is the behavioural reference; `docs/formats/` is the
format reference.
