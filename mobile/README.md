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

Pairing: paste the hub's tailnet link (`http://host:3787/#token=…`), or open
`backplane://pair?url=<that link, URL-encoded>`.

## Board viewer

A thread's toolbar opens its project's board or schematic (the chip
icon). The hub sends it as a plot (`src/core/plot.bend`): chunks of
geometry in paint order, then, on each save, only the chunks that changed
(laws `plot_delta_exact`, `plot_unchanged_sends_nothing`). Plot messages
go straight from the socket to the renderer, never through bridge.js.

The phone uploads a plot to the GPU once; pan, pinch and double-tap only
move a transform, so every frame costs the same whatever the board. Each
layer is drawn as coverage (tracks, arcs and dots as instanced capsules
with an analytic edge, fills by stencil) and laid over the frame in its
colour and opacity. Frames are drawn only while a finger moves, a fling
coasts or new chunks fade in. iOS: Metal (shaders compiled on the device,
so the build needs no Metal toolchain), up to 120 Hz. Android: OpenGL ES 3.

## TestFlight

`archive` needs `~/backplane-ios/signing.env` on the Mac (never committed):

```sh
TEAM_ID=XXXXXXXXXX                    # Apple Developer team
BUNDLE_ID=dev.backplane.mobile        # registered App ID; the app record uses it
ASC_KEY_ID=XXXXXXXXXX                 # App Store Connect API key (App Manager)
ASC_ISSUER_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
ASC_KEY_PATH=/Users/h/.appstoreconnect/AuthKey_XXXXXXXXXX.p8
```

## Notifications and the Dynamic Island

When a turn ends (Completed or Failed; a stop the user asked for is not
news), the phone alerts, and while turns run it shows a live status. What
counts is decided in `src/mobile/notify.bend` (laws `alert_*`).

- iOS in front: the app posts the alert itself and runs one Live Activity
  (lock screen + Dynamic Island) from the screen's `island`.
- iOS asleep: the hub pushes through APNs (`src/server/push.bend`): an
  alert, and Live Activity updates to the activity's push token. The app
  registers its tokens with the `device.register` rpc; tokens never leave
  the hub (laws `device_*`).
- Android: a foreground service keeps the socket open while turns run and
  shows an ongoing notification (promoted to a status-bar chip on Android
  16); alerts come from the same Bend `notify` commands.

APNs needs a key from developer.apple.com (Keys, with Apple Push
Notifications service enabled). Put the .p8 on the hub machine and set:

```
push.apns.key    /path/to/AuthKey_XXXXXXXXXX.p8
push.apns.keyid  XXXXXXXXXX
push.apns.team   <Team ID>
```

(settings via `setting.set`; only the path is stored, never the key).
