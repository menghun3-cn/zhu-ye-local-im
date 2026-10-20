import 'package:flutter/material.dart';

/// The colours of one theme — the light page the design was drawn on, or the
/// dark page the same roles move to.
///
/// A [ThemeExtension] rather than a bag of constants, because a colour is now
/// a fact about *which theme the reader is in*: the panel is a white board on
/// the light page and a near-black one on the dark page, and a widget naming a
/// constant would be pinned to one of them. Riding on the [ThemeData] means the
/// lookup every widget already performs — `Theme.of(context)` — is what answers
/// "which white is this".
///
/// Two palettes are defined, [light] and [dark], and nothing above this line
/// changes between them: a widget asks for *the panel colour*, never for white.
/// That is the whole of what makes dark mode a palette rather than a second
/// paint job — there is no branch anywhere that says "if dark, then…".
///
/// Sizes, radii and type are deliberately absent. They do not move between
/// themes, and keeping them on [WeChat] is what lets this class be read as
/// "the colours" and nothing else.
@immutable
class WeChatColors extends ThemeExtension<WeChatColors> {
  /// Names every colour one theme uses.
  const WeChatColors({
    required this.brightness,
    required this.brand,
    required this.brandStrong,
    required this.brandSoft,
    required this.brandLine,
    required this.onBrand,
    required this.onBrandStrong,
    required this.onDanger,
    required this.bubbleOut,
    required this.bubbleOutText,
    required this.bubbleIn,
    required this.surface,
    required this.surfaceSunken,
    required this.bubbleText,
    required this.pageBackground,
    required this.conversationBackground,
    required this.sidebarBackground,
    required this.divider,
    required this.borderStrong,
    required this.secondaryText,
    required this.disabledText,
    required this.listSelected,
    required this.listHover,
    required this.toolbarBackground,
    required this.danger,
    required this.errorContainer,
    required this.shadow,
    required this.scrim,
    required this.inverseSurface,
    required this.onInverseSurface,
    required this.inversePrimary,
  });

  /// Whether these colours belong on a light page or a dark one.
  ///
  /// Carried here rather than passed beside the palette, because the palette
  /// and the brightness are one decision: a dark palette on a light page is not
  /// a configuration, it is a mistake, and two parameters would let one be
  /// changed without the other.
  final Brightness brightness;

  /// 品牌绿 —— 标识与填充：进度条的推进、选中态的点、图表里的强调。
  ///
  /// 它**不做白字按钮的底**：白字压在这个绿上只有 2.4:1，够不上 AA。
  /// 要「一块绿底 + 可读的字」时，用 [brandStrong]（浅色下白字 5.2:1）。
  final Color brand;

  /// 可点击的品牌色：实心按钮的底、链接文字、选中态的图标与标签。
  ///
  /// 与 [brand] 是两个角色 —— [brand] 说的是「我们是谁」，[brandStrong]
  /// 说的是「可以点这里」。深色下两者取同一个亮绿，因为「亮到能读」这条线
  /// 自己就把它抬到了能当按钮的亮度。
  final Color brandStrong;

  /// 品牌浅底：选中行的底、输入框聚焦的光晕、品牌标签的底。
  final Color brandSoft;

  /// 品牌浅底上的描边。
  final Color brandLine;

  /// 压在 [brand] 那档绿上的深字。
  final Color onBrand;

  /// 压在 [brandStrong] 那档绿上的字：实心按钮的标签、勾选的对号。
  ///
  /// 浅色下是白（绿够深），深色下是近黑（绿够亮）—— 同一个角色，两种纸。
  final Color onBrandStrong;

  /// 压在 [danger] 那档红上的字。
  final Color onDanger;

  /// 发出的消息气泡底色。
  ///
  /// 浅绿 —— 一整屏 `#07C160` 会刺眼。与品牌绿解耦：[brand] 是按钮与标识，
  /// 气泡是一大块面积，两者要的不是同一个绿。
  final Color bubbleOut;

  /// 发出气泡里的字色。浅色下近黑带绿，压在浅绿上 11.4:1。
  final Color bubbleOutText;

  /// 收到的消息气泡底色。
  ///
  /// 两个主题里做的是同一件事——**用填充把气泡从板子上分出来**——只是方向相反。
  /// 浅色下它比白板低一档（`#F0F1F4`，即 [surfaceSunken] 那一档），深色下它比
  /// 板子**亮**一档。发丝线（[divider]）两处都留着，但它现在是补一道边，而不是
  /// 唯一让人看出「这里有个气泡」的东西。
  ///
  /// 浅色下它一度是纯白加一圈发丝线，理由是「灰读起来像不可用」。那句话针对的是
  /// **旧调色板里那档中灰**：一档几乎看不出来的浅灰只会读成浅底，不会读成禁用；
  /// 而白上白的气泡在真实窗口里读成了一个描边空框。见
  /// `2026-10-10-a-received-bubble-is-a-soft-grey.md`。
  ///
  /// 注意这个填充会**圈住别的填充**：气泡里的进度条轨道不能再取 [surfaceSunken]，
  /// 那正好是这个颜色。铺轨道的地方因此取 [divider]——见 `conversation_view.dart`。
  final Color bubbleIn;

