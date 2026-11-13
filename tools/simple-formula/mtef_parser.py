from __future__ import annotations

from dataclasses import dataclass, field


END, LINE, CHAR, TMPL, PILE, MATRIX, EMBELL = range(7)
FONT_STYLE_DEF, SIZE, FULL, SUB, SUB2, SYM, SUBSYM = range(8, 15)
COLOR, COLOR_DEF, FONT_DEF, EQN_PREFS, ENCODING_DEF, FUTURE = range(15, 21)

MTEF_NUDGE = 0x08
CHAR_8, CHAR_16, NO_MTCODE = 0x04, 0x10, 0x20
LINE_NULL, LP_RULER, LINE_LSPACE = 0x01, 0x02, 0x04


@dataclass(slots=True)
class Node:
    kind: int
    null: bool = False
    code: int | None = None
    typeface: int | None = None
    selector: int | None = None
    variation: int | None = None
    embellishment: int | None = None
    children: list["Node"] = field(default_factory=list)


class MtefParser:
    data: bytes
    index: int

    def __init__(self, data: bytes) -> None:
        if len(data) < 29:
            raise ValueError("Equation Native stream is too short")
        self.data = data[28:]
        self.index = 0

    def byte(self) -> int:
        if self.index >= len(self.data):
            raise EOFError("unexpected end of MTEF")
        value = self.data[self.index]
        self.index += 1
        return value

    def u16(self) -> int:
        value = self.data[self.index] | (self.data[self.index + 1] << 8)
        self.index += 2
        return value

    def null_string(self) -> str:
        end = self.data.index(0, self.index)
        value = self.data[self.index:end].decode("latin-1", "replace")
        self.index = end + 1
        return value

    def skip_nudge(self) -> None:
        horizontal, vertical = self.byte(), self.byte()
        if horizontal == 128 or vertical == 128:
            self.index += 4

    def skip_dimensions(self, count: int) -> None:
        seen = 0
        while seen < count:
            value = self.byte()
            for nibble in (value >> 4, value & 0x0F):
                if nibble == 0x0F:
                    seen += 1
                    if seen >= count:
                        break

    def skip_equation_preferences(self) -> None:
        _ = self.byte()
        self.skip_dimensions(self.byte())
        self.skip_dimensions(self.byte())
        for _ in range(self.byte()):
            if self.byte() != 0:
                _ = self.byte()

    def parse(self) -> Node:
        version = self.byte()
        if version != 5:
            raise ValueError(f"unsupported MTEF version {version}")
        self.index += 4
        _ = self.null_string()
        _ = self.byte()
        root = Node(-1)
        stack = [root]
        while self.index < len(self.data):
            kind = self.byte()
            if kind >= FUTURE:
                self.index += self.byte()
                continue
            if kind == END:
                if len(stack) > 1:
                    _ = stack.pop()
                continue
            if kind == LINE:
                options = self.byte()
                if options & MTEF_NUDGE:
                    self.skip_nudge()
                if options & LINE_LSPACE:
                    _ = self.byte()
                if options & LP_RULER:
                    for _ in range(self.byte()):
                        self.index += 3
                node = Node(LINE, null=bool(options & LINE_NULL))
                stack[-1].children.append(node)
                if not node.null:
                    stack.append(node)
                continue
            if kind == CHAR:
                options = self.byte()
                if options & MTEF_NUDGE:
                    self.skip_nudge()
                typeface = self.byte()
                code = self.u16() if not options & NO_MTCODE else 0
                if options & CHAR_8:
                    code = self.byte()
                if options & CHAR_16:
                    code = self.u16()
                stack[-1].children.append(Node(CHAR, code=code, typeface=typeface))
                continue
            if kind == TMPL:
                options = self.byte()
                if options & MTEF_NUDGE:
                    self.skip_nudge()
                selector = self.byte()
                variation = self.byte()
                if variation & 0x80:
                    variation = (variation & 0x7F) | (self.byte() << 8)
                _ = self.byte()
                node = Node(TMPL, selector=selector, variation=variation)
                stack[-1].children.append(node)
                stack.append(node)
                continue
            if kind == PILE:
                options = self.byte()
                if options & MTEF_NUDGE:
                    self.skip_nudge()
                self.index += 2
                node = Node(PILE)
                stack[-1].children.append(node)
                stack.append(node)
                continue
            if kind == MATRIX:
                options = self.byte()
                if options & MTEF_NUDGE:
                    self.skip_nudge()
                self.index += 5
                node = Node(MATRIX)
                stack[-1].children.append(node)
                stack.append(node)
                continue
            if kind == EMBELL:
                options = self.byte()
                if options & MTEF_NUDGE:
                    self.skip_nudge()
                stack[-1].children.append(Node(EMBELL, embellishment=self.byte()))
                continue
            if kind == FONT_STYLE_DEF:
                _ = self.byte()
                _ = self.null_string()
                continue
            if kind == SIZE:
                self.index += 2
                continue
            if kind in (FULL, SUB, SUB2, SYM, SUBSYM):
                continue
            if kind == COLOR:
                _ = self.byte()
                continue
            if kind == COLOR_DEF:
                options = self.byte()
                self.index += 8 if options & 0x01 else 6
                if options & 0x04:
                    _ = self.null_string()
                continue
            if kind == FONT_DEF:
                _ = self.byte()
                _ = self.null_string()
                continue
            if kind == EQN_PREFS:
                self.skip_equation_preferences()
                continue
            if kind == ENCODING_DEF:
                _ = self.null_string()
                continue
            raise ValueError(f"unknown MTEF record {kind} at offset {self.index - 1}")
        return root
