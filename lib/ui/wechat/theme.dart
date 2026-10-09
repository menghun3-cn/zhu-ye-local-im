import 'package:flutter/material.dart';

/// The WeChat look, as numbers.
///
/// Every colour, size and gap the conversation surfaces use is named here, so
/// that "match WeChat" is a thing the code can be held to rather than an
/// impression. The values are the ones the Windows desktop client and the
/// phone client agree on; where the two differ, the desktop client wins,
/// because this is a desktop app and a phone-sized bubble on a 1920px window
/// reads as a toy.
///
/// Nothing in this file depends on `MaterialApp` — it is plain data plus one
/// [ThemeData] built from it, so the tokens can be asserted in a test without
/// pumping a widget.
///
/// The [theme] below is the *only* place a Material component's colours are
/// decided. Material has a default for every slot it reads, and those defaults
/// are Material 3's own palette — lavender containers, a purple-grey
/// `onSurfaceVariant`, a tinted `surfaceTint` that washes every elevated
/// surface towards the seed. A page that left one slot alone would therefore
/// fall back to a colour nobody chose, which is exactly the failure this file
/// exists to prevent: the pages pass tokens, they do not invent them.
class WeChat {
  const WeChat._();

  // ---------------------------------------------------------------- 颜色

  /// 微信品牌绿。用于「发送」按钮、选中态强调、以及发出的消息气泡。
  static const Color brand = Color(0xFF07C160);

  /// 发出的消息气泡底色。比品牌绿浅得多 —— 一整屏 `#07C160` 会刺眼，
  /// 微信实际用的就是这个浅绿。
  static const Color bubbleOut = Color(0xFF95EC69);

  /// 收到的消息气泡底色，也是卡片和对话框的底色。
  static const Color bubbleIn = Color(0xFFFFFFFF);

  /// 气泡里的字色。两种气泡都用近黑，不是纯黑 —— 纯黑在浅绿上发脏。
  static const Color bubbleText = Color(0xFF1A1A1A);

  /// 会话列表、聊天区的页面底色。
  static const Color pageBackground = Color(0xFFEDEDED);

  /// 左侧会话列表、导航栏、工具条的底色。比聊天区略浅，两侧靠这层灰差分开。
  static const Color sidebarBackground = Color(0xFFF7F7F7);

  /// 分隔线。微信的分割线很淡。
  static const Color divider = Color(0xFFE7E7E7);

  /// 次要文字：最后一句话、时间戳、提示语、字段名。
  static const Color secondaryText = Color(0xFF888888);

  /// 比 [secondaryText] 更淡的一层：禁用态、占位符。
  static const Color disabledText = Color(0xFFB2B2B2);

  /// 会话列表里选中那一行的底色。
  static const Color listSelected = Color(0xFFC9C9C9);

  /// 会话列表里鼠标悬停那一行的底色，也是控件被按下时的浅灰。
  static const Color listHover = Color(0xFFE9E9E9);

  /// 输入区工具栏的底色。
  static const Color toolbarBackground = Color(0xFFF7F7F7);

  /// 未读/待处理角标的底色。微信的红。
  static const Color badge = Color(0xFFFA5151);

  /// 出错时那一层浅红，用作错误色的容器。
  static const Color errorContainer = Color(0xFFFDE7E7);

  // ---------------------------------------------------------------- 字号

  /// 消息正文。15 是微信的正文尺寸，不是 Material 默认的 14。
  static const double fontSizeBody = 15;

  /// 正文行高倍数。1.4 让中文段落有呼吸又不散。
  static const double lineHeightBody = 1.4;

  /// 会话名、导航项。
  static const double fontSizeTitle = 15;

  /// 卡片标题、文件名的尺寸。
  static const double fontSizeLabel = 14;

  /// 会话列表里那一句摘要、区块标题。
  static const double fontSizePreview = 13;

  /// 时间戳、字节数这类附属信息，也是导航项的标签。
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

