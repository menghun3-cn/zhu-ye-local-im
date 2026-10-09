# Agent Note: the conversation board and a received bubble trade fills

Status: implemented

## Problem

The conversation was painted the way WeChat paints it: a grey board
(`pageBackground`, `#EDEDED`), a white bubble for anything received
(`bubbleIn`, `#FFFFFF`), and a light green one for anything sent. The request
was the reverse — a white board, a grey received bubble, the two fills
changing places — and the shape of the code made that harder than it sounds.

`bubbleIn` was not the incoming bubble's colour. It was *the* white, shared by
six roles: the incoming bubble, the card, the dialog, the composer's text
field, a staged attachment's chip, the drop overlay's card, and the
`ColorScheme`'s `surface`, `surfaceBright` and three `surfaceContainer*` slots.
Taking it to grey would have taken every card and every dialog on the four
other pages with it — and those pages sit on `pageBackground`, which is the
very grey the bubble was supposed to take. A grey card on a grey page is a card
nobody can see.

The board had the mirror-image problem. There was no token for "the surface a
conversation is drawn on": `ConversationView`'s history had no background of
its own and inherited `scaffoldBackgroundColor`, which is also what the
Devices, Transfers, Clipboard and Settings pages stand on. Repainting that
would have repainted four pages to fix one pane.

## Decision

**The two fills exchange values.** `bubbleIn` takes `#EDEDED` — exactly the
grey `pageBackground` held — and the board takes `#FFFFFF`, exactly the white
`bubbleIn` held. The swap is literal. The request was that these two backgrounds
change places, so the two tokens took each other's value rather than each
drifting to a new grey.

**The white is split three ways, one job each.** `bubbleIn` keeps the incoming
bubble and nothing else. A new `WeChat.surface` is the panel: the card, the
dialog, the composer's field, the staged-attachment chip, the drop overlay's
card, the segmented button's selected fill, and every `ColorScheme` slot that
used to read `bubbleIn`. A new `WeChat.conversationBackground` is the board
itself.

`surface` and `conversationBackground` are the same colour today, and that is
deliberate. They are kept apart because they answer different questions: a
panel is a thing *on* a page, and the board is what messages are drawn *on*.
Sharing one token is what made this request reach into six widgets across three
files; whether the next request is "tint the conversation a little" or "the
settings cards want an edge", it will want to move one of the two and not the
other.

**The board is painted where the history is, not where the page is.**
`ConversationView` wraps its history pane in a `ColoredBox` of
`conversationBackground`. The header and the composer keep their own greys on
purpose, so the pane moves and nothing else does. The Conversations surface's
"pick a conversation" pane — which is where a conversation would open — takes
the same fill, so an empty pane and a real one do not differ in colour.

**The image placeholders move with the bubble, not with the page.** The loading
box and the undecodable-image box *inside* a picture bubble were
`pageBackground` — which is now the incoming bubble's own grey. A grey box in a
grey bubble is invisible, on exactly the messages that most need something
visible. They are `surface`, which reads as a hole punched in the fill on the
grey bubble and on the green one alike.

## Alternatives considered

**Take `bubbleIn` to grey and accept grey cards.** One line, no new tokens.
Rejected outright: the four other pages are `pageBackground` behind white
cards, so their cards would have gone grey-on-grey. The request named the
conversation, and this would have changed most of the application instead.

**Take `scaffoldBackgroundColor` to white.** Also one line, and it does
recolour the conversation. Rejected because it recolours the Devices,
Transfers, Clipboard and Settings pages too — white cards on a white page,
which is the same failure from the other end. It also leaves the received
bubble white, so nothing would have traded places at all.

**Name one white and use it for the board and the panels alike.** Fewer tokens,
and defensible while the two happen to be the same colour. Rejected because it
restores the coupling that caused this note: the board and the panels would
have to move together, and the next request about either one would be a
six-widget change again.

**Give `bubbleIn` a fresh grey instead of the page's exact value.** A slightly
different grey would keep "the bubble's grey" and "the page's grey" from
blurring together in a reader's head. Rejected because the request was that the
two fills change places: the board gives up `#EDEDED` and the bubble takes it.
Inventing a third grey is a different change, and one nobody asked for.

**Keep the image placeholders on `pageBackground`.** They were never wrong
before and no test named them. Rejected because they sit inside a bubble: once
a received bubble is the grey they were painted in, they vanish on the
messages where an unreadable picture most needs saying so.

## Consequences

**`bubbleIn` no longer means "white" anywhere.** Every place that read it as
"the panel colour" moved to `surface` — four call sites in `conversation_view.dart`,
four in `theme.dart` — and a reader looking for "the white" now has two named
tokens to choose between instead of one implied one. The compiler was no help
here: all eight of those call sites type-checked perfectly before and after.

**A grey card is now the symptom of a mistake.** With the panel colour split
out, a card that comes out grey means something reached for `bubbleIn` where it
meant `surface`. That is a one-line grep rather than the six-widget audit this
change would have been without the split.

**Three tokens are the same white, so a colour-based widget test cannot tell
them apart.** `surface`, `conversationBackground` and `ColorScheme.surface` are
all `#FFFFFF` today. A widget test can assert that the history is *not* on the
page grey — which is the regression that matters — but not which of the three
whites it is on. Which token a widget uses is therefore held by the token
assertions in `shell_test.dart` and by review, not by a widget-level failure.

**A received bubble is pinned as a relationship rather than on screen.** The
suite has no pumped window showing a conversation with a *received* message:
the two-window end-to-end test ends with the file in Bob's folder rather than in
his conversation. So `bubbleIn` is held by `WeChat.bubbleIn ==
WeChat.pageBackground`, by `bubbleIn != conversationBackground`, and by
`MessageBubble`'s unchanged `outgoing ? bubbleOut : bubbleIn`. Asserting the
grey bubble on screen would need a received message in a pumped conversation,
which is harness work this change did not need.

## Testing

`test_flutter/ui/shell_test.dart` gains a test named `the conversation board
and a received bubble have traded fills`. It asserts the *relationship* rather
than the values — the board equals `WeChat.surface`, the bubble equals
`WeChat.pageBackground`, and the two are not equal to each other — because what
was asked for is that the fills changed places, and a later tweak that moved
one without the other would silently undo it. It then checks that the panel
roles did not follow the bubble: the card, the dialog and `ColorScheme.surface`
are all `WeChat.surface`. One assertion in the theme group was repointed from
`WeChat.bubbleIn` to `WeChat.surface`, because the card is a panel.

`test_flutter/ui/pages_test.dart`'s `picking a conversation opens it beside the
list` finds the board through the empty-state text and asserts a `ColoredBox`
of `WeChat.conversationBackground` above it, twice: once for the "pick a
conversation" pane and once for the open conversation. Finding it by the text
it contains rather than by position is what makes the assertion a statement
about the history rather than about the layout — and since the page grey and the
board differ, it fails if the history ever falls back to inheriting again.
`text sent from the pane arrives with no answer needed` asserts that the one
bubble in the thread carries `WeChat.bubbleOut`: the fill that did *not* trade
places, pinned so that a later rearrangement of the two cannot quietly take the
sent message with it.
