import 'dart:convert';

import '../protocol/messages.dart';

/// What a Device is willing to receive before anyone has been asked.
///
/// Every limit here is enforced on an Offer, before a byte of payload is
/// accepted and before the receiving side has created anything on disk. An
/// Offer is the peer's claim, not a fact: without these, a Device on the link
/// could propose a terabyte to a receiver that starts writing immediately, and
/// fill its disk without its owner ever agreeing to anything.
///
/// The two timeouts are the sender's, not the receiver's. A sender that hears
/// nothing back has to stop waiting eventually; a receiver that is mid-write
/// has a Transfer the user can cancel, and a silent timeout there would turn a
/// slow link into a failed transfer for no reason. When one of them does fire,
/// the sender tells the peer before it goes: a receiver still looking at the
/// question deserves to hear that the answer is never coming, rather than
/// being left with a bubble that fills in forever.
final class TransferLimits {
  const TransferLimits({
    this.maxItems = 4096,
    this.maxItemBytes = 4 << 30,
    this.maxTotalBytes = 8 << 30,
    this.acceptanceTimeout = const Duration(hours: 24),
    this.verificationTimeout = const Duration(seconds: 120),
  });

  /// The limits an ordinary Device uses.
  static const TransferLimits defaults = TransferLimits();

  /// The most items a single Offer may name.
  final int maxItems;

  /// The most bytes a single item may declare.
  final int maxItemBytes;

  /// The most bytes an Offer may declare in total.
  final int maxTotalBytes;

  /// How long a sender waits for its Offer to be answered.
  ///
  /// A workday, not a tick: the question sits in a dialog on the far side, and
  /// the person it is for may be at lunch, or away until tomorrow. A sender
  /// that gave up sooner would fail a transfer its user still means to send —
  /// and since the sender can always cancel by hand, waiting costs the
  /// impatient nothing.
  final Duration acceptanceTimeout;

  /// How long a sender waits, after its last byte, to hear that the receiver
  /// verified what it wrote.
  ///
  /// Short, on purpose: verification is hashing, which is seconds of work, and
  /// a sender whose receiver went silent here has been hung up on — waiting a
  /// day to learn that would be a day the file sat in limbo.
  final Duration verificationTimeout;

  /// Why [offer] cannot be accepted, or null if it can.
  ///
  /// The message is for logs and for the person reading them; the peer only
  /// ever learns the reason over the wire, which is [RejectionReason.refused].
  String? violationOf(OfferMessage offer) {
    if (offer.items.isEmpty) return 'the offer names no items';
    if (offer.items.length > maxItems) {
      return 'the offer names ${offer.items.length} items, the limit is '
          '$maxItems';
    }
    final seen = <String>{};
    for (final item in offer.items) {
      if (item.id.isEmpty) return 'an item has an empty id';
      if (!seen.add(item.id)) return 'item id "${item.id}" is used twice';
      if (item.size < 0) {
        return 'item "${item.id}" declares ${item.size} bytes';
      }
      if (item.size > maxItemBytes) {
        return 'item "${item.id}" declares ${item.size} bytes, the limit is '
            '$maxItemBytes';
      }
      final digest = item.digest;
      if (digest != null && !_sha256Hex.hasMatch(digest)) {
        return 'item "${item.id}" declares a digest that is not a SHA-256';
      }
    }
    if (offer.totalBytes > maxTotalBytes) {
      return 'the offer totals ${offer.totalBytes} bytes, the limit is '
          '$maxTotalBytes';
    }
    return switch (offer.kind) {
      PayloadKind.text || PayloadKind.clipboard => _inlineViolation(offer),
      // An image is a byte stream like any other: it arrives with a digest per
      // item and is checked against it, exactly as a file is. The only thing
      // that differs is how the receiver draws the result.
      PayloadKind.file || PayloadKind.image => _fileViolation(offer),
    };
  }

  /// Text and clipboard payloads travel inside the Offer, so their shape is
  /// fixed rather than merely bounded.
  String? _inlineViolation(OfferMessage offer) {
    final text = offer.text;
    if (text == null) {
      return 'a ${offer.kind.wireName} offer carries no text';
    }
    if (offer.items.length != 1) {
      return 'a ${offer.kind.wireName} offer must name exactly one item, not '
          '${offer.items.length}';
    }
    final expected = utf8.encode(text).length;
    final declared = offer.items.single.size;
    if (declared != expected) {
      return 'the text is $expected bytes but the item declares $declared';
    }
    return null;
  }

  /// A file offer must describe a byte stream, which means a digest for each
  /// item: without one there is nothing for the receiver to check the bytes
  /// against, and the Transfer would be a copy with no guarantee behind it.
  String? _fileViolation(OfferMessage offer) {
    if (offer.text != null && offer.text!.isNotEmpty) {
      return 'a file offer carries text as well as files';
    }
    for (final item in offer.items) {
      if (!item.hasDigest) {
        return 'file item "${item.id}" declares no digest';
      }
    }
    return null;
  }

  @override
  String toString() =>
      'TransferLimits(maxItems: $maxItems, maxItemBytes: $maxItemBytes, '
      'maxTotalBytes: $maxTotalBytes)';

  static final RegExp _sha256Hex = RegExp(r'^[0-9a-f]{64}$');
}
