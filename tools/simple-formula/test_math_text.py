from lxml import etree

from math_text import W, normalize_math_font_slots


def test_normalization_preserves_source_formatting() -> None:
    paragraph = etree.fromstring(
        f"""<w:p xmlns:w="{W[1:-1]}">
          <w:r><w:rPr><w:rFonts w:ascii="Times New Roman" w:hAnsi="Times New Roman"
              w:eastAsiaTheme="minorEastAsia" w:hint="eastAsia"/><w:i/><w:b/>
              <w:vertAlign w:val="subscript"/><w:position w:val="-3"/>
          </w:rPr><w:t>ij</w:t></w:r>
          <w:r><w:rPr><w:rFonts w:ascii="Times New Roman"/><w:i w:val="0"/></w:rPr><w:t>[</w:t></w:r>
          <w:r><w:rPr><w:rFonts w:ascii="Times New Roman"/><w:i w:val="0"/></w:rPr><w:t>J</w:t></w:r>
          <w:r><w:t>]</w:t></w:r>
          <w:r><w:rPr><w:rFonts w:ascii="Cambria Math"/></w:rPr><w:t>普通正文2011年</w:t></w:r>
        </w:p>"""
    )
    source_properties = etree.tostring(paragraph[0].find(W + "rPr"))
    source_prose = [etree.tostring(run) for run in paragraph[1:]]
    assert normalize_math_font_slots(paragraph) == 1
    fonts = paragraph[0].find(W + "rPr").find(W + "rFonts")
    assert dict(fonts.attrib) == {W + slot: "Times New Roman" for slot in ("ascii", "hAnsi", "eastAsia", "cs")}
    properties = etree.fromstring(source_properties)
    assert [etree.tostring(node) for node in paragraph[0].find(W + "rPr")[1:]] == [
        etree.tostring(node) for node in properties[1:]
    ]
    assert [etree.tostring(run) for run in paragraph[1:]] == source_prose
    assert normalize_math_font_slots(paragraph) == 0


if __name__ == "__main__":
    test_normalization_preserves_source_formatting()
