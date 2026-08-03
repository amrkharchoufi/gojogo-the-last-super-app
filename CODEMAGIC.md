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
   else, change the YAML to match. This one key covers both signing (certificates and profiles are
   fetched and installed automatically) and the TestFlight upload — there is nothing to upload by hand.

3. **Environment group `mapbox`.** Application settings → Environment variables → group `mapbox`,
   both marked *Secure*:

   | Variable | Value |
   | --- | --- |
   | `MAPBOX_DOWNLOADS_TOKEN` | your **secret** `sk.…` token with the `DOWNLOADS:READ` scope — written to `~/.netrc` so SPM can fetch the Mapbox binaries |
   | `MAPBOX_PUBLIC_TOKEN` | your **public** `pk.…` token — written to `GojoGo/MapboxAccessToken`, which is gitignored and so never reaches the runner from git |

4. **App record.** `com.gojo.gojogo` needs to exist as an App ID in the developer portal *and* as an app
   in App Store Connect before the first TestFlight upload. Its numeric Apple ID is already set as
   `APP_STORE_APPLE_ID` in `codemagic.yaml` (`6762012938`), so the build number is read from App Store
   Connect and bumped by one. If that number is ever wrong the lookup fails, the build falls back to
   Codemagic's own counter — which starts at 1 and can collide with builds you have already uploaded —
   and the step prints a `WARNING:` line saying so. Grep the log for it if a build number looks off.

5. **Capabilities on the App ID.** `GojoGo/GojoGo.entitlements` asks for **Push Notifications** and
   **Sign in with Apple**. Both have to be enabled on the App ID in the developer portal, otherwise the
   App Store profile Codemagic fetches won't grant them and the export step fails after a full build.

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
