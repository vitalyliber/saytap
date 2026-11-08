# Word Popup

A menu bar app for macOS. Select a word in any app and tap **⌥ Option twice** (or press **⌃⌥T**): the app reads it aloud and shows its translation in a floating pop-up next to the cursor.

The double tap only counts when ⌥ is pressed on its own: two quick taps, each shorter than 0.3 s and less than 0.4 s apart. Any key, click or other modifier in between cancels it, so ⌥ shortcuts keep working.

- Click 🔊 in the pop-up to hear the word again.
- Every translated word is saved with its translation. The menu bar icon → **History…** lists them, newest first, with how many times each was looked up. Click a word to hear it, search by word or translation, and press ⌫ to delete the selected words. A word looked up again moves to the top. The history is kept in `~/Library/Application Support/Word Popup/history.json` and never leaves the Mac.
- Pick the voice speed in the menu bar icon → **Speed**: Very slow, Slow, Normal, Fast or Very fast. The app remembers it.
- The pop-up closes on Esc, on a click anywhere else, or after 10 seconds. It stays open while the cursor is over it.
- Pick the language to translate into in the menu bar icon → **Translate to**. By default it's the first language other than English in System Settings → General → Language & Region.
- Words and phrasal verbs come from the bilingual Oxford dictionary that ships with macOS: translations grouped by part of speech, with transcription. It works offline and answers instantly. If the dictionary for your language isn't downloaded yet, open Dictionary.app → Settings and tick it.
- Phrases and sentences the dictionary doesn't have go to Google Translate's public endpoint, so that text is sent to Google. When Google fails or limits requests, the app translates on the Mac with Apple's Translation, if the language is downloaded in System Settings → General → Language & Region → Translation Languages.
- Pick the voice in the menu bar icon → **Voice**: Harper, Hadley, Everly, Maeve, Edwin or Spencer.
- Speech comes from [Phonon](https://gradium.ai/phonon), Gradium's open text-to-speech model, through its `ptts` command (step 4 of Install). It runs on the Mac, so the text isn't sent anywhere. A word takes about 0.2 s before it plays. Without `ptts` the pop-up shows the command to install it; if `ptts` fails, the app beeps.

## Install

No Apple Developer account is needed. The app is built on the Mac it runs on and signed with a self-signed certificate made in step 2.

These steps are written so an AI coding agent can run them in Terminal. Steps marked **👤** need the person at the Mac: a password, a dialog or a switch in System Settings. An agent should stop there, tell the person exactly what to do, and wait for them to confirm.

Run the steps in order. If the Accessibility permission is granted before the certificate is trusted (step 3), macOS pins it to that one build, and the app keeps asking for it. See Troubleshooting.

### 1. Requirements

- macOS 26 or later, on Apple silicon or Intel. An Intel Mac needs a CPU with AVX2, which Phonon requires.
- [Homebrew](https://brew.sh), to install Phonon.
- The Swift compiler. Check with `swiftc --version`. If it's missing, run `xcode-select --install`. **👤** The person confirms the installer dialog.

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

### 4. Install Phonon

Install Gradium's `ptts` command. The app finds it in `/opt/homebrew/bin` or `/usr/local/bin`:

```bash
brew install gradium-ai/tap/ptts
```

Download the model (about 100 MB, cached in `~/.cache/huggingface`) and the menu's voices once, so the first look-up doesn't wait for them:

```bash
for voice in Harper Hadley Everly Maeve Edwin Spencer; do ptts --lang en --voice "$voice" -o /tmp/phonon-check.wav -- "Hello"; done; rm /tmp/phonon-check.wav
```

### 5. Build and install

```bash
./build.sh
```

This compiles `Sources/main.swift`, installs `~/Applications/Word Popup.app` and starts the app. A speech bubble icon appears in the menu bar.

**👤** On the first build macOS asks: *"codesign wants to sign using key 'Word Popup Signing' in your keychain."* The person enters their login password and clicks **Always Allow**. Until then the build waits.

### 6. Allow Accessibility

**👤** On first launch the app asks for Accessibility access, which it needs to read the selected text. The person clicks **Open System Settings** and switches **Word Popup** on in Privacy & Security → Accessibility.

Then restart the app and check that it has the permission. The log must say `Accessibility trusted: 1`:

```bash
pkill -x WordPopup; open --stderr /tmp/word-popup.log ~/Applications/Word\ Popup.app; sleep 2; cat /tmp/word-popup.log
```

### 7. Optional: offline translation

**👤** For the best word translations, open Dictionary.app → Settings and tick the dictionary between English and the person's language, for example "Oxford Russian Dictionary". macOS downloads it.

**👤** To translate phrases when Google Translate is unavailable, add the language in System Settings → General → Language & Region → Translation Languages.

### 8. Try it

Select a word in any app, for example in Notes, and tap ⌥ twice. You should hear the word and see the pop-up.

To start the app at login, add `~/Applications/Word Popup.app` in System Settings → General → Login Items.

## Troubleshooting

- **The app asks for Accessibility on every launch, or the log says `Accessibility trusted: 0` although Word Popup is switched on.** The saved entry belongs to an older build. Removing and re-adding the app in System Settings doesn't always replace it. Reset it, then switch it on again from the app's prompt:

  ```bash
  tccutil reset Accessibility local.vitaly.word-popup; pkill -x WordPopup; open ~/Applications/Word\ Popup.app
  ```

  If that doesn't help, check that step 3 was done.

- **`./build.sh` stops at `codesign` and waits.** The keychain dialog from step 5 is open, possibly behind other windows.
- **A double tap of ⌥ only beeps, with no pop-up.** The app found no selected text. Some apps don't expose the selection; the app then copies it with ⌘C, which only works if the app supports copying.
- **The pop-up appears, but there's a beep instead of the word.** `ptts` failed. Run it by hand to see the error: `ptts --lang en --voice Harper -o /tmp/check.wav -- "hello"`. A voice that isn't downloaded yet needs an internet connection the first time.

## Uninstall

```bash
pkill -x WordPopup; rm -rf ~/Applications/Word\ Popup.app
tccutil reset Accessibility local.vitaly.word-popup
defaults delete local.vitaly.word-popup
rm -rf ~/Library/Application\ Support/Word\ Popup
brew uninstall ptts
rm -rf ~/.cache/huggingface/hub/models--gradium--phonon-31m-en ~/.cache/huggingface/hub/models--gradium--phonon-voices
```

**👤** Then delete the **Word Popup Signing** certificate in Keychain Access, from both the login and the System keychain.

## Development

`./build.sh` rebuilds, reinstalls and restarts the app. The certificate keeps the Accessibility permission across rebuilds.

Settings are constants at the top of `Sources/main.swift`: voices (`PHONON_VOICES`; `ptts --list-voices` lists them all), hotkey, double-tap modifier and timing, speed presets, pop-up lifetime and size. Rebuild after you change them.
