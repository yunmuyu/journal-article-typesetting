from __future__ import annotations

from math_text import TextPart


OPENING_DELIMITERS = frozenset(("(", "[", "{", "（", "［", "｛"))


def normalize_semantic_roles(parts: list[TextPart]) -> list[TextPart]:
    output = list(parts)
    index = 0
    while index < len(output):
        part = output[index]
        if part.script is None and part.text.isascii() and part.text.isalpha():
            end = index
            while end < len(output) and output[end].script is None and output[end].text.isascii() and output[end].text.isalpha():
                end += 1
            word = "".join(item.text for item in output[index:end])
            next_text = output[end].text if end < len(output) else ""
            previous_text = output[index - 1].text if index else ""
            function_call = len(word) > 1 and next_text in OPENING_DELIMITERS
            numeric_unit = previous_text.isdigit()
            if function_call or numeric_unit:
                output[index:end] = [TextPart(item.text, False, item.script) for item in output[index:end]]
            index = end
            continue
        if part.script == "subscript" and part.text.isascii() and part.text.isalpha():
            end = index
            while end < len(output) and output[end].script == "subscript" and output[end].text.isascii() and output[end].text.isalpha():
                end += 1
            if end - index >= 3:
                output[index:end] = [TextPart(item.text, False, item.script) for item in output[index:end]]
            index = end
            continue
        index += 1
    return output
