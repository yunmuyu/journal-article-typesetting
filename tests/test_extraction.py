from pathlib import Path
import json
import os
import subprocess
import sys
import tempfile
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[1]
EXTRACTOR = ROOT / "1-提取_Word转JSON"
PS = Path(os.environ["SystemRoot"]) / "System32/WindowsPowerShell/v1.0/powershell.exe"
INTRO = '<w:p><w:r><w:t>0 引言</w:t></w:r></w:p>'


def document(tmp_path: Path, content: str) -> Path:
    path = tmp_path / "[图 表] 中文 % ! 文稿.docx"
    xml = ('<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" '
           'xmlns:m="http://schemas.openxmlformats.org/officeDocument/2006/math"><w:body>'
           + content + '</w:body></w:document>')
    with zipfile.ZipFile(path, "w") as archive:
        archive.writestr("word/document.xml", xml)
    return path


def convert(path: Path, engine: str) -> dict:
    output = path.with_suffix(".json")
    if engine == "powershell":
        command = [str(PS), "-NoProfile", "-ExecutionPolicy", "Bypass", "-File",
                   str(EXTRACTOR / "docx_to_id_json.ps1"), str(path), str(output)]
    else:
        command = [sys.executable, str(EXTRACTOR / "docx_to_id_json.py"), str(path), "-o", str(output)]
    result = subprocess.run(command, capture_output=True, timeout=30)
    assert result.returncode == 0, result.stdout.decode("utf-8", errors="replace") + result.stderr.decode("utf-8", errors="replace")
    return json.loads(output.read_text(encoding="utf-8-sig"))


def test_hyperlink_and_nested_runs_keep_text_and_offsets(tmp_path: Path, engine: str) -> None:
    # Given: hyperlink, content control and revision wrappers in source order.
    content = INTRO + '''<w:p><w:r><w:t>数据集（</w:t></w:r>
    <w:hyperlink><w:r><w:rPr><w:i/></w:rPr><w:t>MVTec-AD</w:t></w:r></w:hyperlink>
    <w:r><w:t>, </w:t></w:r><w:sdt><w:sdtContent><w:r><w:t>VisA</w:t></w:r></w:sdtContent></w:sdt>
    <w:r><w:t>）的测试中取得</w:t></w:r><w:ins><w:r><w:t>成功</w:t></w:r></w:ins>
    <w:del><w:r><w:delText>删除文字</w:delText></w:r></w:del></w:p>'''
    # When: convert using the real entry point.
    block = convert(document(tmp_path, content), engine)["blocks"][1]
    # Then: all visible text is preserved, and its italic range is aligned.
    assert block["text"] == "数据集（MVTec-AD, VisA）的测试中取得成功"
    assert block["text"][block["runs"][0]["start"]:block["runs"][0]["end"]] == "MVTec-AD"


def test_skipped_tables_have_one_location_without_content(tmp_path: Path, engine: str, caption: bool) -> None:
    # Given: a three-line table, possibly with a caption and its existing gap.
    table = '<w:tbl><w:tblPr><w:tblBorders><w:top w:val="single"/><w:bottom w:val="single"/></w:tblBorders></w:tblPr><w:tr><w:tc><w:p><w:r><w:t>表内内容</w:t></w:r></w:p></w:tc></w:tr></w:tbl>'
    content = INTRO + ('<w:p><w:r><w:t>表1 结果</w:t></w:r></w:p>' if caption else '') + table + '<w:p><w:r><w:t>表后正文</w:t></w:r></w:p>'
    # When: extracting the article.
    blocks = convert(document(tmp_path, content), engine)["blocks"]
    # Then: preserve one empty block at the table location, never import cells.
    gaps = [block for block in blocks if block["role"] == "table_gap"]
    assert len(gaps) == 1
    assert gaps[0]["text"] == "   "
    assert blocks[-2]["role"] == "table_gap"
    assert "表内内容" not in "".join(block["text"] for block in blocks)


def test_inline_objects_and_math_keep_multiple_locations_and_offsets(tmp_path: Path, engine: str) -> None:
    # Given: mixed text and objects in one run, plus native Word math.
    content = INTRO + '''<w:p><w:r><w:t>前</w:t><w:object/><w:t>中</w:t><w:object/></w:r>
    <m:oMath><m:r><m:t>x</m:t></m:r></m:oMath><w:hyperlink><w:r><w:rPr><w:i/></w:rPr><w:t>Z</w:t></w:r></w:hyperlink></w:p>'''
    # When: extracting object locations.
    block = convert(document(tmp_path, content), engine)["blocks"][1]
    # Then: every object has a gap, surrounding text and subsequent offsets survive.
    assert block["text"] == "前   中      Z"
    assert block["runs"][-1]["start"] == 11
    assert block["runs"][-1]["end"] == 12


def test_front_matter_math_does_not_leak_and_body_math_is_located(tmp_path: Path, engine: str) -> None:
    # Given: a formula before the introduction and one after it.
    math = '<w:p><m:oMath><m:r><m:t>x</m:t></m:r></m:oMath></w:p>'
    # When: converting.
    blocks = convert(document(tmp_path, math + INTRO + math), engine)["blocks"]
    # Then: body starts at introduction, followed by exactly one formula placeholder.
    assert [block["role"] for block in blocks] == ["heading1", "math", "blank"]


