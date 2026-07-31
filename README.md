# TV Remote for iOS

A simple, local-only iPhone remote for:

- Roku and TCL Roku TV
- Google TV, Android TV, and TCL Google TV
- Apple TV

The app includes navigation, home/back, playback, volume, channel, power,
red/green/yellow/blue buttons where the TV protocol supports them, and text
entry using the iPhone keyboard.

## Requirements

- Xcode 26 or later
- iOS 17 or later
- An Apple development team selected for the `TVRemote` target
- The iPhone and TV on the same local network

Open `TVRemote/TVRemote.xcodeproj`, select your signing team and iPhone, then
build and run.

The generated Xcode project is based on `TVRemote/project.yml`. If the spec is
changed, regenerate it with:

```sh
cd TVRemote
xcodegen generate --spec project.yml
```

## Device setup

### Roku / TCL Roku

Roku uses the documented External Control Protocol (ECP) over local HTTP on
port 8060.

1. On the Roku, open **Settings > System > Advanced system settings >
   Control by mobile apps**.
2. Set network access to **Enabled**.
3. In the app, select a discovered Roku or use **Add by IP Address**.

Roku discovery uses SSDP multicast. Physical iPhones require Apple’s restricted
`com.apple.developer.networking.multicast` entitlement for automatic SSDP
discovery. Without that entitlement, manual IP entry remains fully functional.

Roku accepts text only while its on-screen keyboard is active. Roku ECP does
not expose native red, green, yellow, or blue keys, so those controls are shown
disabled.

### Google TV / Android TV / TCL Google TV

Google TV uses Android TV Remote Service v2:

- Bonjour discovery using `_androidtvremote2._tcp`
- TLS pairing on port 6467
- Encrypted remote sessions on port 6466
- A one-time six-character code shown on the TV

The app creates an on-device RSA identity and stores it in the iOS Keychain.
Pairing remains available across launches. Text works while an editable TV
field is active. The four color buttons send Android key codes 183–186.

Some Android boxes, including Formuler Z10 firmware tested with this app,
filter color keys received directly through Remote Service v2. If the box is
connected to a Google TV over HDMI and HDMI-CEC is enabled, use the
**Color-button relay** picker while connected to the box. Only red, green,
yellow, and blue are sent to the selected TV for HDMI-CEC forwarding; navigation,
volume, and keyboard input remain connected directly to the box. Pair with the
relay TV normally once before selecting it.

### Apple TV

Apple TV support uses the pinned MIT-licensed
[itsytv-core](https://github.com/nickustinov/itsytv-core) package. It discovers
Apple TVs with Bonjour, uses the Companion/AirPlay protocols, stores pairing
credentials in the Keychain, and supports the Apple TV remote-text-input
session.

If discovery or pairing is blocked, confirm AirPlay is enabled and remote app
pairing is allowed in Apple TV settings. Apple TV does not expose native
red/green/yellow/blue commands, so those controls are shown disabled.

## Keyboard behavior

Open a search, login, or other editable field on the TV first. Tap **Type on
TV**, enter text, and tap **Send to TV**. Some streaming apps intentionally
block remote text entry in password or protected fields.

## Privacy

All discovery, pairing, commands, and text stay on the local network. The app
has no account, analytics, ads, or cloud service.

## Tests

Run the protocol and capability tests with an installed simulator:

```sh
xcodebuild \
  -project TVRemote/TVRemote.xcodeproj \
  -scheme TVRemote \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro" \
  -derivedDataPath TVRemote/DerivedData \
  CODE_SIGNING_ALLOWED=NO \
  test
```

Simulator tests verify command mappings, protocol encoding, parsing, and
capability behavior. Pairing and remote compatibility must also be tested on a
signed physical iPhone against each target TV and firmware version.

See `THIRD_PARTY_NOTICES.md` for dependency and attribution details.
