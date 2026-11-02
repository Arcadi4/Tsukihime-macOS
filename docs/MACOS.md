# macOS

The SDL player runs natively on macOS as a self-contained `.app`. The separate WPF launcher is Windows only: the
player has its own game folder picker on first launch and its settings in the pause menu, as on Linux.

## Requirements

- macOS 12 (Monterey) or newer on Apple silicon. An Intel build is a build-time choice (`TSUKI_RID=osx-x64`,
  `docs/MACOS.md` below); the shipped player is `arm64`.
- Apple's OpenGL 4.1 over Metal, which every Mac since macOS 10.9 has. The game asks for a 3.3 core context and
  gets 4.1.
- FFmpeg 9 with ATRAC9, H.264 and AAC, unless the bundle ships its own libraries: `brew install ffmpeg`
  (`/opt/homebrew/lib`, or `/usr/local/lib` on an Intel Mac). The Homebrew build is GPL; it is loaded at run time
  and not redistributed, and `docs/THIRD_PARTY.md` names it.

The game folder is your own extracted `CUSA47999` (about 44 GB). Nothing in it is modified; saves and settings live
in the profile below.

## Run a release

Open `Tsukihime.app`. On first launch it asks for the extracted game folder and remembers it. The app is ad-hoc
signed unless the release says otherwise, so a copy downloaded from another machine needs one of:

- right-click the app in Finder and choose **Open**, then **Open** again; or
- `xattr -dr com.apple.quarantine /path/to/Tsukihime.app` in Terminal.

A notarized build has neither step: Gatekeeper accepts it as it is.

## Build and run

Install the .NET 10 SDK (`brew install --cask dotnet-sdk` also works), then from the repository root:

```sh
tools/setup/publish_macos.sh                 # artifacts/macos-arm64/Tsukihime.app
open artifacts/macos-arm64/Tsukihime.app
```

The script accepts an output folder, then extra `dotnet publish` options. It builds a self-contained bundle (the
.NET runtime and SDL are inside), copies the icon, docs and licences into it, and signs it.

| variable | meaning |
|---|---|
| `TSUKI_RID` | `osx-arm64` (default) or `osx-x64` |
| `TSUKI_CODESIGN_IDENTITY` | a Developer ID Application identity; unset is an ad-hoc signature |
| `TSUKI_NOTARY_PROFILE` | a `xcrun notarytool store-credentials` profile; the script then zips, submits, waits and staples |

Bundled FFmpeg: put `libavutil.61.dylib`, `libswresample.7.dylib`, `libavcodec.63.dylib` and
`libavformat.63.dylib` (an LGPL-only FFmpeg 9 build) in `third_party/ffmpeg/macos/lib/`, and the script copies them
into `Contents/Frameworks/` with their licence texts. The player looks there first, then at Homebrew.

Running from source instead:

```sh
dotnet run --project src/Tsuki.App -- --game /path/to/CUSA47999
dotnet run --project src/Tsuki.App -- --smoke          # SDL, GL 3.3, shaders, audio, loop: 13 checks
```

`TSUKI_GAME_DIR` names the game folder instead of `--game`. The macOS solution is `src/Tsuki.macOS.slnx` (the
Windows launcher is not in it).

## Profile, saves and screenshots

The profile is `~/Library/Application Support/Tsuki` (the Mac home for `ApplicationData`, not the Linux
`~/.config`). `--save-dir /path/to/profile` picks another folder, including one shared with a Linux or Windows
install. Settings are `settings.ini` in the profile; the crash log is written there when possible. Close the player
before copying either file.

Screenshots (`F12`) go to `~/Pictures`. `F11` toggles fullscreen and `Escape` opens the pause menu; `Cmd+Q` quits
through the app menu like any Mac program.

Existing port saves (`save.dat` from the Windows build or a PS4/shadowPS4 export) can be copied into the profile
while the player is closed. The Windows launcher's backup browser and PS4 import UI have no macOS counterpart.

## Text output for dictionary tools

The Windows GDI text hook has no macOS equivalent: LunaHook and Textractor are Windows programs. Use the player's
**Config > System > Text Hooker Output** with the clipboard or the local WebSocket feed, and point the dictionary
tool at it. Both are in the pause menu and in `settings.ini`.

## Checks without game files

```sh
dotnet test tests/Tsuki.Tests.Synthetic     # engine, data readers, VM, UI state: no game data needed
tools/setup/publish_macos.sh && open artifacts/macos-arm64/Tsukihime.app
```

The synthetic suite passes on macOS. Its skips are the ones no Mac can run: the Windows COM shortcut tests, the
tests pinned to the Linux profile and Pictures conventions (`XDG_CONFIG_HOME`, `~/.config`, which macOS does not
use), and the retail-data tests unless `TSUKI_GAME_DIR` names your extracted folder.

The GPU render suite (`tests/Tsuki.Tests.Render`) is not run on macOS: SDL's video subsystem must be initialised
from the process's main thread, and the VSTest host runs tests on a worker thread, so each test fails with
`SDL_InitSubSystem(Video): No available video device` (a plain main-thread `SDL_Init` from the same shell works).
The platform check on macOS is `--smoke`, which creates its window, GL context and shaders on the main thread.

## Notes

- Rendering is Apple's OpenGL 4.1 driver (Metal underneath). The compositor compiles GLSL 3.30 core; GLSL ES 3.00
  shaders are not part of a desktop core context and the smoke reports them as not offered rather than failed.
- Decode workers follow the performance cores (`hw.perflevel0.physicalcpu`), at most 8.
- The bundle icon is `assets/icon/tsukihime.icns`, drawn by `tools/setup/make_icns.py` from the same drawing as the
  Windows `.ico`; the bundle build copies it, so regenerate it after changing that drawing.
- Memory-mapped archive pages are dropped with `madvise(MADV_DONTNEED)`, the macOS counterpart of the Windows
  working-set trim.
- The app is not sandboxed (it must read a 44 GB folder the player chooses) and is not offered on the Mac App Store.
