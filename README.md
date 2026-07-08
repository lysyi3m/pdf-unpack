# PDF Unpack

A tiny native macOS app for extracting the files embedded inside a PDF — the
attachments in a PDF portfolio (`/EmbeddedFiles`), including password-protected
documents. Preview them with Quick Look, save them out, drag them to Finder, or
share them — no third-party dependencies, Apple frameworks only.

<p align="center">
  <img src="assets/drop-screen.png" alt="Drop a PDF to open it" width="49%">
  <img src="assets/file-list.png" alt="Embedded files listed" width="49%">
</p>

## Features

- **Open any PDF** — drag-and-drop, click to choose, ⌘O, or Finder's *Open With* / *Services*.
- **Password-protected PDFs** — unlock with the user or owner password.
- **List embedded files** with name, size, and modification date.
- **Quick Look** — press Space (or ⌘Y) for the full macOS preview; ←/→ walk the list.
- **Save** a file, **Save All…** to a folder (never overwrites existing files), or **Share** via the native share sheet.
- **Drag out** any row straight to Finder or the Desktop.

## Requirements

- macOS 15 (Sequoia) or later
- Xcode 16+ (to build)

## Build & run

```bash
brew install xcodegen        # one-time
xcodegen generate            # generates "PDF Unpack.xcodeproj"
open "PDF Unpack.xcodeproj"  # then select a signing team and press ⌘R
```

The Xcode project is generated from [`project.yml`](project.yml) — it is
gitignored and must not be hand-edited.

## How it works

PDFKit's `PDFDocument` can unlock and render a PDF but exposes **no** API for
document-level embedded files. Those live in the catalog's
`/Names → /EmbeddedFiles` name tree, reachable only through the lower-level
`CGPDFDocument` C API. That name-tree walk — the one genuinely tricky part — is
isolated in the UI-free, unit-tested `PDFUnpackKit` framework.

## Project structure

| Path | Purpose |
| --- | --- |
| `Sources/Kit/` | `PDFUnpackKit` — UI-free core: CGPDF extractor, PDF date parsing, models, filename hygiene |
| `Sources/App/` | The SwiftUI app (imports `PDFUnpackKit`) |
| `Tests/` | Unit tests (`@testable import PDFUnpackKit`) |
| `tools/` | `make_fixture.py` — pikepdf test-fixture generator (not shipped) |
| `fixtures/` | `sample-protected.pdf` — synthetic test fixture (password: `test123`) |

## Testing

```bash
python3 -m pip install pikepdf   # one-time, to (re)generate the fixture
python3 tools/make_fixture.py    # writes fixtures/sample-protected.pdf
xcodebuild test -project "PDF Unpack.xcodeproj" -scheme "PDF Unpack" \
  -destination 'platform=macOS'
```

## Scope

v1 handles document-level `/EmbeddedFiles` attachments. Page-level
`/FileAttachment` annotations and PDF 2.0 `/AF` associated files are out of
scope; the app shows a clean empty state when a PDF has no embedded files.

## License

MIT — see [LICENSE](LICENSE).
