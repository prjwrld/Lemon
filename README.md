# Lemon

A menu bar app for macOS 26+. Hold **Shift** while dragging image files, and a Liquid Glass
wheel appears. Drop the files on a slice to save a converted copy next to the originals.
Lemon never changes the original files. If a name is taken, it adds a number (`photo 2.png`).

## Run
- In Xcode: open `Lemon.xcodeproj`, press ⌘R.
- From Terminal:
  ```
  xcodebuild -project Lemon.xcodeproj -scheme Lemon -derivedDataPath build build
  open build/Build/Products/Debug/Lemon.app
  ```
- Design check: `open build/Build/Products/Debug/Lemon.app --args -LemonDemoWheel YES`
  shows the wheel in the middle of the screen for 8 seconds (Debug builds only).

## Files
| File | Job |
|---|---|
| `LemonApp.swift` | Menu bar icon and menu |
| `AppDelegate.swift` | Connects the parts |
| `DragWatcher.swift` | Notices Shift + file drag anywhere |
| `WheelPanel.swift` | Floating see-through window; receives the drop |
| `WheelView.swift` | The glass wheel (SwiftUI `glassEffect`) |
| `WheelGeometry.swift` | Wheel sizes and slice shape / hit maths |
| `ImageFormat.swift` | The list of formats (one place for all choices) |
| `ImageConverter.swift` | Conversion with ImageIO |
| `SafeSaver.swift` | Saves next to the original without replacing anything |
| `Feedback.swift` | Sounds, trackpad taps, error alerts |

## Release (your website, Developer ID)
One time: `xcrun notarytool store-credentials lemon-notary --apple-id YOUR_APPLE_ID --team-id WR42UXPTXW`
Then: `./scripts/release.sh` → `build/Lemon.zip` (signed, notarized, ready to upload).
