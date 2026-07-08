# PDF Unpack

A tiny native **macOS** app that opens a (possibly password-protected) PDF and
extracts the files embedded inside it (PDF portfolio / `/EmbeddedFiles`), with
inline Quick Look preview, save, drag-out, and Finder integration.

No third-party runtime dependencies — Apple frameworks only (SwiftUI, AppKit,
CoreGraphics/CGPDF, Quartz/QuickLook, UniformTypeIdentifiers, Foundation).

Requires **macOS 15** (Sequoia) or later.

## Why CGPDF and not PDFKit

`PDFDocument` can unlock passwords and render pages, but exposes **no** API for
document-level embedded files. Those live in the catalog's
`/Names → /EmbeddedFiles` name tree, reachable only through the lower-level
`CGPDFDocument` C API. That name-tree walk is the one hard part of the app and
lives, fully unit-tested, in `PDFUnpackKit`.

## Layout

```
Sources/Kit/     PDFUnpackKit — UI-free core (extractor, PDF date, models, filename hygiene)
Sources/App/     PDF Unpack   — the SwiftUI app (imports PDFUnpackKit)
Tests/           PDFUnpackTests — @testable import PDFUnpackKit
tools/           make_fixture.py — pikepdf fixture generator (tooling only, not shipped)
fixtures/        sample-protected.pdf — synthetic test fixture (password: test123)
project.yml      XcodeGen project spec (source of truth for the .xcodeproj)
```

The three targets and their split are defined in `project.yml`. **Do not
hand-edit the generated `.xcodeproj`** — it's gitignored and regenerated.

## Build / test / run

One-time setup:

```bash
brew install xcodegen
python3 -m pip install pikepdf     # only needed to (re)generate the fixture
```

Generate the fixture and project, then build/test:

```bash
python3 tools/make_fixture.py      # writes fixtures/sample-protected.pdf (password: test123)
xcodegen generate                  # creates "PDF Unpack.xcodeproj" (note the space)

# Build (no signing needed)
xcodebuild -project "PDF Unpack.xcodeproj" -scheme "PDF Unpack" build CODE_SIGNING_ALLOWED=NO

# Unit tests (the extraction core)
xcodebuild test -project "PDF Unpack.xcodeproj" -scheme "PDF Unpack" \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
```

> The generated project name contains a **space** (`PDF Unpack.xcodeproj`), so
> quote it in every `xcodebuild` command.

**Running the GUI** is done from Xcode: `open "PDF Unpack.xcodeproj"`, pick your
Team under *Signing & Capabilities* (a free personal Apple ID team is fine), then
press ⌘R. Finder integration (Open-With / Services) needs a signed build
registered with LaunchServices, which the Xcode run handles.

## Manual test checklist

Run against `fixtures/sample-protected.pdf` (password: `test123`):

- [ ] Drop the PDF onto the window (or click the empty-state drop zone) → password sheet → `test123` unlocks → 3 files listed
- [ ] Wrong password → inline error, retry works
- [ ] Select a row and press **Space** (or the toolbar eye / ⌘Y) → Quick Look panel opens; ←/→ walk the list
- [ ] Right-click a row ▸ Save… → bytes match original
- [ ] Save All… → all items land in the chosen folder (collisions deduped)
- [ ] Drag a row to the Desktop → file appears
- [ ] Right-click a PDF in Finder ▸ Open With ▸ PDF Unpack → app opens it
- [ ] Right-click ▸ Services ▸ *Open in PDF Unpack* → app opens it
- [ ] A PDF with no attachments → clean "No Embedded Files" empty state, no crash

## Scope

v1 handles document-level `/EmbeddedFiles` only. Page-level `/FileAttachment`
annotations and PDF 2.0 `/AF` associated files are out of scope; the app shows a
graceful empty state for those.
