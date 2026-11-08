# Word Popup

A menu bar app for macOS. Select a word in any app and tap **⌥ Option twice** (or press **⌃⌥T**): the app reads it aloud and shows its translation in a floating pop-up next to the cursor.

The double tap only counts when ⌥ is pressed on its own: two quick taps, each shorter than 0.3 s and less than 0.4 s apart. Any key, click or other modifier in between cancels it, so ⌥ shortcuts keep working.

- Click 🔊 in the pop-up to hear the word again.
- Every translated word is saved with its translation. The menu bar icon → **History…** lists them, newest first, with how many times each was looked up. Long phrases and translations wrap, so they show in full. Click a word to hear it, search by word or translation, and press ⌫ to delete the selected words. A word looked up again moves to the top, and a phrase looked up again reuses its saved translation instead of asking Google; delete it from the history to translate it afresh. The history is kept in `~/Library/Application Support/Word Popup/history.json` and never leaves the Mac.
- Pick the voice speed in the menu bar icon → **Speed**: 0.25, 0.5, 0.75, Normal, 1.25, 1.5, 1.75 or 2, as on YouTube. The app remembers it.
- The pop-up closes on Esc, on a click anywhere else, or after 10 seconds. It stays open while the cursor is over it.
- Pick the language to translate into in the menu bar icon → **Translate to**. By default it's the first language other than English in System Settings → General → Language & Region. Languages whose dictionary isn't downloaded are marked; choosing one starts the download (about a minute) and offers macOS's dialog to download it for offline translation. Until they're there, the menu shows what's missing under Translate to.
- Words and phrasal verbs come from the bilingual Oxford dictionary that ships with macOS: translations grouped by part of speech, with transcription. It works offline and answers instantly.
- Phrases and sentences the dictionary doesn't have go to Google Translate's public endpoint, so that text is sent to Google. When Google fails, limits requests or doesn't answer within a second, the app translates on the Mac with Apple's Translation, if the language is downloaded for it.
- Pick the voice in the menu bar icon → **Voice**: Harper, Hadley, Everly, Maeve, Edwin or Spencer.
- Pick how the pop-up looks in the menu bar icon → **Style**: Playful, Standard, Minimal or Formal. Choosing one shows the last looked-up word in it.
- Turn on the menu bar icon → **Launch at Login** to start the app with the Mac.
- Speech comes from [Phonon](https://gradium.ai/phonon), Gradium's open text-to-speech model, built into the app with its Swift package and Core ML model. It runs on the Mac's Neural Engine, so the text isn't sent anywhere, and a word starts playing in about 20 ms. Switching the voice adds about half a second to the next word. If speech fails, the app beeps and the pop-up says why.
- Without the Accessibility permission, the shortcut shows a pop-up saying so, and the menu offers **Allow Accessibility…**.

## Install

No Apple Developer account is needed. The app is built on the Mac it runs on and signed with a self-signed certificate made in step 2.

These steps are written so an AI coding agent can run them in Terminal. Steps marked **👤** need the person at the Mac: a password, a dialog or a switch in System Settings. An agent should stop there, tell the person exactly what to do, and wait for them to confirm.

Run the steps in order. If the Accessibility permission is granted before the certificate is trusted (step 3), macOS pins it to that one build, and the app keeps asking for it. See Troubleshooting.

### 1. Requirements

- macOS 26 or later, on Apple silicon. Intel Macs aren't supported: Phonon's Core ML model runs on the Neural Engine.
- Swift 6 or later, with its package manager. Check with `swift --version`. If it's missing, run `xcode-select --install`. **👤** The person confirms the installer dialog.
- About 650 MB of disk space: the app with its model (170 MB), the model copy Core ML compiles on first launch (310 MB), and the build's downloads.

Run the remaining commands from this folder (the one with `build.sh`).

### 2. Create the signing certificate

Do this once per Mac. Skip it if this command already prints a certificate:

```bash
security find-certificate -c "Word Popup Signing"
```

Create the certificate and import it into the login keychain. The temporary folder is removed afterwards, so the private key exists only in the keychain:

```bash
CERT_DIR="$(mktemp -d)"
/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -subj "/CN=Word Popup Signing" \
  -addext "keyUsage=critical,digitalSignature" \
  -addext "extendedKeyUsage=critical,codeSigning" \
  -addext "basicConstraints=critical,CA:false" \
  -keyout "$CERT_DIR/key.pem" -out "$CERT_DIR/cert.pem"
/usr/bin/openssl pkcs12 -export -inkey "$CERT_DIR/key.pem" -in "$CERT_DIR/cert.pem" \
  -name "Word Popup Signing" -out "$CERT_DIR/signing.p12" -passout pass:word-popup
security import "$CERT_DIR/signing.p12" -k ~/Library/Keychains/login.keychain-db -P word-popup -T /usr/bin/codesign
rm -rf "$CERT_DIR"
```

### 3. Trust the certificate system-wide

**👤** This needs the person's admin password. macOS checks app permissions as root, so trusting the certificate only in the login keychain is not enough. The trust covers code signing only.

```bash
security find-certificate -c "Word Popup Signing" -p > /tmp/word-popup-signing.pem
sudo security add-trusted-cert -d -r trustRoot -p codeSign -k /Library/Keychains/System.keychain /tmp/word-popup-signing.pem
rm /tmp/word-popup-signing.pem
```

Check it. The output should list "Word Popup Signing" with Code Signing:

```bash
security dump-trust-settings -d | grep -A3 "Word Popup Signing"
```

### 4. Build and install

```bash
./build.sh
```

This builds the app with Swift Package Manager, installs `~/Applications/Word Popup.app` and starts it. A speech bubble icon appears in the menu bar. The first build also fetches Phonon's Swift package (about 50 MB) and its Core ML model (about 140 MB, kept in `build/` for later builds).

On the first launch the app compiles the model for this Mac, which takes several seconds; a word looked up meanwhile is spoken once it's done, and the pop-up says the voice is being prepared. Later launches load it in about half a second.

**👤** On the first build macOS asks: *"codesign wants to sign using key 'Word Popup Signing' in your keychain."* The person enters their login password and clicks **Always Allow**. Until then the build waits.

### 5. Allow Accessibility

**👤** On first launch the app asks for Accessibility access, which it needs to read the selected text. The person clicks **Open System Settings** and switches **Word Popup** on in Privacy & Security → Accessibility.

Then restart the app and check that it has the permission. The log must say `Accessibility trusted: 1`:

```bash
pkill -x WordPopup; open --stderr /tmp/word-popup.log ~/Applications/Word\ Popup.app; sleep 2; cat /tmp/word-popup.log
```

### 6. Pick the language

**👤** The person opens the menu bar icon → **Translate to** and picks their language, unless the ticked one is already right. If its dictionary isn't downloaded, the app starts the download. If the language isn't downloaded for Apple's offline translation, macOS shows a dialog with a download button next to it; the person clicks it, then **Done**. Either can be done later from the menu, where anything missing appears under Translate to.

### 7. Try it

Select a word in any app, for example in Notes, and tap ⌥ twice. You should hear the word and see the pop-up.

To start the app at login, turn on the menu bar icon → **Launch at Login**.

## Troubleshooting

- **The app asks for Accessibility on every launch, or the log says `Accessibility trusted: 0` although Word Popup is switched on.** The saved entry belongs to an older build. Removing and re-adding the app in System Settings doesn't always replace it. Reset it, then switch it on again from the app's prompt:

  ```bash
  tccutil reset Accessibility local.vitaly.word-popup; pkill -x WordPopup; open ~/Applications/Word\ Popup.app
  ```

  If that doesn't help, check that step 3 was done.

- **`./build.sh` stops at `codesign` and waits.** The keychain dialog from step 4 is open, possibly behind other windows.
- **A double tap of ⌥ only beeps, with no pop-up.** The app found no selected text. Some apps don't expose the selection; the app then copies it with ⌘C, which only works if the app supports copying.
- **The pop-up appears, but there's a beep instead of the word.** Phonon failed to load or speak, and the pop-up's last line says why. For the full error, start the app with its log, look up a word, and read the line starting with `Phonon failed`:

  ```bash
  pkill -x WordPopup; open --stderr /tmp/word-popup.log ~/Applications/Word\ Popup.app; sleep 10; cat /tmp/word-popup.log
  ```

  If the compiled model is broken, delete `~/Library/Application Support/Word Popup/Models` and restart the app: it copies and compiles the model again.

## Uninstall

```bash
pkill -x WordPopup; rm -rf ~/Applications/Word\ Popup.app
tccutil reset Accessibility local.vitaly.word-popup
defaults delete local.vitaly.word-popup
rm -rf ~/Library/Application\ Support/Word\ Popup
```

**👤** Then delete the **Word Popup Signing** certificate in Keychain Access, from both the login and the System keychain.

## Development

`./build.sh` rebuilds, reinstalls and restarts the app. The certificate keeps the Accessibility permission across rebuilds.

`swift test` runs the unit tests: the dictionary and Google parsers, the order of translation sources, the history and the language menu. CLAUDE.md describes the code, its pitfalls and how to check changes in the running app.

Phonon's version is pinned twice: the Swift package in `Package.swift` and the Core ML model in `build.sh` (`PHONON_VERSION`, with the archive's SHA-256). Update them together.

Settings are constants at the top of `Sources/main.swift`: voices (`PHONON_VOICES`; the model's 37 voices are in `build/Models-*/voices`), hotkey, double-tap modifier and timing, speed presets, pop-up lifetime and size. Rebuild after you change them.
