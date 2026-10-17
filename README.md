# ClipVault

ClipVault is a personal library for saving links, notes, and file references in one place. It is built with Flutter and stores its library locally in SQLite.

## Features

- Save, edit, search, sort, and filter links, notes, text, and file references.
- Receive shared text and links from Android apps; shared links are saved to the library automatically.
- Detect copied URLs when the app opens or resumes, with a setting to turn automatic clipboard prompts off.
- View link previews and open saved URLs from item details.
- Organize saved items with automatic and custom tags, favorites, and read status.
- Choose from five accent color themes and five library layouts.
- Move items to Archive or Trash, restore them, or permanently delete them. Trash items expire after 30 days.
- Create and restore local JSON backups, share backup files, and optionally keep up to ten automatic snapshots.
- Import ClipVault JSON backups or HTML bookmarks, and export bookmarks as HTML, Markdown, or CSV.
- Find duplicate links and move older copies to Trash.
- Add images to notes and view them full screen.

## Requirements

- Flutter SDK compatible with the Dart constraint in `pubspec.yaml`.
- Android Studio or an Android device/emulator for Android development.

## Run

```sh
flutter pub get
flutter run
```

To check the Dart and Flutter code:

```sh
flutter analyze
```

## Data and privacy

Saved library records and backups are stored on the device. Link previews fetch page metadata and images from the network. Automatic backups are checked when the app starts, resumes, or remains open; the operating system is not asked to run background backup work after the app is closed.

File records currently store the selected file reference. Keep the referenced file available on the device if you want to open it later.
