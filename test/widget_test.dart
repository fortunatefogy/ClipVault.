import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:clipvault/main.dart';

void main() {
  test('clipboard URL extraction handles pasted text and trailing punctuation',
      () {
    expect(normalizeClipboardUrl('https://example.com/item.'),
        'https://example.com/item');
    expect(normalizeClipboardUrl('Check this out: https://example.com/item\n'),
        'https://example.com/item');
    expect(normalizeClipboardUrl('not a link'), isNull);
  });

  testWidgets('link dialog renders its input and actions', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => const AddLinkDialog(),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Add a link'), findsOneWidget);
    expect(find.text('Link URL'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);
  });

  test('SavedItem round-trips through its map, including image url', () {
    const item = SavedItem(
      id: 7,
      title: 'A product',
      url: 'https://example.com/p/1',
      content: 'A description',
      type: 'link',
      tags: 'shopping,tech',
      imageUrl: 'https://example.com/img.jpg',
      favorite: true,
      isRead: true,
      createdAt: 1700000000000,
    );

    final restored = SavedItem.fromMap(item.toMap());

    expect(restored.id, 7);
    expect(restored.title, 'A product');
    expect(restored.url, 'https://example.com/p/1');
    expect(restored.content, 'A description');
    expect(restored.type, 'link');
    expect(restored.tags, 'shopping,tech');
    expect(restored.imageUrl, 'https://example.com/img.jpg');
    expect(restored.favorite, isTrue);
    expect(restored.isRead, isTrue);
    expect(restored.createdAt, 1700000000000);
  });

  test('SavedItem.fromMap tolerates missing columns from older backups', () {
    final restored = SavedItem.fromMap({'title': 'Legacy', 'created_at': 1});

    expect(restored.title, 'Legacy');
    expect(restored.imageUrl, '');
    expect(restored.type, 'note');
  });
}
