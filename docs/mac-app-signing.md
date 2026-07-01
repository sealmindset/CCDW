# Signing "Claude Code.app" for all Mac users

`scripts/build-mac-app.sh` builds the desktop launcher bundle. macOS will only
launch a script-based `.app` if it has a **usable code signature** — an unsigned
bundle silently does nothing on double-click.

There are two distribution models, and they need different signing:

| How the user gets the .app | Quarantine? | Signing required |
|----------------------------|-------------|------------------|
| **Installer builds it locally** (`install.command` runs `build-mac-app.sh` on the user's own Mac) | No | **Ad-hoc is enough.** Done automatically. |
| **Prebuilt .app copied/zipped/downloaded/MDM-pushed** to another Mac | Yes (macOS adds it) | **Developer ID signature + notarization.** Ad-hoc is Gatekeeper-blocked. |

Because CCDW is distributed **both** ways, produce a **Developer ID signed +
notarized** bundle for anything you hand out prebuilt. The installer path keeps
working on ad-hoc with no cert.

## What the build script does automatically

1. Developer ID identity available → **Developer ID sign** (hardened runtime + timestamp).
2. …plus notarization credentials → **notarize + staple** (launches on any Mac).
3. Neither → **ad-hoc sign** (launches only where it was built; blocked if copied).

No credentials are ever committed — everything is read from environment variables.

## What to obtain from your Apple Developer admin

You need an **Apple Developer Program** membership (org account) and:

1. A **"Developer ID Application"** signing certificate, installed in the build
   machine's login keychain. Verify with:
   ```bash
   security find-identity -v -p codesigning | grep "Developer ID Application"
   ```
2. **Notarization credentials** — one of:
   - **App Store Connect API key** (recommended for CI): a `.p8` key file, its
     Key ID, and the Issuer UUID.
   - **Apple ID**: the Apple ID email, the Team ID, and an **app-specific
     password** (appleid.apple.com → Sign-In & Security).
   - A **stored notarytool profile** created once with
     `xcrun notarytool store-credentials`.

## Producing a distributable bundle

On a machine that has the Developer ID cert in its keychain:

```bash
# Identity (optional if only one Developer ID Application cert is present)
export MACOS_SIGN_IDENTITY="Developer ID Application: Your Org (TEAMID)"

# Notarization — pick ONE method:

# a) Stored profile (create once: xcrun notarytool store-credentials)
export MACOS_NOTARY_PROFILE="ccdw-notary"

# b) App Store Connect API key
export MACOS_NOTARY_KEY_ID="XXXXXXXXXX"
export MACOS_NOTARY_KEY_PATH="$HOME/keys/AuthKey_XXXXXXXXXX.p8"
export MACOS_NOTARY_ISSUER="xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"

# c) Apple ID + app-specific password
export MACOS_NOTARY_APPLE_ID="you@company.com"
export MACOS_NOTARY_TEAM_ID="TEAMID"
export MACOS_NOTARY_PASSWORD="abcd-efgh-ijkl-mnop"

bash scripts/build-mac-app.sh /path/to/output
```

Result: a signed, notarized, stapled `Claude Code.app` that launches on any Mac
with no Gatekeeper prompt, even after download.

Other switches:
- `SKIP_NOTARIZE=1` — Developer ID sign but skip notarization (faster; a
  downloaded copy may warn on first launch until notarized).
- `MACOS_SIGN_ADHOC=1` — force ad-hoc even if a Developer ID cert exists.

## No-signing fallback: `Launch Claude Code.command`

`build-mac-app.sh` also drops a **`Launch Claude Code.command`** next to the
`.app`. It is a plain executable script (no bundle), so it needs **no code
signature, ever**, and it survives being copied. Double-clicking opens Terminal
and runs the same `launch-mac.sh` (same preflight, same dialogs, same browser
open). A *downloaded* copy needs a one-time **right-click → Open** (standard
Gatekeeper for unsigned scripts); an installer-created copy has no quarantine
and just runs.

Use this when you can't sign yet, hand out a prebuilt launcher without the
installer, or hit a locked-down Mac where the unsigned `.app` won't launch. The
polished `.app` remains the primary launcher; the `.command` is the safety net.

## Recommended: sign + notarize in CI

Put the Developer ID cert and notarization credentials in CI secrets (GitHub
Actions), import the cert into a temporary keychain, export the `MACOS_*`
variables, and run `build-mac-app.sh` there to publish a notarized bundle as a
release artifact. This keeps signing material off developer laptops and out of
the repo.
