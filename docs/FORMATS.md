# Supported formats

Local Explorer uses the decoders built into macOS (ImageIO, AVFoundation, PDFKit, Quick
Look). It bundles no extra decoders, so what plays or renders depends on the macOS version.

**Test status.** The format *routing* (which preview each file gets, from its bytes) is
covered by unit tests that run on every platform. Actual decoding and playback is
**not yet verified on a Mac**: the column below stays "untested" until the fixture run in
`IMPLEMENTATION_REPORT.md` has been done on Apple Silicon hardware. Do not advertise a
format as supported until it is marked "verified".

## Images

| Format | Path | Expected on macOS 14+ | Status |
|---|---|---|---|
| JPEG | ImageIO | yes, with EXIF orientation | untested |
| PNG (incl. transparency) | ImageIO | yes | untested |
| HEIC / HEIF | ImageIO | yes | untested |
| GIF (animated) | NSImage + NSImageView | yes, animates | untested |
| TIFF | ImageIO | yes | untested |
| BMP | ImageIO | yes | untested |
| WebP | ImageIO | yes (macOS 11+) | untested |
| AVIF | ImageIO | macOS 13+ | untested |
| SVG | Quick Look | yes (rendered by the system generator) | untested |
| Camera RAW (CR2, CR3, NEF, ARW, DNG, ORF, RAF) | ImageIO | depends on camera model support in macOS | untested |
| PSD | ImageIO | flattened composite only | untested |

Images larger than 12,000 px on the long edge are shown as a reduced copy in the full viewer
(labelled "reduced copy"). The preview pane decodes at most 1,600 px. List cells use
QuickLookThumbnailing, never full-resolution decodes.

## Video

| Container / codec | Expected | Status |
|---|---|---|
| MP4 / MOV with H.264 | plays | untested |
| MP4 / MOV with HEVC (H.265) | plays | untested |
| MOV with ProRes | plays | untested |
| M4V (unprotected) | plays | untested |
| MP4 with AV1 | plays only on Macs with an AV1 decoder (M3 and later) | untested |
| MKV, WebM (VP8/VP9), AVI, WMV, FLV | **not supported by AVFoundation**: shows "macOS can't play this file" | untested |

## Audio

| Format | Expected | Status |
|---|---|---|
| MP3 | plays | untested |
| AAC / M4A | plays | untested |
| ALAC | plays | untested |
| WAV, AIFF, CAF | plays | untested |
| FLAC | plays (macOS 11+) | untested |
| Opus in CAF | plays | untested |
| Ogg Vorbis / Opus in Ogg, WMA | **not supported**: shows an error | untested |

## Documents

| Type | Renderer | Status |
|---|---|---|
| PDF (incl. password-protected) | PDFKit | untested |
| Plain text, Markdown, JSON, YAML, XML, CSV, logs, source code | built-in text view (UTF-8, UTF-16 with BOM, Windows-1252) | decoder unit-tested |
| RTF, DOCX, XLSX, PPTX, Pages, Numbers, Keynote | Quick Look | untested |
| Fonts (TTF, OTF, TTC) | Quick Look | untested |
| Archives, disk images, apps, unknown binaries | icon, properties and Open (no preview) | routing unit-tested |

## Recording results

To verify, put one sample of each format in a folder, open it in Gallery view, and change
"untested" to "verified" (or "fails: reason") with the macOS version and Mac model, for example
`verified (macOS 15.1, M2)`.
