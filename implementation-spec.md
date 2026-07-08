# PDF Unpack — Implementation Spec

A tiny native macOS app that opens a (possibly password-protected) PDF, lists the
files embedded inside it (PDF portfolio / `/EmbeddedFiles` attachments), and lets
you preview and save them. No third-party dependencies — Apple frameworks only.

> **Name:** **PDF Unpack**. Conventions used throughout this spec:
> - **Working directory / repo:** `pdf-unpack/`
> - **Xcode product & display name:** `PDF Unpack` (spaces are fine here and in the
>   window title, Services menu item, and `NSPortName`)
> - **Code identifiers** (no spaces): `PDFUnpack` — e.g. the app struct is
>   `PDFUnpackApp`, temp dir prefix `PDFUnpack-<uuid>`
> - **Bundle ID:** `com.mlkshkvch.pdfunpack` (replace `yourname`)

---

## 1. Goal & scope

**v1 must do:**

1. Main window with a **drop zone** — drop a `.pdf` onto it (also support File ▸ Open).
2. If the PDF is encrypted, show a **password sheet**; unlock with the entered password.
3. Show a **list of embedded files** (name, size, modified date, type icon).
4. **Quick Look preview** of the selected item, inline in the window.
5. **Save** button (single item) and **Save All…** (all items) via a save panel.
6. **Drag-out**: drag a row straight to Finder/Desktop to save it there.
7. **Finder integration**: right-click a PDF ▸ *Open in PDF Unpack* (Services + Open-With).

**Explicitly out of v1 (see §12 stretch goals):** page-level `/FileAttachment`
annotations, PDF 2.0 associated files (`/AF`), batch/multi-PDF, editing.

---

## 2. Target & stack

- **Platform:** macOS 14 (Sonoma) minimum. (13 works if you replace nothing;
  all APIs used are 13+, but target 14 to be safe.)
- **Language / UI:** Swift 5.9+, SwiftUI app lifecycle, AppKit where needed.
- **Frameworks:** SwiftUI, AppKit, CoreGraphics (CGPDF), Quartz / QuickLookUI,
  UniformTypeIdentifiers, Foundation. **No SPM/Cocoapods dependencies.**
- **Project:** single Xcode app target. Bundle ID e.g. `com.mlkshkvch.pdfunpack`.

Why not PDFKit: `PDFDocument` unlocks passwords and renders pages, but exposes
**no** API for document-level embedded files / portfolios. The attachments live
in the catalog's `/Names → /EmbeddedFiles` **name tree**, reachable only via the
lower-level `CGPDFDocument` C API. That's the one hard part of this app, and §4
gives you working code for it.

---

## 3. Architecture

```
PDFUnpackApp.swift            App entry, AppDelegate adaptor, open-file handling
  AppState.swift           ObservableObject: current doc, unlock state, attachments
  PDFAttachmentExtractor.swift   PURE core, no UI — CGPDF unlock + name-tree walk
  Attachment.swift         Model + temp-file materialization
  ServicesProvider.swift   NSServices handler for the Finder right-click item
Views/
  ContentView.swift        Split layout: list (left) + preview (right)
  DropView.swift           Empty-state drop zone
  PasswordSheet.swift      SecureField sheet
  AttachmentRow.swift      One row (icon, name, size, date) + .draggable
  PreviewPane.swift        NSViewRepresentable wrapping QLPreviewView
Support/
  TempStore.swift          Writes extracted bytes to temp files; cleans up on quit
  PDFDate.swift            Parses PDF "D:YYYYMMDD..." date strings
```

Keep `PDFAttachmentExtractor` UI-free and unit-testable — it's the risk center.

---

## 4. Core: `PDFAttachmentExtractor` (the crux — implement & test first)

This is reference code. It compiles against the CGPDF C API as imported into
Swift. Build and run this against a real portfolio PDF **before** writing any UI.

