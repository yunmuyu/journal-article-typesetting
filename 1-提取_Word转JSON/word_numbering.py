"""Materialize direct OOXML decimal list labels; reject unsupported definitions."""
from __future__ import annotations

import re
import xml.etree.ElementTree as ET
from zipfile import ZipFile

W = '{http://schemas.openxmlformats.org/wordprocessingml/2006/main}'


class UnsupportedNumberingError(RuntimeError):
    """Numbering cannot be recovered without guessing."""


class WordNumbering:
    def __init__(self, archive: ZipFile) -> None:
        self.root = ET.fromstring(archive.read('word/numbering.xml')) if 'word/numbering.xml' in archive.namelist() else ET.Element('empty')
        self.counts: dict[str, dict[int, int]] = {}
        self.styles = ET.fromstring(archive.read('word/styles.xml')) if 'word/styles.xml' in archive.namelist() else ET.Element('empty')

    @staticmethod
    def value(element: ET.Element, name: str, default: str) -> str:
        child = element.find(W + name)
        return default if child is None else child.get(W + 'val', default)

    def prefix(self, paragraph: ET.Element) -> str:
        props = paragraph.find(W + 'pPr/' + W + 'numPr')
        if props is None:
            style_node = paragraph.find(W + 'pPr/' + W + 'pStyle')
            style_id = '' if style_node is None else style_node.get(W + 'val', '')
            seen: set[str] = set()
            while style_id and style_id not in seen:
                seen.add(style_id)
                style = next((s for s in self.styles.findall(W + 'style') if s.get(W + 'styleId') == style_id), None)
                if style is None:
                    break
                props = style.find(W + 'pPr/' + W + 'numPr')
                if props is not None:
                    break
                style_id = self.value(style, 'basedOn', '')
            if props is None:
                return ''
        identity = self.value(props, 'numId', '0')
        if identity == '0':
            return ''
        level = int(self.value(props, 'ilvl', '0'))
        instance = next((n for n in self.root.findall(W + 'num') if n.get(W + 'numId') == identity), None)
        if instance is None:
            raise UnsupportedNumberingError('NUMBERING_INSTANCE_MISSING ' + identity)
        abstract = self.value(instance, 'abstractNumId', '')
        definition = next((n for n in self.root.findall(W + 'abstractNum') if n.get(W + 'abstractNumId') == abstract), None)
        if definition is None:
            raise UnsupportedNumberingError('NUMBERING_DEFINITION_MISSING ' + abstract)
        levels = {int(n.get(W + 'ilvl', '-1')): n for n in definition.findall(W + 'lvl')}
        if level not in levels:
            raise UnsupportedNumberingError('NUMBERING_LEVEL_MISSING')
        for override in instance.findall(W + 'lvlOverride'):
            if override.find(W + 'lvl') is not None:
                replacement = override.find(W + 'lvl')
                if replacement is not None:
                    levels[int(override.get(W + 'ilvl', '-1'))] = replacement
        counters = self.counts.setdefault(identity, {})
        current = levels[level]
        if self.value(current, 'numFmt', '') != 'decimal' or current.find(W + 'lvlRestart') is not None:
            raise UnsupportedNumberingError('NUMBERING_FORMAT_OR_RESTART_UNSUPPORTED')
        start = int(self.value(current, 'start', '1'))
        for override in instance.findall(W + 'lvlOverride'):
            if int(override.get(W + 'ilvl', '-1')) == level:
                start = int(self.value(override, 'startOverride', str(start)))
        counters[level] = counters.get(level, start - 1) + 1
        for deeper in list(counters):
            if deeper > level:
                del counters[deeper]
        template = self.value(current, 'lvlText', '')
        def replace(match: re.Match[str]) -> str:
            index = int(match[1]) - 1
            if index not in levels or self.value(levels[index], 'numFmt', '') != 'decimal':
                raise UnsupportedNumberingError('NUMBERING_PLACEHOLDER_UNSUPPORTED')
            return str(counters.get(index, int(self.value(levels[index], 'start', '1'))))
        label = re.sub(r'%([1-9])', replace, template)
        if not label:
            raise UnsupportedNumberingError('NUMBERING_LABEL_EMPTY')
        return label + ' '

    def materialize(self, root: ET.Element) -> None:
        """Insert visible labels into an in-memory XML tree, never the DOCX."""
        for paragraph in root.iter(W + 'p'):
            prefix = self.prefix(paragraph)
            if prefix:
                run = ET.Element(W + 'r')
                text = ET.SubElement(run, W + 't')
                text.set('{http://www.w3.org/XML/1998/namespace}space', 'preserve')
                text.text = prefix
                paragraph.insert(1 if paragraph.find(W + 'pPr') is not None else 0, run)