  /// 卡片、对话框、输入框、附件托盘、分段控件，以及 Material 各种 `surface`
  /// 槽位的底色 —— 一句话说，一块面板。
  final Color surface;

  /// 比 [surface] 低一层的底：悬停的行、凹陷的分段控件槽、进度条的轨道。
  ///
  /// 深色下它仍然「低一层」，只是方向相反：亮一档，而不是暗一档。
  final Color surfaceSunken;

  /// 正文/气泡里的字色。浅色下是暖调近黑，不是纯黑 —— 纯黑在浅绿上发脏。
  final Color bubbleText;

  /// 设备/传输/剪贴板/设置四个页面的底色，也是 `scaffoldBackgroundColor`。
  final Color pageBackground;

  /// 会话历史区的底色：一块板，消息气泡浮在上面。
  ///
  /// 浅色下它是白（比页面亮），深色下它取 [surface]（也比页面亮）。
  /// 两种主题里它都是「比页面抬起来一层的那块板」，变的只是纸。
  final Color conversationBackground;

  /// 左侧会话列表、导航栏、工具条的底色。夹在 [conversationBackground] 与
  /// [pageBackground] 之间，两侧靠这层微差分开。
  final Color sidebarBackground;

  /// 分隔线。一条几乎看不见的发丝线。
  final Color divider;

  /// 比 [divider] 重一档的边界：输入框与幽灵按钮的描边。
  final Color borderStrong;

  /// 次要文字：最后一句话、时间戳、提示语、字段名。
  final Color secondaryText;

  /// 比 [secondaryText] 更淡的一层：禁用态、占位符。
  final Color disabledText;

  /// 会话列表里选中那一行的底色 —— 品牌浅底，而不是一档灰。
  final Color listSelected;

  /// 会话列表里鼠标悬停那一行的底色，也是控件被按下时的浅灰。
  final Color listHover;

  /// 输入区工具栏的底色。
  final Color toolbarBackground;

  /// 语义红：错误、未读角标、危险操作。
  ///
  /// 它替代了从前只叫「角标」的 `badge` —— 那一个名字把「未读几条」和
  /// 「出错了」说成了同一件事，而它们是两件事，只是碰巧都发红。
  final Color danger;

  /// 出错时那一层浅红，用作错误色的容器。
  final Color errorContainer;

  /// 卡片与对话框投下的影子。浅色下带一点环境蓝，深色下是真正的黑。
  final Color shadow;

  /// 模态挡板。深色下更重一档，把底下的页面压得更远。
  final Color scrim;

  /// 「反色」面 —— Material 用它当 SnackBar 的底。
  ///
  /// 它存在的意思是**与页面相反**：浅色页面上的提示是一条深条，深色页面上
  /// 就是一条浅条。取相反而不是取某一档灰，是为了让提示无论在哪张纸上都读得
  /// 出来。
  final Color inverseSurface;

  /// [inverseSurface] 上的字。
  final Color onInverseSurface;

  /// [inverseSurface] 上的品牌色。
  final Color inversePrimary;

  /// The palette the design was drawn in.
  static const WeChatColors light = WeChatColors(
    brightness: Brightness.light,
    brand: Color(0xFF07C160),
    brandStrong: Color(0xFF0A7E43),
    brandSoft: Color(0xFFE8F8EF),
    brandLine: Color(0xFFBFE9D2),
    onBrand: Color(0xFF06291A),
    onBrandStrong: Colors.white,
    onDanger: Colors.white,
    bubbleOut: Color(0xFFA9EA7C),
    bubbleOutText: Color(0xFF17240F),
    bubbleIn: Color(0xFFF0F1F4),
    surface: Color(0xFFFFFFFF),
    surfaceSunken: Color(0xFFF0F1F4),
    bubbleText: Color(0xFF171A21),
    pageBackground: Color(0xFFF4F5F7),
    conversationBackground: Color(0xFFFFFFFF),
    sidebarBackground: Color(0xFFFBFBFD),
    divider: Color(0xFFE7E9EE),
    borderStrong: Color(0xFFD5D9E0),
    secondaryText: Color(0xFF5B6270),
    disabledText: Color(0xFF8B929E),
    listSelected: Color(0xFFE8F8EF),
    listHover: Color(0xFFF0F1F4),
    toolbarBackground: Color(0xFFFBFBFD),
    danger: Color(0xFFC33B3B),
    errorContainer: Color(0xFFFDECEC),
    shadow: Color(0x14101828),
    scrim: Color(0x80000000),
    inverseSurface: Color(0xFF2E2E2E),
    onInverseSurface: Colors.white,
    inversePrimary: Color(0xFFA9EA7C),
  );

