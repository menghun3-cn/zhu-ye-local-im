import 'dart:io';

import 'views.dart';

/// One file found while listing a folder to send.
final class FolderEntry {
  const FolderEntry({
    required this.relativePath,
    required this.file,
    required this.size,
  });

  /// The file's place inside the sent folder, `/`-separated —
  /// `sub/dir/file.txt`. This is the segment list the receiver rebuilds as
  /// directories; see [incomingLandingFor].
  final String relativePath;

  /// Where the bytes are read from.
  final File file;

  /// The size the stat reported when the folder was listed.
  final int size;
}

/// What a folder send will carry, known before a byte is hashed.
final class FolderListing {
  const FolderListing({
    required this.rootName,
    required this.entries,
    required this.totalBytes,
    required this.skipped,
  });

  /// The folder's own name — the first path segment every item name carries,
  /// so the receiver's tree is rooted at something the sender called it.
  final String rootName;

  /// Every regular file under the root, in walk order.
  final List<FolderEntry> entries;

  /// The sum of [entries]' sizes — what the Offer's `totalBytes` will say.
  final int totalBytes;

  /// Entries that were not sent: unreadable directories or files, and links.
  ///
  /// Links are skipped rather than followed on purpose — a link can point
  /// outside the chosen folder, and following it would send bytes the user
  /// never picked. They count here so a folder that arrives missing something
  /// has an explanation, even though nothing surfaces the count yet.
  final int skipped;
}

/// Lists every regular file under [root], preserving the tree as relative
/// paths.
///
/// Only files travel: the wire format has no way to say "this is a directory",
/// so an empty folder — or the directories between files — produces no item
/// of its own. The directories still arrive, because every file's name carries
/// them.
///
/// The walk is iterative rather than recursive so a deep tree cannot exhaust
/// the stack, and breadth-first so the order a user recognises — the folder's
/// own entries before what is inside them — is the order the items go out in.
Future<FolderListing> listFolderForSend(Directory root) async {
  final entries = <FolderEntry>[];
  var totalBytes = 0;
  var skipped = 0;

  // (directory, its path relative to the root, '/'-separated) — '' for the
  // root itself, which is not part of any item's relative path.
  final pending = <(Directory, String)>[(root, '')];
  while (pending.isNotEmpty) {
    final (directory, prefix) = pending.removeAt(0);
    final List<FileSystemEntity> children;
    try {
      children = await directory.list(followLinks: false).toList();
    } on Object {
      // A directory that cannot be listed is skipped whole: there is no way
      // to know what was inside it, and half a folder is still a folder.
      skipped++;
      continue;
    }
    for (final entity in children) {
      // `followLinks: false` on the listing means a link arrives as a [Link]
      // rather than as what it points at, so the concrete type is the whole
      // classification: directories are queued, files are sized, and links —
      // which could point outside the folder the user picked — are skipped.
      if (entity is Link) {
        skipped++;
        continue;
      }
      // The last path segment is the entry's own name. `fileNameOf` reads it
      // the same way for files and directories, under either separator.
      final name = fileNameOf(entity.path);
      final relative = prefix.isEmpty ? name : '$prefix/$name';
      if (entity is Directory) {
        pending.add((entity, relative));
        continue;
      }
      if (entity is! File) {
        skipped++;
        continue;
      }
      final FileStat stat;
      try {
        stat = await entity.stat();
      } on Object {
        skipped++;
        continue;
      }
      entries.add(
        FolderEntry(relativePath: relative, file: entity, size: stat.size),
      );
      totalBytes += stat.size;
    }
  }

  // A trailing separator would leave `fileNameOf` with nothing after the last
  // cut, so the root's own name is read from the path with them trimmed.
  var rootPath = root.path;
  while (rootPath.length > 1 &&
      (rootPath.endsWith('/') || rootPath.endsWith('\\'))) {
    rootPath = rootPath.substring(0, rootPath.length - 1);
  }
  final rootName = fileNameOf(rootPath);
  return FolderListing(
    // A root with no name of its own — a drive root, say — still needs a first
    // segment, or every item's name would begin with a separator that the
    // receiver reads as nothing.
    rootName: rootName.isEmpty ? 'folder' : rootName,
    entries: entries,
    totalBytes: totalBytes,
    skipped: skipped,
  );
}
