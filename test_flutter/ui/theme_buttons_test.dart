import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_transfer/ui/wechat/theme.dart';

/// The theme's promise that "cannot be pressed" never looks like "can be".
///
/// The filled and text pairs are pinned where they are used — the update
/// card's button mid-download in `update_session_test.dart`. What is pinned
/// here is the segmented control, whose disabled segments are a real surface:
/// the clipboard page shows a mode this platform cannot honour greyed out,
/// and the bubble-skin picker's ink toggle disables itself while there is no
/// draft for it to apply to. A segment that kept `bubbleText` on `surface`
/// would read as selectable.
void main() {
  testWidgets('a disabled segment resolves the disabled colours', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: WeChat.theme(WeChatColors.light),
        home: Scaffold(
          body: SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 0, label: Text('mirror')),
              ButtonSegment(value: 1, label: Text('off'), enabled: false),
            ],
            selected: const {},
            emptySelectionAllowed: true,
            onSelectionChanged: (_) {},
          ),
        ),
      ),
    );

    final style = SegmentedButtonTheme.of(
      tester.element(find.byType(SegmentedButton<int>)),
    ).style;
    final colors = WeChatColors.light;

    expect(
      style?.foregroundColor?.resolve(const {WidgetState.disabled}),
      colors.disabledText,
    );
    expect(
      style?.backgroundColor?.resolve(const {WidgetState.disabled}),
      colors.surfaceSunken,
    );
    // The live states are untouched: selected still wears the action green,
    // and an unselected enabled segment — no disabled state at all — still
    // reads as body text.
    expect(
      style?.foregroundColor?.resolve(const {WidgetState.selected}),
      colors.brandStrong,
    );
    expect(
      style?.foregroundColor?.resolve(const <WidgetState>{}),
      colors.bubbleText,
    );
  });
}
