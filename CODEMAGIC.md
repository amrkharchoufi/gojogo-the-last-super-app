# Shipping a new iOS build with Codemagic

The pipeline lives in [codemagic.yaml](codemagic.yaml). Two workflows:

| Workflow | Runs on | What it does |
| --- | --- | --- |
| `ios-check` | every branch push | unsigned simulator build — catches compile breaks in ~5 min |
| `ios-testflight` | a `v*` tag, or a manual start | signed Release IPA → uploaded to TestFlight |

## One-time setup in Codemagic

1. **Connect the repository** — Codemagic → Add application → pick this repo → "I have a `codemagic.yaml`".

2. **App Store Connect integration.** Team settings → Integrations → App Store Connect → add an API key
   (App Store Connect → Users and Access → Integrations → App Store Connect API, role **App Manager**).
   Name it exactly:

   ```
   GojoGo App Store Connect
   ```

   That name is what `integrations.app_store_connect` in the YAML looks up. If you name it something
   else, change the YAML to match. This one key covers both signing and the TestFlight upload — there
   is nothing to upload by hand. The key needs the **App Manager** role, because the build asks it to
   create signing files at Apple, not just read them.

   Signing uses the *automatic* flow: the release workflow runs
   `app-store-connect fetch-signing-files "$BUNDLE_ID" --type IOS_APP_STORE --create`, which makes
   Apple mint the App Store provisioning profile (and a distribution certificate if none matches).
   There is deliberately **no `ios_signing:` block** in the environment — that block means "use the
   certificate and profile I uploaded to Codemagic under Team settings → Code signing identities", and
   with nothing uploaded it fails during machine setup with *No matching profiles found for bundle
   identifier "com.gojo.gojogo" and distribution type "app_store"*. The two styles cannot be mixed.

3. **Environment group `signing`.** One variable, marked *Secure*:

   | Variable | Value |
   | --- | --- |
   | `CERTIFICATE_PRIVATE_KEY` | a 2048-bit RSA private key in PEM form |

   Apple builds the distribution certificate *from a key you own*, so the build cannot invent one —
   without this variable it stops immediately and tells you so. Generate the key once, on any machine:

   ```bash
   ssh-keygen -t rsa -b 2048 -m PEM -f ios_distribution_private_key -q -N ""
   ```

   Paste the whole file into the variable, including the `-----BEGIN RSA PRIVATE KEY-----` and
   `-----END RSA PRIVATE KEY-----` lines. **Do not base64-encode it** — that is the single most common
   cause of *Cannot save Signing Certificates without certificate private key*.

   Then keep that key forever, and back it up somewhere you trust. It is how every later build
   recognises the certificate it already has; change it and the next build asks Apple for another
   certificate, against a cap of three. Treat it like a password — anyone holding it plus your API key
   can sign apps as your team.

4. **Environment group `mapbox`.** Application settings → Environment variables → group `mapbox`,
   both marked *Secure*:

   | Variable | Value |
   | --- | --- |
   | `MAPBOX_DOWNLOADS_TOKEN` | your **secret** `sk.…` token with the `DOWNLOADS:READ` scope — written to `~/.netrc` so SPM can fetch the Mapbox binaries |
   | `MAPBOX_PUBLIC_TOKEN` | your **public** `pk.…` token — written to `GojoGo/MapboxAccessToken`, which is gitignored and so never reaches the runner from git |

5. **App record.** `com.gojo.gojogo` needs to exist as an App ID in the developer portal *and* as an app
   in App Store Connect before the first TestFlight upload. Its numeric Apple ID is already set as
   `APP_STORE_APPLE_ID` in `codemagic.yaml` (`6762012938`), so the build number is read from App Store
   Connect and bumped by one. If that number is ever wrong the lookup fails, the build falls back to
   Codemagic's own counter — which starts at 1 and can collide with builds you have already uploaded —
   and the step prints a `WARNING:` line saying so. Grep the log for it if a build number looks off.