  /// The same roles, on a dark page.
  ///
  /// Not an inversion of [light]. A palette built by flipping each value would
  /// put the brand green on near-black at a luminance that vibrates, and would
  /// leave the raised panel *darker* than the page it is raised above. What is
  /// kept is the *relationships* — the panel lighter than the page, the sidebar
  /// between the two, a received bubble lighter than the board it sits on — and
  /// the green is lifted until it holds the same contrast against the new paper.
  ///
  /// The values are the ones the design system already carries for
  /// `[data-theme=dark]`, so a screenshot of the app and a screenshot of the
  /// draft are still the same design.
  static const WeChatColors dark = WeChatColors(
    brightness: Brightness.dark,
    brand: Color(0xFF12D06C),
    brandStrong: Color(0xFF12D06C),
    brandSoft: Color(0xFF10301F),
    brandLine: Color(0xFF1C4A31),
    onBrand: Color(0xFF04220F),
    onBrandStrong: Color(0xFF04220F),
    onDanger: Color(0xFF2A0E0E),
    bubbleOut: Color(0xFF8FD46F),
    bubbleOutText: Color(0xFF0E1A08),
    bubbleIn: Color(0xFF21262F),
    surface: Color(0xFF15181E),
    surfaceSunken: Color(0xFF20252E),
    bubbleText: Color(0xFFEDEFF3),
    pageBackground: Color(0xFF0E1014),
    conversationBackground: Color(0xFF15181E),
    sidebarBackground: Color(0xFF12151A),
    divider: Color(0xFF262C36),
    borderStrong: Color(0xFF333B47),
    secondaryText: Color(0xFFA6AEBB),
    disabledText: Color(0xFF7B8493),
    listSelected: Color(0xFF10301F),
    listHover: Color(0xFF20252E),
    toolbarBackground: Color(0xFF12151A),
    danger: Color(0xFFF0736F),
    errorContainer: Color(0xFF3A1E1E),
    shadow: Color(0x66000000),
    scrim: Color(0x8C000000),
    inverseSurface: Color(0xFFE3E6EC),
    onInverseSurface: Color(0xFF171A21),
    inversePrimary: Color(0xFF8FD46F),
  );

  /// The palette of the theme [context] is reading.
  ///
  /// Falls back to [light] rather than throwing. A widget that reached here
  /// outside the application's own theme — a test that pumped a bare
  /// `MaterialApp`, a dialog opened over one — has not said which theme it
  /// means, and the light page is a better answer than a crash in a paint
  /// callback. The application itself always installs one of the two, so this
  /// fallback is never what a running window shows.
  static WeChatColors of(BuildContext context) =>
      Theme.of(context).extension<WeChatColors>() ?? light;

  /// A palette with one colour changed.
  ///
  /// Not implemented, and deliberately: this design has exactly two palettes
  /// and no third is derived from them at runtime. A `copyWith` that existed
  /// would be a way to build a palette nobody designed, one colour at a time,
  /// which is the opposite of what this file is for.
  @override
  WeChatColors copyWith() => this;

