# Agent Note: The narrow top bar keeps its menu

Status: implemented

## Problem

The site's top bar hides `.topbar__nav` wholesale under 860 px
(`site/styles.css`). That was fine while the nav held only in-page anchors —
a phone reader can still scroll to 功能 / 下载 / 说明 — but the same nav also
carried 源码 and the 联系 dropdown with the QQ group link, the only feedback
channel the site offers. On a phone the whole entry disappeared: there was no
way to reach the group at all.

## Decision

A hamburger button (`#navMenuBtn`, reusing the `.theme-toggle` square styling)
now sits in the top bar only under 860 px, next to the theme toggle. It opens
`.nav-menu__panel`, a dropdown styled like `.nav-drop__panel`, listing the same
four nav entries plus 联系 as a direct link to the QQ group — the dropdown's
single item did not justify a second level of nesting inside a menu that is
itself a dropdown.

The whole `.nav-menu` subtree is `display: none` above the breakpoint, so the
desktop bar is unchanged; under it, `.nav-menu` takes `margin-left: auto`, the
slot the hidden nav used to hold. `site/app.js` gives the menu the same
contract as the 联系 dropdown: outside click, Escape, and clicking any link
all close it, with `aria-expanded` tracking state.

## Alternatives considered

**Keep the nav visible and let it wrap or scroll.** Rejected: five entries plus
a dropdown do not fit a phone top bar, and horizontal scrolling hides exactly
the entries a narrow screen most needs to reach.

**Show only the 联系 entry on mobile.** Rejected: it solves the reported gap
but leaves 源码 unreachable and creates a second, differently-shaped nav that
has to be maintained beside the first.

**Move 联系 into the footer.** Rejected as the *only* fix: the footer already
carries 源码 / 发布记录 / 更新日志, and contact is a primary action, not a
colophon — burying it contradicts why the entry sits in the top bar at all.

## Consequences

- Mobile readers get every nav destination, including the QQ group, behind one
  tap; desktop markup and behavior are untouched.
- The menu duplicates the nav's link list in `index.html`, so a future nav
  change must be mirrored in `#navMenuPanel` — the same trade-off the footer
  link list already accepts.
- The panel is positioned against `.nav-menu` inside the sticky top bar, so it
  overlays page content rather than pushing layout; `z-index` inherits the
  top bar's 20.