6. **Capabilities on the App ID.** `GojoGo/GojoGo.entitlements` asks for **Push Notifications**,
   **Sign in with Apple**, **iCloud (CloudKit)** and **App Groups**. All have to be enabled on the App ID
   in the developer portal, otherwise the App Store profile Codemagic fetches won't grant them and the
   export step fails after a full build. Keychain sharing is *not* in that list and needs no portal
   action: `keychain-access-groups` is validated by team prefix, and a profile already carries
   `<TeamID>.*`.

7. **The notification extension's App ID** (E2EE Phase G). The app now embeds
   `com.gojo.gojogo.NotificationService`, which is a *second* App ID with its own profile. The build
   fetches signing files for it automatically, but `--create` only mints the identifier — it does not
   turn capabilities on. **Enable App Groups on it and associate `group.com.gojo.gojogo`**, by hand,
   before the next signed build.

   Two different failures hide behind that one step, and they look nothing alike:

   - *Capability off entirely* → the profile has no `com.apple.security.application-groups` key, the
     extension's entitlements ask for one, and the **export step fails loudly** — "provisioning profile
     doesn't include the com.apple.security.application-groups entitlement", after a full build.
   - *Capability on but the group not associated* (or associated with a different group) → the profile
     carries the key with the wrong contents, signing can pass, and the failure moves to **runtime and
     goes silent**: the extension cannot open the shared container, so it finds no session store and no
     profile id, and every banner stays "New message" forever. Nothing in the build log mentions it.

   The second is the one to actually watch for, because a green build reads as proof and isn't.

## Cutting a version

Tag and push:

```bash
git tag v1.1.0 && git push origin v1.1.0
```

The tag only triggers the build — it does not set the version. The version comes from:

- **Build number** — set for you: latest build in App Store Connect + 1 (`CURRENT_PROJECT_VERSION`),
  overriding whatever the project file says.
- **Marketing version** — whatever is in the project file (currently `1.0.0`), unless you start the
  build manually from the Codemagic UI and add a variable `APP_VERSION=1.1.0` for that run.

Neither is written back to the repo, so bump `MARKETING_VERSION` in the Xcode project when you want the
new number to be the permanent default.

To send a build to App Store review instead of stopping at TestFlight, flip `submit_to_app_store` to
`true` under `publishing.app_store_connect`.

`ios-check` triggers on pushes only, not on `pull_request` — a PR from a branch in this repo would
otherwise build twice and Codemagic bills by the minute. Add `pull_request` to its `events` if you ever
take PRs from forks, whose pushes Codemagic doesn't see.

## Things worth knowing about this project

- **The shared scheme is now committed** (`GojoGo.xcodeproj/xcshareddata/xcschemes/GojoGo.xcscheme`).
  It previously existed only under `xcuserdata/`, which is gitignored — CI had no scheme to build.
  Don't delete it.
- **Push entitlement.** `GojoGo/GojoGo.entitlements` asks for `aps-environment: development`, which an
  App Store provisioning profile does not grant — the export would fail. The release workflow rewrites
  it to `production` on the runner only; the file in git is untouched, so local development builds keep
  working. If you ever add a second entitlement that differs between debug and release, move to two
  entitlement files instead of patching.
- **Team ID is `T8348X4CNY` everywhere.** The project-level Debug and Release configs used to say
  `ZUKS346NF6` while the target said `T8348X4CNY`; both now say `T8348X4CNY`. CI never cared —
  `xcode-project use-profiles` overwrites them from the fetched profile — but local archives did.
- **Export compliance is pre-answered.** The target sets
  `INFOPLIST_KEY_ITSAppUsesNonExemptEncryption = NO`, so uploads don't land in TestFlight as *Missing
  Compliance* waiting on a manual answer. If the app ever ships non-exempt encryption, remove it and
  answer the question in App Store Connect instead.
- **No test target exists**, so no test step is wired up. When you add one, add a `run-tests` step to
  `ios-check` (`xcode-project run-tests --project GojoGo.xcodeproj --scheme GojoGo`) and a
  `test_report` entry pointing at `build/ios/test/*.xml`.