  /// Interpolates between two palettes, for the moment a theme change is
  /// animated.
  ///
  /// Every slot is lerped, so a window switching between light and dark fades
  /// through the colours in between rather than snapping. The brightness flips
  /// at the halfway point: it is not a value that can be half of either.
  @override
  WeChatColors lerp(covariant ThemeExtension<WeChatColors>? other, double t) {
    if (other is! WeChatColors) return this;
    return WeChatColors(
      brightness: t < 0.5 ? brightness : other.brightness,
      brand: Color.lerp(brand, other.brand, t)!,
      brandStrong: Color.lerp(brandStrong, other.brandStrong, t)!,
      brandSoft: Color.lerp(brandSoft, other.brandSoft, t)!,
      brandLine: Color.lerp(brandLine, other.brandLine, t)!,
      onBrand: Color.lerp(onBrand, other.onBrand, t)!,
      onBrandStrong: Color.lerp(onBrandStrong, other.onBrandStrong, t)!,
      onDanger: Color.lerp(onDanger, other.onDanger, t)!,
      bubbleOut: Color.lerp(bubbleOut, other.bubbleOut, t)!,
      bubbleOutText: Color.lerp(bubbleOutText, other.bubbleOutText, t)!,
      bubbleIn: Color.lerp(bubbleIn, other.bubbleIn, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceSunken: Color.lerp(surfaceSunken, other.surfaceSunken, t)!,
      bubbleText: Color.lerp(bubbleText, other.bubbleText, t)!,
      pageBackground: Color.lerp(pageBackground, other.pageBackground, t)!,
      conversationBackground: Color.lerp(
        conversationBackground,
        other.conversationBackground,
        t,
      )!,
      sidebarBackground: Color.lerp(
        sidebarBackground,
        other.sidebarBackground,
        t,
      )!,
      divider: Color.lerp(divider, other.divider, t)!,
      borderStrong: Color.lerp(borderStrong, other.borderStrong, t)!,
      secondaryText: Color.lerp(secondaryText, other.secondaryText, t)!,
      disabledText: Color.lerp(disabledText, other.disabledText, t)!,
      listSelected: Color.lerp(listSelected, other.listSelected, t)!,
      listHover: Color.lerp(listHover, other.listHover, t)!,
      toolbarBackground: Color.lerp(
        toolbarBackground,
        other.toolbarBackground,
        t,
      )!,
      danger: Color.lerp(danger, other.danger, t)!,
      errorContainer: Color.lerp(errorContainer, other.errorContainer, t)!,
      shadow: Color.lerp(shadow, other.shadow, t)!,
      scrim: Color.lerp(scrim, other.scrim, t)!,
      inverseSurface: Color.lerp(inverseSurface, other.inverseSurface, t)!,
      onInverseSurface: Color.lerp(
        onInverseSurface,
        other.onInverseSurface,
        t,
      )!,
      inversePrimary: Color.lerp(inversePrimary, other.inversePrimary, t)!,
    );
  }
}

/// The look of 竹叶, as numbers.
///
/// Every size and gap the surfaces use is named here, so that "match the
/// design" is a thing the code can be held to rather than an impression. The
/// *colours* are on [WeChatColors], which each theme carries its own copy of —
/// what is left here is the half of the design that does not move when the
/// lights go out.
///
/// The palette is Material 3's skeleton with one accent colour: two greens
/// ([WeChatColors.brand] to identify, [WeChatColors.brandStrong] to act), a
/// warm near-black for text, hairline greys for structure. It is no longer a
/// token-for-token copy of the WeChat desktop client — the class keeps its name
/// because the conversation surfaces still borrow WeChat's shape, but a value
/// here is now chosen for this design.
///
/// Nothing in this file depends on `MaterialApp` beyond the [ThemeData] it
/// builds, so the tokens can be asserted in a test without pumping a widget.
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

  /// 输入框附件托盘里，一张已暂存图片的正方形缩略图的边长。
  ///
  /// **正方形**是刻意的：会话里的图片要保持原图的构图（见 [imageMaxSide] 的
  /// 注释），而托盘是「即将发出的东西一览」——一格一格对齐的预览比每格各自
  /// 的构图更重要，微信的托盘也正是方格。构图在这里让位给可扫读。
  static const double attachmentThumbSide = 64;

  /// 附件托盘缩略图的圆角。比会话里的 [imageRadius] 小一档：它是一块还没
  /// 发出去的预览，不是一条已经说出口的消息。
  static const double attachmentThumbRadius = 4;

  /// 附件托盘缩略图右上角那个移除角标（× 所在的圆）的直径。
  static const double attachmentThumbBadge = 18;

  /// 气泡到头像的间距。
  static const double bubbleAvatarGap = 10;

  /// 两条消息之间的纵向间距。
  static const double messageGap = 16;

  /// 气泡最大宽度占**聊天区域**宽度的比例。
  ///
  /// 一个比例而不是固定像素：微信的窄屏气泡和宽屏气泡都不会撑满，
  /// 而固定 460 像素在 2560 宽的窗口里显得很短，在 600 宽的窗口里又过长。
  ///
  /// 比例乘的是**聊天区域**（整个会话面板）的宽度，不是文字剩下的地方：
  /// 后者已经扣掉了头像，气泡按它算就会比微信的窄一截。
  static const double bubbleMaxWidthFactor = 0.6;

  /// 气泡的最小宽度。
  ///
  /// 一条只有一个字的消息，气泡也不该缩成一个小点。48 像素里去掉左右各 12
  /// 的内边距，还剩 24 像素——刚好放得下一个字，也刚好是一个气泡该有的
  /// 最小体量。
  static const double bubbleMinWidth = 48;

  /// 文件传输气泡宽度随内容自适应时的**下限**。
  ///
  /// 一个名字只有三个字符的文件，气泡也不能窄到进度条读不出来——这个下限
  /// 就是「还能看清一条 3 像素进度线和『0 B / 4.0 MB』」的最小宽度。
  static const double transferBubbleMinWidth = 160;

