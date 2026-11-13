from __future__ import annotations

# pyright: reportPrivateUsage=false

import json
import os
import sys
import tempfile
import zipfile
from pathlib import Path
from typing import Literal, NotRequired, TypedDict

import olefile
from lxml import etree

from legacy_doc import prepared_input
from docx_package import M, count_ordinary_position_runs, document_parts, parse_xml, relation_targets, relationship_part, resolved_target
from math_text import W, TextPart, is_loss_function, normalize_math_font_slots, replace_with_text_runs
from mathtype_rules import simple_expression
from mtef_parser import MtefParser
from omml_rules import M, simple_omml_expression


NS = {
    "w": "http://schemas.openxmlformats.org/wordprocessingml/2006/main",
    "o": "urn:schemas-microsoft-com:office:office",
    "r": "http://schemas.openxmlformats.org/officeDocument/2006/relationships",
}
R = "{%s}" % NS["r"]
MATH_PROGIDS = {"Equation.DSMT4", "Equation.DSMT6", "Equation.3", "Equation.2", "Equation"}


class FormulaDetail(TypedDict):
    ordinal: int
    source: Literal["MathType", "OMML"]
    target: str | None
    reason: str
    text: NotRequired[str]


class ConversionReport(TypedDict):
    input: str
    input_format: NotRequired[str]
    legacy_doc_converted: NotRequired[bool]
    font_normalized_count: NotRequired[int]
    total: int
    converted: list[FormulaDetail]
    retained: list[FormulaDetail]
    converted_count: int
    retained_count: int
    omml_total: int
    omml_converted: list[FormulaDetail]
    omml_retained: list[FormulaDetail]
    omml_converted_count: int
    omml_retained_count: int
    ordinary_runs_with_position_preserved: int
    converted_runs_with_position: int


def read_equation_native(binary_data: bytes) -> bytes:
    with tempfile.NamedTemporaryFile(suffix=".bin", delete=False) as handle:
        _ = handle.write(binary_data)
        temporary_path = handle.name
    try:
        ole = olefile.OleFileIO(temporary_path)
        try:
            return ole.openstream("Equation Native").read()
        finally:
            ole.close()
    finally:
        _ = os.unlink(temporary_path)


def is_nested_math(math: etree._Element) -> bool:
    parent = math.getparent()
    while parent is not None:
        if parent.tag == M + "oMath":
            return True
        parent = parent.getparent()
    return False


def new_report(input_path: Path) -> ConversionReport:
    return {
        "input": str(input_path),
        "total": 0,
        "converted": [],
        "retained": [],
        "converted_count": 0,
        "retained_count": 0,
        "omml_total": 0,
        "omml_converted": [],
        "omml_retained": [],
        "omml_converted_count": 0,
        "omml_retained_count": 0,
        "ordinary_runs_with_position_preserved": 0,
        "converted_runs_with_position": 0,
    }


def retain(details: list[FormulaDetail], detail: FormulaDetail, reason: str) -> None:
    detail["reason"] = reason
    details.append(detail)


def convert_or_retain(
    source: etree._Element,
    parts: list[TextPart] | None,
    detail: FormulaDetail,
    converted: list[FormulaDetail],
    retained: list[FormulaDetail],
    output_path: Path | None,
) -> None:
    if parts is None:
        retain(retained, detail, "complex or unsupported")
        return
    if is_loss_function(parts):
        retain(retained, detail, "retained: loss-function notation")
        return
    if output_path is not None and not replace_with_text_runs(source, parts):
        retain(retained, detail, "retained: formula was not the sole content of a Word run")
        return
    detail["text"] = "".join(part.text for part in parts)
    converted.append(detail)