```swift
import CoreGraphics
import Foundation

struct RawAttachment {
    let name: String
    let size: Int
    let modDate: Date?
    let data: Data
}

enum PDFError: Error {
    case cannotOpen
    case wrongPassword
    case notUnlocked
}

final class PDFAttachmentExtractor {

    private let doc: CGPDFDocument

    init(url: URL) throws {
        guard let d = CGPDFDocument(url as CFURL) else { throw PDFError.cannotOpen }
        self.doc = d
    }

    var isEncrypted: Bool { doc.isEncrypted }
    var isUnlocked: Bool { doc.isUnlocked }

    /// CGPDF checks the password against BOTH the user and owner password,
    /// so we don't need to know which kind it is. Returns true on success.
    func unlock(password: String) -> Bool {
        if doc.isUnlocked { return true }
        return password.withCString { doc.unlockWithPassword($0) }
    }

    /// Walks catalog → /Names → /EmbeddedFiles (a PDF *name tree*).
    func extractAttachments() throws -> [RawAttachment] {
        guard doc.isUnlocked else { throw PDFError.notUnlocked }
        guard let catalog = doc.catalog else { return [] }

        var namesDict: CGPDFDictionaryRef?
        guard CGPDFDictionaryGetDictionary(catalog, "Names", &namesDict),
              let names = namesDict else { return [] }

        var efNode: CGPDFDictionaryRef?
        guard CGPDFDictionaryGetDictionary(names, "EmbeddedFiles", &efNode),
              let root = efNode else { return [] }

        var results: [RawAttachment] = []
        walkNameTree(root, into: &results)
        return results
    }

    // A name-tree node has EITHER a /Names leaf array OR a /Kids array (or both).
    private func walkNameTree(_ node: CGPDFDictionaryRef,
                              into results: inout [RawAttachment]) {
        // Leaf: /Names = [key1, filespec1, key2, filespec2, ...]
        var namesArray: CGPDFArrayRef?
        if CGPDFDictionaryGetArray(node, "Names", &namesArray), let arr = namesArray {
            let count = CGPDFArrayGetCount(arr)
            var i = 0
            while i + 1 < count {
                var filespec: CGPDFDictionaryRef?
                if CGPDFArrayGetDictionary(arr, i + 1, &filespec), let fs = filespec,
                   let att = attachment(from: fs) {
                    results.append(att)
                }
                i += 2
            }
        }
        // Intermediate: /Kids = [childNode, childNode, ...]
        var kids: CGPDFArrayRef?
        if CGPDFDictionaryGetArray(node, "Kids", &kids), let kidsArr = kids {
            for k in 0..<CGPDFArrayGetCount(kidsArr) {
                var kid: CGPDFDictionaryRef?
                if CGPDFArrayGetDictionary(kidsArr, k, &kid), let child = kid {
                    walkNameTree(child, into: &results)
                }
            }
        }
    }

    private func attachment(from filespec: CGPDFDictionaryRef) -> RawAttachment? {
        // Filename: prefer /UF (unicode), fall back to /F.
        let name = pdfText(filespec, "UF") ?? pdfText(filespec, "F") ?? "Untitled"

        // /EF embedded-file dict → /F (or /UF) is the actual file stream.
        var efDict: CGPDFDictionaryRef?
        guard CGPDFDictionaryGetDictionary(filespec, "EF", &efDict),
              let ef = efDict else { return nil }

        var stream: CGPDFStreamRef?
        if !CGPDFDictionaryGetStream(ef, "F", &stream) {
            _ = CGPDFDictionaryGetStream(ef, "UF", &stream)
        }
        guard let s = stream else { return nil }

        // CGPDFStreamCopyData applies standard filters (e.g. FlateDecode),
        // so `data` is the real file bytes for typical attachments.
        var format: CGPDFDataFormat = .raw
        guard let cf = CGPDFStreamCopyData(s, &format) else { return nil }
        let data = cf as Data

        // Optional metadata from the stream's /Params.
        var size = data.count
        var modDate: Date?
        if let sd = CGPDFStreamGetDictionary(s) {
            var params: CGPDFDictionaryRef?
            if CGPDFDictionaryGetDictionary(sd, "Params", &params), let p = params {
                var sz: CGPDFInteger = 0
                if CGPDFDictionaryGetInteger(p, "Size", &sz) { size = Int(sz) }
                if let ds = pdfText(p, "ModDate") { modDate = PDFDate.parse(ds) }
            }
        }
        return RawAttachment(name: name, size: size, modDate: modDate, data: data)
    }

    private func pdfText(_ dict: CGPDFDictionaryRef, _ key: String) -> String? {
        var strRef: CGPDFStringRef?
        guard CGPDFDictionaryGetString(dict, key, &strRef), let s = strRef,
              let cf = CGPDFStringCopyTextString(s) else { return nil }
        return cf as String
    }
}
```

