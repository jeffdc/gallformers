"""Text extraction from PDFs, URLs, and plain text files."""

from pathlib import Path

import pymupdf4llm
import trafilatura


def extract_text(input_path: str) -> str:
    """Extract text from a PDF, URL, or plain text file.

    Detection rules:
    - Paths ending in .pdf are treated as PDF files.
    - Paths starting with http:// or https:// are treated as URLs.
    - Everything else is read as a plain text file.

    Returns the extracted text as a string.

    Raises:
        FileNotFoundError: If a plain text file does not exist.
        RuntimeError: If URL fetch or extraction fails.
    """
    if input_path.lower().endswith(".pdf"):
        return _extract_pdf(input_path)
    elif input_path.startswith("http://") or input_path.startswith("https://"):
        return _extract_url(input_path)
    else:
        return _extract_plain_text(input_path)


def _extract_pdf(path: str) -> str:
    result = pymupdf4llm.to_markdown(path)
    if isinstance(result, list):
        # pymupdf4llm can return a list of page dicts; join the text content
        return "\n\n".join(str(page.get("text", "")) for page in result)
    return result


def _extract_url(url: str) -> str:
    downloaded = trafilatura.fetch_url(url)
    if downloaded is None:
        raise RuntimeError(f"Failed to fetch URL: {url}")

    text = trafilatura.extract(downloaded, output_format="markdown")
    if text is None:
        raise RuntimeError(f"Failed to extract content from URL: {url}")

    return text


def _extract_plain_text(path: str) -> str:
    p = Path(path)
    if not p.exists():
        raise FileNotFoundError(f"File not found: {path}")
    return p.read_text()
