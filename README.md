# mashroo3

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Windows MSIX build

1. Build and package MSIX:
   ```powershell
   dart run msix:create
   ```
2. The MSIX build uses:
   - `--dart-define=DISABLE_DESKTOP_UPDATER=true`
   - this disables `desktop_updater` inside MSIX packages.

## Standard Windows build (updater enabled)

```powershell
flutter build windows
```