**Notes for the implementer:**

- `CGPDFStringCopyTextString` handles PDFDocEncoding and UTF-16BE filenames for you.
- If `format` ever comes back `.jpegEncoded`/`.jpeg2000Encoded`, the bytes are still
  the real (JPEG) file — fine to write as-is. Attachments almost always come back `.raw`.
- If `extractAttachments()` returns empty on a file you *know* has attachments,
  it's likely a page-annotation attachment or `/AF` — out of v1 scope; log and
  show the empty state gracefully.

`PDFDate.parse` (Support/PDFDate.swift): parse `D:YYYYMMDDHHmmSSZ` /
`D:YYYYMMDDHHmmSS+HH'mm'`. Strip leading `D:`, read fixed-width components, build
`DateComponents`; return nil on malformed input. Don't over-engineer.

---

## 5. Model & temp materialization

```swift
struct Attachment: Identifiable {
    let id = UUID()
    let name: String
    let size: Int
    let modDate: Date?
    let data: Data
    /// Lazily written temp URL used for Quick Look + drag-out. See TempStore.
    var tempURL: URL?
}
```

`TempStore`:
- Session dir: `FileManager.default.temporaryDirectory/PDFUnpack-<uuid>/`.
- `materialize(_ att:) -> URL` writes `att.data` to `<sessionDir>/<sanitized name>`,
  returns the URL. Cache so repeated preview/drag reuse the same file.
- Sanitize names (strip `/`, leading dots). Handle collisions with a numeric suffix.
- Delete the session dir on `applicationWillTerminate`.

Materialize **on demand** (first preview / first drag / save), not eagerly, so a
portfolio with large attachments doesn't hit disk until needed.

---

## 6. App entry & open-file handling

```swift
@main
struct PDFUnpackApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var state = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView().environmentObject(state)
                .frame(minWidth: 720, minHeight: 460)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open…") { state.presentOpenPanel() }
                    .keyboardShortcut("o")
            }
        }
    }
}
```

`AppDelegate`:
- `application(_:open:)` (files opened via Finder / Services / Open-With) →
  forward the first PDF URL to the shared `AppState.load(url:)`.
- Register `NSApp.servicesProvider = ServicesProvider(state:)` and call
  `NSUpdateDynamicServices()` in `applicationDidFinishLaunching`.
- `applicationWillTerminate` → `TempStore.shared.cleanup()`.

`AppState` (ObservableObject) published properties:
`fileURL`, `fileName`, `needsPassword: Bool`, `unlockError: Bool`,
`attachments: [Attachment]`, `selection: Attachment.ID?`, `loadError: String?`.

`load(url:)` flow:
1. `startAccessingSecurityScopedResource()` (balance with a `stop` when replaced).
2. Build `PDFAttachmentExtractor`. On failure → `loadError`.
3. If `isEncrypted && !isUnlocked` → set `needsPassword = true`, stop here.
4. Else call `finishLoading()` → `extractAttachments()` → populate `attachments`.

`submitPassword(_:)` → `extractor.unlock(...)`; on success `needsPassword=false`
then `finishLoading()`; on failure set `unlockError=true` and keep the sheet up.

---

## 7. UI

### ContentView
`NavigationSplitView` (or `HSplitView`):
- **Empty state** (no file loaded): show `DropView` filling the window.
- **Loaded state**: left = attachment `List` (selectable), right = `PreviewPane`.
- Toolbar: file name + item count; `Save All…`; `Open…`.
- Attach `.dropDestination(for: URL.self)` at the ContentView level too, so you
  can drop a new PDF any time to replace the current one.

