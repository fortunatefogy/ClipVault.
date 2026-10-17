import 'dart:async';
import 'dart:convert';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:animations/animations.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:sqflite/sqflite.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:skeletonizer/skeletonizer.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:io';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;
  await VaultDb.instance.database;
  final settings = SharedPreferencesAsync();
  final themeName = await settings.getString('app_theme');
  activePalette.value = appPalettes.firstWhere(
    (palette) => palette.name == themeName,
    orElse: () => appPalettes.first,
  );
  autoPasteClipboard.value =
      await settings.getBool('auto_paste_clipboard') ?? true;
  runApp(const ClipVaultApp());
}

class AppPalette {
  final String name;
  final Color accent, highlight;
  const AppPalette(this.name, this.accent, this.highlight);
}

const appPalettes = [
  AppPalette('Ember', Color(0xFFFF7900), Color(0xFFFF9A2E)),
  AppPalette('Ocean', Color(0xFF38BDF8), Color(0xFF7DD3FC)),
  AppPalette('Violet', Color(0xFFA78BFA), Color(0xFFC4B5FD)),
  AppPalette('Forest', Color(0xFF34D399), Color(0xFF6EE7B7)),
  AppPalette('Rose', Color(0xFFFB7185), Color(0xFFFDA4AF)),
];
final ValueNotifier<AppPalette> activePalette =
    ValueNotifier(appPalettes.first);
final ValueNotifier<bool> autoPasteClipboard = ValueNotifier(true);
Color get auraBase => const Color(0xFF0B0B0D);
Color get auraSurface => const Color(0xFF17181C);
Color get auraDepth => const Color(0xFF1E2025);
Color get auraOrange => activePalette.value.accent;
Color get auraGold => activePalette.value.accent;
Color get auraHighlight => activePalette.value.highlight;
Color get bg => auraBase;
const primaryText = Color(0xFFFFFFFF);
const secondaryText = Color(0xFFA1A1AA);
const mutedText = Color(0xFF71717A);
Color get outline => const Color(0xFF303036);
const successColor = Color(0xFF34D399);
const errorColor = Color(0xFFF87171);

enum LibraryView { grid, compact, gallery, list, simple }

extension LibraryViewPresentation on LibraryView {
  String get label => switch (this) {
        LibraryView.grid => 'Grid',
        LibraryView.compact => 'Compact',
        LibraryView.gallery => 'Gallery',
        LibraryView.list => 'List',
        LibraryView.simple => 'Simple',
      };

  IconData get icon => switch (this) {
        LibraryView.grid => Icons.grid_view_rounded,
        LibraryView.compact => Icons.view_compact_rounded,
        LibraryView.gallery => Icons.dashboard_outlined,
        LibraryView.list => Icons.view_agenda_outlined,
        LibraryView.simple => Icons.menu_rounded,
      };
}

enum LibrarySort { auto, relevance, newest, oldest, mostOpened, recentlyOpened }

extension LibrarySortPresentation on LibrarySort {
  String get label => switch (this) {
        LibrarySort.auto => 'Auto',
        LibrarySort.relevance => 'Relevance',
        LibrarySort.newest => 'Newest',
        LibrarySort.oldest => 'Oldest',
        LibrarySort.mostOpened => 'Most opened',
        LibrarySort.recentlyOpened => 'Recently opened',
      };

  IconData get icon => switch (this) {
        LibrarySort.auto => Icons.auto_awesome_rounded,
        LibrarySort.relevance => Icons.manage_search_rounded,
        LibrarySort.newest => Icons.arrow_downward_rounded,
        LibrarySort.oldest => Icons.arrow_upward_rounded,
        LibrarySort.mostOpened => Icons.trending_up_rounded,
        LibrarySort.recentlyOpened => Icons.history_rounded,
      };
}

class LibraryFilters {
  final String category, type, date, source, tag;

  const LibraryFilters({
    this.category = 'All',
    this.type = 'All',
    this.date = 'All',
    this.source = 'All',
    this.tag = 'All',
  });
}

String? normalizeClipboardUrl(String value) {
  var candidate = value.trim();
  final embeddedUrl = RegExp(
          r'''(?:https?://|www\.)[^\s<>"']+|(?:[A-Za-z0-9-]+\.)+[A-Za-z]{2,}(?:/[^\s<>"']*)?''',
          caseSensitive: false)
      .firstMatch(candidate)
      ?.group(0);
  if (embeddedUrl != null) candidate = embeddedUrl;
  candidate = candidate.replaceFirst(RegExp(r'[),.;!?]+$'), '');

  final hasScheme =
      RegExp(r'^[a-z][a-z0-9+.-]*:', caseSensitive: false).hasMatch(candidate);
  if (!hasScheme &&
      RegExp(r'^(?:www\.)?(?:[A-Za-z0-9-]+\.)+[A-Za-z]{2,}(?::\d+)?(?:[/?#][^\s]*)?$',
              caseSensitive: false)
          .hasMatch(candidate)) {
    candidate = 'https://$candidate';
  }

  final uri = Uri.tryParse(candidate);
  if (uri == null ||
      (uri.scheme != 'https' && uri.scheme != 'http') ||
      uri.host.isEmpty ||
      (!uri.host.contains('.') && uri.host != 'localhost')) {
    return null;
  }
  return uri.toString();
}

bool looksLikeUrl(String value) => normalizeClipboardUrl(value) != null;

List<String> extractUrls(String value) {
  final urlPattern = RegExp(
      r'''(?:https?://|www\.)[^\s<>"']+|(?:[A-Za-z0-9-]+\.)+[A-Za-z]{2,}(?:/[^\s<>"']*)?''',
      caseSensitive: false);
  final urls = <String>{};
  for (final match in urlPattern.allMatches(value)) {
    final url = normalizeClipboardUrl(match.group(0) ?? '');
    if (url != null) urls.add(url);
  }
  return urls.toList();
}

Widget _savedImage(
  String source, {
  required BoxFit fit,
  required Widget placeholder,
  double? width,
  double? height,
}) {
  final localFile = File(source);
  if (localFile.existsSync()) {
    return Image.file(
      localFile,
      fit: fit,
      width: width,
      height: height,
      errorBuilder: (_, __, ___) => placeholder,
    );
  }
  return CachedNetworkImage(
    imageUrl: source,
    fit: fit,
    width: width,
    height: height,
    placeholder: (_, __) => placeholder,
    errorWidget: (_, __, ___) => placeholder,
  );
}

List<String> savedTagsFor(String value) => value
    .split(RegExp(r'[,;\n]'))
    .map((tag) => tag.trim().replaceFirst(RegExp(r'^#'), ''))
    .where((tag) => tag.isNotEmpty)
    .toList();

List<String> autoTagsFor(SavedItem item) {
  final host = Uri.tryParse(item.url)?.host.replaceFirst(
            RegExp(r'^www\.'),
            '',
          ) ??
      '';
  final source = '$host ${item.title} ${item.content} ${item.type}';
  const ignored = {
    'about',
    'after',
    'also',
    'and',
    'are',
    'for',
    'from',
    'has',
    'have',
    'http',
    'https',
    'into',
    'its',
    'more',
    'new',
    'our',
    'the',
    'this',
    'that',
    'their',
    'there',
    'with',
    'you',
    'your',
    'www',
    'com',
    'net',
    'org',
    'link',
    'note',
    'file',
    'html',
    'page',
  };
  final tags = <String>[];
  for (final match in RegExp(r'[A-Za-z0-9]{3,}').allMatches(source)) {
    final tag = match.group(0)!.toLowerCase();
    if (ignored.contains(tag) ||
        int.tryParse(tag) != null ||
        tags.contains(tag)) {
      continue;
    }
    tags.add(tag);
    if (tags.length == 6) break;
  }
  return tags;
}

class SavedItem {
  final int? id;
  final String title, url, content, type, tags, imageUrl;
  final bool favorite, isRead, isArchived;
  final int createdAt, openCount;
  final int? lastOpenedAt, deletedAt;

  const SavedItem({
    this.id,
    required this.title,
    this.url = '',
    this.content = '',
    this.type = 'note',
    this.tags = '',
    this.imageUrl = '',
    this.favorite = false,
    this.isRead = false,
    this.isArchived = false,
    required this.createdAt,
    this.openCount = 0,
    this.lastOpenedAt,
    this.deletedAt,
  });

  SavedItem copyWith(
          {int? id,
          String? title,
          String? url,
          String? content,
          String? type,
          String? tags,
          String? imageUrl,
          bool? favorite,
          bool? isRead,
          int? createdAt,
          int? openCount,
          int? lastOpenedAt,
          bool? isArchived,
          int? deletedAt}) =>
      SavedItem(
          id: id ?? this.id,
          title: title ?? this.title,
          url: url ?? this.url,
          content: content ?? this.content,
          type: type ?? this.type,
          tags: tags ?? this.tags,
          imageUrl: imageUrl ?? this.imageUrl,
          favorite: favorite ?? this.favorite,
          isRead: isRead ?? this.isRead,
          isArchived: isArchived ?? this.isArchived,
          createdAt: createdAt ?? this.createdAt,
          openCount: openCount ?? this.openCount,
          lastOpenedAt: lastOpenedAt ?? this.lastOpenedAt,
          deletedAt: deletedAt == 0 ? null : deletedAt ?? this.deletedAt);

  Map<String, Object?> toMap() => {
        'id': id,
        'title': title,
        'url': url,
        'content': content,
        'type': type,
        'tags': tags,
        'image_url': imageUrl,
        'favorite': favorite ? 1 : 0,
        'is_read': isRead ? 1 : 0,
        'created_at': createdAt,
        'open_count': openCount,
        'last_opened_at': lastOpenedAt,
        'is_archived': isArchived ? 1 : 0,
        'deleted_at': deletedAt,
      };

  factory SavedItem.fromMap(Map<String, Object?> m) => SavedItem(
        id: m['id'] as int?,
        title: m['title'] as String? ?? '',
        url: m['url'] as String? ?? '',
        content: m['content'] as String? ?? '',
        type: m['type'] as String? ?? 'note',
        tags: m['tags'] as String? ?? '',
        imageUrl: m['image_url'] as String? ?? '',
        favorite: (m['favorite'] as int? ?? 0) == 1,
        isRead: (m['is_read'] as int? ?? 0) == 1,
        createdAt:
            m['created_at'] as int? ?? DateTime.now().millisecondsSinceEpoch,
        openCount: m['open_count'] as int? ?? 0,
        lastOpenedAt: m['last_opened_at'] as int?,
        isArchived: (m['is_archived'] as int? ?? 0) == 1,
        deletedAt: m['deleted_at'] as int?,
      );
}

class LinkMetadata {
  final String title, image, description;
  const LinkMetadata({this.title = '', this.image = '', this.description = ''});

  static const _ua =
      'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120 Mobile Safari/537.36';

  static Future<LinkMetadata> fetch(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme) return const LinkMetadata();
    try {
      final res = await http.get(uri, headers: {
        'User-Agent': _ua,
        'Accept': 'text/html,application/xhtml+xml',
      }).timeout(const Duration(seconds: 12));
      if (res.statusCode < 200 || res.statusCode >= 400) {
        return const LinkMetadata();
      }
      final html = utf8.decode(res.bodyBytes, allowMalformed: true);
      final metas = _parseMetas(html);

      String pick(List<String> keys) {
        for (final k in keys) {
          final v = metas[k];
          if (v != null && v.trim().isNotEmpty) return _unescape(v.trim());
        }
        return '';
      }

      final titleTag = RegExp(r'<title[^>]*>(.*?)</title>',
                  caseSensitive: false, dotAll: true)
              .firstMatch(html)
              ?.group(1)
              ?.trim() ??
          '';
      var title = pick(['og:title', 'twitter:title']);
      if (title.isEmpty) title = _unescape(titleTag);

      var image = pick([
        'og:image:secure_url',
        'og:image:url',
        'og:image',
        'twitter:image',
        'twitter:image:src'
      ]);
      if (image.isNotEmpty) image = uri.resolve(image).toString();

      final description =
          pick(['og:description', 'twitter:description', 'description']);
      return LinkMetadata(title: title, image: image, description: description);
    } catch (_) {
      return const LinkMetadata();
    }
  }

  static Map<String, String> _parseMetas(String html) {
    final out = <String, String>{};
    final tagRe = RegExp(r'<meta\b[^>]*>', caseSensitive: false);
    final attrRe = RegExp(
        r'''([a-zA-Z_:][-a-zA-Z0-9_:.]*)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'>]+))''');
    for (final m in tagRe.allMatches(html)) {
      final attrs = <String, String>{};
      for (final a in attrRe.allMatches(m.group(0)!)) {
        attrs[a.group(1)!.toLowerCase()] =
            a.group(2) ?? a.group(3) ?? a.group(4) ?? '';
      }
      final key =
          (attrs['property'] ?? attrs['name'] ?? attrs['itemprop'] ?? '')
              .toLowerCase();
      final content = attrs['content'];
      if (key.isNotEmpty &&
          content != null &&
          content.isNotEmpty &&
          !out.containsKey(key)) {
        out[key] = content;
      }
    }
    return out;
  }

  static String _unescape(String s) => s
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&#x27;', "'")
      .replaceAll('&nbsp;', ' ')
      .replaceAllMapped(RegExp(r'&#(\d+);'),
          (m) => String.fromCharCode(int.tryParse(m.group(1)!) ?? 0));
}

