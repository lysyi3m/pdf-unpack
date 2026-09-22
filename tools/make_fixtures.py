#!/usr/bin/env python3
"""Generate the synthetic PDFs in fixtures/ that PDFUnpackTests read.

Run `make fixtures` from the repo root. It creates tools/.venv, installs the pinned pikepdf
from tools/requirements.txt, and runs this script, which rewrites both fixtures:

  fixtures/sample-protected.pdf
      Encrypted with AES-256; user and owner password are both `test123`. Carries three
      document-level embedded files, each stamped with the same creation and modification
      date. Covers unlock, extraction, byte round-trip and PDF date parsing.

  fixtures/sample-mixed.pdf
      Unencrypted. Carries a file in every place a PDF can hold one: document-level
      /EmbeddedFiles, a page /FileAttachment annotation, and PDF 2.0 associated files (/AF)
      on the catalog and on the page. Two files appear twice on purpose, to cover both
      de-duplication paths. Six unique files in total.

The file contents below are the contract with the tests: EmbeddedFileExtractorTests and
MixedSourcesTests assert these exact names, bytes and dates. Change both sides together.

sample-mixed.pdf is byte-for-byte reproducible. sample-protected.pdf is not: AES-256 uses a
random salt on every save, so its bytes change on each run while its contents stay the same.
"""
from pathlib import Path

import pikepdf
from pikepdf import Array, AttachedFileSpec, Dictionary, Encryption, Name

REPO = Path(__file__).resolve().parent.parent
FIXTURES = REPO / "fixtures"

PROTECTED_PASSWORD = "test123"
PROTECTED_DATE = "D:20240115103000Z"
PROTECTED_FILES = {
    "hello.txt": b"Hello, PDF Unpack!\n",
    "data.csv": b"name,value\nalpha,1\nbeta,2\n",
    # A valid 1x1 PNG, so Quick Look has a real image to preview.
    "pixel.png": bytes.fromhex(
        "89504e470d0a1a0a0000000d4948445200000001000000010802000000907753"
        "de0000000c49444154789c63f8cfc0000003010100c9fe92ef0000000049454e"
        "44ae426082"
    ),
}

MIXED_FILES = {
    "embedded.txt": b"document-level embedded file\n",
    "shared.txt": b"shared between EmbeddedFiles and AF\n",
    "invoice.xml": b"<invoice><total>42</total></invoice>\n",
    "annotated.txt": b"attached to a page annotation\n",
    "page-af.txt": b"page-level associated file\n",
    "dup.txt": b"identical content under two distinct filespec objects\n",
}


def make_protected() -> Path:
    out = FIXTURES / "sample-protected.pdf"
    pdf = pikepdf.new()
    pdf.add_blank_page(page_size=(612, 792))
    for name, data in PROTECTED_FILES.items():
        pdf.attachments[name] = AttachedFileSpec(
            pdf, data, filename=name, creation_date=PROTECTED_DATE, mod_date=PROTECTED_DATE
        )
    pdf.save(
        out,
        static_id=True,
        encryption=Encryption(user=PROTECTED_PASSWORD, owner=PROTECTED_PASSWORD, R=6),
    )
    return out


def make_mixed() -> Path:
    out = FIXTURES / "sample-mixed.pdf"
    pdf = pikepdf.new()
    page = pdf.add_blank_page(page_size=(612, 792))

    def spec(name: str) -> AttachedFileSpec:
        return AttachedFileSpec(pdf, MIXED_FILES[name], filename=name)

    # 1. Document-level /Names → /EmbeddedFiles.
    pdf.attachments["embedded.txt"] = spec("embedded.txt")
    shared = spec("shared.txt")
    pdf.attachments["shared.txt"] = shared
    # dup.txt: two distinct filespec objects with the same name and bytes, one here and one
    # in /AF. Object-identity de-duplication cannot collapse them; content matching must.
    pdf.attachments["dup.txt"] = spec("dup.txt")
    dup_other = spec("dup.txt")

    # 2. Catalog-level /AF: invoice.xml, the same `shared` object that is already in
    #    /EmbeddedFiles (object-identity de-duplication), and `dup_other`.
    invoice = spec("invoice.xml")
    invoice.obj[Name.AFRelationship] = Name.Data
    pdf.Root[Name.AF] = pdf.make_indirect(Array([invoice.obj, shared.obj, dup_other.obj]))

    # 3a. A page /FileAttachment annotation.
    annot = pdf.make_indirect(Dictionary(
        Type=Name.Annot,
        Subtype=Name.FileAttachment,
        Rect=Array([72, 700, 92, 720]),
        FS=spec("annotated.txt").obj,
        Contents="See attached",
    ))
    page.Annots = Array([annot])

    # 3b. A page-level /AF.
    page_af = spec("page-af.txt")
    page_af.obj[Name.AFRelationship] = Name.Supplement
    page[Name.AF] = pdf.make_indirect(Array([page_af.obj]))

    pdf.save(out, deterministic_id=True)
    return out


def main() -> None:
    FIXTURES.mkdir(exist_ok=True)
    for out in (make_protected(), make_mixed()):
        print(f"wrote {out.relative_to(REPO)}")


if __name__ == "__main__":
    main()
