# MileMate

MileMate is a SwiftUI mileage tracking application for gig workers and professionals.

## Requirements

- Xcode 16 or newer
- iOS 17 or newer
- Swift 6

Open `MileMate.xcodeproj` and run the `MileMate` scheme.

## Architecture

The application uses feature-oriented MVVM:

- `App`: application entry point and root navigation
- `Core`: design system, shared components, extensions, and protocols
- `Domain`: platform-independent models
- `Data`: mock repositories (replaceable by Firebase-backed implementations)
- `Features`: views and view models grouped by product feature

`AppDependencies` is the composition root. The first milestone injects a mock
repository, an intentionally inactive location service, and a SwiftData model
container. Feature view models depend on protocols rather than concrete storage.

Automatic trip detection and background location tracking are intentionally
deferred. No location permission is requested in this milestone.