class VaultDb {
  VaultDb._();
  static final instance = VaultDb._();
  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    final dir = await getDatabasesPath();
    _db = await openDatabase(p.join(dir, 'clipvault.db'),
        version: 4,
        onCreate: (db, version) => db.execute('''
        CREATE TABLE items(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          title TEXT NOT NULL, url TEXT NOT NULL DEFAULT '',
          content TEXT NOT NULL DEFAULT '', type TEXT NOT NULL DEFAULT 'note',
          tags TEXT NOT NULL DEFAULT '', image_url TEXT NOT NULL DEFAULT '',
          favorite INTEGER NOT NULL DEFAULT 0,
          is_read INTEGER NOT NULL DEFAULT 0, created_at INTEGER NOT NULL,
          open_count INTEGER NOT NULL DEFAULT 0, last_opened_at INTEGER,
          is_archived INTEGER NOT NULL DEFAULT 0, deleted_at INTEGER
        )
      '''),
        onUpgrade: (db, oldVersion, newVersion) async {
          if (oldVersion < 2) {
            await db.execute(
                "ALTER TABLE items ADD COLUMN image_url TEXT NOT NULL DEFAULT ''");
          }
          if (oldVersion < 3) {
            await db.execute(
                'ALTER TABLE items ADD COLUMN open_count INTEGER NOT NULL DEFAULT 0');
            await db
                .execute('ALTER TABLE items ADD COLUMN last_opened_at INTEGER');
          }
          if (oldVersion < 4) {
            await db.execute(
                'ALTER TABLE items ADD COLUMN is_archived INTEGER NOT NULL DEFAULT 0');
            await db.execute('ALTER TABLE items ADD COLUMN deleted_at INTEGER');
          }
        });
    return _db!;
  }

  Future<List<SavedItem>> all() async {
    final rows =
        await (await database).query('items', orderBy: 'created_at DESC');
    return rows.map(SavedItem.fromMap).toList();
  }

  Future<int> save(SavedItem item) async {
    final db = await database;
    if (item.id == null) {
      return db.insert('items', item.toMap()..remove('id'));
    }
    return db.update('items', item.toMap()..remove('id'),
        where: 'id = ?', whereArgs: [item.id]);
  }

  Future<SavedItem> recordOpen(SavedItem item) async {
    final id = item.id;
    if (id == null) return item;
    final openedAt = DateTime.now().millisecondsSinceEpoch;
    final db = await database;
    await db.rawUpdate(
      'UPDATE items SET open_count = open_count + 1, last_opened_at = ? WHERE id = ?',
      [openedAt, id],
    );
    final rows = await db.query('items', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? item : SavedItem.fromMap(rows.first);
  }

  Future<void> delete(int id) async =>
      (await database).delete('items', where: 'id = ?', whereArgs: [id]);

  Future<void> moveToTrash(int id) async {
    await (await database).update(
      'items',
      {'deleted_at': DateTime.now().millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> purgeExpiredTrash() async {
    final cutoff = DateTime.now()
        .subtract(const Duration(days: 30))
        .millisecondsSinceEpoch;
    await (await database).delete('items',
        where: 'deleted_at IS NOT NULL AND deleted_at < ?',
        whereArgs: [cutoff]);
  }

  Future<void> clearAll() async => (await database).delete('items');

  Future<void> emptyTrash() async => (await database).delete(
        'items',
        where: 'deleted_at IS NOT NULL',
      );

  Future<void> replaceAll(List<SavedItem> items) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('items');
      for (final item in items) {
        await txn.insert('items', item.toMap()..remove('id'));
      }
    });
  }
}

Future<void> runAutomaticBackupIfDue() async {
  try {
    final preferences = SharedPreferencesAsync();
    if (await preferences.getBool('auto_backup') != true) return;
    final now = DateTime.now();
    final previous = await preferences.getInt('last_auto_backup') ?? 0;
    if (now.millisecondsSinceEpoch - previous <
        const Duration(hours: 24).inMilliseconds) {
      return;
    }
    final documents = await getApplicationDocumentsDirectory();
    final directory = Directory(p.join(documents.path, 'backups'));
    if (!await directory.exists()) await directory.create(recursive: true);
    final data =
        (await VaultDb.instance.all()).map((item) => item.toMap()).toList();
    final file = File(p.join(
        directory.path, 'clipvault-auto-${now.millisecondsSinceEpoch}.json'));
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(data));
    await preferences.setInt('last_auto_backup', now.millisecondsSinceEpoch);
    final backups = directory
        .listSync()
        .whereType<File>()
        .where((entry) => entry.path.endsWith('.json'))
        .toList()
      ..sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
    for (final old in backups.skip(10)) {
      await old.delete();
    }
  } catch (_) {
    // An unavailable device filesystem should not interrupt library use.
  }
}

class ClipVaultApp extends StatelessWidget {
  const ClipVaultApp({super.key});
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: activePalette,
        builder: (context, _) => MaterialApp(
          title: 'ClipVault',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            brightness: Brightness.dark,
            scaffoldBackgroundColor: bg,
            colorScheme: ColorScheme.fromSeed(
                    seedColor: auraGold, brightness: Brightness.dark)
                .copyWith(
                    primary: auraGold,
                    onPrimary: auraBase,
                    secondary: auraOrange,
                    tertiary: auraOrange,
                    surface: auraSurface,
                    onSurface: primaryText,
                    error: errorColor,
                    outline: outline,
                    surfaceContainer: auraSurface,
                    surfaceContainerHighest: auraDepth),
            useMaterial3: true,
            canvasColor: auraSurface,
            textSelectionTheme: TextSelectionThemeData(
              cursorColor: auraOrange,
              selectionHandleColor: auraOrange,
            ),
            appBarTheme: const AppBarTheme(
                backgroundColor: Colors.transparent,
                foregroundColor: primaryText,
                elevation: 0,
                scrolledUnderElevation: 0),
            iconTheme: const IconThemeData(color: secondaryText),
            iconButtonTheme: IconButtonThemeData(
              style: IconButton.styleFrom(
                foregroundColor: secondaryText,
                minimumSize: const Size(48, 48),
                tapTargetSize: MaterialTapTargetSize.padded,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
            ),
            textTheme:
                GoogleFonts.playpenSansTextTheme(ThemeData.dark().textTheme)
                    .apply(bodyColor: primaryText, displayColor: primaryText),
            filledButtonTheme: FilledButtonThemeData(
                style: FilledButton.styleFrom(
                    backgroundColor: auraGold,
                    foregroundColor: auraBase,
                    minimumSize: const Size(48, 48),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)))),
            floatingActionButtonTheme: FloatingActionButtonThemeData(
                backgroundColor: auraGold, foregroundColor: auraBase),
            cardTheme: CardThemeData(
              color: auraSurface,
              elevation: 0,
              margin: EdgeInsets.zero,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(color: outline),
              ),
            ),
            dividerTheme: DividerThemeData(color: outline, thickness: 1),
            chipTheme: ChipThemeData(
                backgroundColor: auraDepth,
                selectedColor: auraGold,
                side: BorderSide(color: outline),
                shape: const StadiumBorder(),
                labelStyle: const TextStyle(color: secondaryText),
                secondaryLabelStyle:
                    TextStyle(color: auraBase, fontWeight: FontWeight.w700)),
            dialogTheme: DialogThemeData(
                backgroundColor: auraSurface,
                surfaceTintColor: Colors.transparent,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24))),
            popupMenuTheme: PopupMenuThemeData(
              color: auraDepth,
              textStyle: const TextStyle(color: primaryText),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: outline),
              ),
            ),
            snackBarTheme: SnackBarThemeData(
                backgroundColor: auraDepth,
                contentTextStyle: const TextStyle(color: primaryText),
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14))),
            inputDecorationTheme: InputDecorationTheme(
              filled: true,
              fillColor: auraSurface,
              hintStyle: const TextStyle(color: secondaryText),
              labelStyle: const TextStyle(color: secondaryText),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: outline)),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: outline)),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: auraGold, width: 1.5)),
            ),
          ),
          home: const StartupSplashScreen(),
        ),
      );
}

class StartupSplashScreen extends StatefulWidget {
  const StartupSplashScreen({super.key});

  @override
  State<StartupSplashScreen> createState() => _StartupSplashScreenState();
}

class _StartupSplashScreenState extends State<StartupSplashScreen> {
  @override
  void initState() {
    super.initState();
    Future<void>.delayed(const Duration(milliseconds: 750), () {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        PageRouteBuilder<void>(
          pageBuilder: (_, __, ___) => const LibraryScreen(),
          transitionsBuilder: (_, animation, __, child) => FadeTransition(
            opacity: animation,
            child: child,
          ),
          transitionDuration: const Duration(milliseconds: 220),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: bg,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(30),
                child: Image.asset(
                  'assets/Logo/logo.png',
                  width: 112,
                  height: 112,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'ClipVault',
                style: GoogleFonts.playpenSans(
                  color: primaryText,
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.2,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Your personal library',
                style: GoogleFonts.playpenSans(
                  color: secondaryText,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      );
}

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});
  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class SettingsScreen extends StatefulWidget {
  final List<SavedItem> items;
  final Future<void> Function() onImport, onExport;
  const SettingsScreen(
      {super.key,
      required this.items,
      required this.onImport,
      required this.onExport});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final SharedPreferencesAsync _preferences = SharedPreferencesAsync();

  Future<void> _selectPalette(AppPalette palette) async {
    activePalette.value = palette;
    await _preferences.setString('app_theme', palette.name);
    if (mounted) setState(() {});
  }

  Future<void> _setClipboard(bool enabled) async {
    autoPasteClipboard.value = enabled;
    await _preferences.setBool('auto_paste_clipboard', enabled);
    if (mounted) setState(() {});
  }

  Widget _section({required String title, required Widget child}) => Container(
        margin: const EdgeInsets.only(bottom: 18),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: auraSurface,
          border: Border.all(color: outline),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title.toUpperCase(),
                style: TextStyle(
                    color: auraHighlight,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.5)),
            const SizedBox(height: 14),
            child,
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final mediaCount = widget.items
        .where((item) => item.type == 'file' && item.deletedAt == null)
        .length;
    final linkCount = widget.items
        .where((item) => item.url.isNotEmpty && item.deletedAt == null)
        .length;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: bg,
        appBar: AppBar(
          title: const Text('Settings'),
          bottom: const TabBar(tabs: [
            Tab(text: 'Settings'),
            Tab(text: 'Data'),
          ]),
        ),
        body: TabBarView(children: [
          ListView(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 28),
            children: [
              _section(
                title: 'Your media',
                child: Column(children: [
                  _countRow(Icons.perm_media_outlined, 'Files', mediaCount),
                  const Divider(height: 24),
                  _countRow(Icons.link_rounded, 'Links', linkCount),
                ]),
              ),
              _section(
                title: 'Appearance',
                child: Column(
                  children: [
                    for (final palette in appPalettes)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(
                          radius: 13,
                          backgroundColor: palette.accent,
                          child: activePalette.value.name == palette.name
                              ? Icon(Icons.check_rounded,
                                  color: auraBase, size: 17)
                              : null,
                        ),
                        title: Text(palette.name,
                            style: TextStyle(
                                color: activePalette.value.name == palette.name
                                    ? palette.highlight
                                    : primaryText,
                                fontWeight:
                                    activePalette.value.name == palette.name
                                        ? FontWeight.w700
                                        : FontWeight.w500)),
                        trailing: activePalette.value.name == palette.name
                            ? Icon(Icons.radio_button_checked,
                                color: palette.accent)
                            : const Icon(Icons.radio_button_off,
                                color: secondaryText),
                        onTap: () => _selectPalette(palette),
                      ),
                  ],
                ),
              ),
              _section(
                title: 'Clipboard',
                child: SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Auto-paste links'),
                  subtitle: const Text(
                      'Detect a copied link when ClipVault opens or resumes.',
                      style: TextStyle(color: secondaryText, height: 1.4)),
                  value: autoPasteClipboard.value,
                  activeColor: auraGold,
                  onChanged: _setClipboard,
                ),
              ),
            ],
          ),
          _DataSettingsPage(
            items: widget.items,
            onImport: widget.onImport,
            onExport: widget.onExport,
          ),
        ]),
      ),
    );
  }

  Widget _countRow(IconData icon, String title, int count) => Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
                color: auraDepth, borderRadius: BorderRadius.circular(15)),
            child: Icon(icon, color: auraHighlight, size: 25),
          ),
          const SizedBox(width: 14),
          Expanded(
              child: Text(title,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700))),
          Text('$count',
              style: TextStyle(
                  color: auraHighlight,
                  fontSize: 23,
                  fontWeight: FontWeight.w800)),
        ],
      );
}