  /// 文件传输气泡宽度自适应时的**上限**。
  ///
  /// 名字再长，气泡也不跟着长到通栏：到这条线就**折行**，最多
  /// [transferNameMaxLines] 行，再多才用省略号截断，完整名字放在气泡的
  /// 提示里。微信的文件卡片也是这个手感——宽得有限，从不撑满；而名字
  /// 宁可多占一行，也不要只剩一个 `…`：文件名被截断掉的往往正是它是什么
  /// （扩展名、版本、平台），而那几个字符全在末尾。
  static const double transferBubbleMaxWidth = 280;

  /// 气泡里一个文件名最多占几行。
  ///
  /// 三行足够放下 `local-transfer-1.0.0-windows-x64-portable.zip` 这类真实
  /// 的名字（上限宽去掉图标，一行约 18 个半角字符）。再长的只剩病态输入，
  /// 那种名字本来也该靠提示读全文——所以行数有上限，而不是让气泡无限长高。
  static const int transferNameMaxLines = 3;

  /// 气泡里那条进度**轨道**的不透明度：轨道 = 气泡自己的墨色 × 这个值。
  ///
  /// 轨道要同时落在四种底色上（两个主题 × 收/发两种气泡填充），没有任何一个固定
  /// 的调色板灰同时成立——浅色接收气泡本身就是 `surfaceSunken`，深色下它又和
  /// `bubbleIn` 只差一步。从墨色派生，轨道与气泡之间就恒是一个固定距离。
  static const double progressTrackAlpha = 0.16;

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

  // ---------------------------------------------------------------- 导航轨

  /// 导航轨的宽度。
  ///
  /// 84 是稿子 `.rail` 的宽度（`design-preview/styles.css`）。Material 3 的
  /// 导航轨默认 80，而这一档要让「图标 + 文字」那一块在两侧 8 像素的留白之外
  /// 还站得开 —— 稿子的数就是照着这个块算出来的，所以照抄，不去凑默认值。
  static const double railWidth = 84;

  /// 导航轨左右两侧的留白（稿子 `.rail` 的 `padding: 16px 8px`）。
  static const double railHPadding = 8;

  /// 导航轨上下的留白。上下同一个数：轨道是一条通高的栏，两头一样宽。
  static const double railVPadding = 16;

  /// 导航项之间的间距（稿子 `.rail` 的 `gap: 8px`）。
  static const double railItemGap = 8;

  /// 品牌位那块方形的边长（稿子 `.rail__brand` 的 40 × 40）。
  static const double railBrandBox = 40;

  /// 品牌位里那枚标记的边长（稿子那枚 SVG 的 26 × 26）。
  static const double railBrandMark = 26;

  /// 品牌位与第一个导航项之间的距离（稿子 `.rail__brand` 的 margin-bottom）。
  ///
  /// 与 [railItemGap] 分开数：稿子里这一段是 margin（12）之外**再**加一个
  /// flex gap（8），品牌位因此不是「又一个导航项」。这里照加：品牌位自己带
  /// 12，列还会给它补 8。
  static const double railBrandGap = 12;

  /// 导航项的圆角。
  ///
  /// 10 是稿子的 `--r-md`（导航项、头像、列表行共用的一档）。与
  /// [avatarRadius] 取值相同而不共用：一个是头像的方，一个是能点的块，
  /// 名字分开，改一个就不会顺手带走另一个。
  static const double railItemRadius = 10;

  /// 导航项上下各自的内边距（稿子 `.rail__item` 的 `padding: 8px 0`）。
  ///
  /// 没有左右：导航项是满宽的，左右两边由 [railHPadding] 一次给足。
  static const double railItemPadding = 8;

  /// 导航项里图标与文字之间的距离（稿子 `.rail__item` 的 `gap: 5px`）。
  static const double railIconLabelGap = 5;

  /// 导航项的图标边长。
  ///
  /// 20 是稿子 `.rail__item svg` 的尺寸，也与全站 `iconTheme` 同号。Material
  /// 的导航轨自己会把图标放大一档，而导航项这一块由我们自己画，所以尺寸取稿子
  /// 那个数，不跟随任何组件的默认值。
  static const double railIconSize = 20;

  /// 导航项标签的字号。
  ///
  /// 11 是稿子 `.rail__item` 的字号，比 [fontSizeMeta] 还小一档：它不在字阶
  /// 上，是稿子单独给轨道写下的数 —— 导航项只有图标与文字两行，字号大一档，
  /// 这一块就高出稿子量好的那一格。行高不在这里定：标签继承应用正文的行高
  /// [lineHeightBody]，稿子那一页的行高是它自己的事。
  static const double railLabelSize = 11;

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

  // ------------------------------------------------------- 标准控件尺寸

