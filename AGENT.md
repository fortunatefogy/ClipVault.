# ClipVault Agent Reference

This document is a quick technical map for agents working in this repository. Read it before scanning the full app source. Source code and `pubspec.yaml` remain authoritative; update this document and `README.md` whenever a feature, package, setting, data field, or platform integration changes.

## Project overview

- ClipVault is an offline-first personal library for links, notes, text, and file references.
- The UI and most application logic live in `lib/main.dart` (currently one large Flutter file).
- Android-specific startup and inbound share handling live in `android/app/src/main/`.
- Records are stored locally with SQLite. Preferences use `shared_preferences`.
- The Android application ID is `com.example.clipvault`; the user-facing label is `ClipVault`.

## Main files

| Path | Responsibility |
| --- | --- |
| `lib/main.dart` | App startup, theme, models, SQLite access, screens, search, item flows, backup/import/export, clipboard and share handling |
| `pubspec.yaml` | Dart SDK range, dependencies, assets, launcher icon generation configuration |
| `pubspec.lock` | Resolved Dart/Flutter package versions |
| `android/app/src/main/AndroidManifest.xml` | Android app label, launcher entry point, and `ACTION_SEND` text share target |
| `android/app/src/main/kotlin/com/example/clipvault/MainActivity.kt` | Android intent extraction and Flutter method channel for inbound shared text |
| `android/app/src/main/res/drawable/launch_background.xml` | Legacy Android launch background and centered launcher icon |
| `android/app/src/main/res/values-v31/styles.xml` | Android 12+ splash configuration |
| `android/app/src/main/res/values-night-v31/styles.xml` | Android 12+ dark-mode splash configuration |
| `assets/Logo/logo.png` | Brand logo, Flutter startup screen image, and launcher icon source |
| `assets/fonts/` | Bundled Manrope font files and OFL license |
| `README.md` | User-facing project overview, setup, feature list, and privacy notes |

## App startup and navigation

1. `main()` initializes Flutter, opens the SQLite database, loads the selected theme and clipboard preference, then runs the app.
2. `ClipVaultApp` builds the shared Material theme and starts at `StartupSplashScreen`.
3. The splash screen displays `assets/Logo/logo.png`, “ClipVault,” and “Your personal library,” then fades into `LibraryScreen`.
4. Screens are pushed with Flutter routes from `lib/main.dart`; there is no separate routing package.

## Features

### Library

- Save, edit, open, favorite, mark read/unread, archive, and trash library records.
- Pin records to keep them ahead of other sort results; use the Pinned category to filter them.
- Create, rename, and delete named collections. The home library uses one collection picker (with item counts) to filter records as collection count grows; names persist immediately, and collection assignments are stored on each item.
- Long-press a record to enter multi-select, then select all visible items or pin/unpin, favorite, mark read, assign/remove a collection, archive, or move selected records to Trash.
- Library layouts: Grid, Compact, Gallery, List, and Simple. Grid cards keep a single edit action and show small pin/favorite status badges; pin and favorite actions remain available from item details.
- Search covers saved item text and tags. The library also provides sort options (Auto, Relevance, Newest, Oldest, Most opened, Recently opened) and filters for item kind, added date, source, and tag.
- Link details show fetched page metadata, open-link actions, automatic tags, custom tags, and saved date.
- Notes support attached images; tapping an image opens the full-screen image viewer.
- The Add Link flow is a dedicated page. It accepts a URL, fetches a preview, and saves after the user confirms.

### Incoming links and clipboard

- Android advertises an `ACTION_SEND` / `text/plain` target. Selecting ClipVault from another app’s share sheet passes the shared text to Dart over `com.example.clipvault/share`.
- `extractUrls` finds the first URL in the shared text. ClipVault fetches metadata and saves it directly as a link record; duplicate URLs are rejected by the normal add flow.
- Cold-start shared content is read through `getInitialSharedText`; shares received while ClipVault is already open arrive through the `sharedText` method call.
- Clipboard auto-paste is controlled by the Settings toggle (`auto_paste_clipboard`, default on). It checks for a new URL when the app opens or resumes and opens the Add Link page for confirmation.
- An incoming share suppresses clipboard auto-paste for that foreground session. Suppression clears when Android reports the app paused, so clipboard auto-paste can run on a later app visit.
- Clipboard auto-paste and Android share handling are separate paths. Keep them separate so shared content does not open a second Add Link page.

### Settings and data management

- Settings has Settings and Data tabs. Settings includes total link/media counts, appearance themes, and the clipboard auto-paste toggle.
- Data tools include Archive, Trash, Backups, Import & export, and Clear everything.
- Trash records are purged after 30 days. Records can be restored or permanently removed sooner.
- Backups are local JSON snapshots. Optional automatic backup checks for a due snapshot at startup, resume, and while open; it keeps at most ten snapshots. It is not scheduled to run by the OS while the app is closed.
- Import supports ClipVault JSON backups and browser bookmark HTML. Imports merge records. Export options include JSON, HTML bookmarks, Markdown, and CSV.
- Duplicate finder groups active links by normalized URL and can move older duplicates to Trash.

## Data model and persistence

`SavedItem` is the library record model. SQLite database file: `clipvault.db`, table: `items`, current schema version: 5.