class _DataSettingsPage extends StatelessWidget {
  final List<SavedItem> items;
  final Future<void> Function() onImport, onExport;
  const _DataSettingsPage(
      {required this.items, required this.onImport, required this.onExport});

  @override
  Widget build(BuildContext context) {
    final archived =
        items.where((item) => item.isArchived && item.deletedAt == null).length;
    final trashed = items.where((item) => item.deletedAt != null).length;
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 28),
      children: [
        _dataSectionLabel('DATA'),
        _dataCard(context, [
          _DataEntry(
              Icons.archive_outlined,
              'Archive',
              'Items you archive land here · $archived',
              () => _open(context, ArchiveTrashScreen(archived: true))),
          _DataEntry(
              Icons.delete_outline,
              'Trash',
              'Deleted items are kept for 30 days · $trashed',
              () => _open(context, ArchiveTrashScreen(archived: false))),
          _DataEntry(
              Icons.inventory_2_outlined,
              'Backups',
              'Create, restore, and share local backups.',
              () => _open(context, const BackupsScreen())),
          _DataEntry(
              Icons.storage_outlined,
              'Import & export',
              'Bring in bookmarks or export JSON, HTML, Markdown, and CSV.',
              () => _open(
                  context,
                  ImportExportScreen(
                      onImport: onImport, onExport: onExport, items: items))),
          _DataEntry(Icons.delete_forever_outlined, 'Clear everything',
              'Permanently remove all saved items.', () => _clear(context),
              destructive: true),
        ]),
      ],
    );
  }

  Future<void> _open(BuildContext context, Widget page) async {
    await Navigator.of(context)
        .push<void>(MaterialPageRoute(builder: (_) => page));
  }

  Future<void> _clear(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear all saved items?'),
        content: const Text(
            'This permanently removes every saved item in ClipVault. Back up your library first if you may need it later.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Clear everything')),
        ],
      ),
    );
    if (confirmed == true) await VaultDb.instance.clearAll();
  }

  static Widget _dataSectionLabel(String title) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
        child: Text(title,
            style: const TextStyle(
                color: mutedText, fontSize: 12, letterSpacing: 2)),
      );

  static Widget _dataCard(BuildContext context, List<_DataEntry> entries) =>
      Container(
        decoration: BoxDecoration(
          color: auraSurface,
          border: Border.all(color: outline),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          children: [
            for (var i = 0; i < entries.length; i++) ...[
              ListTile(
                minVerticalPadding: 14,
                leading: Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: auraDepth,
                    border: Border.all(color: outline),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(entries[i].icon,
                      color: entries[i].destructive ? errorColor : primaryText),
                ),
                title: Text(entries[i].title,
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color:
                            entries[i].destructive ? errorColor : primaryText)),
                subtitle: Text(entries[i].subtitle,
                    style: const TextStyle(color: secondaryText, height: 1.35)),
                trailing: const Icon(Icons.chevron_right_rounded,
                    color: secondaryText),
                onTap: entries[i].action,
              ),
              if (i != entries.length - 1)
                const Divider(height: 1, indent: 78, endIndent: 18),
            ],
          ],
        ),
      );
}

class _DataEntry {
  final IconData icon;
  final String title, subtitle;
  final VoidCallback action;
  final bool destructive;
  const _DataEntry(this.icon, this.title, this.subtitle, this.action,
      {this.destructive = false});
}

class ArchiveTrashScreen extends StatefulWidget {
  final bool archived;
  const ArchiveTrashScreen({super.key, required this.archived});
  @override
  State<ArchiveTrashScreen> createState() => _ArchiveTrashScreenState();
}

class _ArchiveTrashScreenState extends State<ArchiveTrashScreen> {
  List<SavedItem> _items = [];
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await VaultDb.instance.purgeExpiredTrash();
    final all = await VaultDb.instance.all();
    if (!mounted) return;
    setState(() => _items = all
        .where((item) => widget.archived
            ? item.isArchived && item.deletedAt == null
            : item.deletedAt != null)
        .toList());
  }

  Future<void> _restore(SavedItem item) async {
    if (item.id == null) return;
    await VaultDb.instance.save(item.copyWith(isArchived: false, deletedAt: 0));
    await _load();
  }

  Future<void> _deleteForever(SavedItem item) async {
    if (item.id == null) return;
    await VaultDb.instance.delete(item.id!);
    await _load();
  }

  Future<void> _emptyTrash() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Empty trash?'),
        content: const Text('These items will be permanently deleted.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Empty trash')),
        ],
      ),
    );
    if (confirmed == true) {
      await VaultDb.instance.emptyTrash();
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: bg,
        appBar: AppBar(
          title: Text(widget.archived ? 'Archive' : 'Trash'),
          actions: [
            if (!widget.archived && _items.isNotEmpty)
              IconButton(
                tooltip: 'Empty trash',
                onPressed: _emptyTrash,
                icon: const Icon(Icons.delete_outline, color: errorColor),
              ),
          ],
        ),
        body: _items.isEmpty
            ? Center(
                child: Text(
                    widget.archived ? 'No archived items' : 'Trash is empty',
                    style: const TextStyle(color: secondaryText)))
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Text(
                        widget.archived
                            ? 'Archived items are stored here until you restore them.'
                            : 'Deleted items are kept for 30 days, then removed automatically.',
                        style: const TextStyle(
                            color: secondaryText, fontSize: 15)),
                  ),
                  for (final item in _items)
                    Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                          color: auraSurface,
                          border: Border.all(color: outline),
                          borderRadius: BorderRadius.circular(18)),
                      child: ListTile(
                        title: Text(item.title,
                            maxLines: 2, overflow: TextOverflow.ellipsis),
                        subtitle: Text(
                            item.url.isEmpty
                                ? item.type.toUpperCase()
                                : item.url,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: secondaryText)),
                        trailing: Wrap(spacing: 4, children: [
                          IconButton(
                              tooltip: 'Restore',
                              onPressed: () => _restore(item),
                              icon: const Icon(Icons.restore_rounded)),
                          IconButton(
                              tooltip: 'Delete permanently',
                              onPressed: () => _deleteForever(item),
                              icon: const Icon(Icons.delete_forever_outlined,
                                  color: errorColor)),
                        ]),
                      ),
                    ),
                ],
              ),
      );
}

class ImportExportScreen extends StatelessWidget {
  final Future<void> Function() onImport, onExport;
  final List<SavedItem> items;
  const ImportExportScreen(
      {super.key,
      required this.onImport,
      required this.onExport,
      required this.items});

  Future<void> _shareText(String name, String contents) async {
    final dir = await getTemporaryDirectory();
    final file = File(p.join(dir.path, name));
    await file.writeAsString(contents);
    await Share.shareXFiles([XFile(file.path)]);
  }

  @override
  Widget build(BuildContext context) {
    final active = items.where((item) => item.deletedAt == null).toList();
    String host(String value) => Uri.tryParse(value)?.host ?? value;
    String escapeHtml(String value) => value
        .replaceAll('&', '&amp;')
        .replaceAll('"', '&quot;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;');
    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(title: const Text('Import & export')),
      body: ListView(padding: const EdgeInsets.all(18), children: [
        const Text(
            'Everything you save is yours. Every format is free — no account, no upgrade.',
            style: TextStyle(color: secondaryText, fontSize: 16)),
        const SizedBox(height: 24),
        _dataSettingsPageLabel('EXPORT'),
        _dataSettingsCard([
          _DataEntry(Icons.file_download_outlined, 'JSON (ClipVault backup)',
              'Full fidelity. Restore it on any device.', onExport),
          _DataEntry(
              Icons.bookmarks_outlined,
              'HTML bookmarks',
              'Universal bookmark format.',
              () => _shareText('clipvault-bookmarks.html',
                  '<!doctype html><meta charset="utf-8"><title>ClipVault bookmarks</title><h1>ClipVault</h1><dl>${active.where((item) => item.url.isNotEmpty).map((item) => '<dt><a href="${escapeHtml(item.url)}">${escapeHtml(item.title)}</a><dd>${escapeHtml(host(item.url))}</dd>').join()}</dl>')),
          _DataEntry(
              Icons.description_outlined,
              'Markdown',
              'Human-readable saved items.',
              () => _shareText(
                  'clipvault.md',
                  active
                      .map((item) =>
                          '## ${item.title}\n\n${item.url.isEmpty ? item.content : item.url}\n')
                      .join('\n'))),
          _DataEntry(
              Icons.table_chart_outlined,
              'CSV',
              'Open in Numbers, Excel, or Sheets.',
              () => _shareText(
                  'clipvault.csv',
                  'title,url,type,tags,created_at\n${active.map((item) => [
                        item.title,
                        item.url,
                        item.type,
                        item.tags,
                        DateTime.fromMillisecondsSinceEpoch(item.createdAt)
                            .toIso8601String()
                      ].map((v) => '"${v.replaceAll('"', '""')}"').join(',')).join('\n')}')),
        ], context),
        const SizedBox(height: 22),
        _dataSettingsPageLabel('IMPORT'),
        _dataSettingsCard([
          _DataEntry(
              Icons.file_upload_outlined,
              'Import from file',
              'JSON backup or HTML bookmarks from Safari, Chrome, and other browsers.',
              onImport),
        ], context),
        const SizedBox(height: 22),
        _dataSettingsPageLabel('TIDY UP'),
        _dataSettingsCard([
          _DataEntry(
              Icons.content_copy_rounded,
              'Find duplicates',
              'Scan for records saved more than once at the same URL.',
              () => Navigator.of(context).push<void>(MaterialPageRoute(
                  builder: (_) => const DuplicateFinderScreen()))),
        ], context),
        const SizedBox(height: 18),
        const Text(
            'Imports merge into your library and never replace existing items.',
            style: TextStyle(color: mutedText, fontStyle: FontStyle.italic)),
      ]),
    );
  }

  static Widget _dataSettingsPageLabel(String text) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(text,
          style: const TextStyle(
              color: mutedText, letterSpacing: 2, fontSize: 12)));
  static Widget _dataSettingsCard(
          List<_DataEntry> entries, BuildContext context) =>
      Container(
          decoration: BoxDecoration(
              color: auraSurface,
              border: Border.all(color: outline),
              borderRadius: BorderRadius.circular(18)),
          child: Column(children: [
            for (var i = 0; i < entries.length; i++) ...[
              ListTile(
                  leading: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                          color: auraDepth,
                          borderRadius: BorderRadius.circular(14)),
                      child: Icon(entries[i].icon, color: primaryText)),
                  title: Text(entries[i].title,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(entries[i].subtitle,
                      style: const TextStyle(color: secondaryText)),
                  onTap: entries[i].action),
              if (i != entries.length - 1)
                const Divider(height: 1, indent: 76, endIndent: 16)
            ]
          ]));
}

class DuplicateFinderScreen extends StatefulWidget {
  const DuplicateFinderScreen({super.key});
  @override
  State<DuplicateFinderScreen> createState() => _DuplicateFinderScreenState();
}

class _DuplicateFinderScreenState extends State<DuplicateFinderScreen> {
  List<List<SavedItem>> _groups = [];

  @override
  void initState() {
    super.initState();
    _scan();
  }

  Future<void> _scan() async {
    final items = await VaultDb.instance.all();
    final grouped = <String, List<SavedItem>>{};
    for (final item in items
        .where((item) => item.url.isNotEmpty && item.deletedAt == null)) {
      final key = normalizeClipboardUrl(item.url)?.toLowerCase() ??
          item.url.toLowerCase();
      grouped.putIfAbsent(key, () => []).add(item);
    }
    final groups = grouped.values.where((group) => group.length > 1).toList();
    if (!mounted) return;
    setState(() => _groups = groups);
  }

