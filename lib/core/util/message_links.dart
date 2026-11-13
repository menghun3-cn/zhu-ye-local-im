/// Web addresses found inside a message's text, and the rules they are found
/// by.
///
/// Plain Dart, like everything else in `lib/core`: the recogniser is one
/// regular expression plus a little trimming, and the trimming rules are the
/// part worth pinning down under `dart test` rather than in a widget tree.
library;

/// One address found in a message: the half-open range it occupies in the
/// message's text, and the address to hand to a browser.
final class MessageLink {
  /// An address at [start] (inclusive) to [end] (exclusive) of the text.
  const MessageLink({
    required this.start,
    required this.end,
    required this.url,
  });

  /// Where the address starts in the message's text.
  final int start;

  /// Where it ends — exclusive, like every Dart range.
  final int end;

  /// The address with a scheme. A `www.` match is answered as
  /// `https://www.…`, because a browser cannot be handed a scheme-less one.
  final String url;
}

/// The two spellings an address may begin with in a message.
///
/// `https?://` covers what a sender pastes; `www.` covers what a person
/// types. Anything else — `ftp:`, a bare `example.com` — is deliberately not
/// a link: a bare domain is indistinguishable from ordinary text often enough
/// (versions, file names, `a.b` abbreviations) that guessing at it produces
/// more false hits than the convenience is worth.
final RegExp _candidate = RegExp(
  r'(?:https?://|www\.)[A-Za-z0-9\-._~:/?#\[\]@!$&()*+,;=%]+',
  caseSensitive: false,
);

/// Punctuation a sentence puts *after* an address. Every one of these is also
/// legal inside a URI, which is why they are trimmed from the end rather than
/// excluded from the match: `,` and `;` appear in real query strings, but
/// nothing writes `https://a.com,` on purpose — the comma belongs to the
/// sentence around it.
const String _trailingPunctuation = '.,;:!?';

/// The web addresses in [text], in the order they appear.
///
/// The range is over the message's UTF-16 code units, which is what
/// [String.substring] and `TextSpan` both count in — an index the caller can
/// slice with directly.
List<MessageLink> messageLinks(String text) {
  if (text.isEmpty) return const [];
  final links = <MessageLink>[];
  for (final match in _candidate.allMatches(text)) {
    var end = match.end;
    // Trailing sentence punctuation is not part of the address.
    while (end > match.start && _trailingPunctuation.contains(text[end - 1])) {
      end--;
    }
    // A closing bracket belongs to the sentence around the address when the
    // address never opened one: `(see https://a.com)` ends at `m`, not `)`.
    while (end > match.start && _closesWithoutOpening(text, match.start, end)) {
      end--;
    }
    final found = text.substring(match.start, end);
    final prefix = _prefixLength(found);
    // `https://` with nothing after it is punctuation's leftovers, not an
    // address — the same for a bare `www.`.
    if (prefix == null || end - match.start <= prefix) continue;
    links.add(
      MessageLink(
        start: match.start,
        end: end,
        url: found.toLowerCase().startsWith('www.') ? 'https://$found' : found,
      ),
    );
  }
  return links;
}

/// How many characters [found]'s scheme-or-`www.` prefix is, or null when it
/// has none — which cannot happen for a [_candidate] match, but keeps the
/// function honest if the pattern ever changes.
int? _prefixLength(String found) {
  final lower = found.toLowerCase();
  if (lower.startsWith('https://')) return 'https://'.length;
  if (lower.startsWith('http://')) return 'http://'.length;
  if (lower.startsWith('www.')) return 'www.'.length;
  return null;
}

/// Whether [text]'s last character before [end] is a bracket the address at
/// [start] never opened — `)` without a `(`, `]` without a `[` inside the
/// matched range.
bool _closesWithoutOpening(String text, int start, int end) {
  final last = text[end - 1];
  if (last != ')' && last != ']') return false;
  final body = text.substring(start, end);
  final opens = last == ')' ? '(' : '[';
  final closes = last;
  var open = 0;
  var close = 0;
  for (var i = 0; i < body.length; i++) {
    if (body[i] == opens) open++;
    if (body[i] == closes) close++;
  }
  return close > open;
}