| Field | Meaning |
| --- | --- |
| `id` | Local integer primary key |
| `title`, `url`, `content` | Main display text and optional URL/content |
| `type` | Record kind, such as `link`, `note`, or `file` |
| `tags` | Custom tags stored on the record |
| `collection` | Assigned collection name, or empty when unassigned |
| `image_url` | Link preview image or local note image reference |
| `favorite`, `is_read`, `is_archived`, `pinned` | Library state flags |
| `created_at` | Creation time in Unix milliseconds |
| `open_count`, `last_opened_at` | Usage/sort metadata |
| `deleted_at` | Trash timestamp; `null` means not in Trash |

Use `VaultDb` methods for persistence. Schema changes must increment the SQLite version and add a migration in `onUpgrade`; preserve existing user records. `SharedPreferencesAsync` currently stores `app_theme`, `auto_paste_clipboard`, `library_view`, `library_sort`, `collections` (collection names), `auto_backup`, and `last_auto_backup`.

ClipVault JSON backup files use a versioned envelope containing `collections` and `items`. The importer also accepts the older top-level item-list format. Keep this backward compatibility when changing backup data.

## Design system

The default selected palette is **Ember**. Palette selection is stored as a preference and drives the app accent/highlight getters.

### Base colors

| Role | Hex |
| --- | --- |
| Main background (`auraBase`) | `#0B0B0D` |
| Card surface (`auraSurface`) | `#17181C` |
| Elevated surface (`auraDepth`) | `#1E2025` |
| Primary text | `#FFFFFF` |
| Secondary text | `#A1A1AA` |
| Muted text | `#71717A` |
| Border (`outline`) | `#303036` |
| Success | `#34D399` |
| Error | `#F87171` |

### Accent palettes

`AppPalette(name, accent, highlight)` in `lib/main.dart` defines these five options:

| Name | Accent | Highlight |
| --- | --- | --- |
| Ember | `#FF7900` | `#FF9A2E` |
| Ocean | `#38BDF8` | `#7DD3FC` |
| Violet | `#A78BFA` | `#C4B5FD` |
| Forest | `#34D399` | `#6EE7B7` |
| Rose | `#FB7185` | `#FDA4AF` |

Use `auraOrange`/`auraGold` for the selected palette accent and `auraHighlight` for its highlight. Use the shared base/surface/text/border values instead of introducing unrelated colors. The UI uses a dark charcoal style with restrained borders and elevation.

### Typography and motion

- The app theme calls `GoogleFonts.playpenSansTextTheme` from `google_fonts` and disables runtime font fetching in `main()`.
- `assets/fonts/` currently contains Manrope font files. Check font availability and offline behavior before changing typography; keep the README/reference accurate if the configured font changes.
- `flutter_animate` and `animations` provide UI transitions; `flutter_slidable` provides swipe actions.

## Packages

Runtime dependencies are declared in `pubspec.yaml`:

| Package | Current use |
| --- | --- |
| `sqflite` | Local SQLite library database |
| `path`, `path_provider` | Paths and app document/temp directories |
| `shared_preferences` | Theme, view, clipboard, and backup preferences |
| `share_plus` | Sharing backup files and exports to other apps |
| `file_picker` | Selecting import files and files to save |
| `url_launcher` | Opening saved URLs in external apps/browser |
| `http` | Fetching link metadata |
| `cached_network_image` | Remote preview images |
| `google_fonts` | Theme typography |
| `animations`, `flutter_animate` | Screen and component animations |
| `flutter_slidable` | Swipe actions on records |
| `skeletonizer` | Loading placeholders |

Development dependencies: `flutter_test`, `flutter_lints`, and `flutter_launcher_icons`. Launcher icons are generated from `assets/Logo/logo.png` for Android; iOS icon generation is disabled. Do not document packages as used unless they are present in the manifest and connected to app behavior.

## Android platform details

- Minimum SDK follows `flutter.minSdkVersion`; `flutter_launcher_icons` configuration specifies Android min SDK 21.
- The manifest registers the launcher activity and inbound `ACTION_SEND` `text/plain` intent filter. Keep `android:exported="true"` for the launcher/share activity.
- The Kotlin method channel name and Dart channel name must remain exactly `com.example.clipvault/share`.
- Native splash resources show the launcher icon on a `#0B0B0D` background. Flutter then shows the app name in the branded startup screen.
- Rebuild and reinstall after changing Android manifest, Kotlin, launcher icon, or splash resources. Hot reload cannot update native resources.

## Working agreements for future changes

1. Read this reference, then inspect only the relevant source section and platform files before making changes.
2. Preserve local records, database migrations, current navigation, and existing behavior unless the feature request requires a change.
3. When adding or changing a feature, update the matching section above and the README feature list. Include any new package, preference key, database field/migration, platform channel, permission, or platform-specific limitation.
4. Keep Dart and Kotlin method channel names, payload formats, and intent filters synchronized.
5. Prefer the existing palette, `SavedItem`, `VaultDb`, and screen patterns over adding parallel implementations.
6. Do not claim a build or device behavior was verified unless it was actually run and observed.

## Local commands

```sh
flutter pub get
flutter run
flutter analyze
flutter build apk --release
```

Release APK output is normally `build/app/outputs/flutter-apk/app-release.apk`.