  Future<void> _cleanGroup(List<SavedItem> group) async {
    final ordered = [...group]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    for (final item in ordered.skip(1)) {
      if (item.id != null) await VaultDb.instance.moveToTrash(item.id!);
    }
    await _scan();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: bg,
        appBar: AppBar(title: const Text('Find duplicates')),
        body: _groups.isEmpty
            ? const Center(
                child: Text('No duplicate links found.',
                    style: TextStyle(color: secondaryText)))
            : ListView(
                padding: const EdgeInsets.all(18),
                children: [
                  Text('${_groups.length} duplicate URL groups',
                      style: const TextStyle(color: secondaryText)),
                  const SizedBox(height: 12),
                  for (final group in _groups)
                    Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                          color: auraSurface,
                          border: Border.all(color: outline),
                          borderRadius: BorderRadius.circular(18)),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(group.first.url,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(color: auraHighlight)),
                              const SizedBox(height: 6),
                              Text('${group.length} saved records',
                                  style: const TextStyle(color: secondaryText)),
                              Align(
                                  alignment: Alignment.centerRight,
                                  child: TextButton.icon(
                                      onPressed: () => _cleanGroup(group),
                                      icon: const Icon(
                                          Icons.auto_fix_high_rounded),
                                      label: const Text(
                                          'Keep newest, move others to Trash'))),
                            ]),
                      ),
                    ),
                ],
              ),
      );
}

class BackupsScreen extends StatefulWidget {
  const BackupsScreen({super.key});
  @override
  State<BackupsScreen> createState() => _BackupsScreenState();
}

class _BackupsScreenState extends State<BackupsScreen> {
  final SharedPreferencesAsync _prefs = SharedPreferencesAsync();
  List<File> _files = [];
  bool _auto = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<Directory> _backupDirectory() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'backups'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<void> _load() async {
    await VaultDb.instance.purgeExpiredTrash();
    _auto = await _prefs.getBool('auto_backup') ?? false;
    final dir = await _backupDirectory();
    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.json'))
        .toList()
      ..sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
    if (!mounted) return;
    setState(() => _files = files);
    if (_auto) await _autoSnapshotIfDue();
  }

  Future<void> _snapshot({bool automatic = false}) async {
    final dir = await _backupDirectory();
    final data =
        (await VaultDb.instance.all()).map((item) => item.toMap()).toList();
    final now = DateTime.now();
    final stamp =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}-${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}';
    final file = File(p.join(dir.path, 'clipvault-$stamp.json'));
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(data));
    if (automatic) {
      await _prefs.setInt('last_auto_backup', now.millisecondsSinceEpoch);
    }
    await _trimBackups(dir);
    await _load();
  }

  Future<void> _autoSnapshotIfDue() async {
    final last = await _prefs.getInt('last_auto_backup') ?? 0;
    if (DateTime.now().millisecondsSinceEpoch - last >=
        const Duration(hours: 24).inMilliseconds) {
      await _snapshot(automatic: true);
    }
  }

  Future<void> _trimBackups(Directory dir) async {
    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.json'))
        .toList()
      ..sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
    for (final file in files.skip(10)) {
      await file.delete();
    }
  }

  Future<void> _restore(File file) async {
    final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
                title: const Text('Restore this backup?'),
                content: const Text(
                    'Restoring replaces your current library with the contents of this snapshot.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancel')),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Restore'))
                ]));
    if (ok != true) return;
    try {
      final decoded = jsonDecode(await file.readAsString()) as List;
      final items = decoded.map((row) {
        final map = Map<String, Object?>.from(row as Map);
        map.remove('id');
        return SavedItem.fromMap(map);
      }).toList();
      await VaultDb.instance.replaceAll(items);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Restored ${items.length} items')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not restore this backup')));
      }
    }
  }

  Future<void> _share(File file) async => Share.shareXFiles([XFile(file.path)]);

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: bg,
        appBar: AppBar(title: const Text('Backups')),
        body: ListView(padding: const EdgeInsets.all(18), children: [
          const Text(
              'Backups are stored on this device. You can restore one any time or share it for safekeeping.',
              style: TextStyle(color: secondaryText, fontSize: 15)),
          const SizedBox(height: 20),
          Container(
              decoration: BoxDecoration(
                  color: auraSurface,
                  border: Border.all(color: outline),
                  borderRadius: BorderRadius.circular(18)),
              child: Column(children: [
                SwitchListTile(
                    title: const Text('Auto backup'),
                    subtitle: const Text(
                        'Take a snapshot every 24 hours. Keep the last 10.',
                        style: TextStyle(color: secondaryText)),
                    value: _auto,
                    activeColor: auraGold,
                    onChanged: (value) async {
                      setState(() => _auto = value);
                      await _prefs.setBool('auto_backup', value);
                      if (value) await _autoSnapshotIfDue();
                    }),
                const Divider(height: 1, indent: 72),
                ListTile(
                    leading: const Icon(Icons.add_rounded),
                    title: const Text('Snapshot now'),
                    subtitle: const Text(
                        'Save the current library as a new backup file.',
                        style: TextStyle(color: secondaryText)),
                    onTap: () => _snapshot()),
                const Divider(height: 1, indent: 72),
                ListTile(
                    leading: const Icon(Icons.file_open_outlined),
                    title: const Text('Restore from file'),
                    subtitle: const Text(
                        'Pick a JSON backup shared from another device.',
                        style: TextStyle(color: secondaryText)),
                    onTap: () async {
                      final result = await FilePicker.platform.pickFiles(
                          type: FileType.custom, allowedExtensions: ['json']);
                      if (result?.files.single.path != null) {
                        await _restore(File(result!.files.single.path!));
                      }
                    }),
              ])),
          const SizedBox(height: 24),
          Text('${_files.length} BACKUPS ON DEVICE',
              style: const TextStyle(
                  color: mutedText, letterSpacing: 2, fontSize: 12)),
          const SizedBox(height: 12),
          if (_files.isEmpty)
            const Text('No backups yet. Create a snapshot to start.',
                style: TextStyle(color: secondaryText)),
          for (final file in _files)
            Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                    color: auraSurface,
                    border: Border.all(color: outline),
                    borderRadius: BorderRadius.circular(18)),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Expanded(
                            child: Text(p.basenameWithoutExtension(file.path),
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700))),
                        Text(
                            '${(file.lengthSync() / 1024).toStringAsFixed(1)} KB',
                            style: const TextStyle(color: mutedText))
                      ]),
                      const SizedBox(height: 12),
                      Wrap(spacing: 6, children: [
                        TextButton.icon(
                            onPressed: () => _restore(file),
                            icon: const Icon(Icons.restore_rounded),
                            label: const Text('Restore')),
                        TextButton.icon(
                            onPressed: () => _share(file),
                            icon: const Icon(Icons.share_outlined),
                            label: const Text('Share')),
                        TextButton.icon(
                            onPressed: () async {
                              await file.delete();
                              await _load();
                            },
                            icon: const Icon(Icons.delete_outline,
                                color: errorColor),
                            label: const Text('Delete',
                                style: TextStyle(color: errorColor)))
                      ])
                    ])),
        ]),
      );
}

