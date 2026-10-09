import 'package:flutter/material.dart';

/// The WeChat look, as numbers.
///
/// Every colour, size and gap the conversation surfaces use is named here, so
/// that "match WeChat" is a thing the code can be held to rather than a
/// impression. The values are the ones the Windows desktop client and the
/// phone client agree on; where the two differ, the desktop client wins,
/// because this is a desktop app and a phone-sized bubble on a 1920px window
/// reads as a toy.
///
/// Nothing in this file depends on `MaterialApp` — it is plain data plus one
/// [ThemeData] built from it, so the tokens can be asserted in a test without
/// pumping a widget.
class WeChat {
  const WeChat._();

  // ---------------------------------------------------------------- 颜色

  /// 微信品牌绿。用于「发送」按钮、选中态强调、以及发出的消息气泡。
  static const Color brand = Color(0xFF07C160);

  /// 发出的消息气泡底色。比品牌绿浅得多 —— 一整屏 `#07C160` 会刺眼，
  /// 微信实际用的就是这个浅绿。
  static const Color bubbleOut = Color(0xFF95EC69);

  /// 收到的消息气泡底色。
  static const Color bubbleIn = Color(0xFFFFFFFF);

  /// 气泡里的字色。两种气泡都用近黑，不是纯黑 —— 纯黑在浅绿上发脏。
  static const Color bubbleText = Color(0xFF1A1A1A);

  /// 会话列表、聊天区的页面底色。
  static const Color pageBackground = Color(0xFFEDEDED);

  /// 左侧会话列表的底色。比聊天区略浅，两侧靠这层灰差分开。
  static const Color sidebarBackground = Color(0xFFF7F7F7);

  /// 分隔线。微信的分割线很淡。
  static const Color divider = Color(0xFFE7E7E7);

  /// 次要文字：最后一句话、时间戳、提示语。
  static const Color secondaryText = Color(0xFF888888);

  /// 会话列表里选中那一行的底色。
  static const Color listSelected = Color(0xFFC9C9C9);

  /// 会话列表里鼠标悬停那一行的底色。
  static const Color listHover = Color(0xFFE9E9E9);

  /// 输入区工具栏的底色。
  static const Color toolbarBackground = Color(0xFFF7F7F7);

  /// 未读/待处理角标的底色。微信的红。
  static const Color badge = Color(0xFFFA5151);

  // ---------------------------------------------------------------- 字号

  /// 消息正文。15 是微信的正文尺寸，不是 Material 默认的 14。
  static const double fontSizeBody = 15;

  /// 正文行高倍数。1.4 让中文段落有呼吸又不散。
  static const double lineHeightBody = 1.4;

  /// 会话名、导航项。
  static const double fontSizeTitle = 15;

  /// 会话列表里那一句摘要。
  static const double fontSizePreview = 13;

  /// 时间戳、字节数这类附属信息。
  static const double fontSizeMeta = 12;

  /// 输入框里的字，与正文同号。
  static const double fontSizeInput = 15;

  // ---------------------------------------------------------------- 尺寸

  /// 头像直径。
  static const double avatar = 40;

  /// 气泡圆角。微信是 6，比 Material 默认的 12 方正很多。
  static const double bubbleRadius = 6;

  /// 气泡内边距。
  static const EdgeInsets bubblePadding = EdgeInsets.symmetric(
    horizontal: 12,
    vertical: 9,
  );

  /// 气泡到头像的间距。
  static const double bubbleAvatarGap = 10;

  /// 两条消息之间的纵向间距。
  static const double messageGap = 16;

  /// 气泡最大宽度占可用宽度的比例。
  ///
  /// 一个比例而不是固定像素：微信的窄屏气泡和宽屏气泡都不会撑满，
  /// 而固定 460 像素在 2560 宽的窗口里显得很短，在 600 宽的窗口里又过长。
  static const double bubbleMaxWidthFactor = 0.6;

  /// 会话列表宽度。
  static const double conversationListWidth = 250;

  /// 会话列表里一行的高度。
  static const double conversationRowHeight = 64;

  // ---------------------------------------------------------------- 主题

  /// The [ThemeData] the app runs on.
  ///
  /// Built from the tokens above rather than seeded, because a seeded scheme
  /// invents its own green and the whole point here is a *specific* green. The
  /// text theme is set in logical pixels with explicit line heights so that a
  /// bubble measures the same as the reference.
  static ThemeData theme() {
    const scheme = ColorScheme.light(
      primary: brand,
      onPrimary: Colors.white,
      secondary: brand,
      surface: bubbleIn,
      onSurface: bubbleText,
      error: badge,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: pageBackground,
      dividerColor: divider,
      // 中文优先：Windows 上 Material 默认的 Roboto 不含汉字，会回退到
      // 系统字体；显式点名雅黑能让中英混排的基线一致。
      fontFamily: 'Microsoft YaHei UI',
      fontFamilyFallback: const ['Microsoft YaHei', 'PingFang SC', 'Roboto'],
      appBarTheme: const AppBarTheme(
        backgroundColor: sidebarBackground,
        foregroundColor: bubbleText,
        elevation: 0,
        centerTitle: true,
      ),
      textTheme: const TextTheme(
        bodyMedium: TextStyle(fontSize: fontSizeBody, height: lineHeightBody),
        bodySmall: TextStyle(fontSize: fontSizeMeta, color: secondaryText),
        titleMedium: TextStyle(fontSize: fontSizeTitle, color: bubbleText),
        labelSmall: TextStyle(fontSize: fontSizeMeta, color: secondaryText),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        border: InputBorder.none,
        isDense: true,
        hintStyle: TextStyle(fontSize: fontSizeInput, color: secondaryText),
      ),
    );
  }
}
