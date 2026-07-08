#!/usr/bin/env python3
"""Generate the synthetic test fixture for PDFUnpackTests.

Produces a password-protected (password: "test123") one-page PDF that embeds
three files (.txt, .csv, .png) in the document-level /EmbeddedFiles name tree —
i.e. a minimal PDF portfolio. The contents are deterministic so the Swift tests
can assert exact filenames, sizes, and byte-for-byte round-trips.

Requires pikepdf (tooling only, not shipped in the app):
    python3 -m pip install pikepdf
    python3 tools/make_fixture.py
"""
from __future__ import annotations

import struct
import zlib
from pathlib import Path

import pikepdf

PASSWORD = "test123"
REPO_ROOT = Path(__file__).resolve().parent.parent
OUT_PATH = REPO_ROOT / "fixtures" / "sample-protected.pdf"

# A known ModDate so the tests can also exercise PDFDate.parse via the extractor.
MOD_DATE = "D:20240115103000Z"


def minimal_png() -> bytes:
    """A 1x1 opaque red PNG, built from stdlib only (no Pillow)."""
    def chunk(tag: bytes, data: bytes) -> bytes:
        return (
            struct.pack(">I", len(data))
            + tag
            + data
            + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
        )

    sig = b"\x89PNG\r\n\x1a\n"
    ihdr = struct.pack(">IIBBBBB", 1, 1, 8, 2, 0, 0, 0)  # 1x1, 8-bit, truecolor
    raw = b"\x00\xff\x00\x00"  # one scanline: filter 0 + RGB red
    idat = zlib.compress(raw)
    return sig + chunk(b"IHDR", ihdr) + chunk(b"IDAT", idat) + chunk(b"IEND", b"")


# Deterministic attachment contents. Keep these in sync with the Swift tests.
ATTACHMENTS: dict[str, bytes] = {
    "hello.txt": b"Hello, PDF Unpack!\n",
    "data.csv": b"name,value\nalpha,1\nbeta,2\n",
    "pixel.png": minimal_png(),
}


def main() -> None:
    OUT_PATH.parent.mkdir(parents=True, exist_ok=True)

    pdf = pikepdf.new()
    pdf.add_blank_page(page_size=(612, 792))

    for name, data in ATTACHMENTS.items():
        spec = pikepdf.AttachedFileSpec(
            pdf, data, filename=name, mod_date=MOD_DATE, creation_date=MOD_DATE
        )
        pdf.attachments[name] = spec

    pdf.save(
        OUT_PATH,
        encryption=pikepdf.Encryption(user=PASSWORD, owner=PASSWORD, R=6),
    )

    print(f"Wrote {OUT_PATH.relative_to(REPO_ROOT)} (password: {PASSWORD})")
    for name, data in ATTACHMENTS.items():
        print(f"  {name:12} {len(data):5} bytes")


if __name__ == "__main__":
    main()
