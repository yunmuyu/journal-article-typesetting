from __future__ import annotations

# pyright: reportPrivateUsage=false, reportUnknownMemberType=false, reportUnknownArgumentType=false, reportUnknownVariableType=false

from lxml import etree

from math_text import TextPart
from semantic_text import normalize_semantic_roles


M = "{http://schemas.openxmlformats.org/officeDocument/2006/math}"
W = "{http://schemas.openxmlformats.org/wordprocessingml/2006/main}"
SCRIPT_ARGUMENTS = {
    M + "sSub": (M + "e", M + "sub"),
    M + "sSup": (M + "e", M + "sup"),
    M + "sSubSup": (M + "e", M + "sub", M + "sup"),
}
SCRIPT_PROPERTIES = {
    M + "sSub": M + "sSubPr",
    M + "sSup": M + "sSupPr",
    M + "sSubSup": M + "sSubSupPr",
}


def delimiter_parts(delimiter: etree._Element) -> list[TextPart] | None:
    properties = delimiter.find(M + "dPr")
    if properties is not None:
        begin = properties.find(M + "begChr")
        end = properties.find(M + "endChr")
        if begin is not None and (begin.get(M + "val") or "(") != "(":
            return None
        if end is not None and (end.get(M + "val") or ")") != ")":
            return None
    arguments = [child for child in delimiter if child.tag == M + "e"]
    if len(arguments) != 1:
        return None
    inner = flat_argument_parts(arguments[0])
    if inner is None or len(inner) > 6:
        return None
    return [TextPart("(", italic=False), *inner, TextPart(")", italic=False)]


def math_run_italic(run: etree._Element) -> bool:
    properties = run.find(M + "rPr")
    if properties is None:
        return True
    if properties.find(M + "nor") is not None:
        return False
    style = properties.find(M + "sty")
    return style is None or style.get(M + "val") not in {"p", "b"}


def flat_run_parts(run: etree._Element) -> list[TextPart] | None:
    text_nodes = []
    for child in run:
        if child.tag in {M + "rPr", W + "rPr"}:
            continue
        if child.tag != M + "t":
            return None
        text_nodes.append(child)
    text = "".join(node.text or "" for node in text_nodes)
    return [TextPart(text=text, italic=math_run_italic(run))] if text else None


def flat_argument_parts(argument: etree._Element) -> list[TextPart] | None:
    output: list[TextPart] = []
    for child in argument:
        if child.tag == M + "ctrlPr":
            continue
        if child.tag != M + "r":
            return None
        parts = flat_run_parts(child)
        if parts is None:
            return None
        output.extend(parts)
    return output if output else None


def script_parts(script: etree._Element) -> list[TextPart] | None:
    expected_arguments = SCRIPT_ARGUMENTS.get(script.tag)
    property_tag = SCRIPT_PROPERTIES.get(script.tag)
    if expected_arguments is None or property_tag is None:
        return None
    arguments = []
    for child in script:
        if child.tag == property_tag:
            continue
        if child.tag not in expected_arguments:
            return None
        arguments.append(child)
    if tuple(argument.tag for argument in arguments) != expected_arguments:
        return None
    parsed_arguments = [flat_argument_parts(argument) for argument in arguments]
    if any(parts is None or not parts for parts in parsed_arguments):
        return None
    parts = [argument for argument in parsed_arguments if argument is not None]
    if len(parts[0]) > 22 or any(len(argument) > 3 for argument in parts[1:]):
        return None
    base = parts[0]
    if script.tag == M + "sSub":
        return base + [TextPart(part.text, part.italic, "subscript") for part in parts[1]]
    if script.tag == M + "sSup":
        return base + [TextPart(part.text, part.italic, "superscript") for part in parts[1]]
    subscripts = [TextPart(part.text, part.italic, "subscript") for part in parts[1]]
    superscripts = [TextPart(part.text, part.italic, "superscript") for part in parts[2]]
    return base + subscripts + superscripts


def simple_omml_expression(math: etree._Element) -> list[TextPart] | None:
    output: list[TextPart] = []
    script_count = 0
    delimiter_count = 0
    for child in math:
        if child.tag == M + "r":
            parts = flat_run_parts(child)
        elif child.tag in SCRIPT_ARGUMENTS:
            script_count += 1
            if script_count > 1:
                return None
            parts = script_parts(child)
        elif child.tag == M + "d":
            delimiter_count += 1
            if delimiter_count > 1:
                return None
            parts = delimiter_parts(child)
        else:
            return None
        if parts is None:
            return None
        output.extend(parts)
    if not output or len(output) > 25:
        return None
    return normalize_semantic_roles(output)
