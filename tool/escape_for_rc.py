r"""Spells a string as the C++ wide-literal escapes the Windows runner needs.

The runner is compiled with /WX, and a source file that carries a non-ASCII
byte is warning C4819 on a machine whose active code page is 936 -- which /WX
promotes to the hard error C2220. So everything the runner says has to be
written as \uXXXX escapes, and this is what writes them, rather than a person
counting code points.

Usage: python tool/escape_for_rc.py 竹叶局域网传输 "显示主窗口" ...
"""

import sys


def escape(text: str) -> str:
    pieces = []
    for character in text:
        if character == "\\":
            pieces.append("\\\\")
        elif character == '"':
            pieces.append('\\"')
        elif 0x20 <= ord(character) < 0x7F:
            pieces.append(character)
        else:
            pieces.append("\\u%04x" % ord(character))
    return 'L"' + "".join(pieces) + '"'


def main() -> None:
    for argument in sys.argv[1:]:
        print(escape(argument))


if __name__ == "__main__":
    main()
