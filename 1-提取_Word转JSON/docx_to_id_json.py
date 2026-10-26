# -*- coding: utf-8 -*-
"""Convert a Word article into JSON for the InDesign importer.

Current workflow:
- import starts at "0 引言";
- front matter before the introduction is skipped;
- includes references and author biography;
- tables are skipped with an empty location block, while captions remain;
- MathType OLE objects detected; standalone formulas emit "math" blocks + 1 blank after;
  inline formulas get 3 spaces around them in text;
- figure_caption preceded by 3 blank lines, table_caption followed by 1 blank line;
- run-level italic, superscript, subscript, bold preserved, with val check.
"""
from __future__ import annotations

from word_numbering import WordNumbering

import argparse
import json
import re
import zipfile
import xml.etree.ElementTree as ET
from pathlib import Path
from collections.abc import Iterator
from typing import Dict, List, Optional

W_NS = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"
M_NS = "http://schemas.openxmlformats.org/officeDocument/2006/math"
NS = {"w": W_NS, "m": M_NS}
W = "{%s}" % W_NS


def _flag_val(rpr: ET.Element, tag: str) -> bool:
    """Check w:i or w:b, respecting w:val='false'/'0'."""
    el = rpr.find("{%s}%s" % (W_NS, tag))
    if el is None:
        return False
    v = el.get("{%s}val" % W_NS)
    if v is None:
        return True
    return v not in ("false", "0", "off", "0")


def attr(el: Optional[ET.Element], name: str) -> Optional[str]:
    return el.get(W + name) if el is not None else None


def has_ole(para: ET.Element) -> bool:
    """True if the paragraph contains a w:object (MathType OLE embedding)."""
    return any(item.tag == "{%s}oMath" % M_NS or
               item.find("w:object", NS) is not None for item in inline_items(para))


def inline_items(element: ET.Element) -> Iterator[ET.Element]:
    for child in element:
        if child.tag in (W + "del", W + "moveFrom", W + "pPr", W + "rPr", W + "sdtPr"):
            continue
        if child.tag in (W + "r", "{%s}oMath" % M_NS):
            yield child
        else:
            yield from inline_items(child)


def body_items(element: ET.Element) -> Iterator[ET.Element]:
    for child in element:
        if child.tag in (W + "del", W + "moveFrom", W + "sdtPr"):
            continue
        if child.tag in (W + "p", W + "tbl"):
            yield child
        else:
            yield from body_items(child)


def run_content(run: ET.Element) -> str:
    tokens: list[str] = []
    for child in run:
        if child.tag == W + "t":
            tokens.append(child.text or "")
        elif child.tag in (W + "object", W + "drawing", W + "pict"):
            tokens.append("   ")
        elif child.tag == W + "tab":
            tokens.append("\t")
        elif child.tag in (W + "br", W + "cr"):
            tokens.append("\n")
        elif child.tag == W + "noBreakHyphen":
            tokens.append("\u2011")
        elif child.tag == W + "softHyphen":
            tokens.append("\u00ad")
    return "".join(tokens)


def run_flags(r: ET.Element, run_text: str = "") -> Dict[str, object]:
    rpr = r.find("w:rPr", NS)
    flags: Dict[str, object] = {}
    if rpr is None:
        return flags
    if _flag_val(rpr, "i"):
        flags["italic"] = True
    if _flag_val(rpr, "b"):
        flags["bold"] = True
    va = rpr.find("w:vertAlign", NS)
    if va is not None:
        v = attr(va, "val")
        if v == "superscript":
            flags["position"] = "superscript"
        elif v == "subscript":
            flags["position"] = "subscript"
        # 只有“纯数字”的上下标强制直立（去斜体）；希腊字母等变量也保留 Word 原本的斜体。
        if v in ("superscript", "subscript") and re.fullmatch(r"\d+", run_text):
            flags.pop("italic", None)
    return flags


def paragraph_runs(p: ET.Element) -> tuple[str, List[Dict[str, object]]]:
    text_parts: List[str] = []
    runs: List[Dict[str, object]] = []
    cursor = 0
    for r in inline_items(p):
        if r.tag == "{%s}oMath" % M_NS:
            text_parts.append("   ")
            cursor += 3
            continue
        text = run_content(r)
        if not text:
            continue
        start = cursor
        text_parts.append(text)
        cursor += len(text.encode("utf-16-le")) // 2
        flags = run_flags(r, text)
        if flags:
            item: Dict[str, object] = {"start": start, "end": cursor}
            item.update(flags)
            runs.append(item)
    return "".join(text_parts).replace("＋", "+"), runs  # 全角＋ → 半角+（不改字体）


def clean_text(s: str) -> str:
    return re.sub(r"[ \t\u3000]+", " ", s.strip())