class _LibraryScreenState extends State<LibraryScreen>
    with WidgetsBindingObserver {
  List<SavedItem> items = [];
  String query = '';
  String filter = 'All';
  bool _checkingClipboard = false;
  bool _loadingItems = true;
  String _lastSeenClipboardUrl = '';
  LibraryView _libraryView = LibraryView.grid;
  LibrarySort _librarySort = LibrarySort.auto;
  String _typeFilter = 'All';
  String _dateFilter = 'All';
  String _sourceFilter = 'All';
  String _tagFilter = 'All';
  final SharedPreferencesAsync _preferences = SharedPreferencesAsync();
  Timer? _autoBackupTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadViewPreference();
    _refresh(showLoading: true);
    _scheduleClipboardCheck();
    _autoBackupTimer = Timer.periodic(const Duration(hours: 1), (_) {
      unawaited(runAutomaticBackupIfDue());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _autoBackupTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _scheduleClipboardCheck();
      unawaited(runAutomaticBackupIfDue());
    }
  }

  void _scheduleClipboardCheck() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future<void>.delayed(const Duration(milliseconds: 250), _checkClipboard);
    });
  }

  Future<void> _loadViewPreference() async {
    final savedView = await _preferences.getString('library_view');
    final savedSort = await _preferences.getString('library_sort');
    final view = LibraryView.values.where((value) => value.name == savedView);
    final sort = LibrarySort.values.where((value) => value.name == savedSort);
    if (mounted && (view.isNotEmpty || sort.isNotEmpty)) {
      setState(() {
        if (view.isNotEmpty) _libraryView = view.first;
        if (sort.isNotEmpty) _librarySort = sort.first;
      });
    }
  }

  Future<void> _refresh({bool showLoading = false}) async {
    if (showLoading && mounted) setState(() => _loadingItems = true);
    try {
      await VaultDb.instance.purgeExpiredTrash();
      await runAutomaticBackupIfDue();
      final data = await VaultDb.instance.all();
      if (mounted) setState(() => items = data);
    } finally {
      if (mounted && _loadingItems) setState(() => _loadingItems = false);
    }
  }

  Future<String> _clipboardUrl() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      return normalizeClipboardUrl(data?.text ?? '') ?? '';
    } catch (_) {
      // Clipboard access can be restricted by Android or unavailable on some platforms.
      return '';
    }
  }

  Future<void> _checkClipboard() async {
    if (!autoPasteClipboard.value || _checkingClipboard || !mounted) return;
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return;
    _checkingClipboard = true;
    try {
      final url = await _clipboardUrl();
      final hasNewClipboardUrl = url.isNotEmpty && url != _lastSeenClipboardUrl;
      _lastSeenClipboardUrl = url;
      if (hasNewClipboardUrl && mounted) {
        await _addLink(initialUrl: url);
      }
    } finally {
      _checkingClipboard = false;
    }
  }

  Future<void> _addLinkFromClipboard() async {
    if (_checkingClipboard || !mounted) return;
    _checkingClipboard = true;
    try {
      final url = await _clipboardUrl();
      _lastSeenClipboardUrl = url;
      if (mounted) await _addLink(initialUrl: url);
    } finally {
      _checkingClipboard = false;
    }
  }

  Future<void> _addLink({String initialUrl = ''}) async {
    if (!mounted) return;
    final result = await Navigator.of(context, rootNavigator: true)
        .push<SavedItem>(MaterialPageRoute(
      builder: (_) => AddLinkPage(initialUrl: initialUrl),
    ));
    if (result != null && mounted) await _add(result);
  }

  Future<SavedItem> _enrich(SavedItem item) async {
    if (item.url.isEmpty || item.imageUrl.isNotEmpty) return item;
    final meta = await LinkMetadata.fetch(item.url);
    return item.copyWith(
      title: (item.title.isEmpty || item.title == item.url) &&
              meta.title.isNotEmpty
          ? meta.title
          : null,
      imageUrl: meta.image.isEmpty ? null : meta.image,
      content: item.content.isEmpty && meta.description.isNotEmpty
          ? meta.description
          : null,
    );
  }

  Future<void> _add(SavedItem item) async {
    if (item.url.isNotEmpty &&
        items.any((i) => i.url == item.url && i.id != item.id)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('That link is already in your library')));
      return;
    }
    final enriched = await _enrich(item);
    await VaultDb.instance.save(enriched);
    await _refresh();
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Saved to your library')));
    }
  }

  Future<void> _edit([SavedItem? item]) async {
    final result = await showItemEditor(context, item: item);
    if (result?.deleted == true) {
      await _refresh();
    } else if (result?.item != null) {
      await _add(result!.item!);
    }
  }

  Future<void> _export() async {
    final data = (await VaultDb.instance.all()).map((e) => e.toMap()).toList();
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'clipvault-backup.json'));
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(data));
    if (!mounted) return;
    await Share.shareXFiles([XFile(file.path)], text: 'ClipVault JSON backup');
  }

  Future<void> _import() async {
    final result = await FilePicker.platform.pickFiles(
        type: FileType.custom, allowedExtensions: ['json', 'html', 'htm']);
    if (result == null || result.files.single.path == null) return;
    try {
      final inputFile = File(result.files.single.path!);
      final contents = await inputFile.readAsString();
      final restored = <SavedItem>[];
      if (p.extension(inputFile.path).toLowerCase() == '.json') {
        final decoded = jsonDecode(contents) as List;
        restored.addAll(decoded.map((e) {
          final map = Map<String, Object?>.from(e as Map);
          map.remove('id');
          return SavedItem.fromMap(map);
        }));
      } else {
        final anchors = RegExp(
                r'''<a\b[^>]*href=["']([^"']+)["'][^>]*>(.*?)</a>''',
                caseSensitive: false, dotAll: true)
            .allMatches(contents);
        for (final anchor in anchors) {
          final url = normalizeClipboardUrl(
              LinkMetadata._unescape(anchor.group(1) ?? ''));
          final title = LinkMetadata._unescape(anchor.group(2) ?? '')
              .replaceAll(RegExp(r'<[^>]*>'), ' ')
              .replaceAll(RegExp(r'\s+'), ' ')
              .trim();
          if (url == null) continue;
          restored.add(SavedItem(
            title: title.isEmpty ? Uri.parse(url).host : title,
            url: url,
            type: 'link',
            createdAt: DateTime.now().millisecondsSinceEpoch,
          ));
        }
      }
      final existing = await VaultDb.instance.all();
      final keys = existing
          .map((item) => item.url.isNotEmpty
              ? 'url:${item.url}'
              : 'item:${item.title}:${item.content}')
          .toSet();
      final merged = [...existing];
      for (final item in restored) {
        final key = item.url.isNotEmpty
            ? 'url:${item.url}'
            : 'item:${item.title}:${item.content}';
        if (keys.add(key)) merged.add(item);
      }
      await VaultDb.instance.replaceAll(merged);
      await _refresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content:
                Text('Imported ${merged.length - existing.length} new items')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not import this file')));
      }
    }
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(withData: false);
    if (result == null) return;
    final file = result.files.single;
    await _add(SavedItem(
        title: file.name,
        content: file.path ?? '',
        type: 'file',
        tags: 'imported',
        createdAt: DateTime.now().millisecondsSinceEpoch));
  }

  Future<void> _open(SavedItem item) async {
    final openedItem = await VaultDb.instance.recordOpen(item);
    if (!mounted) return;
    if (mounted && item.id != null) {
      setState(() {
        items = items
            .map((saved) => saved.id == openedItem.id ? openedItem : saved)
            .toList();
      });
    }
    if (openedItem.url.isNotEmpty) {
      await Navigator.of(context).push(PageRouteBuilder<void>(
        pageBuilder: (_, __, ___) => ItemDetailScreen(item: openedItem),
        transitionsBuilder: (_, primary, secondary, child) =>
            SharedAxisTransition(
          animation: primary,
          secondaryAnimation: secondary,
          transitionType: SharedAxisTransitionType.scaled,
          child: child,
        ),
      ));
      await _refresh();
    } else if (openedItem.type == 'file' && openedItem.content.isNotEmpty) {
      final f = File(openedItem.content);
      if (await f.exists()) {
        await Share.shareXFiles([XFile(f.path)]);
      }
    } else {
      await _edit(openedItem);
    }
  }

  int _relevanceScore(SavedItem item, String query) {
    final term = query.trim().replaceFirst(RegExp(r'^#'), '');
    if (term.isEmpty) return 0;
    final title = item.title.toLowerCase();
    final url = item.url.toLowerCase();
    final tags = [...savedTagsFor(item.tags), ...autoTagsFor(item)]
        .join(' ')
        .toLowerCase();
    if (title == term) return 100;
    if (title.startsWith(term)) return 80;
    if (title.contains(term)) return 60;
    if (url.contains(term)) return 40;
    if (tags.contains(term)) return 30;
    return 10;
  }

  int _compareItems(SavedItem a, SavedItem b, String query) {
    final sort = _librarySort == LibrarySort.auto
        ? (query.isEmpty ? LibrarySort.newest : LibrarySort.relevance)
        : _librarySort;
    switch (sort) {
      case LibrarySort.auto:
      case LibrarySort.newest:
        return b.createdAt.compareTo(a.createdAt);
      case LibrarySort.relevance:
        final relevance =
            _relevanceScore(b, query).compareTo(_relevanceScore(a, query));
        return relevance != 0 ? relevance : b.createdAt.compareTo(a.createdAt);
      case LibrarySort.oldest:
        return a.createdAt.compareTo(b.createdAt);
      case LibrarySort.mostOpened:
        final opens = b.openCount.compareTo(a.openCount);
        if (opens != 0) return opens;
        return b.createdAt.compareTo(a.createdAt);
      case LibrarySort.recentlyOpened:
        final openedA = a.lastOpenedAt ?? 0;
        final openedB = b.lastOpenedAt ?? 0;
        final recent = openedB.compareTo(openedA);
        return recent != 0 ? recent : b.createdAt.compareTo(a.createdAt);
    }
  }

  Future<void> _showSortOptions() async {
    final selected = await showModalBottomSheet<LibrarySort>(
      context: context,
      backgroundColor: auraSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: mutedText,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              ...LibrarySort.values.map((option) {
                final selectedOption = option == _librarySort;
                return ListTile(
                  leading: Icon(option.icon,
                      color: selectedOption ? auraOrange : secondaryText),
                  title: Text(option.label,
                      style: TextStyle(
                        color: selectedOption ? auraOrange : primaryText,
                        fontWeight:
                            selectedOption ? FontWeight.w700 : FontWeight.w500,
                      )),
                  trailing: selectedOption
                      ? Icon(Icons.check_rounded, color: auraOrange)
                      : null,
                  onTap: () => Navigator.pop(sheetContext, option),
                );
              }),
            ],
          ),
        ),
      ),
    );
    if (selected != null && mounted) {
      setState(() => _librarySort = selected);
      await _preferences.setString('library_sort', selected.name);
    }
  }

  List<String> get _availableTags {
    final tags = <String>{};
    for (final item in items) {
      tags.addAll(savedTagsFor(item.tags).map((tag) => tag.toLowerCase()));
      tags.addAll(autoTagsFor(item));
    }
    final sorted = tags.toList()..sort();
    return sorted;
  }

  List<SavedItem> _filteredItems({
    String? category,
    String? type,
    String? date,
    String? source,
    String? tag,
  }) {
    final q = query.toLowerCase();
    final selectedCategory = category ?? filter;
    final selectedType = type ?? _typeFilter;
    final selectedDate = date ?? _dateFilter;
    final selectedSource = source ?? _sourceFilter;
    final selectedTag = tag ?? _tagFilter;
    final now = DateTime.now().millisecondsSinceEpoch;
    final cutoff = switch (selectedDate) {
      '7 days' => now - const Duration(days: 7).inMilliseconds,
      '30 days' => now - const Duration(days: 30).inMilliseconds,
      _ => null,
    };

    return items.where((item) {
      if (item.isArchived || item.deletedAt != null) return false;
      final itemTags = [
        ...savedTagsFor(item.tags),
        ...autoTagsFor(item),
      ].map((value) => value.toLowerCase()).toSet();
      final searchableTags = itemTags.map((value) => '#$value').join(' ');
      final matchesQuery =
          '${item.title} ${item.url} ${item.content} ${item.tags} $searchableTags'
              .toLowerCase()
              .contains(q);
      final matchesCategory = selectedCategory == 'All' ||
          (selectedCategory == 'Favorites' && item.favorite) ||
          (selectedCategory == 'Unread' && !item.isRead) ||
          (selectedCategory == 'Links' && item.url.isNotEmpty) ||
          (selectedCategory == 'Notes' &&
              (item.type == 'note' || item.type == 'text'));
      final matchesType = selectedType == 'All' ||
          (selectedType == 'Link' && item.url.isNotEmpty) ||
          (selectedType == 'Text' &&
              (item.type == 'note' || item.type == 'text')) ||
          (selectedType == 'Image' && item.imageUrl.isNotEmpty) ||
          (selectedType == 'File' && item.type == 'file');
      final matchesDate = cutoff == null || item.createdAt >= cutoff;
      final matchesSource = selectedSource == 'All' ||
          (selectedSource == 'Web' && item.url.isNotEmpty);
      final normalizedTag = selectedTag.toLowerCase().replaceFirst('#', '');
      final matchesTag =
          selectedTag == 'All' || itemTags.contains(normalizedTag);
      return matchesQuery &&
          matchesCategory &&
          matchesType &&
          matchesDate &&
          matchesSource &&
          matchesTag;
    }).toList();
  }

  int _activeFilterCount() => [
        filter,
        _typeFilter,
        _dateFilter,
        _sourceFilter,
        _tagFilter,
      ].where((value) => value != 'All').length;

  Future<void> _showFilterOptions() async {
    var draftCategory = filter;
    var draftType = _typeFilter;
    var draftDate = _dateFilter;
    var draftSource = _sourceFilter;
    var draftTag = _tagFilter;

    final selected = await showModalBottomSheet<LibraryFilters>(
      context: context,
      isScrollControlled: true,
      backgroundColor: auraSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          int countFor({
            String? category,
            String? type,
            String? date,
            String? source,
            String? tag,
          }) =>
              _filteredItems(
                category: category ?? draftCategory,
                type: type ?? draftType,
                date: date ?? draftDate,
                source: source ?? draftSource,
                tag: tag ?? draftTag,
              ).length;

          Widget facet(
            String title,
            List<String> options,
            String selectedValue,
            ValueChanged<String> onChanged,
            int Function(String) countForOption,
          ) =>
              Padding(
                padding: const EdgeInsets.only(bottom: 22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            color: mutedText,
                            fontSize: 12,
                            letterSpacing: 1.8,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: options.map((option) {
                        final isSelected = option == selectedValue;
                        final count = countForOption(option);
                        return ChoiceChip(
                          selected: isSelected,
                          showCheckmark: false,
                          side: BorderSide(
                              color: isSelected ? auraOrange : outline),
                          backgroundColor: auraSurface,
                          selectedColor: auraOrange,
                          shape: const StadiumBorder(),
                          label: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(option,
                                  style: TextStyle(
                                    color: isSelected ? auraBase : primaryText,
                                    fontWeight: isSelected
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                  )),
                              const SizedBox(width: 7),
                              Text('$count',
                                  style: TextStyle(
                                    color: isSelected ? auraBase : mutedText,
                                    fontSize: 12,
                                  )),
                            ],
                          ),
                          onSelected: (_) => onChanged(option),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              );

          final tagOptions = ['All', ..._availableTags];
          final resultCount = countFor();
          return FractionallySizedBox(
            heightFactor: .86,
            child: SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 16, 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text('Filters',
                              style: Theme.of(sheetContext)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w700)),
                        ),
                        TextButton(
                          onPressed: () => setSheetState(() {
                            draftCategory = 'All';
                            draftType = 'All';
                            draftDate = 'All';
                            draftSource = 'All';
                            draftTag = 'All';
                          }),
                          child: const Text('Clear all'),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                      children: [
                        facet(
                          'CATEGORY',
                          const [
                            'All',
                            'Links',
                            'Notes',
                            'Favorites',
                            'Unread'
                          ],
                          draftCategory,
                          (value) => setSheetState(() => draftCategory = value),
                          (value) => countFor(category: value),
                        ),
                        facet(
                          'TYPE',
                          const ['All', 'Link', 'Text', 'Image', 'File'],
                          draftType,
                          (value) => setSheetState(() => draftType = value),
                          (value) => countFor(type: value),
                        ),
                        facet(
                          'DATE ADDED',
                          const ['All', '7 days', '30 days'],
                          draftDate,
                          (value) => setSheetState(() => draftDate = value),
                          (value) => countFor(date: value),
                        ),
                        facet(
                          'SOURCE',
                          const ['All', 'Web'],
                          draftSource,
                          (value) => setSheetState(() => draftSource = value),
                          (value) => countFor(source: value),
                        ),
                        facet(
                          'TAGS',
                          tagOptions,
                          draftTag,
                          (value) => setSheetState(() => draftTag = value),
                          (value) => countFor(tag: value),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () => Navigator.pop(
                          sheetContext,
                          LibraryFilters(
                            category: draftCategory,
                            type: draftType,
                            date: draftDate,
                            source: draftSource,
                            tag: draftTag,
                          ),
                        ),
                        child: Text('Show $resultCount results'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    if (selected != null && mounted) {
      setState(() {
        filter = selected.category;
        _typeFilter = selected.type;
        _dateFilter = selected.date;
        _sourceFilter = selected.source;
        _tagFilter = selected.tag;
      });
    }
  }

  Future<void> _showViewOptions() async {
    final selected = await showModalBottomSheet<LibraryView>(
      context: context,
      backgroundColor: auraSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: secondaryText.withValues(alpha: .35),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text('View', style: Theme.of(sheetContext).textTheme.titleLarge),
              const SizedBox(height: 4),
              const Text('How your library is laid out',
                  style: TextStyle(color: secondaryText)),
              const SizedBox(height: 12),
              ...LibraryView.values.map((view) {
                final isSelected = view == _libraryView;
                return ListTile(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  leading: Icon(view.icon, color: auraOrange),
                  title: Text(view.label,
                      style: TextStyle(
                        color: isSelected ? auraBase : primaryText,
                        fontWeight:
                            isSelected ? FontWeight.w700 : FontWeight.w500,
                      )),
                  trailing: isSelected
                      ? Icon(Icons.check_rounded, color: auraBase)
                      : null,
                  selected: isSelected,
                  selectedTileColor: auraGold,
                  onTap: () => Navigator.pop(sheetContext, view),
                );
              }),
            ],
          ),
        ),
      ),
    );
    if (selected != null && mounted) {
      setState(() => _libraryView = selected);
      await _preferences.setString('library_view', selected.name);
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = query.toLowerCase();
    final shown = _filteredItems()..sort((a, b) => _compareItems(a, b, q));

    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('ClipVault',
              style:
                  TextStyle(fontWeight: FontWeight.w800, letterSpacing: -.5)),
          Text('Your personal library',
              style: TextStyle(fontSize: 13, color: auraHighlight)),
        ]),
        actions: [
          IconButton(
              tooltip: 'Change view',
              onPressed: _showViewOptions,
              icon: Icon(_libraryView.icon)),
          IconButton(
              tooltip: 'Export backup',
              onPressed: _export,
              icon: const Icon(Icons.file_upload_outlined)),
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'settings') {
                await Navigator.of(context).push<void>(MaterialPageRoute(
                  builder: (_) => SettingsScreen(
                    items: items,
                    onImport: _import,
                    onExport: _export,
                  ),
                ));
                await _refresh();
                return;
              }
              if (v == 'import') await _import();
              if (v == 'file') await _pickFile();
              if (v == 'note') await _edit();
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'note', child: Text('Write a note')),
              const PopupMenuItem(
                  value: 'import', child: Text('Import JSON backup')),
              PopupMenuItem(
                  value: 'file', child: Text('Save a file reference')),
              const PopupMenuItem(value: 'settings', child: Text('Settings')),
            ],
          ),
        ],
      ),
      body: Container(
        color: bg,
        child: SafeArea(
            child: Column(children: [
          Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: _glass(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Keep what matters.',
                          style: TextStyle(
                              fontSize: 23, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 4),
                      Text(
                          '${items.length} saved items · stored on this device',
                          style: const TextStyle(
                              color: secondaryText, fontSize: 14)),
                      const SizedBox(height: 14),
                      TextField(
                        onChanged: (v) => setState(() => query = v),
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: 'Sort saved items',
                                onPressed: _showSortOptions,
                                icon: const Icon(Icons.sort_rounded),
                              ),
                              IconButton(
                                tooltip: 'Filter saved items',
                                onPressed: _showFilterOptions,
                                icon: Stack(
                                  clipBehavior: Clip.none,
                                  alignment: Alignment.center,
                                  children: [
                                    const Icon(Icons.tune_rounded),
                                    if (_activeFilterCount() > 0)
                                      Positioned(
                                        right: -7,
                                        top: -7,
                                        child: Container(
                                          constraints: const BoxConstraints(
                                              minWidth: 16, minHeight: 16),
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 4),
                                          decoration: BoxDecoration(
                                            color: auraOrange,
                                            shape: BoxShape.circle,
                                          ),
                                          child: Center(
                                            child: Text(
                                              '${_activeFilterCount()}',
                                              style: TextStyle(
                                                color: auraBase,
                                                fontSize: 11,
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          hintText: 'Search your library',
                          isDense: true,
                        ),
                      ),
                    ]),
              )),
          SizedBox(
              height: 44,
              child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: ['All', 'Links', 'Notes', 'Favorites', 'Unread']
                      .map((f) => Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                                label: Text(
                                  f,
                                  style: TextStyle(
                                    color:
                                        filter == f ? auraBase : secondaryText,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                showCheckmark: false,
                                side: BorderSide(
                                    color: filter == f ? auraOrange : outline),
                                shape: const StadiumBorder(),
                                selected: filter == f,
                                onSelected: (_) => setState(() => filter = f)),
                          ))
                      .toList())),
          Expanded(
              child: _loadingItems
                  ? _loadingPlaceholder()
                  : shown.isEmpty
                      ? Center(
                          child: Padding(
                              padding: const EdgeInsets.all(28),
                              child: _glass(
                                  child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                    Icon(Icons.bookmarks_outlined,
                                        size: 42, color: auraOrange),
                                    const SizedBox(height: 12),
                                    Text(
                                        query.isEmpty
                                            ? 'Your library starts here'
                                            : 'No matching items',
                                        style: const TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.w700)),
                                    const SizedBox(height: 6),
                                    Text(
                                        query.isEmpty
                                            ? 'Copy a link, open ClipVault, and save it — or add a note.'
                                            : 'Try another search or filter.',
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                            color: secondaryText)),
                                  ]))))
                      : _buildRecords(shown)),
        ])),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addLinkFromClipboard,
        icon: const Icon(Icons.add_link),
        label: const Text('Add link'),
      ),
    );
  }

  Widget _buildRecords(List<SavedItem> records) {
    switch (_libraryView) {
      case LibraryView.grid:
        return _buildGrid(records, gallery: false);
      case LibraryView.gallery:
        return _buildGrid(records, gallery: true);
      case LibraryView.compact:
        return _buildCompact(records);
      case LibraryView.list:
        return _buildList(records);
      case LibraryView.simple:
        return _buildSimple(records);
    }
  }

  Widget _buildGrid(List<SavedItem> records, {required bool gallery}) =>
      GridView.builder(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
        itemCount: records.length,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: gallery ? .82 : .72,
        ),
        itemBuilder: (context, index) =>
            _gridRecord(records[index], gallery: gallery)
                .animate()
                .fadeIn(duration: 220.ms)
                .slideY(begin: .035, duration: 220.ms),
      );

  Widget _loadingPlaceholder() => Skeletonizer(
        enabled: true,
        child: ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
          itemCount: 4,
          itemBuilder: (_, __) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Container(
              height: 92,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                  color: auraSurface,
                  border: Border.all(color: outline),
                  borderRadius: BorderRadius.circular(20)),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Loading your saved item'),
                  SizedBox(height: 10),
                  Text('https://clipvault.example/saved-link'),
                ],
              ),
            ),
          ),
        ),
      );

  Widget _gridRecord(SavedItem item, {required bool gallery}) => Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: .28),
              blurRadius: 12,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Material(
            color: auraSurface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(color: outline),
            ),
            child: InkWell(
              onTap: () => _open(item),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        flex: gallery ? 10 : 6,
                        child: _heroImage(item),
                      ),
                      if (!gallery)
                        Expanded(
                          flex: 5,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(14, 12, 10, 10),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(item.title,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        color: primaryText,
                                        fontWeight: FontWeight.w700)),
                                const Spacer(),
                                Row(
                                  children: [
                                    if (!item.isRead)
                                      Container(
                                        width: 7,
                                        height: 7,
                                        margin: const EdgeInsets.only(right: 7),
                                        decoration: BoxDecoration(
                                          color: auraOrange,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                    if (item.url.isNotEmpty) ...[
                                      Icon(Icons.link_rounded,
                                          size: 14, color: auraOrange),
                                      const SizedBox(width: 4),
                                    ],
                                    Expanded(
                                      child: Text(
                                        item.url.isNotEmpty
                                            ? Uri.tryParse(item.url)?.host ??
                                                'Link'
                                            : item.type.toUpperCase(),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                            color: secondaryText, fontSize: 12),
                                      ),
                                    ),
                                    if (item.url.isNotEmpty)
                                      _cardActionButton(
                                        icon: Icons.open_in_new_rounded,
                                        tooltip: 'Open saved link',
                                        color: auraOrange,
                                        onPressed: () => _open(item),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                  if (gallery)
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              Colors.black.withValues(alpha: .68),
                            ],
                          ),
                        ),
                      ),
                    ),
                  if (gallery)
                    Positioned(
                      left: 12,
                      right: 58,
                      bottom: 14,
                      child: Text(item.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700)),
                    ),
                  if (gallery && item.url.isNotEmpty)
                    Positioned(
                      right: 4,
                      bottom: 4,
                      child: _cardActionButton(
                        icon: Icons.open_in_new_rounded,
                        tooltip: 'Open saved link',
                        color: auraOrange,
                        onPressed: () => _open(item),
                      ),
                    ),
                  Positioned(
                    top: 4,
                    left: 4,
                    child: _favoriteButton(item, onThumbnail: true),
                  ),
                  Positioned(
                    top: 4,
                    right: 4,
                    child: _cardActionButton(
                      icon: Icons.edit_outlined,
                      tooltip: 'Edit item',
                      color: primaryText,
                      onPressed: () => _edit(item),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

  Widget _cardActionButton({
    required IconData icon,
    required String tooltip,
    required Color color,
    required VoidCallback onPressed,
  }) =>
      Material(
        color: auraDepth.withValues(alpha: .92),
        shape: const CircleBorder(),
        child: IconButton(
          tooltip: tooltip,
          onPressed: onPressed,
          icon: Icon(icon, color: color, size: 19),
          constraints: const BoxConstraints.tightFor(width: 48, height: 48),
          padding: const EdgeInsets.all(12),
          visualDensity: VisualDensity.compact,
        ),
      );

  Widget _favoriteButton(SavedItem item, {bool onThumbnail = false}) =>
      _cardActionButton(
        icon: item.favorite ? Icons.favorite_rounded : Icons.favorite_border,
        tooltip: item.favorite ? 'Remove favorite' : 'Add favorite',
        color: item.favorite
            ? auraOrange
            : (onThumbnail ? primaryText : mutedText),
        onPressed: () => _runItemAction(item, 'favorite'),
      );

  Widget _heroImage(SavedItem item) {
    if (item.imageUrl.isEmpty) return _heroFallback(item);
    return _savedImage(
      item.imageUrl,
      fit: BoxFit.cover,
      placeholder: _heroFallback(item),
    );
  }

  Widget _heroFallback(SavedItem item) => Container(
        decoration: BoxDecoration(
          color: auraDepth,
          border: Border(
            bottom:
                BorderSide(color: auraGold.withValues(alpha: .65), width: 2),
          ),
        ),
        child: Center(
          child: Icon(
            item.url.isNotEmpty
                ? Icons.link_rounded
                : item.type == 'file'
                    ? Icons.attach_file_rounded
                    : Icons.notes_rounded,
            size: 42,
            color: auraOrange,
          ),
        ),
      );

  Widget _buildCompact(List<SavedItem> records) => ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
        itemCount: records.length,
        itemBuilder: (context, index) {
          final item = records[index];
          return _swipeActions(
              item,
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _glass(
                  blur: false,
                  yellowCard: false,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(22),
                    onTap: () => _open(item),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _thumb(item),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(item.title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: item.isRead
                                          ? mutedText
                                          : primaryText)),
                              if (item.url.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Icon(Icons.link_rounded,
                                        size: 14, color: auraOrange),
                                    const SizedBox(width: 4),
                                    Expanded(
                                      child: Text(
                                        Uri.tryParse(item.url)?.host ??
                                            item.url,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                            color: secondaryText, fontSize: 13),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                              if (item.content.isNotEmpty &&
                                  item.type != 'file')
                                Padding(
                                  padding: const EdgeInsets.only(top: 5),
                                  child: Text(item.content,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          color: secondaryText, fontSize: 14)),
                                ),
                              if (item.tags.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Text(item.tags,
                                      style: const TextStyle(
                                          color: secondaryText, fontSize: 12)),
                                ),
                            ],
                          ),
                        ),
                        _favoriteButton(item),
                        _editButton(item),
                      ],
                    ),
                  ),
                ),
              ));
        },
      );

  Widget _buildList(List<SavedItem> records) => ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
        itemCount: records.length,
        separatorBuilder: (_, __) => const SizedBox(height: 4),
        itemBuilder: (context, index) {
          final item = records[index];
          return _swipeActions(
              item,
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _glass(
                  blur: false,
                  yellowCard: false,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  child: ListTile(
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    leading: _thumb(item),
                    title: Text(item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: primaryText, fontWeight: FontWeight.w700)),
                    subtitle: item.url.isNotEmpty
                        ? Row(
                            children: [
                              Icon(Icons.link_rounded,
                                  size: 14, color: auraOrange),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  Uri.tryParse(item.url)?.host ?? item.url,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: secondaryText),
                                ),
                              ),
                            ],
                          )
                        : Text(item.content,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: secondaryText)),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _favoriteButton(item),
                        _editButton(item),
                      ],
                    ),
                    onTap: () => _open(item),
                  ),
                ),
              ));
        },
      );

  Widget _buildSimple(List<SavedItem> records) => ListView.separated(
        padding: const EdgeInsets.fromLTRB(20, 8, 16, 100),
        itemCount: records.length,
        separatorBuilder: (_, __) => Divider(height: 1, color: outline),
        itemBuilder: (context, index) {
          final item = records[index];
          return _swipeActions(
              item,
              InkWell(
                onTap: () => _open(item),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(item.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: item.isRead
                                        ? secondaryText
                                        : primaryText)),
                            if (item.url.isNotEmpty) ...[
                              const SizedBox(height: 3),
                              Text(item.url,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      color: secondaryText, fontSize: 13)),
                            ],
                          ],
                        ),
                      ),
                      _favoriteButton(item),
                      _editButton(item),
                    ],
                  ),
                ),
              ));
        },
      );

  Widget _swipeActions(SavedItem item, Widget child) => Slidable(
        key: ValueKey('saved-${item.id ?? item.createdAt}'),
        endActionPane: ActionPane(
          motion: const StretchMotion(),
          extentRatio: .9,
          children: [
            SlidableAction(
              onPressed: (_) => _runItemAction(item, 'favorite'),
              backgroundColor: auraOrange,
              foregroundColor: auraBase,
              icon: item.favorite
                  ? Icons.favorite_rounded
                  : Icons.favorite_border,
              label: 'Favorite',
            ),
            SlidableAction(
              onPressed: (_) => _runItemAction(item, 'read'),
              backgroundColor: auraSurface,
              foregroundColor: primaryText,
              icon: item.isRead
                  ? Icons.mark_email_unread_outlined
                  : Icons.mark_email_read_outlined,
              label: item.isRead ? 'Unread' : 'Read',
            ),
            SlidableAction(
              onPressed: (_) => _runItemAction(item, 'share'),
              backgroundColor: auraDepth,
              foregroundColor: primaryText,
              icon: Icons.share_outlined,
              label: 'Share',
            ),
            SlidableAction(
              onPressed: (_) => _runItemAction(item, 'delete'),
              backgroundColor: errorColor,
              foregroundColor: primaryText,
              icon: Icons.delete_outline,
              label: 'Delete',
            ),
          ],
        ),
        child: child,
      );

  Widget _editButton(SavedItem item) => _cardActionButton(
        icon: Icons.edit_outlined,
        tooltip: 'Edit item',
        color: auraOrange,
        onPressed: () => _edit(item),
      );

  Future<void> _runItemAction(SavedItem item, String value) async {
    if (value == 'edit') await _edit(item);
    if (value == 'delete' && item.id != null) {
      await VaultDb.instance.moveToTrash(item.id!);
      await _refresh();
    }
    if (value == 'favorite') {
      await VaultDb.instance.save(item.copyWith(favorite: !item.favorite));
      await _refresh();
    }
    if (value == 'read') {
      await VaultDb.instance.save(item.copyWith(isRead: !item.isRead));
      await _refresh();
    }
    if (value == 'share') {
      await Share.share([item.title, item.url, item.content]
          .where((text) => text.isNotEmpty)
          .join('\n'));
    }
  }

  Widget _thumb(SavedItem item) {
    final fallback = Icon(
        item.url.isNotEmpty
            ? Icons.link
            : item.type == 'file'
                ? Icons.attach_file
                : Icons.notes,
        color: auraOrange);
    if (item.imageUrl.isEmpty) {
      return Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
              color: auraDepth.withValues(alpha: .5),
              borderRadius: BorderRadius.circular(14)),
          child: fallback);
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        width: 42,
        height: 42,
        child: _savedImage(
          item.imageUrl,
          fit: BoxFit.cover,
          placeholder: Container(
              color: auraDepth.withValues(alpha: .5), child: fallback),
          width: 42,
          height: 42,
        ),
      ),
    );
  }

  Widget _glass(
          {required Widget child,
          bool blur = true,
          bool yellowCard = false,
          EdgeInsetsGeometry padding = const EdgeInsets.all(16)}) =>
      GlassSurface(
          blur: blur, yellowCard: yellowCard, padding: padding, child: child);
}