def test_wrapped_paragraphs_and_utf16_offsets(tmp_path: Path, engine: str) -> None:
    content = INTRO + '<w:sdt><w:sdtContent><w:p><w:r><w:t>😀</w:t><w:tab/></w:r><w:r><w:rPr><w:i/></w:rPr><w:t>Z</w:t></w:r></w:p></w:sdtContent></w:sdt>'
    block = convert(document(tmp_path, content), engine)["blocks"][1]
    assert block["text"] == "😀\tZ"
    assert block["runs"] == [{"start": 3, "end": 4, "italic": True}]


def test_consecutive_tables_keep_separate_locations(tmp_path: Path, engine: str) -> None:
    table = '<w:tbl><w:tr><w:tc><w:p><w:r><w:t>skip</w:t></w:r></w:p></w:tc></w:tr></w:tbl>'
    blocks = convert(document(tmp_path, INTRO + table + table), engine)["blocks"]
    assert [block["role"] for block in blocks] == ["heading1", "table_gap", "table_gap"]
    assert [block["text"] for block in blocks[1:]] == ["   ", "   "]


def test_tables_separated_by_ignored_blank_keep_locations(tmp_path: Path, engine: str) -> None:
    table = '<w:tbl><w:tr><w:tc><w:p><w:r><w:t>skip</w:t></w:r></w:p></w:tc></w:tr></w:tbl>'
    blocks = convert(document(tmp_path, INTRO + table + '<w:p/>' + table), engine)["blocks"]
    assert [block["text"] for block in blocks[1:]] == ["   ", "   "]


def test_bat_reports_failure_and_preserves_literal_paths(tmp_path: Path) -> None:
    # Given: literal brackets, %, ! and spaces, and a missing second input.
    path = document(tmp_path, INTRO + '<w:p><w:r><w:t>正文</w:t></w:r></w:p>')
    env = dict(os.environ, W2ID_NO_PAUSE="1")
    # When: running the actual drag/drop batch with a partial failure.
    result = subprocess.run(["cmd.exe", "/d", "/c", str(EXTRACTOR / "Word转JSON-拖这里.bat"), str(path), str(tmp_path / "missing.docx")], capture_output=True, env=env, timeout=30)
    # Then: successful input produces JSON and the batch exposes the failure.
    assert path.with_suffix(".json").exists()
    assert result.returncode != 0


def test_install_bat_updates_both_aliases_and_backs_up(tmp_path: Path) -> None:
    panel = tmp_path / "appdata/Adobe/InDesign/Version 15.0-J/zh_CN/Scripts/Scripts Panel"
    panel.mkdir(parents=True)
    (panel / "0文章.jsx").write_text("old", encoding="utf-8")
    target = panel / "期刊文章自动排版系统"
    target.mkdir()
    (target / "0文章.jsx").write_text("old-system", encoding="utf-8")
    env = dict(os.environ, W2ID_NO_PAUSE="1", APPDATA=str(tmp_path / "appdata"), LOCALAPPDATA=str(tmp_path / "local"))
    result = subprocess.run(["cmd.exe", "/d", "/c", str(ROOT / "2-导入_InDesign/安装脚本到InDesign-双击我.bat")], capture_output=True, env=env, timeout=30)
    assert result.returncode == 0, result.stderr.decode("utf-8", errors="replace")
    source = (ROOT / "2-导入_InDesign/import_word_article_to_indesign.jsx").read_bytes()
    for name in ("0文章.jsx", "import_word_article_to_indesign.jsx"):
        assert (target / name).read_bytes() == source
    assert (panel / "0文章.jsx").read_text(encoding="utf-8") == "old"
    for name in ("journal_layout_rules.jsxinc", "journal_prepreview_gate.jsxinc", "journal_bottom_plan.jsxinc", "journal_layout_and_check.jsx"):
        assert (target / name).read_bytes() == (ROOT / "2-导入_InDesign" / name).read_bytes()
    backups = list((tmp_path / "local/JournalArticleTypesetting/backups").rglob("0文章.jsx"))
    assert len(backups) == 1
    assert backups[0].read_text(encoding="utf-8") == "old-system"


class ExtractionRegression(unittest.TestCase):
    def test_conversion_engines(self) -> None:
        for engine in ("powershell", "python"):
            for scenario in (
                test_hyperlink_and_nested_runs_keep_text_and_offsets,
                test_inline_objects_and_math_keep_multiple_locations_and_offsets,
                test_front_matter_math_does_not_leak_and_body_math_is_located,
                test_wrapped_paragraphs_and_utf16_offsets,
                test_consecutive_tables_keep_separate_locations,
                test_tables_separated_by_ignored_blank_keep_locations,
            ):
                with self.subTest(engine=engine, scenario=scenario.__name__), tempfile.TemporaryDirectory() as directory:
                    scenario(Path(directory), engine)
            for caption in (False, True):
                with self.subTest(engine=engine, caption=caption), tempfile.TemporaryDirectory() as directory:
                    test_skipped_tables_have_one_location_without_content(Path(directory), engine, caption)

    def test_batch_entry(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            test_bat_reports_failure_and_preserves_literal_paths(Path(directory))

    def test_install_entry(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            test_install_bat_updates_both_aliases_and_backs_up(Path(directory))


if __name__ == "__main__":
    unittest.main()
