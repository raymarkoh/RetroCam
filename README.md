# RetroCam

A retro-inspired camera app built with Flutter.

## Features

- Live camera viewfinder with front/rear camera switching.
- Photo capture with an in-app captured-photo preview.
- Warm, faded, monochrome, and original looks applied to the viewfinder and
  saved photos.
- Captured photos are stored in the app's documents directory with a date/time
  stamp embedded in the image. They remain available after restarting the app.
- In-app gallery with full-size photo viewing.
- Flash/torch toggle.

## App icon

The Android launcher icon is generated from
`assets/retrocam_launcher_icon.png`.
After changing the source image, regenerate the launcher resources with
`dart run flutter_launcher_icons`.

## Running

Run `flutter pub get`, then `flutter run` on an Android device or
camera-enabled emulator. Allow camera access when prompted. The Android app
requests camera permission at runtime through the camera plugin; saved photos
are private to the app and do not require external-storage permission.
