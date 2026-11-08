# Releasing a signed build

This makes `Saytap.dmg`, an installer anyone can download and open: the app is signed with a Developer ID, the disk image is notarized by Apple, and the window inside shows where to drag the app. Building from source with a self-signed certificate, as in the README, isn't needed then.

It has to be done by a member of the Apple Developer Program, on their Mac.

## Requirements

- A Mac with Apple silicon, macOS 26 or later and Swift 6. Check with `swift --version`; if it's missing, run `xcode-select --install`.
- A **Developer ID Application** certificate in the login keychain. If there isn't one: Xcode → Settings → Accounts → Manage Certificates → **+** → Developer ID Application. An "Apple Development" certificate won't do: it only runs on your own devices.

## 1. Get the code

```bash
git clone https://github.com/vitalyliber/saytap.git
cd saytap
```

## 2. Find the certificate's name

```bash
security find-identity -v -p codesigning | grep "Developer ID Application"
```

The name is the part in quotes, for example `Developer ID Application: Jane Appleseed (ABCDE12345)`; the code in brackets is your Team ID. Steps 4 and 5 use the name.

## 3. Save the notarization credentials

Do this once per Mac. Create an app-specific password at [account.apple.com](https://account.apple.com) → Sign-In and Security → App-Specific Passwords, then save it in the keychain under the profile name `saytap-notary`. The command asks for the password:

```bash
xcrun notarytool store-credentials saytap-notary --apple-id YOUR_APPLE_ID --team-id YOUR_TEAM_ID
```

## 4. Build and sign the app

```bash
DEVELOPER_ID="Developer ID Application: Jane Appleseed (ABCDE12345)" ./build.sh
```

With `DEVELOPER_ID` set, `build.sh` signs with that certificate, the hardened runtime and a timestamp, which notarization requires, instead of the self-signed "Saytap Signing" certificate. The first build downloads about 200 MB. The app is installed in `~/Applications/Saytap.app` and started; you can quit it.

Check the signature:

```bash
codesign --verify --deep --strict --verbose=2 ~/Applications/Saytap.app
```

## 5. Make, sign and notarize the installer

```bash
DEVELOPER_ID="Developer ID Application: Jane Appleseed (ABCDE12345)" NOTARY_PROFILE=saytap-notary ./dmg.sh
```

- The first time, macOS asks whether Terminal may control Finder: click **Allow**. `dmg.sh` lays out the installer window through Finder.
- The script closes Finder's windows, then opens and closes the installer window. Leave Finder alone for about 15 seconds.
- If it stops with "Finder saved the window at … instead of 640x400", run it again.
- Apple's notarization takes a few minutes. The script ends with "The staple and validate action worked!" and "Made build/Saytap.dmg".

## 6. Check it

```bash
spctl -a -t open --context context:primary-signature -vv build/Saytap.dmg
```

The output must say `accepted` and `source=Notarized Developer ID`.

## 7. Publish it

Attach the disk image to a GitHub release whose tag matches the app's version (`CFBundleShortVersionString` in `Info.plist`):

```bash
gh release create v1.0 build/Saytap.dmg --title "Saytap 1.0" --notes "…"
```

The latest release's file is always at `https://github.com/vitalyliber/saytap/releases/latest/download/Saytap.dmg`, as long as it's named `Saytap.dmg`.

## When notarization fails

If `notarytool` reports `Invalid`, read Apple's log for that submission, using the id it printed:

```bash
xcrun notarytool log SUBMISSION_ID --keychain-profile saytap-notary
```