  /// 会话列表一行的左右内边距。
  ///
  /// 同时是行分隔线的左侧缩进：分隔线从**头像左缘**起笔，而不是从这一行的
  /// 最左边起笔 —— 整行通栏的横线会把列表切成一块块，而微信的列表是一整片，
  /// 线只是把两条会话轻轻分开。
  static const double conversationRowPadding = 12;

  /// 卡片圆角。比气泡略方一点，微信桌面端的设置面板就是这个手感。
  static const double cardRadius = 8;

  /// 页面四周的留白。四个页面共用同一个数，页与页之间才不会各写各的。
  static const EdgeInsets pagePadding = EdgeInsets.all(16);

  /// 卡片内部的留白。
  static const double cardPadding = 16;

  /// 两张卡片之间的间距。
  static const double cardGap = 12;

  /// 区块与区块之间的间距，比 [cardGap] 大一档。
  static const double sectionGap = 20;

  /// 小按钮/小控件的圆角。比卡片更方，一个 pill 不该出现在列表行里。
  static const double controlRadius = 4;

  // ---------------------------------------------------------------- 主题

  /// The [ThemeData] the app runs on.
  ///
  /// Built from the tokens above rather than seeded, because a seeded scheme
  /// invents its own green and the whole point here is a *specific* green. The
  /// text theme is set in logical pixels with explicit line heights so that a
  /// bubble measures the same as the reference.
  ///
  /// Every colour slot Material might reach for is named, including the ones no
  /// page mentions by hand: a slot left at its default is a slot that renders
  /// Material's lavender, and a single lavender chip in a WeChat-grey list is
  /// more jarring than a whole page of the wrong theme.
  static ThemeData theme() {
    const scheme = ColorScheme.light(
      primary: brand,
      onPrimary: Colors.white,
      primaryContainer: listHover,
      onPrimaryContainer: bubbleText,
      secondary: brand,
      onSecondary: Colors.white,
      secondaryContainer: listHover,
      onSecondaryContainer: bubbleText,
      tertiary: brand,
      onTertiary: Colors.white,
      tertiaryContainer: listHover,
      onTertiaryContainer: bubbleText,
      error: badge,
      onError: Colors.white,
      errorContainer: errorContainer,
      onErrorContainer: badge,
      surface: bubbleIn,
      onSurface: bubbleText,
      surfaceDim: pageBackground,
      surfaceBright: bubbleIn,
      surfaceContainerLowest: bubbleIn,
      surfaceContainerLow: bubbleIn,
      surfaceContainer: bubbleIn,
      surfaceContainerHigh: sidebarBackground,
      surfaceContainerHighest: listHover,
      onSurfaceVariant: secondaryText,
      outline: divider,
      outlineVariant: divider,
      shadow: Color(0x14000000),
      scrim: Color(0x80000000),
      inverseSurface: Color(0xFF2E2E2E),
      onInverseSurface: Colors.white,
      inversePrimary: bubbleOut,
      // Transparent, so nothing Material draws is tinted towards the seed:
      // WeChat's surfaces are flat greys and whites, and the elevation tint
      // Material 3 applies by default is the one thing that would make a flat
      // white card look like it came from a different application.
      surfaceTint: Colors.transparent,
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
      // Icons on a WeChat surface are grey unless a component says otherwise;
      // an icon that inherited `onSurface` would be near-black and shout.
      iconTheme: const IconThemeData(color: secondaryText, size: 20),
      appBarTheme: const AppBarTheme(
        backgroundColor: sidebarBackground,
        foregroundColor: bubbleText,
        elevation: 0,
        centerTitle: true,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: const CardThemeData(
        color: bubbleIn,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        // Flush, because the pages put their own gaps between cards: a
        // built-in margin on top of those would make every gap depend on
        // whether the page remembered to add one.
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(cardRadius)),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: divider,
        thickness: 1,
        space: 1,
      ),
      chipTheme: const ChipThemeData(
        backgroundColor: listHover,
        surfaceTintColor: Colors.transparent,
        side: BorderSide(color: divider),
        elevation: 0,
        padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        labelStyle: TextStyle(fontSize: fontSizeMeta, color: bubbleText),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(controlRadius)),
        ),
      ),
      listTileTheme: const ListTileThemeData(
        iconColor: secondaryText,
        textColor: bubbleText,
        subtitleTextStyle: TextStyle(
          fontSize: fontSizePreview,
          color: secondaryText,
        ),
        horizontalTitleGap: 12,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: brand,
        linearTrackColor: divider,
        linearMinHeight: 3,
      ),
      switchTheme: SwitchThemeData(
        // A WeChat switch is grey when off and the brand green when on; the
        // thumb keeps Material's own shape, which the desktop client matches.
        thumbColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? Colors.white : null,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? brand : null,
        ),
        trackOutlineColor: const WidgetStatePropertyAll(divider),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? brand : null,
        ),
        checkColor: const WidgetStatePropertyAll(Colors.white),
        side: const BorderSide(color: divider, width: 1.5),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(3)),
        ),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? brand : null,
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) =>
                states.contains(WidgetState.selected) ? brand : bubbleText,
          ),
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected) ? bubbleIn : null,
          ),
          side: const WidgetStatePropertyAll(BorderSide(color: divider)),
          shape: const WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(controlRadius)),
            ),
          ),
          textStyle: const WidgetStatePropertyAll(
            TextStyle(fontSize: fontSizePreview),
          ),
          visualDensity: VisualDensity.compact,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          backgroundColor: const WidgetStatePropertyAll(brand),
          foregroundColor: const WidgetStatePropertyAll(Colors.white),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          elevation: const WidgetStatePropertyAll(0),
          shape: const WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(controlRadius)),
            ),
          ),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          ),
          minimumSize: const WidgetStatePropertyAll(Size.zero),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
          textStyle: const WidgetStatePropertyAll(
            TextStyle(fontSize: fontSizePreview),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          // A text button is the "link" of this design: the brand colour with
          // no fill, which is how the desktop client draws every quiet action.
          foregroundColor: const WidgetStatePropertyAll(brand),
          shape: const WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(controlRadius)),
            ),
          ),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          ),
          minimumSize: const WidgetStatePropertyAll(Size.zero),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
          textStyle: const WidgetStatePropertyAll(
            TextStyle(fontSize: fontSizePreview),
          ),
        ),
      ),
      navigationRailTheme: const NavigationRailThemeData(
        backgroundColor: sidebarBackground,
        indicatorColor: listHover,
        selectedIconTheme: IconThemeData(color: brand, size: 22),
        unselectedIconTheme: IconThemeData(color: secondaryText, size: 22),
        selectedLabelTextStyle: TextStyle(fontSize: fontSizeMeta, color: brand),
        unselectedLabelTextStyle: TextStyle(
          fontSize: fontSizeMeta,
          color: secondaryText,
        ),
        useIndicator: true,
        elevation: 0,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: toolbarBackground,
        surfaceTintColor: Colors.transparent,
        // No pill: the WeChat bottom bar marks the current tab by tinting the
        // icon and its label, not by drawing a shape behind them.
        indicatorColor: Colors.transparent,
        elevation: 0,
        height: 56,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: fontSizeMeta,
            color: states.contains(WidgetState.selected)
                ? brand
                : secondaryText,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            size: 22,
            color: states.contains(WidgetState.selected)
                ? brand
                : secondaryText,
          ),
        ),
      ),
      dialogTheme: const DialogThemeData(
        backgroundColor: bubbleIn,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(cardRadius)),
        ),
      ),
      textTheme: const TextTheme(
        bodyMedium: TextStyle(fontSize: fontSizeBody, height: lineHeightBody),
        bodySmall: TextStyle(fontSize: fontSizeMeta, color: secondaryText),
        titleLarge: TextStyle(
          fontSize: fontSizeTitle,
          color: bubbleText,
          height: lineHeightBody,
        ),
        titleMedium: TextStyle(fontSize: fontSizeTitle, color: bubbleText),
        // Content titles — a file's name, a peer's name on a card. The quiet
        // group heading above a section is a *different* thing and asks for
        // `secondaryText` explicitly, which is why it is not folded in here.
        titleSmall: TextStyle(fontSize: fontSizeLabel, color: bubbleText),
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
