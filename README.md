# Icontuck

Icontuck is a sandbox-compatible macOS menu bar utility that uses a deliberately wide `NSStatusItem` to tuck menu bar items off the left edge. It uses public AppKit APIs and requires no Accessibility or Screen Recording permission.

## Requirements

- Xcode with the macOS 26 SDK (Xcode 26 or later)
- macOS 15.0 or later deployment target
- An Apple Development team for signing and launch-at-login testing

## Build

1. Open `Icontuck.xcodeproj` in Xcode.
2. Select the Icontuck target, then choose your development team under Signing & Capabilities.
3. Let Xcode resolve the optional Sparkle Swift package.
4. Select **My Mac** and run.

The app is an agent (`LSUIElement`) and appears only in the menu bar. Click its icon for separator, preferences, and quit controls.

## Sparkle and distribution channels

Sparkle 2 is linked as an optional Swift package, while the app source imports and starts it only when `SPARKLE_ENABLED` is defined. Add that Active Compilation Condition to a direct-distribution configuration after supplying the required Sparkle feed URL, signing keys, and update UI. Do not enable Sparkle in a Mac App Store build; App Store releases are updated by the store.

## Tahoe behavior

The separator requests a width of 10,000 points. macOS 26 may clamp this to about 5,016 points, and a newly inserted item can initially be parked near x = -4,220 when the menu bar is already full. Hiding and showing recreates the status item so AppKit recalculates its placement. No private window manipulation is used.

## App icon

The asset catalog includes a simple vector placeholder. Replace it with production artwork before submission.
