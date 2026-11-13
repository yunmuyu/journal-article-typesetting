from __future__ import annotations

from mtef_parser import CHAR, LINE, TMPL, Node
from math_text import TextPart
from semantic_text import normalize_semantic_roles


TM_SUB, TM_SUP, TM_SUBSUP = 27, 28, 29
SYMBOL_TYPEFACE = 132
SYMBOL_GREEK = {
    ord("a"): "α", ord("b"): "β", ord("c"): "χ", ord("d"): "δ",
    ord("e"): "ε", ord("f"): "φ", ord("g"): "γ", ord("h"): "η",
    ord("i"): "ι", ord("j"): "ϕ", ord("k"): "κ", ord("l"): "λ",
    ord("m"): "μ", ord("n"): "ν", ord("o"): "ο", ord("p"): "π",
    ord("q"): "θ", ord("r"): "ρ", ord("s"): "σ", ord("t"): "τ",
    ord("u"): "υ", ord("v"): "ϖ", ord("w"): "ω", ord("x"): "ξ",
    ord("y"): "ψ", ord("z"): "ζ",
    ord("A"): "Α", ord("B"): "Β", ord("C"): "Χ", ord("D"): "Δ",
    ord("E"): "Ε", ord("F"): "Φ", ord("G"): "Γ", ord("H"): "Η",
    ord("I"): "Ι", ord("J"): "ϑ", ord("K"): "Κ", ord("L"): "Λ",
    ord("M"): "Μ", ord("N"): "Ν", ord("O"): "Ο", ord("P"): "Π",
    ord("Q"): "Θ", ord("R"): "Ρ", ord("S"): "Σ", ord("T"): "Τ",
    ord("U"): "Υ", ord("V"): "ς", ord("W"): "Ω", ord("X"): "Ξ",
    ord("Y"): "Ψ", ord("Z"): "Ζ",
}


def visible_nodes(node: Node) -> list[Node]:
    return [child for child in node.children if child.kind != LINE or not child.null]


def char_text(node: Node) -> str:
    if node.code is None or node.code == 0:
        return ""
    if node.typeface == SYMBOL_TYPEFACE:
        return SYMBOL_GREEK.get(node.code, chr(node.code))
    return chr(node.code)


def italic_for_typeface(typeface: int | None) -> bool:
    return typeface is not None and typeface not in (129, 130, 134, 136)


def extract_line(node: Node) -> list[TextPart] | None:
    parts: list[TextPart] = []
    for child in visible_nodes(node):
        if child.kind != CHAR:
            return None
        text = char_text(child)
        if not text:
            return None
        parts.append(TextPart(text=text, italic=italic_for_typeface(child.typeface)))
    return parts


def line_children(node: Node) -> list[Node] | None:
    children = visible_nodes(node)
    lines = [child for child in children if child.kind == LINE]
    return lines if len(lines) == len(children) else None


def _script_parts(parts: list[TextPart], script: str) -> list[TextPart]:
    return [TextPart(part.text, part.italic, script) for part in parts]


def simple_template_parts(template: Node) -> list[TextPart] | None:
    if template.selector not in (TM_SUB, TM_SUP, TM_SUBSUP):
        return None
    slots = line_children(template)
    if slots is None:
        return None
    simple_parts: list[list[TextPart]] = []
    for slot in slots:
        if slot.null:
            continue
        parts = extract_line(slot)
        if parts is None or not parts:
            return None
        simple_parts.append(parts)
    if template.selector == TM_SUB:
        if len(simple_parts) != 1:
            return None
        return _script_parts(simple_parts[0], "subscript")
    if template.selector == TM_SUP:
        if len(simple_parts) != 1:
            return None
        return _script_parts(simple_parts[0], "superscript")
    if len(simple_parts) != 2:
        return None
    subscripts = _script_parts(simple_parts[0], "subscript")
    superscripts = _script_parts(simple_parts[1], "superscript")
    return subscripts + superscripts


def simple_expression(root: Node) -> list[TextPart] | None:
    top = visible_nodes(root)
    if len(top) != 1 or top[0].kind != LINE:
        return None
    direct = visible_nodes(top[0])
    if not direct:
        return None
    output: list[TextPart] = []
    can_attach_script = False
    template_count = 0
    for child in direct:
        if child.kind == CHAR:
            text = char_text(child)
            if not text:
                return None
            output.append(TextPart(text=text, italic=italic_for_typeface(child.typeface)))
            can_attach_script = True
            continue
        if child.kind == TMPL and can_attach_script:
            template_count += 1
            if template_count > 1:
                return None
            script_parts = simple_template_parts(child)
            if script_parts is None:
                return None
            output.extend(script_parts)
            continue
        return None
    return normalize_semantic_roles(output) if len(output) <= 25 else None