### DropView (empty state)
```swift
struct DropView: View {
    @EnvironmentObject var state: AppState
    @State private var targeted = false
    var body: some View {
        RoundedRectangle(cornerRadius: 16)
            .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8]))
            .foregroundStyle(targeted ? .accent : .secondary)
            .overlay {
                VStack(spacing: 10) {
                    Image(systemName: "doc.badge.plus").font(.system(size: 40))
                    Text("Drop a PDF here").font(.title3)
                    Text("or press ⌘O").foregroundStyle(.secondary)
                }
            }
            .padding(30)
            .dropDestination(for: URL.self) { urls, _ in
                guard let pdf = urls.first(where: { $0.pathExtension.lowercased() == "pdf" })
                else { return false }
                state.load(url: pdf); return true
            } isTargeted: { targeted = $0 }
    }
}
```

### PasswordSheet
`.sheet(isPresented: $state.needsPassword)` — `SecureField` bound to local
`@State password`, "Unlock" (default button, submits on Return) + "Cancel".
Show an inline error label when `state.unlockError`. Clear error on edit.

### AttachmentRow
Icon from UTType (`NSWorkspace.shared.icon(for:)` derived from the file
extension, or SF Symbol fallback), name, `ByteCountFormatter` size, formatted
`modDate`. Make each row draggable to Finder:
```swift
.draggable(att.tempURLMaterialized())   // returns a file URL (Transferable)
```
Materialize the temp file at drag time.

### PreviewPane (Quick Look, inline)
Wrap `QLPreviewView` — previews a **file on disk**, so materialize the selected
attachment first, then set `previewItem`.
```swift
import Quartz

final class PreviewItem: NSObject, QLPreviewItem {
    let previewItemURL: URL?
    init(url: URL) { previewItemURL = url }
}

struct PreviewPane: NSViewRepresentable {
    let url: URL?   // temp URL of selected attachment, or nil
    func makeNSView(context: Context) -> QLPreviewView {
        let v = QLPreviewView(frame: .zero, style: .normal) ?? QLPreviewView()
        v.autostarts = true
        return v
    }
    func updateNSView(_ v: QLPreviewView, context: Context) {
        v.previewItem = url.map { PreviewItem(url: $0) }
    }
}
```
When `state.selection` changes, materialize that attachment and pass its temp URL
to `PreviewPane`. Show a neutral placeholder when nothing is selected or the type
is not Quick-Look-previewable.

### Save / Save All
- **Save (single):** `NSSavePanel`, default filename = attachment name, write bytes.
- **Save All…:** `NSOpenPanel` with `canChooseDirectories = true` to pick a folder,
  write every attachment into it (dedupe collisions). Report count on completion.
- (Alternatively use SwiftUI `.fileExporter`; `NSSavePanel`/`NSOpenPanel` are less
  fuss for this and play nicely with sandbox powerbox.)

---

## 8. Finder / menu integration

Two low-effort mechanisms, both driven off document-type registration:

**A. Open-With (near free).** In Info.plist add `CFBundleDocumentTypes` with
`LSItemContentTypes = ["com.adobe.pdf"]`, role `Viewer`. Finder's right-click
▸ *Open With* then lists PDF Unpack automatically; the open is delivered to
`application(_:open:)`.

**B. Explicit right-click item via Services.** Info.plist:
```xml
<key>NSServices</key>
<array>
  <dict>
    <key>NSMenuItem</key>
    <dict><key>default</key><string>Open in PDF Unpack</string></dict>
    <key>NSMessage</key><string>openInPDFUnpack</string>
    <key>NSPortName</key><string>PDF Unpack</string>
    <key>NSSendFileTypes</key>
    <array><string>com.adobe.pdf</string></array>
  </dict>
</array>
```
`ServicesProvider`:
```swift
@objc func openInPDFUnpack(_ pboard: NSPasteboard,
                           userData: String?,
                           error: AutoreleasingUnsafeMutablePointer<NSString>?) {
    let urls = pboard.readObjects(forClasses: [NSURL.self]) as? [URL] ?? []
    if let pdf = urls.first(where: { $0.pathExtension.lowercased() == "pdf" }) {
        DispatchQueue.main.async { self.state.load(url: pdf) }
        NSApp.activate(ignoringOtherApps: true)
    }
}
```
The Services entry appears under right-click ▸ *Services* (and the app's Services
menu). A full **Finder Sync** extension would put an item at the top level of the
context menu but needs a separate app-extension target and more entitlements —
**not worth it for v1**; skip unless you specifically want top-level placement.