  /// 一个**对话框动作**按钮的最小高度。
  ///
  /// 36 是这一档按钮的标准高度（桌面客户端、系统对话框都是这个量级）：
  /// 从前按钮的 `minimumSize` 是 `Size.zero`、`visualDensity` 又压到
  /// `compact`，一个「连接」按出来只有二十来像素高，比旁边的输入框还矮，
  /// 读起来像一个没做完的控件。这一档是给**对话框底部的动作**用的 ——
  /// 它不与列表行争高度，所以可以取标准尺寸。
  static const double buttonHeight = 36;

  /// 一个标准按钮的左右内边距。
  ///
  /// 比列表行里的行内动作宽：那个是「贴着文字的一个词」，这个是「一个按钮」，
  /// 四周要有呼吸。横向 16 让两个汉字的标签（「连接」「取消」）读起来不憋。
  static const double buttonHPadding = 16;

  /// 输入框的最小高度。
  ///
  /// 44 是触控/桌面两用的输入行标准高度，也是微信单行输入框的量级：
  /// 从前把它压到 36，再减去 `isDense` 的收缩，光标几乎贴着上下两条边。
  /// 多出来的高度由内边距给，不由字号给 —— 字还是 [fontSizeInput]。
  static const double fieldHeight = 44;

  /// 输入框的左右内边距。
  ///
  /// 12 让光标离边框有一指宽；从前是 10，且没有边框衬托，几乎看不出来是在
  /// 一个框里打字。
  static const double fieldHPadding = 12;

  /// 输入框的上下内边距。
  ///
  /// 与 [fieldHPadding] 分开命名：横竖两个方向在这一档里不是同一个数 ——
  /// 横向是「离边框多远」，纵向是「离上下沿多远」，把单行高度撑到
  /// [fieldHeight]。
  static const double fieldVPadding = 10;

  /// 会话输入行上两个**按钮**的高度：附件按钮与发送按钮。
  ///
  /// 34 是设计稿 `.btn` 的 `min-height`（`.btn--icon` 同宽，是一个正方形）。
  /// 输入框**不**取这个数：它取 [fieldHeight]（44，设计稿 `.composer__box`
  /// 的 `min-height`），三个控件在行内**底端对齐**（设计稿
  /// `align-items: flex-end`）——按钮比框矮一档是设计稿明确的布局，不是参差。
  ///
  /// 从前三个控件共用同一个 40，理由写的是「一行控件不同高会看出参差」；
  /// 设计稿给的不是这个答案，所以这里改成按钮自己的高度，输入框回到
  /// [fieldHeight]。
  static const double composerControl = 34;

  /// 表情面板里一个表情格子的边长。
  ///
  /// 32 让一行放下八个格子（含间距）后仍是微信桌面端面板的窄度 —— 面板宽度
  /// 就按 `8 × 32 + 7 × 2` 计算，不另起一个数。
  static const double emojiTileSide = 32;

  /// 表情面板里一个表情的字号。比工具栏字形大一档，让格子里的脸一眼可辨。
  static const double emojiTileFontSize = 22;

  /// 会话气泡里一个表情的字号。
  ///
  /// 比普通正文大三倍半，让单发的一个表情像微信里那样读作一张「贴纸」而不是
  /// 一行文字。
  static const double emojiBubbleFontSize = 48;

  // ---------------------------------------------------------------- 主题

