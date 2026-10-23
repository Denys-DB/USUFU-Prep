# USUFU Prep, for judges

**USUFU Prep** is a free, offline practice app for the digital SAT and PSAT. It turns a PDF exported from the College Board's own question bank into a timed practice test laid out like the real one. It shows the results afterwards and lets a student review what they missed. It has no accounts, uses no internet and makes no score predictions.

## Opening it

**macOS (13 or later), the main route.** Unzip, and drag **USUFU Prep.app** to Applications. The app is not signed by Apple, so the first time:
1. Double-click it. macOS says it cannot verify it. Click **Done** (not Move to Trash).
2. Open **System Settings → Privacy & Security**. Scroll down to the message about "USUFU Prep" and click **Open Anyway**.
3. Click **Open Anyway** in the box that appears, and enter your password if asked. From then on it opens normally.

If that message does not appear, this command in Terminal does the same thing. It removes only the download flag:

```
xattr -dr com.apple.quarantine "/Applications/USUFU Prep.app"
```

**Windows (10 or 11), from source.** The Windows version runs from source. Install Python 3.10 to 3.14 from [python.org/downloads](https://www.python.org/downloads/) (on Windows, tick **Add Python to PATH**), then run `pip install -r requirements.txt` (this installs the libraries the app needs, from PyPI), then run **run.bat**. No Windows installer is provided.
- `run.bat` also does the pip step itself the first time, into a folder beside it. That start needs the internet once and downloads about 100 MB, which takes a minute or two. After that the app starts straight away, offline.
- Windows may warn about a file from an unknown publisher when you double-click **run.bat**; choose **Run**.

## Trying it

- **The quickest way:** drag **USUFU-Prep-Sample-Set.pdf**, which is in the zip, into the app's window. It holds 24 questions written for this demo, not College Board material, laid out like a real export.
- **With real questions:** open the free College Board **Educator Question Bank** at [satsuiteeducatorquestionbank.collegeboard.org](https://satsuiteeducatorquestionbank.collegeboard.org/). Pick SAT or PSAT and some questions, choose **Export**, and drag the PDF into the app.

Then choose a section and click **Start practice**. When you finish, the results screen shows each answer, and you can export the missed questions as a PDF.

## Good to know

- **No calculator is built in.** The real test has one; use your own, or the reference sheet in the app.
- Everything stays on the computer. The app makes no network connections; only the first run from source on Windows downloads its two libraries.
- It works in English, Ukrainian, Spanish and Portuguese (Settings).
- **The source code is available on request.**

*United States Universities For Ukraine. Not affiliated with the College Board.*
