# USUFU Prep — Windows

The same app as the macOS version, in Python and Qt. It reads the same College
Board question-bank PDFs, keeps progress the same way, and its exported review
PDFs open in the macOS version and the other way round.

## Running it

Install Python 3.10 to 3.14 (tick **Add Python to PATH** in the installer), then
double-click **`run.bat`**. The first start makes a private `.venv` folder beside
it and installs what the app needs from `requirements.txt`; that start needs the
internet, once. If it will not start, `satprep-error.log` appears beside
`run.bat` and says why.

From a terminal, in a virtual environment: `pip install -r requirements.txt`,
then `python main.py`.

Progress, plans and imported sets are kept under `%APPDATA%\SAT Prep`, not next
to the app. Settings › Students › **Export**, then **Import** on the other
computer, moves a student.

## How it differs from the macOS version

Very little. The parsing rules, grading, selection, progress model and export
format are the same. Two things a student can notice:

- **Reminders** arrive only while the app is open (the plan window says so); the
  Mac schedules real notifications that arrive either way.
- **Learn's diagrams.** Learn names eleven; this version draws three of them (the
  reference sheet and the two supplied figures, similar and special right
  triangles). The other eight are drawn in code on the Mac, so those articles
  stand on their words alone.

## Files

| File | Role |
| --- | --- |
| `main.py` | Entry point |
| `satprep/pdfparse.py` | Reads the PDF: positioned text, artwork bounds, rasterising |
| `satprep/core.py` | Questions, banks, sessions, grading, progress, storage |
| `satprep/export.py` | The missed-questions PDF, and reading one back in |
| `satprep/ui.py` | The test screen |
| `satprep/home.py` | Import, study setup, and results |
| `satprep/reference.py` | The Math reference sheet, drawn with QPainter |
