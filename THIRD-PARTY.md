# Third-party software

The macOS app uses only Apple's frameworks (SwiftUI, AppKit, PDFKit, Core
Graphics) and bundles no third-party code.

The Windows app needs the libraries listed in `windows/requirements.txt`. They are
installed from PyPI when the app first starts. None of them is included in this
repository, and each keeps its own licence.

The code in this repository is © 2026 Denys Baranovskyi, all rights reserved.
