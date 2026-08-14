<p align="center">
  <img src="demo_middleClickForMac/Assets.xcassets/AppIcon.appiconset/icon_256x256.png" width="128">
</p>

<p align="center">iMiddleClick</p>

<h2 align="center">
  Middle-click gestures for MacBook Magic Mouse and trackpad.
</h2>

<table>
  <tr>
    <td width="40%" align="center">
      <img src="assets/demo_mouse.gif" width="100%">
    </td>
    <td width="40%" align="center">
      <img src="assets/demo.gif" width="100%">
    </td>
  </tr>
</table>

## Features

### Magic Mouse

- Configurable 2-finger or 3-finger gestures
- Tap → Middle Click
- Physical click → Middle Click
- Tap and physical-click gestures can be enabled independently

### MacBook Trackpad

- Three-finger tap → Middle Click
- Three-finger physical click → Middle Click
- Supports the natural `2 → 3 → 2` gesture:
  keep two fingers resting on the trackpad and briefly tap with a third finger

### Other

- Runs as a lightweight menu-bar utility
- Launch at Login support
- Per-device gesture configuration
- Native macOS implementation

## Download

Download the latest version from the
[Releases](../../releases/latest) page.

## Installation & Permissions

1. Download the latest `.dmg` from the Releases page.
2. Drag **iMiddleClick** into the **Applications** folder.
3. Open **iMiddleClick** from Applications.
4. macOS may block the app because it is not currently notarized. Click **Done**.
5. Open **System Settings → Privacy & Security**, scroll down, and click **Open Anyway** next to iMiddleClick.
6. Launch iMiddleClick again and approve any permission requests from macOS.
7. When macOS notifies you that iMiddleClick added a new background item, choose **Allow**.
8. Enter your administrator password if macOS asks for it.

If the helper is not running after setup, quit iMiddleClick and launch it again.

Once setup is complete, iMiddleClick runs from the menu bar.

## Why iMiddleClick?

macOS does not provide a native middle-click gesture for the MacBook trackpad or Magic Mouse.

iMiddleClick adds that functionality while staying focused on one job instead of being a full gesture-customization suite.

Middle click is especially useful for:

- Opening links in a new browser tab
- Closing browser tabs
- Middle-click actions in development tools
- Applications designed around a three-button mouse

## Permissions

iMiddleClick needs system-level access in order to detect multitouch gestures globally and generate middle-click events.

The project includes a privileged helper used for accessing raw multitouch data.

The source code is available here so you can inspect exactly what the application and helper do.

## Compatibility

- macOS
- MacBook trackpads
- Apple Magic Mouse

> Apple Silicon is currently the primary tested platform.

## Privacy

iMiddleClick does not collect or transmit your gesture data.

Multitouch information is processed locally and is used only to recognize the configured middle-click gestures.

## Support the Project

iMiddleClick is free.

If you find it useful and would like to support development, you can buy me a coffee:

[☕ Buy me a coffee](https://ko-fi.com/kleinutilities)

## Building from Source

Open the Xcode project:

```text
demo_middleClickForMac.xcodeproj