  /// The [ThemeData] the app runs on, for one [WeChatColors] palette.
  ///
  /// Built from the palette rather than seeded, because a seeded scheme invents
  /// its own green and the whole point here is a *specific* green. The text
  /// theme is set in logical pixels with explicit line heights so that a bubble
  /// measures the same as the reference.
  ///
  /// Every colour slot Material might reach for is named, including the ones no
  /// page mentions by hand: a slot left at its default is a slot that renders
  /// Material's lavender, and a single lavender chip in a WeChat-grey list is
  /// more jarring than a whole page of the wrong theme.
  ///
  /// The one thing the palette does *not* carry is the choice between
  /// Material's two constructors — `ColorScheme.light` and `ColorScheme.dark`
  /// differ in the brightness they stamp and in the defaults for the handful of
  /// slots nothing here names. Every slot this design can render is given a
  /// value below, so the choice decides only the unused defaults.
  static ThemeData theme(WeChatColors colors) {
    final dark = colors.brightness == Brightness.dark;
    final scheme = (dark ? ColorScheme.dark : ColorScheme.light)(
      // The action colour is the one a filled button carries white-on-green
      // from — never the identifying green, which white sits on at 2.4:1.
      primary: colors.brandStrong,
      onPrimary: colors.onBrandStrong,
      primaryContainer: colors.brandSoft,
      onPrimaryContainer: colors.onBrand,
      // The identifying green, for the quieter tonal slots.
      secondary: colors.brand,
      onSecondary: colors.onBrand,
      secondaryContainer: colors.listHover,
      onSecondaryContainer: colors.bubbleText,
      tertiary: colors.brand,
      onTertiary: colors.onBrand,
      tertiaryContainer: colors.listHover,
      onTertiaryContainer: colors.bubbleText,
      error: colors.danger,
      onError: colors.onDanger,
      errorContainer: colors.errorContainer,
      onErrorContainer: colors.danger,
      surface: colors.surface,
      onSurface: colors.bubbleText,
      surfaceDim: colors.pageBackground,
      surfaceBright: colors.surface,
      surfaceContainerLowest: colors.surface,
      surfaceContainerLow: colors.surface,
      surfaceContainer: colors.surface,
      surfaceContainerHigh: colors.sidebarBackground,
      surfaceContainerHighest: colors.listHover,
      onSurfaceVariant: colors.secondaryText,
      outline: colors.divider,
      outlineVariant: colors.divider,
      shadow: colors.shadow,
      scrim: colors.scrim,
      inverseSurface: colors.inverseSurface,
      onInverseSurface: colors.onInverseSurface,
      inversePrimary: colors.inversePrimary,
      // Transparent, so nothing Material draws is tinted towards the seed:
      // these surfaces are flat greys and whites, and the elevation tint
      // Material 3 applies by default is the one thing that would make a flat
      // card look like it came from a different application.
      surfaceTint: Colors.transparent,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: colors.pageBackground,
      dividerColor: colors.divider,
      // What makes the palette reachable: without this the [WeChatColors] above
      // would be built and then dropped, and every `WeChatColors.of` below the
      // theme would fall back to the light page.
      extensions: [colors],
      // 中文优先：Windows 上 Material 默认的 Roboto 不含汉字，会回退到
      // 系统字体；显式点名雅黑能让中英混排的基线一致。
      fontFamily: 'Microsoft YaHei UI',
      fontFamilyFallback: const ['Microsoft YaHei', 'PingFang SC', 'Roboto'],
      // Icons on a quiet surface are grey unless a component says otherwise;
      // an icon that inherited `onSurface` would be near-black and shout.
      iconTheme: IconThemeData(color: colors.secondaryText, size: 20),
      appBarTheme: AppBarTheme(
        backgroundColor: colors.sidebarBackground,
        foregroundColor: colors.bubbleText,
        elevation: 0,
        centerTitle: true,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        color: colors.surface,
        surfaceTintColor: Colors.transparent,
        // One whisper of a shadow rather than none: a card that sits flush on
        // the page reads as a table row, and the scale's first step is what
        // tells it apart from the background without drawing a heavy edge.
        elevation: 1,
        shadowColor: colors.shadow,
        // Flush, because the pages put their own gaps between cards: a
        // built-in margin on top of those would make every gap depend on
        // whether the page remembered to add one.
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(cardRadius)),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: colors.divider,
        thickness: 1,
        space: 1,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: colors.surfaceSunken,
        surfaceTintColor: Colors.transparent,
        side: BorderSide(color: colors.divider),
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        labelStyle: TextStyle(fontSize: fontSizeMeta, color: colors.bubbleText),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(controlRadius)),
        ),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: colors.secondaryText,
        textColor: colors.bubbleText,
        subtitleTextStyle: TextStyle(
          fontSize: fontSizePreview,
          color: colors.secondaryText,
        ),
        horizontalTitleGap: 12,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: colors.brand,
        linearTrackColor: colors.surfaceSunken,
        linearMinHeight: 3,
      ),
      switchTheme: SwitchThemeData(
        // A switch is off at the border grey and on at the *action* green: it
        // is a control, and every control that can be pressed wears the same
        // green as a button. The thumb stays white on top of it in both
        // themes, which is what the design's own switch does and what every
        // desktop platform's does.
        thumbColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? Colors.white : null,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? colors.brandStrong : null,
        ),
        trackOutlineColor: WidgetStatePropertyAll(colors.borderStrong),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? colors.brandStrong : null,
        ),
        // The tick is *on* the green, so it takes the ink that goes on green —
        // white on the deep light-mode green, near-black on the bright dark
        // one. A white tick on `#12D06C` would be a tick nobody can see.
        checkColor: WidgetStatePropertyAll(colors.onBrandStrong),
        side: BorderSide(color: colors.borderStrong, width: 1.5),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(3)),
        ),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? colors.brandStrong : null,
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? colors.brandStrong
                : colors.bubbleText,
          ),
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) =>
                states.contains(WidgetState.selected) ? colors.surface : null,
          ),
          side: WidgetStatePropertyAll(BorderSide(color: colors.divider)),
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
          backgroundColor: WidgetStatePropertyAll(colors.brandStrong),
          foregroundColor: WidgetStatePropertyAll(colors.onBrandStrong),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          elevation: const WidgetStatePropertyAll(0),
          shape: const WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(controlRadius)),
            ),
          ),
          // Standard size, not a shrunken one. These are the buttons at the
          // foot of a dialog — Connect, Send, Save — and the thing they have
          // to match is the field above them, not a list row. The old
          // `Size.zero` + `compact` made a filled button about twenty pixels
          // tall, which read as a control somebody forgot to finish.
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: buttonHPadding),
          ),
          minimumSize: const WidgetStatePropertyAll(Size(0, buttonHeight)),
          tapTargetSize: MaterialTapTargetSize.padded,
          textStyle: const WidgetStatePropertyAll(
            TextStyle(fontSize: fontSizeLabel),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          // A text button is the "link" of this design: the action green with
          // no fill, which is how every quiet action is drawn.
          foregroundColor: WidgetStatePropertyAll(colors.brandStrong),
          shape: const WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(controlRadius)),
            ),
          ),
          // The same standard height as a filled one, because the two sit
          // shoulder to shoulder at the foot of a dialog (Cancel beside
          // Connect) and a row of buttons at two heights looks broken. An
          // action that genuinely belongs *inside* a line — the row action in
          // the conversation list, a bubble's own answer — overrides every one
          // of these metrics at its own call site rather than relying on this
          // being small; see `_RowAction` and `_BubbleAction`.
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: buttonHPadding),
          ),
          minimumSize: const WidgetStatePropertyAll(Size(0, buttonHeight)),
          tapTargetSize: MaterialTapTargetSize.padded,
          textStyle: const WidgetStatePropertyAll(
            TextStyle(fontSize: fontSizeLabel),
          ),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: colors.toolbarBackground,
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
                ? colors.brandStrong
                : colors.secondaryText,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            size: 22,
            color: states.contains(WidgetState.selected)
                ? colors.brandStrong
                : colors.secondaryText,
          ),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
        // A modal floats above everything, so it takes the scale's third step:
        // the page and any card stay visibly below it.
        elevation: 3,
        shadowColor: colors.shadow,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(cardRadius)),
        ),
      ),
      textTheme: TextTheme(
        bodyMedium: const TextStyle(
          fontSize: fontSizeBody,
          height: lineHeightBody,
        ),
        bodySmall: TextStyle(
          fontSize: fontSizeMeta,
          color: colors.secondaryText,
        ),
        titleLarge: TextStyle(
          fontSize: fontSizeTitle,
          color: colors.bubbleText,
          height: lineHeightBody,
        ),
        titleMedium: TextStyle(
          fontSize: fontSizeTitle,
          color: colors.bubbleText,
        ),
        // Content titles — a file's name, a peer's name on a card. The quiet
        // group heading above a section is a *different* thing and asks for
        // `secondaryText` explicitly, which is why it is not folded in here.
        titleSmall: TextStyle(
          fontSize: fontSizeLabel,
          color: colors.bubbleText,
        ),
        labelSmall: TextStyle(
          fontSize: fontSizeMeta,
          color: colors.secondaryText,
        ),
      ),
      // Every field on every surface: a real outline, a standard height, and a
      // hit of brand when it is being edited.
      //
      // This used to be `InputBorder.none` with `isDense: true`, and the two
      // together were the bug a user reported — a field with no line around it
      // on a panel of nearly the same fill reads as a labelled blank rather
      // than as somewhere to type. The one field that genuinely wants no
      // outline is the conversation composer's, because *it* sits inside a
      // drawn box of its own; that field overrides this at its own call site.
      //
      // The focused state is a hairline of brand plus a soft ring of it,
      // rather than the ring alone: on a light panel a one-pixel green line is
      // about the same luminance as the grey it replaces, so the ring is what
      // actually says "this one is live".
      inputDecorationTheme: InputDecorationTheme(
        filled: false,
        isDense: false,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: fieldHPadding,
          vertical: fieldVPadding,
        ),
        constraints: const BoxConstraints(minHeight: fieldHeight),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(controlRadius),
          borderSide: BorderSide(color: colors.borderStrong),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(controlRadius),
          borderSide: BorderSide(color: colors.borderStrong),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(controlRadius),
          borderSide: BorderSide(color: colors.brandStrong, width: 2),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(controlRadius),
          borderSide: BorderSide(color: colors.danger, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(controlRadius),
          borderSide: BorderSide(color: colors.danger),
        ),
        labelStyle: TextStyle(
          fontSize: fontSizeInput,
          color: colors.secondaryText,
        ),
        floatingLabelStyle: TextStyle(
          fontSize: fontSizeInput,
          color: colors.brandStrong,
        ),
        helperStyle: TextStyle(
          fontSize: fontSizeMeta,
          color: colors.secondaryText,
        ),
        hintStyle: TextStyle(
          fontSize: fontSizeInput,
          color: colors.disabledText,
        ),
      ),
    );
  }
}
