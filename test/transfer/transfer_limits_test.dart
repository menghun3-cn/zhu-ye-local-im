import 'package:local_transfer/core/core.dart';
import 'package:test/test.dart';

import 'support.dart';

/// Limits small enough that every rule can be broken by one offer.
const TransferLimits _limits = TransferLimits(
  maxItems: 2,
  maxItemBytes: 100,
  maxTotalBytes: 150,
);

PayloadItem _file(String id, int size, {String? digest}) => PayloadItem(
  id: id,
  name: id,
  size: size,
  digest: digest ?? sha256Hex(List<int>.filled(size, 1)),
);

OfferMessage _fileOffer(List<PayloadItem> items, {String? text}) =>
    OfferMessage(
      transferId: 't',
      kind: PayloadKind.file,
      items: items,
      text: text,
    );

OfferMessage _inline(PayloadKind kind, {String? text, int? size}) =>
    OfferMessage(
      transferId: 't',
      kind: kind,
      items: [
        PayloadItem(
          id: kind.wireName,
          name: kind.wireName,
          size: size ?? (text == null ? 0 : text.length),
        ),
      ],
      text: text,
    );

void main() {
  group('an offer within the limits', () {
    test('has nothing to complain about', () {
      expect(
        _limits.violationOf(_fileOffer([_file('i0', 10), _file('i1', 20)])),
        isNull,
      );
      expect(
        _limits.violationOf(_inline(PayloadKind.text, text: 'hello')),
        isNull,
      );
    });
  });

  group('an offer that breaks a limit', () {
    test('names no items', () {
      expect(_limits.violationOf(_fileOffer(const [])), contains('no items'));
    });

    test('names more items than the limit allows', () {
      final offer = _fileOffer([
        _file('i0', 1),
        _file('i1', 1),
        _file('i2', 1),
      ]);
      expect(_limits.violationOf(offer), contains('3 items'));
    });

    test('declares an item larger than the per-item limit', () {
      expect(
        _limits.violationOf(_fileOffer([_file('i0', 101)])),
        contains('101'),
      );
    });

    test('declares more in total than the total limit', () {
      final offer = _fileOffer([_file('i0', 90), _file('i1', 90)]);
      expect(_limits.violationOf(offer), contains('180'));
    });

    test('reuses an item id', () {
      final offer = _fileOffer([_file('i0', 1), _file('i0', 1)]);
      expect(_limits.violationOf(offer), contains('twice'));
    });

    test('names an item with an empty id', () {
      expect(
        _limits.violationOf(_fileOffer([_file('', 1)])),
        contains('empty id'),
      );
    });

    test('declares a negative size', () {
      final offer = _fileOffer([_file('i0', 0, digest: sha256Hex(const []))]);
      expect(_limits.violationOf(offer), isNull);

      expect(
        _limits.violationOf(
          _fileOffer([
            PayloadItem(
              id: 'i0',
              name: 'i0',
              size: -1,
              digest: sha256Hex(const []),
            ),
          ]),
        ),
        contains('-1'),
      );
    });

    test('declares a digest that is not a SHA-256', () {
      final offer = _fileOffer([_file('i0', 1, digest: 'abc')]);
      expect(_limits.violationOf(offer), contains('not a SHA-256'));
    });

    test('describes a file item with no digest at all', () {
      final offer = OfferMessage(
        transferId: 't',
        kind: PayloadKind.file,
        items: [PayloadItem(id: 'i0', name: 'i0', size: 4)],
      );
      // Without a digest there is nothing for the receiver to check the bytes
      // against, so the copy would carry no guarantee.
      expect(_limits.violationOf(offer), contains('no digest'));
    });

    test('carries text alongside files', () {
      final offer = _fileOffer([_file('i0', 1)], text: 'and a note');
      expect(_limits.violationOf(offer), contains('carries text'));
    });
  });

  group('a text or clipboard offer', () {
    test('must carry a body', () {
      expect(
        _limits.violationOf(_inline(PayloadKind.text)),
        contains('no text'),
      );
    });

    test('must name exactly one item', () {
      final offer = OfferMessage(
        transferId: 't',
        kind: PayloadKind.text,
        items: [
          PayloadItem(id: 'text', name: 'text', size: 2),
          PayloadItem(id: 'more', name: 'more', size: 0),
        ],
        text: 'hi',
      );
      expect(_limits.violationOf(offer), contains('exactly one item'));
    });

    test('must declare its own length', () {
      expect(
        _limits.violationOf(_inline(PayloadKind.text, text: 'hello', size: 4)),
        contains('5 bytes'),
      );
    });

    test('is held to the same shape when it is clipboard content', () {
      expect(
        _limits.violationOf(_inline(PayloadKind.clipboard, text: 'copied')),
        isNull,
      );
      expect(
        _limits.violationOf(_inline(PayloadKind.clipboard)),
        contains('no text'),
      );
    });
  });
}
