import 'dart:io';

import 'package:local_transfer/app/app.dart';
import 'package:test/test.dart';

void main() {
  // A received file's name comes from the peer, which makes it the one piece of
  // untrusted input that reaches a filesystem path. These tests pin the answer
  // to "a name may name a file in the chosen directory, and nothing else".
  group('sanitiseIncomingName', () {
    test('keeps an ordinary name', () {
      expect(sanitiseIncomingName('holiday photo.jpg'), 'holiday photo.jpg');
      expect(sanitiseIncomingName('archive.tar.gz'), 'archive.tar.gz');
    });

    test('strips every separator, so a name cannot address a directory', () {
      expect(sanitiseIncomingName('../../etc/passwd'), '.._.._etc_passwd');
      expect(
        sanitiseIncomingName(r'..\..\windows\system32\cmd.exe'),
        '.._.._windows_system32_cmd.exe',
      );
      expect(sanitiseIncomingName('/etc/shadow'), '_etc_shadow');
      expect(sanitiseIncomingName(r'C:\autoexec.bat'), 'C__autoexec.bat');
    });

    test('a name made only of dots cannot become a directory reference', () {
      expect(sanitiseIncomingName('.'), 'received');
      expect(sanitiseIncomingName('..'), 'received');
      expect(sanitiseIncomingName('...'), 'received');
    });

    test('drops characters Windows would refuse rather than failing later', () {
      expect(sanitiseIncomingName('a<b>c:d"e|f?g*h'), 'a_b_c_d_e_f_g_h');
      expect(
        sanitiseIncomingName('name\u0000with\u001fcontrols'),
        'namewithcontrols',
      );
    });

    test('drops trailing dots and spaces, which Windows would drop anyway', () {
      expect(sanitiseIncomingName('report.txt.  '), 'report.txt');
      expect(sanitiseIncomingName('report. '), 'report');
    });

    test('an empty name still yields a usable one', () {
      expect(sanitiseIncomingName(''), 'received');
      expect(sanitiseIncomingName('   '), 'received');
    });
  });

  group('incomingPathFor', () {
    late Directory directory;

    setUp(() {
      directory = Directory.systemTemp.createTempSync('local-transfer-paths-');
    });

    tearDown(() {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });

    test('lands a plain name inside the directory', () {
      final file = incomingPathFor(directory, 'notes.txt');
      expect(file.parent.path, directory.path);
      expect(file.path.endsWith('notes.txt'), isTrue);
    });

    test('a traversal attempt still lands inside the directory', () {
      final file = incomingPathFor(directory, '../../escape.txt');
      // The invariant is not "the name looks clean" but "the path is inside":
      // stripping the separators is only how that is achieved.
      expect(
        file.absolute.path.startsWith(
          '${directory.absolute.path}${Platform.pathSeparator}',
        ),
        isTrue,
        reason: '${file.path} escaped ${directory.path}',
      );
      expect(file.parent.absolute.path, directory.absolute.path);
    });

    test('numbers around an existing file instead of overwriting it', () {
      File('${directory.path}${Platform.pathSeparator}notes.txt')
          .writeAsStringSync('already here');
      final file = incomingPathFor(directory, 'notes.txt');
      expect(file.path, endsWith('notes (2).txt'));
      expect(
        File('${directory.path}${Platform.pathSeparator}notes.txt')
            .readAsStringSync(),
        'already here',
      );
    });

    test('keeps the extension when it numbers a clash', () {
      File('${directory.path}${Platform.pathSeparator}archive.tar.gz')
          .writeAsStringSync('x');
      expect(
        incomingPathFor(directory, 'archive.tar.gz').path,
        endsWith('archive.tar (2).gz'),
      );
    });

    test('numbers around a file with a trailing-dot name after sanitising', () {
      File('${directory.path}${Platform.pathSeparator}report')
          .writeAsStringSync('x');
      expect(
        incomingPathFor(directory, 'report.').path,
        endsWith('report (2)'),
      );
    });
  });

  // A folder send arrives as item names that are paths — `a/b/c.txt` — and
  // this is where those segments become directories on this Device's disk.
  // The invariant is the same one the flat name keeps: whatever the peer
  // sent, the answer is a place inside the folder the user picked.
  group('incomingLandingFor', () {
    late Directory directory;

    setUp(() {
      directory = Directory.systemTemp.createTempSync('local-transfer-land-');
    });

    tearDown(() {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });

    /// Whether [path] sits inside [directory], separator-aware.
    bool inside(Directory root, String path) =>
        path == root.path ||
        path.startsWith('${root.path}${Platform.pathSeparator}');

    test('a plain name lands in the root, as it always has', () {
      final landing = incomingLandingFor(directory, 'notes.txt');
      expect(landing.directory.path, directory.path);
      expect(landing.name, 'notes.txt');
    });

    test('a path name becomes directories under the root', () {
      final landing = incomingLandingFor(directory, 'photos/2024/beach.jpg');
      expect(
        landing.directory.path,
        endsWith('photos${Platform.pathSeparator}2024'),
      );
      expect(landing.name, 'beach.jpg');
      expect(
        inside(directory, landing.directory.path),
        isTrue,
        reason: '${landing.directory.path} escaped ${directory.path}',
      );
    });

    test('a traversal attempt stays inside, segment by segment', () {
      final landing = incomingLandingFor(directory, '../../etc/passwd');
      expect(
        inside(directory, landing.directory.path),
        isTrue,
        reason: '${landing.directory.path} escaped ${directory.path}',
      );
      // `..` sanitises to `received`, so the climb becomes directories named
      // for what they are not.
      expect(landing.name, 'passwd');
    });

    test('empty and dot segments carry no name and are dropped', () {
      final landing = incomingLandingFor(directory, 'a//b/./c.txt');
      expect(landing.directory.path, endsWith('a${Platform.pathSeparator}b'));
      expect(landing.name, 'c.txt');
    });

    test('a name that is all separators still lands a file', () {
      final landing = incomingLandingFor(directory, '/');
      expect(landing.directory.path, directory.path);
      expect(landing.name, isNotEmpty);
    });

    test('a backslash inside a segment is not a separator', () {
      // The wire convention is '/'; a '\' arrives inside a segment and is
      // sanitised like any other character Windows refuses in a name.
      final landing = incomingLandingFor(directory, r'a\b/c.txt');
      expect(landing.directory.path, endsWith('a_b'));
      expect(landing.name, 'c.txt');
    });
  });

  // The name a file wears while its bytes are crossing. It exists so that a
  // Transfer that dies takes nothing with it: no empty file under a name that
  // looks received, and no occupied name for the next attempt to number around.
  group('stagingPathFor', () {
    late Directory directory;

    setUp(() {
      directory = Directory.systemTemp.createTempSync('local-transfer-stage-');
    });

    tearDown(() {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });

    test('stages inside the directory, under a name that says what it is', () {
      final staged = stagingPathFor(directory, 'report.pdf');
      expect(staged.parent.absolute.path, directory.absolute.path);
      expect(staged.path, endsWith('.part'));
      expect(fileNameOf(staged.path), contains('report.pdf'));
    });

    test('never takes the name the file will finally have', () {
      final staged = stagingPathFor(directory, 'report.pdf');
      expect(
        staged.path,
        isNot(incomingPathFor(directory, 'report.pdf').path),
        reason:
            'the whole point is that the final name stays free until it is '
            'earned',
      );
    });

    test('a traversal attempt still stages inside the directory', () {
      final staged = stagingPathFor(directory, '../../escape.pdf');
      expect(
        staged.absolute.path.startsWith(
          '${directory.absolute.path}${Platform.pathSeparator}',
        ),
        isTrue,
        reason: '${staged.path} escaped ${directory.path}',
      );
    });

    test('two attempts at one name stage apart', () {
      expect(
        stagingPathFor(directory, 'report.pdf').path,
        isNot(stagingPathFor(directory, 'report.pdf').path),
      );
    });
  });
}
