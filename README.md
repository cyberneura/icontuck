# Icontuck

Icontuck is a sandbox-compatible macOS menu bar utility that uses a deliberately wide `NSStatusItem` to tuck menu bar items off the left edge. It calls no private API and requires no Accessibility or Screen Recording permission.

## Install

```shell
brew install --cask cyberneura/tap/icontuck
```

The cask is added to the tap with the first release; until then, build from source.

## Requirements

- Xcode with the macOS 26 SDK (Xcode 26 or later)
- macOS 15.0 or later deployment target
- An Apple Development team for signing and launch-at-login testing

## Build

1. Open `Icontuck.xcodeproj` in Xcode.
2. Select the Icontuck scheme, then choose your development team under Signing & Capabilities.
3. Select **My Mac** and run.

The project has no package dependencies.

From the command line:

```shell
xcodebuild -project Icontuck.xcodeproj -scheme Icontuck -configuration Debug build
```

The app is an agent (`LSUIElement`) and appears only in the menu bar.

## Usage

- **Left click** the Icontuck icon to hide or show icons.
- **Right click** (or Control-click) for preferences and quit.
- **Command-drag** the Icontuck icon to move the boundary between the icons that get tucked and the ones that stay.

Hiding tucks every icon to the *left* of the Icontuck icon off the screen edge. Icons to its right are unaffected. On first launch the icon is placed at the right end of the third-party group, so the first click hides all of them.

To keep one icon permanently visible, Command-drag that icon to the right of the Icontuck icon. Icontuck cannot move another app's icon for you: a status item's slot lives in its own app's preferences, and only the owning app or a Command-drag can change it.

### Preferences

- **Hide icons** — the same toggle as a left click.
- **Hide when only the built-in display is connected** — tuck while the Mac runs on its own panel, and reveal when any external display is attached. Applied at launch and whenever a display is attached or removed, not continuously: a click still overrides it until the next change, which is what keeps the icon usable on a laptop with no external display. A status item lives on whichever screen currently owns the menu bar, so visibility cannot be set per display; the rule keys off the set of attached displays instead.
- **Launch at login**.

## Updates

The app has no update mechanism. Releases are installed and upgraded through the Homebrew cask.

## Tahoe behavior

The separator requests a width of 10,000 points, which macOS 26 clamps to about 5,000 points — still wider than any menu bar.

An oversized status item only pushes the items to its *left*, so it has to be inserted immediately to the left of the control item; anywhere further right and the control item is pushed off screen too, leaving the app unclickable. AppKit parks a brand new status item at the far left of the third-party group, where it pushes nothing, so the insertion point is chosen by writing the `NSStatusItem Preferred Position <autosaveName>` default before the item is created.

That number is not a screen coordinate: AppKit sorts the items by it and then packs them against the right edge. Deriving the separator's slot from the control item's stored slot — rather than from either item's on-screen frame — is what keeps other apps from sorting in between the two and surviving the tuck.

No private API and no window manipulation is used. The one undocumented dependency is the `NSStatusItem Preferred Position <autosaveName>` default itself: Apple documents that `autosaveName` makes a status item remember its position, but not the key's spelling or the meaning of the number. Both are observed behaviour and can change in a macOS release, and the two failure modes are not equally benign. If the key stops being honoured, the separator lands where AppKit parks any new item — at the far left, tucking nothing. If instead the ordering the number expresses were reversed, the separator would sort to the *right* of the control item and push it off screen, leaving an agent app with no icon to click and no Dock entry to quit from. Nothing detects that today.

## Release

Releases are built by the `Release` workflow on a macOS runner: universal archive, Developer ID signing, notarization, stapling, and a dmg attached to a GitHub Release. The workflow is manual only — pushes never build.

### One-time setup

Six repository secrets are required. The workflow fails immediately if any is missing: an empty signing identity does not stop the build — xcodebuild produces an ad-hoc, linker-signed app — and the failure would otherwise surface only after a full universal build.

| Secret | Value |
| --- | --- |
| `APPLE_CERTIFICATE` | Developer ID Application `.p12`, base64-encoded |
| `APPLE_CERTIFICATE_PASSWORD` | Password of that `.p12` |
| `APPLE_SIGNING_IDENTITY` | e.g. `Developer ID Application: Cyberneura K.K. (2YN5TLNQ9J)` |
| `APPLE_ID` | Apple ID used for notarization |
| `APPLE_PASSWORD` | App-specific password for that Apple ID |
| `APPLE_TEAM_ID` | e.g. `2YN5TLNQ9J` |

```shell
base64 -i DeveloperID.p12 | gh secret set APPLE_CERTIFICATE -R cyberneura/icontuck
gh secret set APPLE_CERTIFICATE_PASSWORD -R cyberneura/icontuck
gh secret set APPLE_SIGNING_IDENTITY -R cyberneura/icontuck
gh secret set APPLE_ID -R cyberneura/icontuck
gh secret set APPLE_PASSWORD -R cyberneura/icontuck
gh secret set APPLE_TEAM_ID -R cyberneura/icontuck
```

### Cutting a release

```shell
./scripts/release.sh [patch|minor|major]   # default: patch
```

The script refuses to run unless the working tree is clean and `HEAD` matches `origin/main`. It bumps `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in the project file, commits, pushes, triggers the workflow and watches it. The version is incremented on every release, so a run can never collide with an already published tag.

A draft release is created before the workflow finishes, and a draft does not create the git tag — that happens when the release is published.

If a run fails after the draft exists, delete the draft. GitHub does not require a draft's tag name to be unique, so a second run on the same version would add another draft on the same pending tag. The workflow publishes by release id rather than by tag name, and it establishes that id by looking for a release whose body carries this run attempt's own marker — nothing else about a draft is unique, since the dmg name follows from the version. What a leftover draft does break is the step that finds it: two releases on the tag is treated as an error rather than a guess. That is why the workflow refuses to run while any release already carries the version's tag.

That guard does not force the cleanup, though: `./scripts/release.sh` always cuts the next version, so a leftover draft for the failed version is not in its way. Only re-dispatching the *same* version from the UI is blocked. Nothing else will remind you, so drafts holding a dmg for a version that was never published pile up until they are deleted:

```shell
gh release delete "v<version>" --repo cyberneura/icontuck --yes
```

`gh release delete` resolves by tag name, so if two drafts already share one, run it once per draft. It removes the release only; `--cleanup-tag` removes the tag as well — but check who created the tag first, because the workflow only ever creates one by publishing.

If the workflow instead fails right after publishing, with `Tag v… points at …, not …`, the tag for that version already existed and pointed somewhere else. The release is put back to draft, but the tag stays: publishing creates a tag, un-publishing does not remove one, and this tag was not the workflow's. Delete the draft, skip that version, and cut the next one; what to do with the stray tag is a question for whoever created it.

### Updating the tap

The cask in [cyberneura/homebrew-tap](https://github.com/cyberneura/homebrew-tap) is maintained by hand and does not follow a release automatically. The workflow prints the two fields that change into its run summary:

```ruby
  version "0.1.0"
  sha256 "..."
```

Copy them into `Casks/icontuck.rb` and push the tap.

## App icon

The asset catalog includes a simple vector placeholder. Replace it with production artwork before submission.
