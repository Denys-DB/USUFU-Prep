# USUFU Prep

A free, offline practice app for the digital SAT and PSAT, by United States
Universities For Ukraine. A student imports the PDF they export from the College
Board's own Educator Question Bank, and the app turns it into timed practice laid
out like the real test: the split passage and question panes, Mark for Review, the
answer eliminator, the reference sheet, full tests, review of missed questions,
statistics, flashcards and study plans. It works in English, Ukrainian, Spanish
and Portuguese. There is no account, no network and nothing leaves the computer.

No College Board questions are included. `demo/USUFU-Prep-Sample-Set.pdf` holds 24
original questions, laid out like an export, so the app can be tried without one.

Not affiliated with the College Board.

## What is here

| Path | What |
| --- | --- |
| `Sources/`, `Resources/` | The macOS app (Swift and SwiftUI, no outside libraries) |
| `build.sh` | Builds it: `./build.sh`, then `open "build/USUFU Prep.app"` |
| `windows/` | The Windows app (Python), started with `windows/run.bat`; see `windows/README.md` |
| `demo/` | The sample set, 24 original questions to try the app with |
| `FOR-JUDGES.md` | How to open and try the app |

## Copyright

© 2026 Denys Baranovskyi. All rights reserved. The source is published so the Congressional App Challenge can evaluate the project. No licence to copy, modify or redistribute it is granted.

The Windows app uses libraries it installs separately; see `THIRD-PARTY.md`.