def paragraph_role(text: str, seq_index: int) -> str:
    t = clean_text(text)
    if not t:
        return "blank"
    if re.match(r"^\u53c2\u8003\u6587\u732e[\uff1a:]?\s*$", t):
        return "references_title"
    if t.startswith("\u4f5c\u8005\u7b80\u4ecb") or t.startswith("\u4f5c\u8005\u7b80\u4ecb\uff1a"):
        return "author_bio"
    # 图 / 表 标题分离
    if re.match(r"^\u56fe\s*\d+\s+", t):
        return "figure_caption"
    if re.match(r"^\u8868\s*\d+\s+", t):
        return "table_caption"
    if re.match(r"^[\uff08(][a-zA-Z0-9\u4e00-\u9fa5][\uff09)]\s*\S", t):
        return "caption"  # (a)(b) 子图注
    # 标题必须含汉字、且不含赋值箭头 ←（否则像 "4 sub ← copy(v)"、"8 if x ∈ T'" 这类算法伪代码会被误判成标题）
    if re.match(r"^\d+(?:\.\d+)+\s+\S", t) and re.search(r"[一-龥]", t) and "←" not in t:
        return "heading2"
    if re.match(r"^\d+\s+\S", t) and len(t) <= 40 and re.search(r"[一-龥]", t) and "←" not in t:
        return "heading1"
    if re.match(r"^\[\d+\]", t):
        return "reference_item"
    return "body"


def convert_docx(docx_path: Path) -> Dict[str, object]:
    with zipfile.ZipFile(docx_path) as zf:
        document_xml = ET.fromstring(zf.read("word/document.xml"))
        numbering = WordNumbering(zf)
        numbering.materialize(document_xml)
    body = document_xml.find("w:body", NS)
    if body is None:
        raise RuntimeError("word/document.xml has no body")

    blocks: List[Dict[str, object]] = []
    seq = 0
    started = False
    last_was_table = False
    for child in body_items(body):
        if child.tag == W + "p":
            text, runs = paragraph_runs(child)
            is_ole = has_ole(child)
            seq += 1

            # -- 独立 MathType 公式（文本空 + OLE）→ math 占位 + 空行 --
            if not text.strip():
                if is_ole and started:
                    last_was_table = False
                    blocks.append({"role": "math", "text": "", "runs": [], "seq": seq})
                    seq += 1
                    blocks.append({"role": "blank", "text": "", "runs": [], "seq": seq})
                # 普通空行仍然跳过
                continue

            last_was_table = False
            role = paragraph_role(text, seq)

            # -- 前置跳过逻辑 --
            if not started:
                normalized = clean_text(text)
                if role == "heading1" and re.match(r"^0\s+\u5f15\s*\u8a00$", normalized):
                    started = True
                else:
                    continue

            # 参考文献 / 作者简介 现在也排版（不再跳过）。
            # ⚠ 这些段落在 Word 里常被整段误设为粗体，去掉 bold，由段落样式（参考文献 内容 / 作者简介）决定字重；
            #    保留 italic / 上下标（外文文献偶有）。字符样式由导入脚本按位置补（见 jsx）。
            if role in ("references_title", "reference_item", "author_bio"):
                cleaned_runs = []
                for rr in runs:
                    rr2 = {k: v for k, v in rr.items() if k != "bold"}
                    if any(k not in ("start", "end") for k in rr2):
                        cleaned_runs.append(rr2)
                runs = cleaned_runs

            # -- 图前 3 空行（图注/表名样式）。若上一块是 (a)(b) 子图注，空行插到它前面，
            #    使顺序为：空行 空行 空行 → (a)(b)子图注 → 图题 --
            if role == "figure_caption":
                insert_at = len(blocks)
                if blocks and blocks[-1]["role"] == "caption":
                    insert_at = len(blocks) - 1
                spacers = [{"role": "figure_caption", "text": "", "runs": [], "seq": 0} for _ in range(3)]
                blocks[insert_at:insert_at] = spacers

            # 内嵌 MathType 占位已在 paragraph_runs 中处理（每个 OLE 对象 = 3 空格，偏移对齐）。

            blocks.append({"role": role, "text": text, "runs": runs, "seq": seq})

            # -- 表名后 1 空行（role=table_gap，导入时左对齐、无缩进，给表格留位）--
            if role == "table_caption":
                blocks.append({"role": "table_gap", "text": "", "runs": [], "seq": 0})

        elif child.tag == W + "tbl":
            if started:
                if last_was_table or not blocks or blocks[-1]["role"] != "table_gap":
                    blocks.append({"role": "table_gap", "text": "   ", "runs": [], "seq": 0})
                else:
                    blocks[-1]["text"] = "   "
                last_was_table = True

    # Re-number seq for output consistency
    for i, b in enumerate(blocks):
        b["seq"] = i + 1

    summary: Dict[str, int] = {}
    for b in blocks:
        summary[b["role"]] = summary.get(b["role"], 0) + 1
    return {"source": str(docx_path), "blocks": blocks, "summary": summary}


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("docx", type=Path)
    parser.add_argument("-o", "--output", type=Path, required=True)
    args = parser.parse_args()
    if args.docx.suffix.lower() == ".doc":
        # 旧版 .doc 是二进制 OLE 复合文档，不是 zip，python-docx/zipfile 读不了。
        # .doc 支持只在 PowerShell 版（docx_to_id_json.ps1，调用 Word 自动化）里实现；
        # 这里给出清晰提示，避免 BadZipFile 报错。
        raise SystemExit(
            ".doc 暂不支持本 Python 版。请用 docx_to_id_json.ps1（会调用 Word 转换），"
            "或先在 Word 里把它另存为 .docx 再处理。"
        )
    data = convert_docx(args.docx)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(data["summary"], ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
