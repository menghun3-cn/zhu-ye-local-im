# Agent Note: a staged picture is previewed by itself

Status: implemented

## Problem

Pasting a screenshot into the composer staged it the way a *file* is staged: a chip
reading an icon, the file name, and a ×. For a screenshot the name is the worst
possible label — the clipboard wrote it, so it reads `pasted-179162029439184….png`,
which identifies the paste by its timestamp rather than by what it shows. The user
who pasted two screenshots in a row could not tell them apart without tapping each
one, and the user who pasted one had to read a path to confirm a thing they had just
looked at on their own screen.

WeChat previews a staged picture as the picture: a small square of its own bytes
with a × on the corner. The name chip is what WeChat shows for *files*, which have
nothing else to be previewed by. The composer had one shape where it needed two.

## Decision

The tray now renders each staged attachment by what it is (`_AttachmentTile`):

**A picture is a thumbnail.** A fixed `attachmentThumbSide` (64) square, `BoxFit.cover`,
rounded at `attachmentThumbRadius` (4). The square is deliberate and is the one place
the tray disagrees with the conversation: a received picture keeps its own composition
(`ImageBubble` sizes the box from the decoded aspect ratio) because a message *is* the
picture, while the tray is a row of things about to be sent, where aligned squares
scan better than mixed compositions — which is also WeChat's own choice for its tray.

**The decode is sized to the drawing.** The image resolves through
`ResizeImage(FileImage(...), width: side × devicePixelRatio, allowUpscaling: false)`,
so a tray of five screenshots is five small decodes in the image cache rather than
five full-size ones. `errorBuilder` draws the broken-image glyph on the grey, and the
× stays — taking a bad staging back out must not depend on whether the picture ever
rendered. A tap opens the same `showImagePreview` lightbox a sent picture opens into,
because the tray preview and the message preview are previews of the same bytes.

**The × is a translucent badge on the corner, not a chip suffix.** An 18px
`IconButton` (real focus ring, keyboard activation, and the existing
`removeAttachment` tooltip) filled with the palette's `scrim` and a white glyph,
positioned at the thumbnail's top-right. White on a 55% black circle reads on any
picture a user can paste, on either theme.

**A file stays a chip.** Nothing about a file changed — its name is still the only
preview it has. The chip loses its image-icon branch, which is now dead: pictures
never reach it.

The name is not lost on a thumbnail: it is on the thumbnail's tooltip, and one long
name can no longer push anything around because nothing lays the name out at all.

## Alternatives considered

**Decode the aspect ratio and keep the conversation's shaped-thumbnail rule in the
tray too.** Rejected: it would make the tray faithful to a rule whose reason — a
message's composition is the message — does not apply to a staging list, and it
needs the `ImageStream` bookkeeping `ImageBubble` carries just to size a box. The
fixed square needs none of it and matches the reference.

**Keep the chip and swap only the icon for a thumbnail.** Rejected: a chip with a
64px picture inside it is a card that says nothing the square does not, and keeps
the name's layout weight, which is exactly what makes `pasted-…png` the identity of
the row.

**Fall back to the chip when the decode fails.** Considered and cut: the fallback
would re-render a `pasted-…png` label for the one case where the user least expects
a file metaphor, while the broken-image glyph plus the still-working × and tooltip
say "this did not render; remove it or send it anyway" without renaming anything.

## Consequences

- New size tokens on `WeChat`: `attachmentThumbSide` (64), `attachmentThumbRadius`
  (4), `attachmentThumbBadge` (18). No new colours — the badge uses `scrim`.
- No wire, protocol, or staging-model change: `StagedAttachment` is unchanged; only
  the tray's rendering branches on `isImage` differently.
- The widget tests that waited for the staged picture by its *name text* now wait
  by its tooltip (`pages_test.dart`), and a focused suite
  (`test_flutter/ui/composer_attachment_test.dart`) pins the two shapes: picture →
  thumbnail + badge, file → chip, undecodable bytes → broken glyph with the badge
  still present.
