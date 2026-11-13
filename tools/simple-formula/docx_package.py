from __future__ import annotations

import posixpath
import zipfile
from pathlib import Path

from lxml import etree


W = "{http://schemas.openxmlformats.org/wordprocessingml/2006/main}"
M = "{http://schemas.openxmlformats.org/officeDocument/2006/math}"
XML_PARSER = etree.XMLParser(resolve_entities=False, no_network=True, load_dtd=False, huge_tree=False)


def relation_targets(relationships_xml: bytes, part_name: str = "relationship part") -> dict[str, str]:
    root = parse_xml(relationships_xml, part_name)
    targets: dict[str, str] = {}
    for relation in root:
        identifier = relation.get("Id")
        target = relation.get("Target")
        if relation.get("Type", "").endswith("/oleObject") and identifier and target:
            targets[identifier] = target
    return targets


def parse_xml(payload: bytes, part_name: str) -> etree._Element:
    try:
        return etree.fromstring(payload, parser=XML_PARSER)
    except etree.XMLSyntaxError as error:
        raise SystemExit(f"invalid XML in {part_name}: {error}") from error


def relationship_part(part_name: str) -> str:
    path = Path(part_name)
    return str(path.parent / "_rels" / f"{path.name}.rels").replace("\\", "/")


def resolved_target(part_name: str, target: str) -> str | None:
    candidate = posixpath.normpath(posixpath.join(posixpath.dirname(part_name), target))
    if candidate.startswith("../") or candidate.startswith("/"):
        return None
    return candidate


def document_parts(source: zipfile.ZipFile) -> list[str]:
    names = source.namelist()
    return [
        name
        for name in names
        if name == "word/document.xml"
        or name.startswith("word/header") and name.endswith(".xml")
        or name.startswith("word/footer") and name.endswith(".xml")
        or name in {"word/footnotes.xml", "word/endnotes.xml"}
    ]


def count_ordinary_position_runs(root: etree._Element) -> int:
    count = 0
    for run in root.iter(W + "r"):
        properties = run.find(W + "rPr")
        if properties is None or properties.find(W + "position") is None:
            continue
        parent = run.getparent()
        inside_formula = False
        while parent is not None:
            if parent.tag in {M + "oMath", W + "object"}:
                inside_formula = True
                break
            parent = parent.getparent()
        if not inside_formula:
            count += 1
    return count
