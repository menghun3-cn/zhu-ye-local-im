import 'package:local_transfer/core/util/message_links.dart';
import 'package:test/test.dart';

/// The rules a web address is recognised by inside a message.
///
/// The facts under test are the ones a widget tree cannot pin down cheaply:
/// where a link starts and ends in the text, which spellings count, and the
/// punctuation a sentence leaves outside the address.
void main() {
  group('messageLinks', () {
    test('finds nothing in plain text', () {
      expect(messageLinks(''), isEmpty);
      expect(messageLinks('你好，今天天气不错。'), isEmpty);
      expect(messageLinks('version 1.2.3 and file a.b'), isEmpty);
    });

    test('finds an https address and reports its range', () {
      const text = 'see https://example.com/a?x=1 now';
      final links = messageLinks(text);
      expect(links, hasLength(1));
      expect(links.single.url, 'https://example.com/a?x=1');
      expect(
        text.substring(links.single.start, links.single.end),
        'https://example.com/a?x=1',
      );
    });

    test('finds an http address too', () {
      final links = messageLinks('go to http://a.b/c please');
      expect(links.single.url, 'http://a.b/c');
    });

    test('answers a www. match with an https scheme', () {
      final links = messageLinks('看 www.example.com 这个');
      expect(links, hasLength(1));
      expect(links.single.url, 'https://www.example.com');
    });

    test('matches the scheme and www. prefix in any case', () {
      expect(messageLinks('HTTPS://A.COM').single.url, 'HTTPS://A.COM');
      expect(
        messageLinks('WWW.Example.COM/x').single.url,
        'https://WWW.Example.COM/x',
      );
    });

    test('keeps query punctuation that is part of the address', () {
      final links = messageLinks('https://a.com/?x=1&y=2;z=3');
      expect(links.single.url, 'https://a.com/?x=1&y=2;z=3');
    });

    test('leaves sentence punctuation outside the address', () {
      const text = '打开https://a.com。然后呢？';
      final links = messageLinks(text);
      expect(links, hasLength(1));
      expect(links.single.url, 'https://a.com');
      expect(text.substring(links.single.end), '。然后呢？');
    });

    test('trims trailing commas, colons and exclamation marks', () {
      expect(messageLinks('见https://a.com,').single.url, 'https://a.com');
      expect(messageLinks('见https://a.com:').single.url, 'https://a.com');
      expect(messageLinks('见https://a.com!').single.url, 'https://a.com');
      expect(messageLinks('见https://a.com...').single.url, 'https://a.com');
    });

    test('drops a closing bracket the address never opened', () {
      expect(messageLinks('(https://a.com)').single.url, 'https://a.com');
      expect(messageLinks('[www.a.com]').single.url, 'https://www.a.com');
      // A bracket the address did open stays: the path really ends in one.
      expect(
        messageLinks('https://a.com/f(x)').single.url,
        'https://a.com/f(x)',
      );
      expect(
        messageLinks('https://a.com/f(x))').single.url,
        'https://a.com/f(x)',
      );
    });

    test('ends the address at the first non-URI character', () {
      // A raw non-ASCII character is not a URI character; letting one in
      // would let 「看https://a.com很棒」 swallow the sentence.
      expect(messageLinks('看https://a.com很棒').single.url, 'https://a.com');
      expect(messageLinks('a "https://b.com" c').single.url, 'https://b.com');
    });

    test('finds every address in the message, in order', () {
      const text = 'one https://a.com two www.b.com three';
      final links = messageLinks(text);
      expect(links.map((l) => l.url), ['https://a.com', 'https://www.b.com']);
      expect(links[0].start, lessThan(links[1].start));
    });

    test('does not mistake a bare prefix for an address', () {
      expect(messageLinks('https:// alone'), isEmpty);
      expect(messageLinks('https://.'), isEmpty);
      expect(messageLinks('www. next'), isEmpty);
      expect(messageLinks('ftp://a.com'), isEmpty);
      expect(messageLinks('example.com'), isEmpty);
    });
  });
}
