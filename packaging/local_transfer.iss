; 竹叶局域网传输 —— Windows 安装包定义（Inno Setup）
;
; 同一份 build/windows/x64/runner/Release 有两种分发方式：绿色免安装 zip 由
; scripts/pack-windows-portable.ps1 产出，安装包由
; scripts/pack-windows-installer.ps1 调用本文件产出。两者的内容完全相同，
; 区别只在「怎么送到用户机器上」。
;
; 一律经由那个脚本调用 —— 它负责把下面几个 #define 传进来，ISCC 不会替你猜。
; 注意每行的写法是 `/D` + 名字 + `=值`：**开头的 `/D` 就是「定义变量」这个开关**，
; 名字本身叫 LTStage / LTVersion……，不带 D。漏了那个 D，ISCC 会把它当成不认识的开关：
; 往 stderr 写一行 `Unknown option:` 就直接以 1 退出，**本文件一个字都不会被解析**
; —— 它不会把 `{#LTVersion}` 悄悄展开成空串，但那条报错只说「这个选项不认识」，
; 不说「你少给了一个定义」，指不到病根上。
; 2026-10-12 第一次真正发版时本文件的这段注释把六个定义全写成了 `/LT…`（同样漏 D），
; 而 /LTDocs 那一行照抄了它。写错不要紧，别把错的当范本。
;   /DLTStage=<dir>         已经组装好的绿色目录（含 VC++ 运行库与使用说明）
;   /DLTName=LocalTransfer  英文名，用于安装目录与文件名
;   /DLTVersion=0.1.0       版本号（与 pubspec.yaml 一致，由脚本读出）
;   /DLTOut=<dir>           安装包输出目录
;   /DLTIcon=<file>         app_icon.ico 的绝对路径
;   /DLTDocs=<dir>          packaging 目录（取「安装说明.txt」）
;
; 需要 Inno Setup 6.3 或更高：下面的 ArchitecturesAllowed=x64compatible 是
; 6.3 引入的写法（6.2 及更早只认 x64）。
;
; ⚠️ 本文件必须存为 UTF-8 **带 BOM**。Inno Setup 6 对含非 ASCII 的 .iss 要求有 BOM，
;    没有 BOM 时中文会按系统 ANSI 代码页（本机是 936）解析 —— 简体中文恰好能被
;    936 吃掉一部分，于是它不报错，只是字符串悄悄变成乱码，最难查。
;    改这个文件之后请确认前三字节是 EF BB BF。
;
; ⚠️ 向导界面本身是英文的。Inno Setup 官方只随附 Default.isl，简体中文
;    （ChineseSimplified.isl）属于非官方翻译，本仓库没有引入它。所以下面的
;    界面文案分两类：**属于本产品的字符串**（产品名、快捷方式名、任务说明）是
;    中文，**属于向导框架的字符串**（按钮、每页正文）仍是英文。

[Setup]
; AppId 决定「这是同一个程序」的判定：升级安装与卸载项都按它匹配。
; 一旦发布就不能再改 —— 改了等于变成另一个程序，用户会看到两个「竹叶局域网传输」。
AppId={{6F1C0F1E-9C33-4E2B-8C6A-2B7D5A4E9F31}
AppName=竹叶局域网传输
AppVersion={#LTVersion}
AppPublisher=menghun3-cn
AppPublisherURL=https://github.com/menghun3-cn/zhu-ye-local-im
AppSupportURL=https://github.com/menghun3-cn/zhu-ye-local-im/issues
AppUpdatesURL=https://github.com/menghun3-cn/zhu-ye-local-im/releases

; 每用户安装：装到 %LOCALAPPDATA%\Programs，不需要管理员权限、不弹 UAC。
; 本程序只做局域网直连，不装驱动、不写系统目录、不注册服务，没有要管理员
; 权限的理由；要管理员权限只会让人在 UAC 面前犹豫一下然后放弃。
DefaultDirName={localappdata}\Programs\{#LTName}
DefaultGroupName=竹叶局域网传输
DisableProgramGroupPage=yes
PrivilegesRequired=lowest

OutputDir={#LTOut}
OutputBaseFilename={#LTName}-{#LTVersion}-windows-x64-setup
SetupIconFile={#LTIcon}
UninstallDisplayIcon={app}\local_transfer.exe
UninstallDisplayName=竹叶局域网传输 {#LTVersion}

Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
; Windows 10 1809 —— 与 packaging\使用说明.txt 里写的系统要求一致。
MinVersion=10.0.17763
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "创建桌面快捷方式"; GroupDescription: "附加任务："; Flags: unchecked

[Files]
; 整个绿色目录原样搬进去 —— 它是 scripts/pack-windows-portable.ps1 组装并验证过的
; 那一份（exe、flutter_windows.dll、三个 VC++ 运行库、data\），这里不再挑拣文件，
; 免得两个脚本对「包里该有什么」各有一套说法。
Source: "{#LTStage}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
; 安装版要补一份说明：绿色包那份「使用说明.txt」开头写着「不需要安装、不写注册表、
; 想删除就直接删掉整个文件夹」，对安装版是错的。两份都在包里，各自说自己那种装法。
Source: "{#LTDocs}\安装说明.txt"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{userprograms}\竹叶局域网传输"; Filename: "{app}\local_transfer.exe"
Name: "{userdesktop}\竹叶局域网传输"; Filename: "{app}\local_transfer.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\local_transfer.exe"; Description: "立即运行竹叶局域网传输"; Flags: nowait postinstall skipifsilent
