import 'package:flutter/material.dart';

/// The look of 竹叶, as numbers.
///
/// Every colour, size and gap the surfaces use is named here, so that "match
/// the design" is a thing the code can be held to rather than an impression.
///
/// The palette is Material 3's skeleton with one accent colour: two greens
/// ([brand] to identify, [brandStrong] to act), a warm near-black for text,
/// hairline greys for structure. It is no longer a token-for-token copy of the
/// WeChat desktop client — the class keeps its name because the conversation
/// surfaces still borrow WeChat's shape, but a value here is now chosen for
/// this design.
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

  /// 品牌绿 —— 标识与填充：进度条的推进、选中态的点、图表里的强调。
  ///
  /// 它**不做白字按钮的底**：白字压在这个绿上只有 2.4:1，够不上 AA。
  /// 要「一块绿底 + 可读的字」时，用 [brandStrong]（白字 5.2:1）。
  static const Color brand = Color(0xFF07C160);

  /// 可点击的品牌色：实心按钮的底、链接文字、选中态的图标与标签。
  ///
  /// 与 [brand] 是两个角色 —— [brand] 说的是「我们是谁」，[brandStrong]
  /// 说的是「可以点这里」。白字压在它上面 5.2:1。
  static const Color brandStrong = Color(0xFF0A7E43);

  /// 品牌浅底：选中行的底、输入框聚焦的光晕、品牌标签的底。
  static const Color brandSoft = Color(0xFFE8F8EF);

  /// 品牌浅底上的描边。
  static const Color brandLine = Color(0xFFBFE9D2);

  /// 压在 [brand] 那档绿上的深字。
  static const Color onBrand = Color(0xFF06291A);

  /// 发出的消息气泡底色。
  ///
  /// 浅绿 —— 一整屏 `#07C160` 会刺眼。与品牌绿解耦：[brand] 是按钮与标识，
  /// 气泡是一大块面积，两者要的不是同一个绿。
  static const Color bubbleOut = Color(0xFFA9EA7C);

  /// 发出气泡里的字色。近黑带绿，压在浅绿上 11.4:1。
  static const Color bubbleOutText = Color(0xFF17240F);

  /// 收到的消息气泡底色 —— 白，靠一圈发丝线（[divider]）从白板上浮起来。
  ///
  /// 从前它取的是 [pageBackground] 那档灰。重设计把它换成白底 + 描边：
  /// 一档灰在浅色主题里读起来像「不可用」，而一张描边的白卡才像一条消息。
  static const Color bubbleIn = Color(0xFFFFFFFF);

  /// 卡片、对话框、输入框、附件托盘、分段控件，以及 Material 各种 `surface`
  /// 槽位的底色 —— 一句话说，一块面板。
  static const Color surface = Color(0xFFFFFFFF);

  /// 比 [surface] 低一层的底：悬停的行、凹陷的分段控件槽、进度条的轨道。
  static const Color surfaceSunken = Color(0xFFF0F1F4);

  /// 正文/气泡里的字色。暖调近黑，不是纯黑 —— 纯黑在浅绿上发脏。
  static const Color bubbleText = Color(0xFF171A21);

  /// 设备/传输/剪贴板/设置四个页面的底色，也是 `scaffoldBackgroundColor`。
  static const Color pageBackground = Color(0xFFF4F5F7);

  /// 会话历史区的底色：一块白板，消息气泡浮在上面。
  static const Color conversationBackground = Color(0xFFFFFFFF);

  /// 左侧会话列表、导航栏、工具条的底色。比会话区略浅，两侧靠这层灰差分开。
  static const Color sidebarBackground = Color(0xFFFBFBFD);

  /// 分隔线。一条几乎看不见的发丝线。
  static const Color divider = Color(0xFFE7E9EE);

  /// 比 [divider] 重一档的边界：输入框与幽灵按钮的描边。
  static const Color borderStrong = Color(0xFFD5D9E0);

  /// 次要文字：最后一句话、时间戳、提示语、字段名。
  static const Color secondaryText = Color(0xFF5B6270);

  /// 比 [secondaryText] 更淡的一层：禁用态、占位符。
  static const Color disabledText = Color(0xFF8B929E);

  /// 会话列表里选中那一行的底色 —— 品牌浅底，而不是一档灰。
  static const Color listSelected = brandSoft;

  /// 会话列表里鼠标悬停那一行的底色，也是控件被按下时的浅灰。
  static const Color listHover = surfaceSunken;

  /// 输入区工具栏的底色。
  static const Color toolbarBackground = Color(0xFFFBFBFD);

  /// 语义红：错误、未读角标、危险操作。
  ///
  /// 它替代了从前只叫「角标」的 `badge` —— 那一个名字把「未读几条」和
  /// 「出错了」说成了同一件事，而它们是两件事，只是碰巧都发红。
  static const Color danger = Color(0xFFC33B3B);

  /// 出错时那一层浅红，用作错误色的容器。
  static const Color errorContainer = Color(0xFFFDECEC);

  // ---------------------------------------------------------------- 字号

  /// 消息正文。14 —— 标题比它大一档，正文才退得下去。
  static const double fontSizeBody = 14;

  /// 正文行高倍数。1.4 让中文段落有呼吸又不散。
  static const double lineHeightBody = 1.4;

  /// 会话名、导航项。
  static const double fontSizeTitle = 16;

  /// 卡片标题、文件名的尺寸。
  static const double fontSizeLabel = 13;

  /// 会话列表里那一句摘要、区块标题。
  static const double fontSizePreview = 13;

  /// 时间戳、字节数这类附属信息，也是导航项的标签。
  static const double fontSizeMeta = 12;

  /// 输入框里的字，与正文同号。
  static const double fontSizeInput = 14;

  // ---------------------------------------------------------------- 尺寸

  /// 头像直径。
  static const double avatar = 40;

  /// 头像的圆角。比气泡方一档 —— 头像是「一个方块里的首字母」，不该和气泡
  /// 争圆角。从前它借用 [bubbleRadius]，两个角色共用一个数。
  static const double avatarRadius = 10;

  /// 气泡圆角。四条边都按这个圆，只有朝头像那一角收小到 [bubbleTuckRadius]。
  static const double bubbleRadius = 14;

  /// 气泡朝头像那一角收进去的半径。
  ///
  /// 重设计去掉了气泡的尾巴，改用这个不对称的角说明「这条是谁发的」——
  /// 收角的一侧朝头像。取 3 而不是 0：直角太硬，看不出是刻意收的。
  static const double bubbleTuckRadius = 3;

  /// 气泡内边距。
  static const EdgeInsets bubblePadding = EdgeInsets.symmetric(
    horizontal: 12,
    vertical: 9,
  );

  /// 图片缩略图的圆角。
  ///
  /// 与 [bubbleRadius] 分开命名：缩略图没有底色衬着，只有一张图自己，
  /// 圆角比气泡小一档才不显得「泡」。
  static const double imageRadius = 8;

  /// 图片缩略图两条边各自的上限。
  ///
  /// 一个**正方形**的界限而不是宽度：竖构图在固定宽度下会变成一条比窗口
  /// 还高的像素柱，微信两边都限住正是因为这个。聊天气泡下方那条传输进度条
  /// 也用它当宽度上限 —— 进度条不该比它所描述的那张图还长。
  static const double imageMaxSide = 200;

  /// 气泡到头像的间距。
  static const double bubbleAvatarGap = 10;

  /// 两条消息之间的纵向间距。
  static const double messageGap = 16;

  /// 气泡最大宽度占可用宽度的比例。
  ///
  /// 一个比例而不是固定像素：微信的窄屏气泡和宽屏气泡都不会撑满，
  /// 而固定 460 像素在 2560 宽的窗口里显得很短，在 600 宽的窗口里又过长。
  static const double bubbleMaxWidthFactor = 0.6;

  /// 文件传输气泡宽度随内容自适应时的**下限**。
  ///
  /// 一个名字只有三个字符的文件，气泡也不能窄到进度条读不出来——这个下限
  /// 就是「还能看清一条 3 像素进度线和『0 B / 4.0 MB』」的最小宽度。
  static const double transferBubbleMinWidth = 160;

  /// 文件传输气泡宽度自适应时的**上限**。
  ///
  /// 名字再长，气泡也不跟着长到通栏：超过这条线的名字用省略号截断，
  /// 完整名字放在气泡的提示里。微信的文件卡片也是这个手感——宽得有限，
  /// 从不撑满。
  static const double transferBubbleMaxWidth = 280;

  /// 会话列表宽度。
  ///
  /// 300 而不是 250：1280 宽的窗口里，250 会让「最后一句话」那一行截断得
  /// 太频繁 —— 摘要刚说半句就上省略号，列表就不再能扫读。
  static const double conversationListWidth = 300;

  /// 会话列表一行的上下内边距。
  ///
  /// 一行的**高度不是固定值**，是由内容撑出来的：两行文字（名字 + 摘要）和
  /// 头像谁高听谁的。从前写死一个 64，字号一改行里就会多出或挤掉几像素的
  /// 空白 —— 而这一行的正确高度本来就是它内容的高度。
  static const double conversationRowVPadding = 10;

  /// 会话列表一行的左右内边距。
  ///
  /// 同时是行分隔线的左侧缩进：分隔线从**头像左缘**起笔，而不是从这一行的
  /// 最左边起笔 —— 整行通栏的横线会把列表切成一块块，而微信的列表是一整片，
  /// 线只是把两条会话轻轻分开。
  static const double conversationRowPadding = 12;

  /// 卡片圆角。与气泡同档：一块面板和一个气泡属于同一个家族。
  static const double cardRadius = 14;

  /// 页面四周的留白。四个页面共用同一个数，页与页之间才不会各写各的。
  static const EdgeInsets pagePadding = EdgeInsets.all(16);

  /// 卡片内部的留白。
  static const double cardPadding = 16;

  /// 两张卡片之间的间距。
  static const double cardGap = 12;

  /// 区块与区块之间的间距，比 [cardGap] 大一档。
  static const double sectionGap = 24;

  /// 小按钮/小控件的圆角。比卡片小一档，一个 pill 不该出现在列表行里。
  static const double controlRadius = 8;

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
      // The action colour is the *dark* green: Material reaches for `primary`
      // for a filled button, and a filled button carries white text.
      primary: brandStrong,
      onPrimary: Colors.white,
      primaryContainer: brandSoft,
      onPrimaryContainer: onBrand,
      // The identifying green, for the quieter tonal slots — dark text on it,
      // because white on `#07C160` is only 2.4:1.
      secondary: brand,
      onSecondary: onBrand,
      secondaryContainer: listHover,
      onSecondaryContainer: bubbleText,
      tertiary: brand,
      onTertiary: onBrand,
      tertiaryContainer: listHover,
      onTertiaryContainer: bubbleText,
      error: danger,
      onError: Colors.white,
      errorContainer: errorContainer,
      onErrorContainer: danger,
      surface: surface,
      onSurface: bubbleText,
      surfaceDim: pageBackground,
      surfaceBright: surface,
      surfaceContainerLowest: surface,
      surfaceContainerLow: surface,
      surfaceContainer: surface,
      surfaceContainerHigh: sidebarBackground,
      surfaceContainerHighest: listHover,
      onSurfaceVariant: secondaryText,
      outline: divider,
      outlineVariant: divider,
      shadow: Color(0x14101828),
      scrim: Color(0x80000000),
      inverseSurface: Color(0xFF2E2E2E),
      onInverseSurface: Colors.white,
      inversePrimary: bubbleOut,
      // Transparent, so nothing Material draws is tinted towards the seed:
      // these surfaces are flat greys and whites, and the elevation tint
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
      // Icons on a quiet surface are grey unless a component says otherwise;
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
        color: surface,
        surfaceTintColor: Colors.transparent,
        // One whisper of a shadow rather than none: a card that sits flush on
        // the page reads as a table row, and the scale's first step is what
        // tells it apart from the background without drawing a heavy edge.
        elevation: 1,
        shadowColor: Color(0x14101828),
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
        backgroundColor: surfaceSunken,
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
        linearTrackColor: surfaceSunken,
        linearMinHeight: 3,
      ),
      switchTheme: SwitchThemeData(
        // A switch is off at the border grey and on at the *action* green: it
        // is a control, and every control that can be pressed wears the same
        // green as a button.
        thumbColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? Colors.white : null,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? brandStrong : null,
        ),
        trackOutlineColor: const WidgetStatePropertyAll(borderStrong),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? brandStrong : null,
        ),
        checkColor: const WidgetStatePropertyAll(Colors.white),
        side: const BorderSide(color: borderStrong, width: 1.5),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(3)),
        ),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? brandStrong : null,
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? brandStrong
                : bubbleText,
          ),
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected) ? surface : null,
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
          backgroundColor: const WidgetStatePropertyAll(brandStrong),
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
          // A text button is the "link" of this design: the action green with
          // no fill, which is how every quiet action is drawn.
          foregroundColor: const WidgetStatePropertyAll(brandStrong),
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
        // The current surface is marked by a soft green pill behind it, and
        // its icon and label wear the action green.
        indicatorColor: brandSoft,
        selectedIconTheme: IconThemeData(color: brandStrong, size: 22),
        unselectedIconTheme: IconThemeData(color: secondaryText, size: 22),
        selectedLabelTextStyle: TextStyle(
          fontSize: fontSizeMeta,
          color: brandStrong,
        ),
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
        // No pill: the bar marks the current tab by tinting the icon and its
        // label, not by drawing a shape behind them.
        indicatorColor: Colors.transparent,
        elevation: 0,
        height: 56,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: fontSizeMeta,
            color: states.contains(WidgetState.selected)
                ? brandStrong
                : secondaryText,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            size: 22,
            color: states.contains(WidgetState.selected)
                ? brandStrong
                : secondaryText,
          ),
        ),
      ),
      dialogTheme: const DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        // A modal floats above everything, so it takes the scale's third step:
        // the page and any card stay visibly below it.
        elevation: 3,
        shadowColor: Color(0x14101828),
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
        hintStyle: TextStyle(fontSize: fontSizeInput, color: disabledText),
      ),
    );
  }
}
