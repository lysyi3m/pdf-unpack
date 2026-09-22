# Test fixtures

Synthetic PDFs that `PDFUnpackTests` read. Every file here is generated — none is a real
document. Regenerate them with `make fixtures`, which runs
[`tools/make_fixtures.py`](../tools/make_fixtures.py) with a pinned `pikepdf`.

| Fixture | Password | Contents | Tested by |
| --- | --- | --- | --- |
| `sample-protected.pdf` | `test123` (user and owner) | AES-256 encrypted. Three document-level embedded files: `hello.txt`, `data.csv`, `pixel.png`, each dated 2024-01-15 10:30:00 UTC. | `EmbeddedFileExtractorTests` |
| `sample-mixed.pdf` | none | One file in each place a PDF can hold one: `/EmbeddedFiles`, a page `/FileAttachment` annotation, catalog `/AF` and page `/AF`. `shared.txt` and `dup.txt` appear twice to cover both de-duplication paths; six unique files. | `MixedSourcesTests` |

The file names, bytes and dates are a contract: the generator declares them, and the tests
assert them. Change both together.

`sample-mixed.pdf` regenerates byte for byte. `sample-protected.pdf` does not — AES-256 salts
every save — so regenerating it produces a diff even when nothing changed. Commit it only when
its contents change.

Never commit a real PDF. Put one you want to try under `fixtures/real/` or name it
`*.private.pdf`; both are git-ignored.