---

## 9. App config: Info.plist & entitlements

- **Sandbox:** default **on** for a clean, distributable build. Entitlements:
  - `com.apple.security.app-sandbox = YES`
  - `com.apple.security.files.user-selected.read-write = YES`
  - Use `startAccessingSecurityScopedResource()` / `stop…` around dropped &
    opened URLs. Save panels grant write access via powerbox automatically.
  - *Shortcut for a purely local personal build:* set sandbox `NO` and skip the
    security-scoped dance. Note this in the README; it's fine for local use, not
    for distribution/notarization.
- `LSMinimumSystemVersion = 14.0`.
- App Transport Security etc.: not needed (no networking).

---

## 10. Error handling & edge cases

- **Not encrypted:** skip the password sheet, go straight to listing.
- **Owner-password-only PDFs:** often already `isUnlocked` for reading — handle by
  checking `isUnlocked` before prompting.
- **Wrong password:** keep sheet up, show error, allow retry.
- **Zero attachments:** valid outcome — show an empty state ("No embedded files
  found"), not an error. Mention page-annotation/`/AF` possibility in a footnote.
- **Corrupt / non-PDF dropped:** `CGPDFDocument` init fails → friendly `loadError`.
- **Huge attachment:** materialize lazily; consider a size column so the user sees
  what they're about to preview.
- **Duplicate filenames within one portfolio:** dedupe on temp write and on Save All.
- **Weird filenames** (slashes, emoji, non-ASCII): sanitize for disk, keep original
  for display.

---

## 11. Build, run, test

1. New Xcode ▸ macOS ▸ App (SwiftUI). Set bundle ID, min target 14.
2. Drop in the files from §3. Implement `PDFAttachmentExtractor` first.
3. **Core test:** a tiny command-line harness or unit test that loads a known
   portfolio PDF, unlocks it, and prints `name / size` for each attachment.
   Verify counts and that saved bytes open correctly in their native apps.
4. Then build the UI shell around the verified core.

**Manual test checklist:**
- [ ] Drop an unencrypted portfolio → list populates.
- [ ] Drop an encrypted portfolio → sheet → correct password unlocks → list.
- [ ] Wrong password → error, retry works.
- [ ] Select item → inline Quick Look preview renders.
- [ ] Save one item → bytes match original, opens in native app.
- [ ] Save All → all items land in chosen folder, no collisions lost.
- [ ] Drag a row to Desktop → file appears.
- [ ] Right-click a PDF in Finder ▸ Services ▸ *Open in PDF Unpack* → app opens it.
- [ ] Right-click ▸ Open With ▸ PDF Unpack → app opens it.
- [ ] PDF with no attachments → clean empty state, no crash.

---

## 12. Stretch goals (v2+)

- **Page-level attachments:** scan each page's annotations for subtype
  `/FileAttachment`, pull `/FS` filespec → same `attachment(from:)` path.
- **PDF 2.0 associated files:** catalog/page/object `/AF` arrays of filespecs.
- **Recursive portfolios** (a PDF attachment that is itself a portfolio).
- **Batch mode:** drop several PDFs, aggregate all attachments.
- **Menu-bar mode:** `MenuBarExtra` quick-drop, in addition to the main window.
- **Finder Sync extension** for a top-level (not Services-submenu) context item.
- **Notarization + DMG** for sharing the app outside your machine.

---

## 13. Effort estimate

- `PDFAttachmentExtractor` + PDFDate + core test: the real work, a few focused hours.
- SwiftUI shell (drop, list, password, preview, save, drag-out): straightforward.
- Finder integration (Services + Open-With): small, mostly Info.plist.
- Total for a comfortable Swift dev: roughly a weekend, front-loaded onto the CGPDF core.
