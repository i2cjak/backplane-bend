# Phone apps

Native iOS (SwiftUI) and Android (Jetpack Compose) clients for a Backplane
hub. The client logic is the same Bend the web page runs: `src/mobile/`
turns `core/client.bend`'s `Ui` into a screen model (JSON), and
`bridge.js` carries strings between it and the app. The apps own the socket
and draw the screen with native lists, toolbars and text fields; they make
no product decisions. iOS runs the bridge in JavaScriptCore, Android in
QuickJS.

```sh
scripts/build-mobile.sh           # bridge.js + dist/backplane-android.apk
scripts/build-ios.sh sim          # build on the Mac, run in the Simulator
scripts/build-ios.sh archive      # sign and upload to TestFlight
```

`build-ios.sh` bundles bridge.js here (bend), rsyncs `mobile/ios` to
`~/backplane-ios` on the Mac (`BACKPLANE_MAC`, default `hs-mac-mini`) and
runs xcodebuild there. Debug builds read `BACKPLANE_LINK` and
`BACKPLANE_SELECT` from the environment (`SIMCTL_CHILD_…`) to pair and open
a thread without taps.

Pairing: paste the hub's tailnet link (`http://host:3773/#token=…`), or open
`backplane://pair?url=<that link, URL-encoded>`.

## TestFlight

`archive` needs `~/backplane-ios/signing.env` on the Mac (never committed):

```sh
TEAM_ID=XXXXXXXXXX                    # Apple Developer team
BUNDLE_ID=dev.backplane.mobile        # registered App ID; the app record uses it
ASC_KEY_ID=XXXXXXXXXX                 # App Store Connect API key (App Manager)
ASC_ISSUER_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
ASC_KEY_PATH=/Users/h/.appstoreconnect/AuthKey_XXXXXXXXXX.p8
```
