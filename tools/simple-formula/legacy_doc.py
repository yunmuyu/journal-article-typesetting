from __future__ import annotations

import base64
import shutil
import subprocess
import zipfile
from contextlib import contextmanager
from pathlib import Path
from tempfile import TemporaryDirectory
from typing import Iterator


CONVERSION_TIMEOUT_SECONDS = 120
_WORD_SCRIPT = (
    "$ErrorActionPreference = 'Stop'\n"
    "$inputPath = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('__INPUT__'))\n"
    "$outputPath = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('__OUTPUT__'))\n"
    "$word = $null\n"
    "$document = $null\n"
    "try {\n"
    "    $wordType = [Type]::GetTypeFromProgID('Word.Application')\n"
    "    if ($wordType -eq $null) { throw 'Word.Application ProgID is unavailable' }\n"
    "    $word = [Activator]::CreateInstance($wordType)\n"
    "    try { $word.Visible = $false } catch {}\n"
    "    try { $word.DisplayAlerts = 0 } catch {}\n"
    "    $documents = $word.Documents\n"
    "    if ($documents -eq $null) { throw 'Word COM Documents collection is unavailable' }\n"
    "    $document = $documents.Open($inputPath, $false, $true, $false)\n"
    "    $document.SaveAs2($outputPath, 16)\n"
    "} finally {\n"
    "    if ($document -ne $null) { try { $document.Close(0) } catch {} }\n"
    "    if ($word -ne $null) { try { $word.Quit() } catch {} }\n"
    "}\n"
)


def _encoded(path: Path) -> str:
    return base64.b64encode(str(path).encode("utf-8")).decode("ascii")


def _run(command: list[str], backend: str) -> None:
    try:
        completed = subprocess.run(
            command,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=CONVERSION_TIMEOUT_SECONDS,
            check=False,
        )
    except subprocess.TimeoutExpired as error:
        raise RuntimeError(f"{backend} conversion timed out after {CONVERSION_TIMEOUT_SECONDS} seconds") from error
    except OSError as error:
        raise RuntimeError(f"{backend} converter is not available: {error}") from error
    if completed.returncode != 0:
        message = (completed.stderr or completed.stdout).strip()
        if backend == "Microsoft Word":
            message = "Microsoft Word could not automate the legacy DOC; install or repair desktop Word, or install LibreOffice. Details: " + (message or "unknown error")
        raise RuntimeError(f"{backend} conversion failed: {message or 'unknown error'}")


def _convert_with_soffice(input_path: Path, output_path: Path, executable: str) -> None:
    _run(
        [
            executable,
            "--headless",
            "--convert-to",
            "docx",
            "--outdir",
            str(output_path.parent),
            str(input_path),
        ],
        "LibreOffice",
    )


def _convert_with_word(input_path: Path, output_path: Path) -> None:
    script = _WORD_SCRIPT.replace("__INPUT__", _encoded(input_path)).replace("__OUTPUT__", _encoded(output_path))
    _run(
        [
            shutil.which("powershell.exe") or "powershell.exe",
            "-NoProfile",
            "-NonInteractive",
            "-ExecutionPolicy",
            "Bypass",
            "-Command",
            script,
        ],
        "Microsoft Word",
    )


def _legacy_contains_equation(input_path: Path) -> bool:
    data = input_path.read_bytes()
    markers = (b"Equation Native", b"Equation.DSMT", b"Equation.3", b"Equation.2")
    return any(marker in data or marker.decode("ascii").encode("utf-16le") in data for marker in markers)


def _converted_contains_formula(output_path: Path) -> bool:
    try:
        with zipfile.ZipFile(output_path) as document:
            for name in document.namelist():
                if not name.startswith("word/") or not name.endswith(".xml"):
                    continue
                payload = document.read(name)
                if b"oMath" in payload or any(marker in payload for marker in (b"Equation.DSMT", b"Equation.3", b"Equation.2")):
                    return True
    except (OSError, zipfile.BadZipFile, KeyError):
        return False
    return False


def convert_legacy_doc(input_path: Path, output_path: Path) -> None:
    if not input_path.is_file():
        raise RuntimeError(f"input legacy DOC does not exist: {input_path}")
    executable = shutil.which("soffice") or shutil.which("libreoffice")
    if executable:
        try:
            _convert_with_soffice(input_path, output_path, executable)
        except RuntimeError as error:
            try:
                _convert_with_word(input_path, output_path)
            except RuntimeError as word_error:
                raise RuntimeError(f"LibreOffice failed ({error}); Microsoft Word fallback failed ({word_error})") from word_error
        if _legacy_contains_equation(input_path) and not _converted_contains_formula(output_path):
            try:
                _convert_with_word(input_path, output_path)
            except RuntimeError as word_error:
                raise RuntimeError(
                    "LibreOffice produced a DOCX without recognizable formula objects; "
                    f"Microsoft Word fallback failed: {word_error}"
                ) from word_error
    else:
        _convert_with_word(input_path, output_path)
    if not output_path.is_file() or output_path.stat().st_size == 0:
        raise RuntimeError("the converter reported success but did not create a non-empty DOCX")


@contextmanager
def prepared_input(input_path: Path) -> Iterator[Path]:
    if input_path.suffix.lower() != ".doc":
        yield input_path
        return
    with TemporaryDirectory(prefix="mathtype-doc-convert-") as temporary_directory:
        converted_path = Path(temporary_directory) / f"{input_path.stem}.docx"
        convert_legacy_doc(input_path, converted_path)
        yield converted_path