class GlassSurface extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool blur;
  final bool yellowCard;
  const GlassSurface(
      {super.key,
      required this.child,
      this.padding = const EdgeInsets.all(16),
      this.blur = true,
      this.yellowCard = false});

  @override
  Widget build(BuildContext context) => Container(
        padding: padding,
        decoration: BoxDecoration(
          color: yellowCard ? auraGold : auraSurface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: yellowCard ? auraGold : outline,
          ),
          boxShadow: blur
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: .18),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ]
              : const [],
        ),
        child: child,
      );
}

class ItemEditorResult {
  final SavedItem? item;
  final bool deleted;

  const ItemEditorResult({this.item, this.deleted = false});
}

Future<ItemEditorResult?> showItemEditor(BuildContext context,
    {SavedItem? item}) {
  return Navigator.of(context).push<ItemEditorResult>(
    MaterialPageRoute(
      builder: (_) => ItemEditorScreen(item: item),
    ),
  );
}

class ItemEditorScreen extends StatefulWidget {
  final SavedItem? item;
  const ItemEditorScreen({super.key, this.item});

  @override
  State<ItemEditorScreen> createState() => _ItemEditorScreenState();
}

class _ItemEditorScreenState extends State<ItemEditorScreen> {
  late final TextEditingController _title =
      TextEditingController(text: widget.item?.title ?? '');
  late final TextEditingController _url =
      TextEditingController(text: widget.item?.url ?? '');
  late final TextEditingController _content =
      TextEditingController(text: widget.item?.content ?? '');
  late final TextEditingController _tags =
      TextEditingController(text: widget.item?.tags ?? '');
  late String _type = widget.item?.type ?? 'note';
  late String _imagePath = widget.item?.imageUrl ?? '';
  bool _savingImage = false;

