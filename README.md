# Word Popup

A menu bar app for macOS. Select a word in any app and press **⌃⌥T**: the app reads it aloud and shows the Russian translation in a floating pop-up next to the cursor.

- Click 🔊 in the pop-up to hear the word again.
- The pop-up closes on Esc, on a click anywhere else, or after 10 seconds. It stays open while the cursor is over it.
- Translations come from Google Translate's public endpoint, so the selected text is sent to Google.
- Speech uses the best installed English voice: Premium or Enhanced first, then en-US. Install more voices in System Settings → Accessibility → Spoken Content → System voice → Manage Voices.

## Build

```bash
./build.sh
```

This compiles `Sources/main.swift`, installs `~/Applications/Word Popup.app` and starts the app.

## Permissions

The first time you run the app, allow it in **System Settings → Privacy & Security → Accessibility**. The app needs that permission to read the selected text. At launch it logs `Accessibility trusted: 0/1`.

`build.sh` signs the app with the self-signed **Word Popup Signing** certificate from the login keychain, so the permission survives rebuilds. macOS checks permissions as root, so the certificate must be trusted for Code Signing system-wide, not only in your login keychain:

```bash
sudo security add-trusted-cert -d -r trustRoot -p codeSign -k /Library/Keychains/System.keychain cert.pem
```

If the app keeps asking for the permission, re-adding it in System Settings may keep a stale entry. Reset it instead, then switch it on from the app's prompt:

```bash
tccutil reset Accessibility local.vitaly.word-popup
```

## Settings

Settings are constants at the top of `Sources/main.swift`: target language, hotkey, pop-up lifetime and size. Rebuild after you change them.

To start the app at login, add it in System Settings → General → Login Items.
