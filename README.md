<img src=".github/Icon-cropped.png" width="200" alt="App icon" align="left"/>

<div>
<h3>BetterMonitor</h3>
<p>Control your external display brightness, volume and contrast with native OSD support.
Use menubar sliders, keyboard shortcuts, or the CLI for automation.</p>
<a href="https://github.com/Darkroom4364/BetterMonitor/releases"><img src=".github/macos_badge_noborder.png" width="175" alt="Download for macOS"/></a>
</div>

<br/><br/>

<div align="center">
<a href="https://github.com/Darkroom4364/BetterMonitor/releases"><img src="https://img.shields.io/github/release-pre/Darkroom4364/BetterMonitor.svg?style=flat" alt="latest version"/></a>
<a href="https://github.com/Darkroom4364/BetterMonitor/blob/main/License.txt"><img src="https://img.shields.io/github/license/Darkroom4364/BetterMonitor.svg?style=flat" alt="license"/></a>
<img src="https://img.shields.io/badge/platform-macOS-blue.svg?style=flat" alt="platform"/>

<br/>
<br/>

<img src=".github/screenshot.png" width="824" alt="Screenshot"/><br/>

</div>

<hr>

## Features

- **Brightness, volume & contrast** control for external displays via DDC
- **Native OSD** — shows the system brightness/volume overlay
- **CLI tool** (`bettermonitor`) for scripted and automated control
- **Multiple protocols** — DDC for external displays, native Apple protocol for built-in displays, gamma/shade for virtual screens
- **Smooth transitions** and combined hardware + software dimming (dim beyond your display's minimum)
- **Brightness sync** — replicate ambient light sensor changes from built-in displays to externals
- **Keyboard shortcuts** — Apple media keys and custom shortcuts
- **Dozens of settings** — enable `Show advanced settings` to fine-tune for your hardware
- **Free and open source**

### Screenshots

<div align="center">
<img src=".github/pref_1.png" width="392" alt="Screenshot"/>
<img src=".github/pref_2.png" width="392" alt="Screenshot"/>
<img src=".github/pref_3.png" width="392" alt="Screenshot"/>
<img src=".github/pref_4.png" width="392" alt="Screenshot"/>
</div>

## Install

Download the latest `.dmg` from [Releases](https://github.com/Darkroom4364/BetterMonitor/releases).

## CLI

BetterMonitor includes a command-line tool for automation:

```sh
# List all displays
bettermonitor list

# Get/set brightness
bettermonitor get brightness
bettermonitor set brightness 70

# JSON output
bettermonitor list --json
```

The CLI communicates with the running BetterMonitor app — make sure it's open.

## Getting started

1. Download and copy BetterMonitor to your Applications folder
2. Launch the app
3. Grant Accessibility access when prompted (required for keyboard brightness/media keys)
4. Use your keyboard or the menubar sliders to control displays
5. Open Settings for customization (enable `Show advanced settings` for more options)

## Supported displays

- **DDC displays** — most modern LCDs from all major manufacturers via USB-C, DisplayPort, HDMI, DVI
- **Apple & built-in displays** — native protocol support
- **TVs** — supported via software dimming (most TVs don't implement DDC)
- **DisplayLink, AirPlay, Sidecar** — shade (overlay) control

**Known limitations:**
- Built-in HDMI on Apple Silicon Macs does not support DDC. Use USB-C or a Thunderbolt dock instead.
- EIZO displays using MCCS over USB are limited to software dimming.
- DisplayLink docks do not support DDC on macOS.

## macOS compatibility

| BetterMonitor | macOS |
|---|---|
| Latest | Catalina 10.15+ (full features on Big Sur 11+) |

## Build from source

**Requirements:** Xcode, [SwiftLint](https://github.com/realm/SwiftLint), [SwiftFormat](https://github.com/nicklockwood/SwiftFormat), [BartyCrouch](https://github.com/Flinesoft/BartyCrouch)

```sh
git clone https://github.com/Darkroom4364/BetterMonitor.git
cd BetterMonitor
open BetterMonitor.xcodeproj
```

Dependencies resolve automatically via SPM.

### Dependencies

- [MediaKeyTap](https://github.com/MonitorControl/MediaKeyTap)
- [Settings](https://github.com/sindresorhus/Settings)
- [SimplyCoreAudio](https://github.com/rnine/SimplyCoreAudio)
- [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts)
- [Sparkle](https://github.com/sparkle-project/Sparkle)

## Credits

BetterMonitor is a fork of [MonitorControl](https://github.com/MonitorControl/MonitorControl) with added CLI support, automation features, and active development.

Original MonitorControl contributors:
- [@waydabber](https://github.com/waydabber) — maintainer, developer of [BetterDisplay](https://github.com/waydabber/BetterDisplay)
- [@the0neyouseek](https://github.com/the0neyouseek), [@JoniVR](https://github.com/JoniVR) — honorary maintainers
- [@alin23](https://github.com/alin23) — M1 DDC support, developer of [Lunar](https://lunar.fyi)
- [@mathew-kurian](https://github.com/mathew-kurian/) — original developer
- [Full contributor list](https://github.com/MonitorControl/MonitorControl/graphs/contributors)

## License

[MIT](License.txt)
