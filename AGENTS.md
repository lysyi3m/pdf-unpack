# PDF Unpack — working rules for coding agents

Native macOS app that opens a PDF — password-protected or not — and extracts the files embedded
inside it, with Quick Look preview, save, drag-out and Finder integration.

## Ground rules

Shared by `recogs`, `time-strip` and `pdf-unpack`. Where a repo-specific section below
contradicts a rule here, the repo-specific rule wins — and say so when you notice it.

- **XcodeGen owns the project.** `project.yml` is the source of truth. Never hand-edit the
  generated `.xcodeproj`. Never commit it, `Config/*.plist` or `Config/*.entitlements`. Run
  `make generate` after every `project.yml` change.
- **The Makefile is the entry point.** Run `make` to list targets. Prefer `make test` and
  `make build` over hand-written `xcodebuild` lines; the Makefile carries the flags that work.
- **No third-party runtime dependencies.** Apple frameworks only. Build tooling (XcodeGen,
  anything under `tools/`) is exempt because it does not ship. If you believe a runtime
  dependency is needed, stop and ask.
- **Logic lives in the `*Kit` framework.** `Sources/Kit` is UI-free and holds the testable
  core — no `SwiftUI`, `AppKit`, `UIKit` or `WidgetKit` imports there. App and extension
  targets stay thin.
- **Tests run offline, unsigned and unhosted.** They need no network, credentials or signing.
  A test that needs any of those belongs somewhere else.
- **Secrets never enter the repo.** No tokens, keys or Team IDs in tracked files. Each repo
  states where its own secrets live.
- **Signing reads `.env`.** Set `DEVELOPMENT_TEAM` in `.env` (copy `.env.example`).
  `make generate` projects it into the git-ignored `Config/Local.xcconfig`, which
  `Config/Base.xcconfig` includes, so `xcodebuild` and ⌘R sign with the same team. Never pass
  the team on the command line or commit it.
- **One word per concept.** The Terminology section is binding for UI strings, code
  identifiers and docs alike. Do not introduce synonyms for variety.

## Stack

- SwiftUI app lifecycle with AppKit where needed, macOS 26+, Swift 6 language mode. No iOS target.
- Apple frameworks only: SwiftUI, AppKit, CoreGraphics (CGPDF), Quartz/QuickLookUI,
  UniformTypeIdentifiers, Foundation.
- Two product targets: `PDFUnpackKit` (`Sources/Kit`, UI-free core) and `PDF Unpack`
  (`Sources/App`, the SwiftUI app). `PDFUnpackTests` covers the core.
- Tooling, not shipped: XcodeGen for the project, `pikepdf` (Python) to generate fixtures.

## Terminology

- **Embedded file** — a file carried inside a PDF, from any source. `EmbeddedFile` and
  `RawEmbeddedFile` in code.
- **Portfolio** — a PDF whose purpose is to carry embedded files.
- **Owner / user password** — the two ways a PDF can be locked. Both unlock the document.

Never "attachment" for the general concept. In the PDF standard a file attachment is one
specific source — the `/FileAttachment` page annotation — so the word would name a part as the
whole.

## Invariants

1. **PDFKit cannot do the core job.** `PDFDocument` exposes no API for document-level embedded
   files, so extraction drops to the `CGPDFDocument` C API and walks catalog → `/Names` →
   `/EmbeddedFiles` by hand. Never "simplify" this back to PDFKit.
2. **Three sources, one list.** Embedded files come from document-level `/EmbeddedFiles`, page
   `/FileAttachment` annotations, and PDF 2.0 associated files (`/AF`) on the catalog and on
   pages. A file referenced from more than one place is listed once.
3. **Sanitize for disk, never for display.** PDF names can carry path separators, leading dots,
   or be empty. `Filename.sanitized` strips directory components and neutralizes `:`; the
   original name stays in the UI. Collisions get a numeric suffix before the extension, matched
   case-insensitively because typical macOS volumes are.
4. **Materialize bytes lazily.** Quick Look and drag-out need a real file on disk. `TempStore`
   defers that write until first use and removes the session directory on termination, so a
   large portfolio does not hit disk eagerly.
5. **Saving never overwrites.** Save All picks a free name rather than replacing an existing
   file.
6. Prefer `NSOpenPanel` / `NSSavePanel` over `.fileExporter` for save flows.

## Secrets

Never commit a real or sensitive PDF. Only synthetic fixtures are committable. `fixtures/real/`
and `*.private.pdf` are git-ignored — keep it that way.

## Housekeeping

- **Quote the project path** in every command — `"PDF Unpack.xcodeproj"` contains a space.
- **The app is currently unsandboxed** (`com.apple.security.app-sandbox: false`). A sandboxed
  Quick Look helper runs out of process and cannot read the temp files `TempStore` writes into
  the app container. Turning the sandbox on requires solving that first, plus
  `files.user-selected.read-write`.
- **Naming.** Display name `PDF Unpack`; code identifiers `PDFUnpack` (app struct
  `PDFUnpackApp`, temp dir prefix `PDFUnpack-<uuid>`, Services handler `openInPDFUnpack`);
  bundle id `com.mlkshkvch.pdfunpack`.
- Finder integration is declared in `project.yml`, not in code: `CFBundleDocumentTypes` gives
  *Open With*, `NSServices` gives the right-click *Open in PDF Unpack* item.
- The GUI cannot be exercised headlessly. Verify what unit tests can reach, then hand over a
  manual checklist.
- **Fixtures are generated.** `make fixtures` rebuilds `fixtures/` from
  `tools/make_fixtures.py`. The names, bytes and dates it declares are asserted by the tests;
  change both together. Commit `sample-protected.pdf` only when its contents change — its
  encryption salt makes every regeneration a binary diff. See `fixtures/README.md`.
- A missing fixture fails the tests on purpose. Never turn it back into a skip: a skip lets CI
  pass without running the extractor.
