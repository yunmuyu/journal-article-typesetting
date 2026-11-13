from __future__ import annotations

# pyright: reportPrivateUsage=false

import copy
from dataclasses import dataclass
from typing import Literal, TypeAlias

from lxml import etree


ScriptPosition: TypeAlias = Literal["subscript", "superscript"]
W = "{http://schemas.openxmlformats.org/wordprocessingml/2006/main}"
M = "{http://schemas.openxmlformats.org/officeDocument/2006/math}"
MATHISH_CHARS = set("∂∆∇∈∉∑∏√∞≈≠≤≥⊂⊆⊄⊇×÷±∥αβγδεζηθικλμνξοπρστυφχψω")
WRAPPERS = {M + "oMathPara", W + "sdt", W + "sdtContent", W + "hyperlink", W + "smartTag"}
WRAPPER_PROPERTIES = {M + "oMathParaPr", W + "sdtPr", W + "sdtEndPr"}


@dataclass(frozen=True, slots=True)
class TextPart:
    text: str
    italic: bool
    script: ScriptPosition | None = None


def is_loss_function(parts: list[TextPart]) -> bool:
    if not parts or not parts[0].text.startswith("L"):
        return False
    if all(part.script is None for part in parts) and "".join(part.text for part in parts).startswith("L("):
        return True
    if parts[0].text != "L":
        return False
    index = 1
    if index < len(parts) and parts[index].script is not None:
        if parts[index].script != "subscript":
            return False
        while index < len(parts) and parts[index].script == "subscript":
            index += 1
    return index < len(parts) and parts[index].script is None and parts[index].text == "("


def add_math_properties(run_properties: etree._Element, part: TextPart) -> None:
    run_fonts = run_properties.find(W + "rFonts")
    if run_fonts is None:
        run_fonts = etree.Element(W + "rFonts")
        run_properties.insert(0, run_fonts)
    for attribute in ("ascii", "hAnsi", "eastAsia", "cs"):
        run_fonts.set(W + attribute, "Times New Roman")
    for attribute in ("asciiTheme", "hAnsiTheme", "eastAsiaTheme", "cstheme"):
        _ = run_fonts.attrib.pop(W + attribute, None)
    if run_fonts.get(W + "hint") == "eastAsia":
        _ = run_fonts.attrib.pop(W + "hint")
    for tag in (W + "i", W + "iCs", W + "vertAlign", W + "position"):
        for property_node in run_properties.findall(tag):
            _ = run_properties.remove(property_node)
    if part.italic:
        run_properties.append(etree.Element(W + "i"))
        run_properties.append(etree.Element(W + "iCs"))
    if part.script is not None:
        alignment = etree.Element(W + "vertAlign")
        alignment.set(W + "val", part.script)
        run_properties.append(alignment)


def build_run(source_run: etree._Element, part: TextPart) -> etree._Element:
    run = etree.Element(W + "r")
    source_properties = source_run.find(W + "rPr")
    properties = copy.deepcopy(source_properties) if source_properties is not None else etree.Element(W + "rPr")
    add_math_properties(properties, part)
    run.append(properties)
    text = etree.Element(W + "t")
    if part.text.startswith(" ") or part.text.endswith(" "):
        text.set("{http://www.w3.org/XML/1998/namespace}space", "preserve")
    text.text = part.text
    run.append(text)
    return run


def _has_unrelated_content(node: etree._Element, source: etree._Element) -> bool:
    for child in node:
        if child is source or child.tag in WRAPPER_PROPERTIES:
            continue
        if any(descendant is source for descendant in child.iter()):
            if _has_unrelated_content(child, source):
                return True
            continue
        return True
    return False


def _wrapper_anchor(source: etree._Element) -> etree._Element:
    anchor = source
    parent = anchor.getparent()
    while parent is not None and parent.tag in WRAPPERS:
        anchor = parent
        parent = anchor.getparent()
    return anchor


def _contains_cjk(text: str) -> bool:
    return any(
        "\u3000" <= character <= "\u30ff"
        or "\u3400" <= character <= "\u9fff"
        or "\uac00" <= character <= "\ud7af"
        or "\uff00" <= character <= "\uffef"
        for character in text
    )


def _inside_omml(node: etree._Element) -> bool:
    return any(ancestor.tag.startswith(M) for ancestor in node.iterancestors())


def replace_with_text_runs(
    source: etree._Element,
    parts: list[TextPart],
    generated_runs: list[etree._Element] | None = None,
) -> bool:
    source_parent = source.getparent()
    if source_parent is None:
        return False
    if source_parent.tag == W + "r":
        content_nodes = [node for node in source_parent if node.tag != W + "rPr"]
        if content_nodes != [source]:
            return False
        parent = source_parent.getparent()
        if parent is None:
            return False
        template_run = source_parent
        position = parent.index(source_parent)
    else:
        anchor = _wrapper_anchor(source)
        parent = anchor.getparent()
        if parent is None or parent.tag != W + "p":
            return False
        if anchor is not source and _has_unrelated_content(anchor, source):
            return False
        position = parent.index(anchor)
        siblings = list(parent)
        template_run = next(
            (siblings[index] for index in range(position - 1, -1, -1) if siblings[index].tag == W + "r"),
            None,
        )
        if template_run is None:
            template_run = next(
                (siblings[index] for index in range(position + 1, len(siblings)) if siblings[index].tag == W + "r"),
                etree.Element(W + "r"),
            )
    for part in parts:
        run = build_run(template_run, part)
        parent.insert(position, run)
        if generated_runs is not None:
            generated_runs.append(run)
        position += 1
    if source_parent.tag == W + "r":
        _ = parent.remove(template_run)
    else:
        _ = parent.remove(anchor)
    return True


def normalize_math_font_slots(root: etree._Element) -> int:
    """Repair East Asian font fallback in existing math runs, preserving source formatting."""
    normalized = 0
    for run in root.iter(W + "r"):
        properties = run.find(W + "rPr")
        if properties is None or _inside_omml(run):
            continue
        fonts = properties.find(W + "rFonts")
        if fonts is None or fonts.get(W + "hint") != "eastAsia":
            continue
        latin_fonts = {fonts.get(W + slot) for slot in ("ascii", "hAnsi")} - {None}
        if latin_fonts != {"Times New Roman"}:
            continue
        content = [node for node in run if node.tag != W + "rPr"]
        if not content or any(node.tag != W + "t" for node in content):
            continue
        text = "".join(node.text or "" for node in content)
        if not 0 < len(text) <= 12 or _contains_cjk(text):
            continue
        script = properties.find(W + "vertAlign")
        is_script = script is not None and script.get(W + "val") in {"subscript", "superscript"}
        has_math_symbol = any(character in MATHISH_CHARS or "\u0391" <= character <= "\u03a9" for character in text)
        if not is_script and not has_math_symbol:
            continue
        for slot in ("ascii", "hAnsi", "eastAsia", "cs"):
            fonts.set(W + slot, "Times New Roman")
        for attribute in ("asciiTheme", "hAnsiTheme", "eastAsiaTheme", "cstheme", "hint"):
            _ = fonts.attrib.pop(W + attribute, None)
        normalized += 1
    return normalized