  @override
  void dispose() {
    _title.dispose();
    _url.dispose();
    _content.dispose();
    _tags.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final selected = result.files.single;
    setState(() => _savingImage = true);
    try {
      final documents = await getApplicationDocumentsDirectory();
      final imageDirectory = Directory(p.join(documents.path, 'saved_images'));
      await imageDirectory.create(recursive: true);
      final extension = p.extension(selected.name).isEmpty
          ? '.jpg'
          : p.extension(selected.name);
      final target = File(p.join(
        imageDirectory.path,
        'clipvault_${DateTime.now().microsecondsSinceEpoch}$extension',
      ));
      if (selected.path != null) {
        await File(selected.path!).copy(target.path);
      } else if (selected.bytes != null) {
        await target.writeAsBytes(selected.bytes!);
      } else {
        throw StateError('The selected image could not be read.');
      }
      if (mounted) setState(() => _imagePath = target.path);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not add that image')),
        );
      }
    } finally {
      if (mounted) setState(() => _savingImage = false);
    }
  }

  Future<void> _viewImage() async {
    if (_imagePath.isEmpty) return;
    await Navigator.of(context).push<void>(MaterialPageRoute(
      builder: (_) => ImageViewerScreen(source: _imagePath),
    ));
  }

  void _save() {
    final title = _title.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add a title to save this item')),
      );
      return;
    }
    Navigator.of(context).pop(ItemEditorResult(
      item: SavedItem(
        id: widget.item?.id,
        title: title,
        url: _url.text.trim(),
        content: _content.text.trim(),
        tags: _tags.text.trim(),
        type: _type,
        imageUrl: _imagePath,
        favorite: widget.item?.favorite ?? false,
        isRead: widget.item?.isRead ?? false,
        createdAt:
            widget.item?.createdAt ?? DateTime.now().millisecondsSinceEpoch,
        openCount: widget.item?.openCount ?? 0,
        lastOpenedAt: widget.item?.lastOpenedAt,
      ),
    ));
  }

  Future<void> _delete() async {
    final id = widget.item?.id;
    if (id == null) return;
    await VaultDb.instance.moveToTrash(id);
    if (!mounted) return;
    Navigator.of(context).pop(const ItemEditorResult(deleted: true));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text(widget.item == null ? 'Write a note' : 'Edit item'),
          actions: [
            if (widget.item != null)
              IconButton(
                tooltip: 'Delete item',
                onPressed: _delete,
                icon: const Icon(Icons.delete_outline, color: errorColor),
              ),
            TextButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.check_rounded),
              label: const Text('Save'),
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
                children: [
                  TextField(
                    controller: _title,
                    autofocus: widget.item == null,
                    textCapitalization: TextCapitalization.sentences,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                    decoration: const InputDecoration(
                      labelText: 'Title',
                      hintText: 'Give this item a name',
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _url,
                    keyboardType: TextInputType.url,
                    decoration: const InputDecoration(
                      labelText: 'Link',
                      hintText: 'https://…',
                      prefixIcon: Icon(Icons.link_rounded),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _content,
                    minLines: 6,
                    maxLines: 14,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'Your note',
                      hintText: 'Write something worth keeping…',
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _tags,
                    decoration: const InputDecoration(
                      labelText: 'Tags',
                      hintText: 'Comma separated',
                      prefixIcon: Icon(Icons.tag_rounded),
                    ),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: _type,
                    decoration: const InputDecoration(labelText: 'Type'),
                    items: const ['link', 'note', 'text', 'file']
                        .map((value) => DropdownMenuItem(
                              value: value,
                              child: Text(value.toUpperCase()),
                            ))
                        .toList(),
                    onChanged: (value) =>
                        setState(() => _type = value ?? 'note'),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: Text('Image',
                            style: Theme.of(context).textTheme.titleMedium),
                      ),
                      OutlinedButton.icon(
                        onPressed: _savingImage ? null : _pickImage,
                        icon: Icon(_imagePath.isEmpty
                            ? Icons.add_photo_alternate_outlined
                            : Icons.swap_horiz_rounded),
                        label: Text(
                            _imagePath.isEmpty ? 'Add image' : 'Change image'),
                      ),
                    ],
                  ),
                  if (_savingImage) ...[
                    const SizedBox(height: 12),
                    const LinearProgressIndicator(),
                  ],
                  if (_imagePath.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Material(
                        color: auraSurface,
                        child: InkWell(
                          onTap: _viewImage,
                          child: AspectRatio(
                            aspectRatio: 1.6,
                            child: _savedImage(
                              _imagePath,
                              fit: BoxFit.cover,
                              placeholder: Container(
                                color: auraSurface,
                                child: Icon(Icons.image_outlined,
                                    color: auraOrange, size: 40),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: () => setState(() => _imagePath = ''),
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('Remove image'),
                      ),
                    ),
                  ],
                  const SizedBox(height: 28),
                  FilledButton.icon(
                    onPressed: _save,
                    icon: const Icon(Icons.check_rounded),
                    label: const Text('Save item'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}

class AddLinkPage extends StatefulWidget {
  final String initialUrl;
  const AddLinkPage({super.key, this.initialUrl = ''});
  @override
  State<AddLinkPage> createState() => _AddLinkPageState();
}

class _AddLinkPageState extends State<AddLinkPage> {
  final _url = TextEditingController();
  bool _loading = false;
  bool _fetched = false;
  LinkMetadata _meta = const LinkMetadata();
  String _metaUrl = '';

  @override
  void initState() {
    super.initState();
    _url.text = widget.initialUrl;
    if (widget.initialUrl.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _fetch(widget.initialUrl);
      });
    }
  }

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  Future<void> _fetch(String rawUrl) async {
    final url = rawUrl.trim();
    if (!looksLikeUrl(url)) {
      if (mounted) {
        setState(() {
          _meta = const LinkMetadata();
          _fetched = false;
          _metaUrl = '';
        });
      }
      return;
    }
    if (url == _metaUrl && _fetched) return;
    setState(() => _loading = true);
    final meta = await LinkMetadata.fetch(url);
    if (!mounted) return;
    setState(() {
      _meta = meta;
      _metaUrl = url;
      _fetched = true;
      _loading = false;
    });
  }

  Future<void> _save() async {
    final url = _url.text.trim();
    if (!looksLikeUrl(url)) return;
    if (!_fetched || _metaUrl != url) {
      setState(() => _loading = true);
      final meta = await LinkMetadata.fetch(url);
      if (!mounted) return;
      _meta = meta;
      _metaUrl = url;
      _fetched = true;
      setState(() => _loading = false);
    }
    final title = _meta.title.isNotEmpty ? _meta.title : url;
    Navigator.pop(
        context,
        SavedItem(
            title: title,
            url: url,
            imageUrl: _meta.image,
            content: _meta.description,
            type: 'link',
            createdAt: DateTime.now().millisecondsSinceEpoch));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(title: const Text('Add a link')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 22, 24, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _url,
                    keyboardType: TextInputType.url,
                    onSubmitted: _fetch,
                    onChanged: (_) {
                      if (_fetched || _loading) {
                        setState(() {
                          _fetched = false;
                          _meta = const LinkMetadata();
                        });
                      }
                    },
                    decoration: InputDecoration(
                      labelText: 'Link URL',
                      hintText: 'https://…',
                      prefixIcon: const Icon(Icons.link),
                      suffixIcon: IconButton(
                        tooltip: 'Fetch preview',
                        onPressed: _loading ? null : () => _fetch(_url.text),
                        icon: const Icon(Icons.refresh),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Flexible(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (_loading)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 20),
                              child: Center(child: CircularProgressIndicator()),
                            )
                          else ...[
                            if (_meta.image.isNotEmpty) ...[
                              ClipRRect(
                                borderRadius: BorderRadius.circular(14),
                                child: CachedNetworkImage(
                                  imageUrl: _meta.image,
                                  height: 170,
                                  width: double.infinity,
                                  fit: BoxFit.cover,
                                  placeholder: (_, __) => Container(
                                    height: 170,
                                    color: auraOrange.withValues(alpha: .08),
                                  ),
                                  errorWidget: (_, __, ___) =>
                                      const SizedBox.shrink(),
                                ),
                              ),
                              const SizedBox(height: 12),
                            ],
                            if (_meta.title.isNotEmpty)
                              Text(
                                _meta.title,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700),
                              ),
                            if (_meta.description.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Text(
                                _meta.description,
                                maxLines: 4,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: secondaryText,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                            if (_meta.title.isEmpty &&
                                _meta.description.isEmpty &&
                                _meta.image.isEmpty)
                              const Text(
                                'Paste or type a link. If your clipboard has one, it is filled in for you.',
                                style: TextStyle(
                                    color: secondaryText, fontSize: 14),
                              ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed:
                            _loading ? null : () => Navigator.pop(context),
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: _loading ? null : _save,
                        child: const Text('Save'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class ItemDetailScreen extends StatefulWidget {
  final SavedItem item;
  const ItemDetailScreen({super.key, required this.item});
  @override
  State<ItemDetailScreen> createState() => _ItemDetailScreenState();
}

class _ItemDetailScreenState extends State<ItemDetailScreen> {
  late SavedItem item = widget.item;
  final TextEditingController _tagController = TextEditingController();
  List<String> _suggestedTags = [];

  @override
  void initState() {
    super.initState();
    _loadSuggestedTags();
  }

  @override
  void dispose() {
    _tagController.dispose();
    super.dispose();
  }

  Future<void> _loadSuggestedTags() async {
    final records = await VaultDb.instance.all();
    final counts = <String, int>{};
    for (final record in records) {
      if (record.id == item.id) continue;
      for (final tag in savedTagsFor(record.tags)) {
        counts[tag] = (counts[tag] ?? 0) + 1;
      }
    }
    final current = savedTagsFor(item.tags).toSet();
    final suggestions =
        counts.entries.where((entry) => !current.contains(entry.key)).toList()
          ..sort((a, b) {
            final byCount = b.value.compareTo(a.value);
            return byCount == 0 ? a.key.compareTo(b.key) : byCount;
          });
    if (mounted) {
      setState(() => _suggestedTags =
          suggestions.take(8).map((entry) => entry.key).toList());
    }
  }

  Future<void> _save(SavedItem updated) async {
    await VaultDb.instance.save(updated);
    if (mounted) setState(() => item = updated);
  }

  Future<void> _edit() async {
    final result = await showItemEditor(context, item: item);
    if (result?.deleted == true) {
      if (mounted) Navigator.of(context).pop();
    } else if (result?.item != null) {
      await _save(result!.item!);
      await _loadSuggestedTags();
    }
  }

  Future<void> _addTag([String? value]) async {
    final raw = (value ?? _tagController.text).trim().replaceFirst('#', '');
    final tag = raw
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), '-')
        .replaceAll(RegExp(r'[^a-z0-9_-]'), '');
    if (tag.isEmpty) return;
    final tags = savedTagsFor(item.tags);
    if (tags.contains(tag)) {
      _tagController.clear();
      return;
    }
    _tagController.clear();
    await _save(item.copyWith(tags: [...tags, tag].join(', ')));
    await _loadSuggestedTags();
  }

  Future<void> _removeTag(String tag) async {
    final tags = savedTagsFor(item.tags)..remove(tag);
    await _save(item.copyWith(tags: tags.join(', ')));
    await _loadSuggestedTags();
  }

  Future<void> _openUrl([String? value]) async {
    final urls = extractUrls(item.content);
    final url = normalizeClipboardUrl(value ?? item.url) ??
        (urls.isEmpty ? null : urls.first);
    final uri = url == null ? null : Uri.tryParse(url);
    if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _viewImage() async {
    if (item.imageUrl.isEmpty) return;
    await Navigator.of(context).push<void>(MaterialPageRoute(
      builder: (_) => ImageViewerScreen(source: item.imageUrl),
    ));
  }

  Future<void> _menu(String v) async {
    if (v == 'edit') await _edit();
    if (v == 'favorite') await _save(item.copyWith(favorite: !item.favorite));
    if (v == 'read') await _save(item.copyWith(isRead: !item.isRead));
    if (v == 'archive') {
      await _save(item.copyWith(isArchived: true));
      if (mounted) Navigator.of(context).pop();
    }
    if (v == 'share') {
      await Share.share([item.title, item.url, item.content]
          .where((s) => s.isNotEmpty)
          .join('\n'));
    }
    if (v == 'delete') {
      if (item.id != null) await VaultDb.instance.moveToTrash(item.id!);
      if (mounted) Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final detailLinks = <String>{
      ...extractUrls(item.url),
      ...extractUrls(item.content),
    }.toList();
    final primaryLink = detailLinks.isEmpty ? null : detailLinks.first;
    final host = (primaryLink == null ? null : Uri.tryParse(primaryLink))
            ?.host
            .replaceFirst(
              RegExp(r'^www\.'),
              '',
            ) ??
        '';
    final savedAt =
        DateTime.fromMillisecondsSinceEpoch(item.createdAt).toLocal();
    final savedLabel =
        '${MaterialLocalizations.of(context).formatMediumDate(savedAt)} · ${TimeOfDay.fromDateTime(savedAt).format(context)}';
    final customTags = savedTagsFor(item.tags);

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        title: Text(
          (host.isEmpty ? item.type : host).toUpperCase(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: auraHighlight,
            fontSize: 13,
            fontWeight: FontWeight.w700,
            letterSpacing: 2,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Share item',
            onPressed: () => _menu('share'),
            icon: const Icon(Icons.share_outlined),
          ),
          IconButton(
            tooltip: 'Edit item',
            onPressed: _edit,
            icon: const Icon(Icons.edit_outlined),
          ),
          IconButton(
            tooltip: 'Delete item',
            onPressed: () => _menu('delete'),
            icon: const Icon(Icons.delete_outline, color: errorColor),
          ),
          PopupMenuButton<String>(
            tooltip: 'More options',
            onSelected: _menu,
            itemBuilder: (_) => [
              PopupMenuItem(
                  value: 'favorite',
                  child:
                      Text(item.favorite ? 'Remove favorite' : 'Add favorite')),
              PopupMenuItem(
                  value: 'read',
                  child: Text(item.isRead ? 'Mark unread' : 'Mark read')),
              const PopupMenuItem(
                  value: 'archive', child: Text('Archive item')),
            ],
          ),
        ],
      ),
      body: Container(
        color: bg,
        child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 32),
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Material(
                  color: auraSurface,
                  child: InkWell(
                    onTap: item.imageUrl.isEmpty ? null : _viewImage,
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: item.imageUrl.isEmpty
                          ? Icon(Icons.link_rounded,
                              color: auraOrange, size: 56)
                          : _savedImage(
                              item.imageUrl,
                              fit: BoxFit.cover,
                              placeholder: Container(
                                color: auraSurface,
                                child: const Center(
                                    child: CircularProgressIndicator()),
                              ),
                            ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(item.title,
                  style: const TextStyle(
                      fontSize: 26, height: 1.12, fontWeight: FontWeight.w800)),
              if (item.content.isNotEmpty) ...[
                const SizedBox(height: 14),
                Text(item.content,
                    style: const TextStyle(
                        color: secondaryText, fontSize: 15, height: 1.4)),
              ],
              const SizedBox(height: 18),
              if (item.url.isNotEmpty)
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: auraSurface,
                    border: Border.all(color: outline),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: () => _openUrl(item.url),
                          borderRadius: BorderRadius.circular(12),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 12),
                            child: Row(
                              children: [
                                Icon(Icons.open_in_new_rounded,
                                    color: auraOrange, size: 20),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    item.url,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        color: auraHighlight, fontSize: 14),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: item.isRead ? 'Mark unread' : 'Mark read',
                        onPressed: () => _menu('read'),
                        icon: Icon(item.isRead
                            ? Icons.bookmark_added_outlined
                            : Icons.bookmark_add_outlined),
                      ),
                    ],
                  ),
                ),
              for (final link in detailLinks.where(
                  (link) => extractUrls(item.url).contains(link) == false))
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Material(
                    color: auraSurface,
                    shape: RoundedRectangleBorder(
                      side: BorderSide(color: outline),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: ListTile(
                      leading:
                          Icon(Icons.open_in_new_rounded, color: auraOrange),
                      title: Text(link,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: auraHighlight)),
                      onTap: () => _openUrl(link),
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              _detailPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.shopping_bag_outlined,
                            color: auraOrange, size: 19),
                        const SizedBox(width: 10),
                        Text(item.type.toUpperCase(),
                            style: TextStyle(
                                color: auraHighlight,
                                fontSize: 13,
                                letterSpacing: 1.8,
                                fontWeight: FontWeight.w700)),
                      ],
                    ),
                    if (host.isNotEmpty) ...[
                      const SizedBox(height: 18),
                      _detailMetadataRow('SITE', host),
                    ],
                    if (primaryLink != null) ...[
                      const SizedBox(height: 18),
                      FilledButton.icon(
                        onPressed: () => _openUrl(primaryLink),
                        icon: const Icon(Icons.open_in_new_rounded, size: 19),
                        label: const Text('Open link'),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 24),
              _sectionLabel('AUTO TAGS'),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children:
                    autoTagsFor(item).map((tag) => _tagChip('#$tag')).toList(),
              ),
              const SizedBox(height: 24),
              _sectionLabel('YOUR TAGS'),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _tagController,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _addTag(),
                      decoration: const InputDecoration(
                        hintText: 'Add a tag…',
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  FilledButton(
                    onPressed: () => _addTag(),
                    child: const Text('Add'),
                  ),
                ],
              ),
              if (customTags.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: customTags
                      .map((tag) => InputChip(
                            label: Text('#$tag'),
                            onDeleted: () => _removeTag(tag),
                            deleteIconColor: secondaryText,
                          ))
                      .toList(),
                ),
              ],
              if (_suggestedTags.isNotEmpty) ...[
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _suggestedTags
                      .map((tag) => ActionChip(
                            avatar: const Icon(Icons.add_rounded, size: 15),
                            label: Text('#$tag'),
                            onPressed: () => _addTag(tag),
                          ))
                      .toList(),
                ),
              ],
              const SizedBox(height: 32),
              Text(
                'Saved $savedLabel',
                style: const TextStyle(
                    color: mutedText, fontSize: 13, letterSpacing: .4),
              ),
            ]),
      ),
    );
  }

  Widget _detailPanel({required Widget child}) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: auraSurface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: outline),
        ),
        child: child,
      );

  Widget _detailMetadataRow(String label, String value) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 74,
            child: Text(label,
                style: const TextStyle(
                    color: mutedText, fontSize: 12, letterSpacing: 1.2)),
          ),
          Expanded(
            child: Text(value,
                textAlign: TextAlign.right,
                style: const TextStyle(
                    color: primaryText, fontWeight: FontWeight.w600)),
          ),
        ],
      );

  Widget _sectionLabel(String label) => Text(
        label,
        style: const TextStyle(
          color: mutedText,
          fontSize: 12,
          letterSpacing: 2,
          fontWeight: FontWeight.w600,
        ),
      );

  Widget _tagChip(String label) => Chip(
        label: Text(label),
        backgroundColor: auraDepth,
        side: BorderSide(color: outline),
        labelStyle: const TextStyle(color: primaryText, fontSize: 13),
        visualDensity: VisualDensity.compact,
      );
}

class ImageViewerScreen extends StatelessWidget {
  final String source;
  const ImageViewerScreen({super.key, required this.source});

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: auraBase,
        appBar: AppBar(
          backgroundColor: auraBase,
          title: const Text('Image'),
          leading: IconButton(
            tooltip: 'Close image',
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded),
          ),
        ),
        body: SizedBox.expand(
          child: InteractiveViewer(
            minScale: .75,
            maxScale: 4,
            child: Center(
              child: _savedImage(
                source,
                fit: BoxFit.contain,
                placeholder: const Icon(Icons.broken_image_outlined,
                    color: secondaryText, size: 48),
              ),
            ),
          ),
        ),
      );
}
