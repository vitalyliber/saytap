# Saytap

A macOS menu bar app: select English text, tap ⌥ twice (or ⌃⌥T), hear it and see its translation in a pop-up. Swift, AppKit, one Swift package, no Xcode project. README.md is the install guide for people; this file is for working on the code.

## Commands

- `./build.sh` builds a release, bundles the Phonon model and the icon, installs `~/Applications/Saytap.app`, signs it with the "Saytap Signing" certificate and restarts it.
- `swift test` runs the unit tests in `Tests/SaytapTests` (Swift Testing). They need no network and no system dictionary: Oxford entries and Google responses are saved in `Tests/SaytapTests/Fixtures`.
- `swift build -c release --arch arm64` only compiles.
- `./dmg.sh [app]` packs an app into `build/Saytap.dmg` with a drag-to-Applications window; `DEVELOPER_ID` and `NOTARY_PROFILE` sign and notarize it.

## Where things are

| File | What |
|---|---|
| `Sources/main.swift` | Startup only. Keep it that way: globals in `main.swift` are initialised by its top-level code, which doesn't run under `swift test`, so constants live in `Settings.swift`. |
| `Settings.swift` | Every constant: languages, speeds, voices, hotkeys, sizes, file names. |
| `Translator.swift` | The order of sources: Oxford dictionary → saved translation from the history → Google → Apple Translation. Sources are parameters, so tests replace them. |
| `BilingualDictionary.swift` | Private DictionaryServices calls and the Oxford XHTML parser (`translation(from:)`). |
| `History.swift`, `HistoryWindow.swift` | `history.json` in `~/Library/Application Support/Saytap`, and its window. |
| `Speaker.swift` | Phonon through the `PhononTTS` Swift package, on the Neural Engine. |
| `Popup.swift`, `PopupStyle.swift` | The pop-up and its styles (Playful, Standard, Minimal, Formal). |
| `TranslationPackDownloader.swift` | Shows macOS's dialog that downloads a language for Apple Translation. |
| `AppDelegate.swift` | The menu, settings and the look-up flow. |
| `icon.swift` (next to `build.sh`, not in the package) | Draws the app icon; `build.sh` turns it into `build/AppIcon.icns` whenever the script changes. It fills Apple's icon grid, so macOS 26 shows it as is, not inside a grey squircle. |

## Gotchas

- **Searching a dictionary that isn't downloaded downloads it.** `DCSCopyRecordsForSearchString` starts a background download of the whole dictionary. A probe that searched every dictionary once downloaded 46 of them (1.2 GB). Never search dictionaries in a loop; `DCSDictionaryGetURL` returning nil is how the app tells one isn't downloaded.
- **`XMLNode`'s relative XPath (`.//text()`) also returns text after the node.** The Oxford parser walks the tree by hand; keep it that way.
- **Accessibility permission follows the code signature.** The installed app is signed with a self-signed certificate trusted system-wide, so rebuilds keep the permission. Ad-hoc signed copies have none when started with `open`, but run straight from a terminal they borrow the terminal's.
- **The pop-up's corners.** `NSVisualEffectView` ignores its layer's corner radius and draws square corners; it needs a `maskImage`. `PopupBackground` paints its layer in `viewDidMoveToWindow`, because `updateLayer` isn't called for it. Call `invalidateShadow()` after resizing the panel.
- **Animations run on Core Animation, not window or timer animations.** macOS slows and batches the timers of a background app like this one, so `NSWindow` alpha animations start late, and timers used to sample them all fire at once. The pop-up's fades in and out are `CAAnimation`s on the content view's layer. Nothing else moves: a bouncing or sliding window and animated speaker waves were both tried and found distracting.
- **Phonon.** The Core ML model ships in the app's Resources and is copied to `Application Support/Saytap/Models` on first launch, where Core ML compiles it (about 6 s, once; later loads take 0.5 s). Switching voices costs about 0.5 s. The Core ML model has no speed condition, so speed is a time-pitch unit at playback. The package version in `Package.swift` and the model in `build.sh` (`PHONON_VERSION`, with the archive's SHA-256) must match.
- **`LanguageAvailability`** can report a downloaded language as `.supported` right after the translation daemon starts; the menu checks again on every open.
- **Google** is the public `gtx` endpoint with a 1 s timeout; HTTP 429 means it's limiting requests, and Apple Translation takes over.
- **The installer window is laid out by Finder over AppleScript** and saved in the image's `.DS_Store`. Finder keeps the window's size and bars from the first opening but drops view options (icon size, background) set then, and writes the `.DS_Store` a few seconds after the window closes. So `dmg.sh` sets the window on the first opening, the view options on a second one, and waits for both records before detaching. It also drops `.VolumeIcon.icns` while laying out the window, so the disk icon goes on last.
- **No screenshots.** The terminal has no Screen Recording permission. Use the recipes below.

## Checking changes in the running app

- **Protect the person's data first.** Copy `~/Library/Application Support/Saytap/history.json` and run `defaults export local.vitaly.saytap <file>` before testing; restore both afterwards. Every look-up, including `--show <text>`, is recorded in the history, and menu clicks change settings.
- **`--show <text>`** looks the text up at launch: `open ~/Applications/Saytap.app --args --show "harbour"`.
- **An instrumented copy.** Copy `Package.swift`, `Package.resolved` and `Sources` to a scratch folder, rename the product (`SaytapTest`), add `NSLog` lines or a scripted sequence in `applicationDidFinishLaunching`, and build. Put the binary into a copy of the installed app (it needs the bundled model), set `CFBundleExecutable` to the new name, sign it ad hoc (`codesign --force --sign -`) and run the binary directly to read its log.
- **A picture of the pop-up.** In the copy, about 0.4 s after `show`, render `panel.contentView!.layer` into a `CGContext` with `layer.render(in:)` and save a PNG. `cacheDisplay` misses layer backgrounds, and neither captures the blur behind the Standard style.
- **The menu** can be read and clicked with AppleScript: `tell application "System Events" to tell process "Saytap"` → `menu bar item 1 of menu bar 2`.
- **Windows on screen**, such as the pop-up or a system dialog, are listed by `CGWindowListCopyWindowInfo`; the owner name is "Saytap".