def scan_or_convert(input_path: Path, output_path: Path | None, report_path: Path) -> ConversionReport:
    with zipfile.ZipFile(input_path) as source:
        report = new_report(input_path)
        roots: dict[str, etree._Element] = {}
        for part_name in document_parts(source):
            try:
                roots[part_name] = parse_xml(source.read(part_name), part_name)
            except KeyError as error:
                raise SystemExit(f"input DOCX is missing {part_name}") from error
        for part_name, root in roots.items():
            try:
                rels = source.read(relationship_part(part_name))
            except KeyError:
                relationships = {}
            else:
                relationships = relation_targets(rels, relationship_part(part_name))
            for ordinal, object_node in enumerate(root.iter(W + "object"), start=1):
                ole = object_node.find(".//o:OLEObject", namespaces=NS)
                if ole is None or ole.get("ProgID") not in MATH_PROGIDS:
                    continue
                report["total"] += 1
                relation_id = ole.get(R + "id")
                target = relationships.get(relation_id) if relation_id else None
                target = resolved_target(part_name, target) if target is not None else None
                detail: FormulaDetail = {"ordinal": ordinal, "source": "MathType", "target": target, "reason": ""}
                if target is None:
                    retain(report["retained"], detail, "retained: missing OLE relationship target")
                    continue
                try:
                    native = read_equation_native(source.read(target))
                    parts = simple_expression(MtefParser(native).parse())
                except (EOFError, IndexError, KeyError, OSError, ValueError, zipfile.BadZipFile) as error:
                    retain(report["retained"], detail, f"retained after parser check: {error}")
                    continue
                convert_or_retain(object_node, parts, detail, report["converted"], report["retained"], output_path)
            for ordinal, math in enumerate(list(root.iter(M + "oMath")), start=1):
                if is_nested_math(math):
                    continue
                report["omml_total"] += 1
                detail = {"ordinal": ordinal, "source": "OMML", "target": None, "reason": ""}
                parts = simple_omml_expression(math)
                convert_or_retain(math, parts, detail, report["omml_converted"], report["omml_retained"], output_path)
            report["font_normalized_count"] = report.get("font_normalized_count", 0) + normalize_math_font_slots(root)
            report["ordinary_runs_with_position_preserved"] += count_ordinary_position_runs(root)
        report["converted_count"] = len(report["converted"])
        report["retained_count"] = len(report["retained"])
        report["omml_converted_count"] = len(report["omml_converted"])
        report["omml_retained_count"] = len(report["omml_retained"])
        report["converted_runs_with_position"] = 0
        _ = report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
        if output_path is not None:
            _ = output_path.parent.mkdir(parents=True, exist_ok=True)
            try:
                with zipfile.ZipFile(output_path, "w", zipfile.ZIP_DEFLATED) as destination:
                    for item in source.infolist():
                        root = roots.get(item.filename)
                        payload = (
                            etree.tostring(root, xml_declaration=True, encoding="UTF-8", standalone=True)
                            if root is not None
                            else source.read(item.filename)
                        )
                        _ = destination.writestr(item, payload)
            except PermissionError as error:
                raise SystemExit(f"cannot write output DOCX; close any open copy and retry: {output_path}") from error
    return report


def parse_paths(arguments: list[str]) -> tuple[Path, Path | None, Path]:
    if not arguments:
        raise SystemExit("input DOC or DOCX is required")
    input_path = Path(arguments[0])
    if input_path.suffix.lower() not in {".doc", ".docx"}:
        raise SystemExit(
            f"unsupported input format: {input_path.suffix or '<no extension>'}; "
            "only .DOC and .DOCX are supported"
        )
    output_path: Path | None = None
    scan_only = False
    report_path: Path | None = None
    index = 1
    while index < len(arguments):
        option = arguments[index]
        if option == "--scan-only":
            scan_only = True
            index += 1
            continue
        if index + 1 >= len(arguments):
            raise SystemExit("each option requires a path")
        value = Path(arguments[index + 1])
        if option == "--output":
            output_path = value
        elif option == "--report":
            report_path = value
        else:
            raise SystemExit(f"unsupported option: {option}")
        index += 2
    if report_path is None:
        raise SystemExit("--report is required")
    if output_path is None and not scan_only:
        output_path = input_path.with_name(f"{input_path.stem}_converted.docx")
    if output_path is not None and output_path.resolve() == input_path.resolve():
        raise SystemExit("output must be a separately named file; the source document is never overwritten")
    return input_path, output_path, report_path


def main() -> None:
    input_path, output_path, report_path = parse_paths(sys.argv[1:])
    try:
        with prepared_input(input_path) as processing_path:
            result = scan_or_convert(processing_path, output_path, report_path)
    except RuntimeError as error:
        raise SystemExit(f"legacy .DOC conversion unavailable: {error}") from error
    except (zipfile.BadZipFile, OSError) as error:
        raise SystemExit(f"cannot process input document: {error}") from error
    result["input"] = str(input_path)
    result["input_format"] = input_path.suffix.lower()
    result["legacy_doc_converted"] = input_path.suffix.lower() == ".doc"
    _ = report_path.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    summary = {key: result[key] for key in ("total", "converted_count", "retained_count", "omml_total", "omml_converted_count", "omml_retained_count")}
    print(json.dumps(summary, ensure_ascii=False))


if __name__ == "__main__":
    main()
