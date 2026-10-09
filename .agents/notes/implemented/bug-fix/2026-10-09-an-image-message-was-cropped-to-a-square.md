# Agent Note: an image message was cropped to a square

Status: implemented

## Problem

A picture that arrived did not look like itself. `ImageBubble` drew every image
into a fixed 200×200 box with `BoxFit.cover`, which scales the picture until it
covers the box and then cuts off whatever hangs over the edge. For a photograph
that happens to be square, almost nothing is lost. For the shapes people
actually send — a screenshot, a phone photo — a great deal is: a 4:1 capture is
shown as its middle quarter, a portrait as a horizontal band through the middle.
The bubble was the right size and the wrong picture, and the only place the file
could really be read was the full-size view behind a click. Reported from the
packaged Windows build as "接收的图片，未正确显示预览".

## Decision

**Read the picture's shape once, then make the box that shape.** `ImageBubble`
becomes a `StatefulWidget` that follows the picture's `ImageStream` and, on the
first `ImageInfo`, records `Size(width / scale, height / scale)` — the picture's
own size — reduced to fit 200 pixels on both sides and **never scaled up**. The
`Image` is then built inside a `SizedBox` of exactly that size with
`BoxFit.cover`, which crops nothing at all when the box is already the picture's
shape, and only rules out the hairline that rounding to whole pixels would
otherwise leave.

Never up, because a 32-pixel icon drawn at 200 pixels is a preview of the
decoder's guesswork rather than of the file.

**Three states, and the meaning of each is unchanged.** No size yet → a
placeholder; a size → the picture; a decode error → the existing
name-and-broken-image fallback, which is now also not made to look clickable,
since a picture that cannot be read has nothing to open into.

**The placeholder is a landscape-ish 200×132 box, not a zero-sized one.** A
zero-sized box makes the bubble collapse and spring back as the picture lands,
which reads as a glitch rather than as loading; a box already close to the
common shape grows only a little.

**The subscription is added in `didChangeDependencies`, not `initState`.** The
decode is keyed on the display's pixel ratio, which is only known once the
widget is in a tree. A picture already in Flutter's cache is handed over
**synchronously** during `addListener` — which is to say during
`didChangeDependencies`, a phase where `setState` is an error — so that case
writes the field directly and lets the build that immediately follows read it.

## Alternatives considered

**A fixed 200×200 box with `BoxFit.contain`.** Keeps the shape but pads: a 4:1
picture inside a square box is drawn with bars of empty bubble above and below,
which is a preview of the box rather than of the picture. The box has to *be*
the picture's shape, and the only way to know that shape is to decode it.

**No explicit size, letting the `Image` size itself inside a `ConstrainedBox`.**
`RenderImage` does size itself to its intrinsic size, constrained and
aspect-preserved — but only once it has decoded, and until then it takes
`constraints.smallest`, which is zero. The bubble would be an empty sliver for
the frames before the decode and then jump to full size, with no placeholder to
cover the gap.

**A square box with `BoxFit.cover`** — what it was. It is the bug.

**Send the picture's dimensions, or a thumbnail, over the wire.** The offer
carries a digest and the receiver draws the file it verified. A size, or a
preview path, would be a protocol change for a display detail, and would let the
sender describe a picture differently from the one it actually sends.

**Decode at the display size with `ResizeImage`/`cacheWidth`.** A decode-time
saving with no bearing on the shape of the preview, and one more thing to get
wrong about a picture the user can open at full size anyway.

## Consequences

**A message's height is no longer known before its picture is decoded.** The
thumbnail's height follows the picture, so the conversation cannot reserve the
space in advance and the placeholder is what keeps the arrival from being a
jump. A message drawn twice — placeholder, then picture — is the normal frame
sequence, not a fault.

**`FileImage`'s scale is 1, so a picture's pixels are its logical pixels.** This
is how `Image.file` has always behaved and the old code inherited it. The
consequence here is that the 200-pixel bound is a bound in *image* pixels: a
60-pixel logo is drawn 60 logical pixels wide, which on a 3× display is small
and slightly soft rather than crisp. Decoding at the display's ratio is the fix
if that ever matters; it is not what this change is about, and it would make
small pictures smaller still.

**The bubble resolves its picture twice — once to measure, once to draw.** Both
goes use `FileImage` with the same configuration, so the second is a cache hit
and there is no second decode. `ImageBubble` holds no bytes of its own, which is
what keeps it cheap in a conversation that rebuilds on every progress tick of
every live Transfer.

**The full-size view is untouched.** `showImagePreview` already drew the picture
unconstrained inside an `InteractiveViewer`; only the thumbnail was wrong.

## Testing

`test_flutter/ui/image_bubble_test.dart` is new. It reads the size the layout
actually gave the picture, which is the only thing a user can see:

* a 4:1 picture is laid out 200×50 — the assertion that fails against the old
  `BoxFit.cover` box, which would have produced 200×200;
* a 1:4 picture is laid out 50×200, so the bound holds on the other axis too;
* a 40-pixel picture is laid out 40 pixels wide, so the box shrinks to a small
  picture rather than blowing it up;
* a picture whose file is not there falls back to its name and draws no `Image`
  at all;
* a bubble with no `onOpen` has no click target inside it, and one with an
  `onOpen` calls it when the thumbnail is clicked.

The fixtures are real PNGs of a requested size, encoded by the engine
(`writePng` in `test_flutter/support/ui_harness.dart`) rather than written out
as byte literals: the preview's shape comes from decoding, so a fixture that
merely looked like a PNG would test the fallback instead of the preview.

`test/app/app_controller_test.dart` gains "a received picture keeps a path worth
drawing", which pins the other half of the join: an image offer has no path to
draw until it is accepted, and a landed image has one that reads back the bytes
that were sent.
