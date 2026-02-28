# Release Guide

KeyMagic is distributed directly (outside the Mac App Store) via Developer ID
signing and Apple Notarization. This document covers every path from local dev
builds to a fully notarized DMG ready for users to download.

---

## Prerequisites

### Tools

```bash
make setup          # installs xcodegen, swift-format, xcbeautify via Homebrew
brew install create-dmg   # needed for DMG packaging (not included in setup)
```

### Apple Developer Account

You need a paid Apple Developer Program membership (USD 99/yr). Log in at
[developer.apple.com](https://developer.apple.com).

---

## Signing Architecture

| Configuration | Signing Style | Identity | Used For |
|---|---|---|---|
| Debug | Automatic | Apple Development | Daily dev, `make build` |
| Release (local) | Manual (CLI override) | Developer ID Application | `make archive` / `make dist` |
| Release (CI) | Manual (CLI override) | Developer ID Application | GitHub Actions |

`project.yml` always stores `Apple Development` as the base identity.
The `Developer ID Application` identity is injected at build time via
`xcodebuild` command-line overrides — this is necessary because Xcode's
Automatic signing mode and Developer ID are mutually exclusive.

### iCloud Entitlements

The iCloud sync entitlements (`com.apple.developer.icloud-container-identifiers`
and `com.apple.developer.ubiquity-container-identifiers`) are currently
**commented out** in `Resources/KeyMagic.entitlements`. Developer ID + iCloud
requires a provisioning profile explicitly created in the Developer Portal with
both the App ID and iCloud container registered. Until that profile exists,
enabling those entitlements will cause `xcodebuild archive` to fail.

To re-enable iCloud for distribution, see the [iCloud section](#re-enabling-icloud-sync) below.

---

## Build Scenarios

### 1. Local Debug Build (daily development)

No signing setup required. Xcode manages everything automatically.

```bash
make build      # Debug build via xcodebuild
make run        # Debug build + launch app
open KeyMagic.xcodeproj   # or open in Xcode and press ⌘R
```

### 2. Local Release — Full Distribution Build

Produces a notarized, stapled DMG ready to hand to users.

```bash
make dist
```

Pipeline: `archive` → `export` → `notarize` → `staple` → `dmg`

Output: `build/KeyMagic.dmg`

Requires the one-time Keychain profile setup described below.

Individual steps can also be run in isolation:

```bash
make archive    # .xcarchive signed with Developer ID
make export     # export .xcarchive → .app (uses Resources/exportOptions.plist)
make notarize   # submit to Apple Notary Service, staple ticket
make dmg        # package .app into DMG
```

### 3. Xcode Archive (GUI alternative to `make dist`)

If you prefer not to use the terminal for releases:

1. Product → Archive
2. Distribute App → Developer ID → Upload → Automatically notarize
3. Export the stapled `.app`
4. Run `create-dmg` manually or use `make dmg` (assumes `.app` is at `build/export/KeyMagic.app`)

### 4. CI — GitHub Actions

Triggered automatically on `v*` tag push or via manual `workflow_dispatch`.
See `.github/workflows/build.yml`.

```bash
git tag v1.0.0
git push origin v1.0.0
```

The DMG artifact is uploaded to the Actions run page (retained 30 days) and
can be downloaded from Actions → the run → Artifacts.

---

## One-Time Local Setup

### Step 1 — Developer ID Application Certificate

1. Open Xcode → Settings → Accounts → select your Apple ID → Manage Certificates
2. Click `+` → Developer ID Application
3. Xcode creates and installs the certificate in your login Keychain

Verify it is present:

```bash
security find-identity -v -p codesigning | grep "Developer ID Application"
```

### Step 2 — Notarization Keychain Profile

Apple Notarization requires an App-specific password (your main Apple ID
password cannot be used).

**Get an App-specific password:**

1. Go to [appleid.apple.com](https://appleid.apple.com)
2. Sign In → Sign-In and Security → App-Specific Passwords → Generate
3. Name it `KeyMagic Notarization`, copy the generated password (`xxxx-xxxx-xxxx-xxxx`)

**Store it in Keychain:**

```bash
xcrun notarytool store-credentials "KeyMagic" \
  --apple-id  you@example.com \
  --team-id   3FKXTCP8JU \
  --password  "xxxx-xxxx-xxxx-xxxx"
```

The profile name `KeyMagic` matches `NOTARIZE_PROFILE` in the Makefile.
To use a different profile name:

```bash
make dist NOTARIZE_PROFILE=MyProfile
```

---

## CI Setup — GitHub Secrets

Navigate to: **GitHub repo → Settings → Secrets and variables → Actions → New repository secret**

| Secret | Description | How to get it |
|---|---|---|
| `APPLE_CERTIFICATE_BASE64` | Developer ID Application certificate as Base64 | See below |
| `APPLE_CERTIFICATE_PASSWORD` | Password set when exporting the `.p12` | Set when exporting |
| `APPLE_TEAM_ID` | Apple Developer Team ID | `3FKXTCP8JU` — or check [developer.apple.com/account](https://developer.apple.com/account) → Membership |
| `APPLE_ID` | Apple ID email for notarytool | Your Apple ID login email |
| `APPLE_APP_PASSWORD` | App-specific password for notarytool | Same as Step 2 above (`xxxx-xxxx-xxxx-xxxx`) |

### Exporting the certificate as Base64

1. Open **Keychain Access**
2. Find `Developer ID Application: <your name>` under My Certificates
3. Right-click → Export → save as `DeveloperID.p12`, set a strong password
4. Base64-encode it:

```bash
base64 -i DeveloperID.p12 | pbcopy   # copies to clipboard, paste into GitHub Secret
```

5. Delete the local `.p12` file after uploading — it is sensitive.

---

## Re-enabling iCloud Sync

When ready to ship iCloud sync in a notarized build:

1. **Register App ID** at [developer.apple.com](https://developer.apple.com) →
   Certificates, Identifiers & Profiles → Identifiers → `com.keymagic.app`
   → enable iCloud capability

2. **Create iCloud container** `iCloud.com.keymagic.app` under Identifiers → iCloud Containers

3. **Associate container** with the App ID under the iCloud capability settings

4. **Create a provisioning profile**: Profiles → `+` → Developer ID → select App ID
   `com.keymagic.app` → select your Developer ID certificate → download and
   double-click to install

5. **Uncomment the entitlements** in `Resources/KeyMagic.entitlements`:

```xml
<key>com.apple.developer.icloud-container-identifiers</key>
<array>
    <string>iCloud.com.keymagic.app</string>
</array>
<key>com.apple.developer.ubiquity-container-identifiers</key>
<array>
    <string>iCloud.com.keymagic.app</string>
</array>
```

6. **Update `Makefile` archive target** to reference the profile by name or UUID:

```makefile
PROVISIONING_PROFILE_SPECIFIER="KeyMagic Developer ID"
```

7. **Update `Resources/exportOptions.plist`** to add the profile mapping:

```xml
<key>provisioningProfiles</key>
<dict>
    <key>com.keymagic.app</key>
    <string>KeyMagic Developer ID</string>
</dict>
```

8. **Update CI**: store the `.mobileprovision` file as an additional secret
   (`APPLE_PROVISIONING_PROFILE_BASE64`) and add a step to install it before
   the archive step (decode with `base64 --decode`, copy to
   `~/Library/MobileDevice/Provisioning Profiles/`).

---

## Verification

After `make dist` or `make export`, confirm the signing is correct:

```bash
# Verify Developer ID chain
codesign -dv --verbose=4 build/export/KeyMagic.app

# Verify notarization staple
xcrun stapler validate build/export/KeyMagic.app

# Check Gatekeeper would pass
spctl --assess --type exec --verbose build/export/KeyMagic.app
```

Expected output for `codesign`:

```
Authority=Developer ID Application: Xiaowei Jin (3FKXTCP8JU)
Authority=Developer ID Certification Authority
Authority=Apple Root CA
```

Expected output for `spctl`:

```
build/export/KeyMagic.app: accepted
source=Notarized Developer ID
```
