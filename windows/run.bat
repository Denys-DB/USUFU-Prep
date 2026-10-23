@echo off
REM ---------------------------------------------------------------------------
REM  USUFU Prep - double-click to run on Windows.
REM
REM  Finds a Python it can use, installs the two libraries the app needs into a
REM  private folder beside it (.venv) the first time, then starts the app with no
REM  console window. Anything that goes wrong after that is written to
REM  satprep-error.log beside this file and shown in a dialog.
REM
REM  Plain ASCII on purpose: cmd reads this file in the console's code page, and
REM  packaging writes it with Windows line endings (package.sh).
REM ---------------------------------------------------------------------------
setlocal
cd /d "%~dp0"

set "NEED=Python 3.10 to 3.14"
set "OK=import sys; sys.exit(0 if (3, 10) <= sys.version_info[:2] <= (3, 14) else 1)"

REM Already set up? Then start straight away, quietly.
if exist ".venv\Scripts\python.exe" (
    ".venv\Scripts\python.exe" -c "import PySide6, fitz" >nul 2>nul
    if not errorlevel 1 goto run
)

REM The py launcher ships with the official installer. Its newest Python may be
REM one the libraries do not support yet, so a supported one is asked for by
REM name before giving up.
set "PY="
where py >nul 2>nul && (
    py -3 -c "%OK%" 2>nul && set "PY=py -3"
    if not defined PY for %%V in (3.13 3.12 3.11 3.10 3.14) do (
        if not defined PY py -%%V -c "%OK%" 2>nul && set "PY=py -%%V"
    )
)
if not defined PY (
    where python >nul 2>nul && python -c "%OK%" 2>nul && set "PY=python"
)
if defined PY goto install

REM A Python that is there but the wrong version is named, so nobody goes
REM looking for one that is not on the PATH.
set "HAVE="
set "SAY=import sys; print(*sys.version_info[:2], sep='.')"
where py >nul 2>nul && for /f "delims=" %%H in ('py -3 -c "%SAY%" 2^>nul') do set "HAVE=%%H"
if not defined HAVE where python >nul 2>nul && for /f "delims=" %%H in ('python -c "%SAY%" 2^>nul') do set "HAVE=%%H"
echo.
if defined HAVE (
    echo   USUFU Prep needs %NEED%. This computer has Python %HAVE%.
) else (
    echo   USUFU Prep needs %NEED%, and none was found on this computer.
)
echo.
echo   Get it from https://www.python.org/downloads/
echo   During setup, tick "Add Python to PATH". Then double-click run.bat again.
echo.
pause
exit /b 1

:install
echo.
echo   First run: installing the two things USUFU Prep needs.
echo   This downloads about 100 MB, once, and takes a minute or two.
echo.
%PY% -m venv .venv
if errorlevel 1 (
    echo.
    echo   Could not set up the folder USUFU Prep installs into. See the message
    echo   above, or reinstall Python from https://www.python.org/downloads/
    echo.
    pause
    exit /b 1
)
REM pip's own words go to a log: "Could not find a version that satisfies the
REM requirement" is what being offline looks like to it.
".venv\Scripts\python.exe" -m pip install --disable-pip-version-check -q -r requirements.txt > pip-install.log 2>&1
if errorlevel 1 (
    echo.
    echo   That did not work. The first start needs the internet, once, to download
    echo   the two libraries USUFU Prep is built on. Connect to the internet and
    echo   double-click run.bat again.
    echo.
    echo   What went wrong is in pip-install.log in this folder.
    echo.
    pause
    exit /b 1
)
del pip-install.log >nul 2>nul

:run
REM pythonw runs without leaving a console window behind the app. Fall back to
REM the console one if it is missing: a visible console is far better than the
REM app appearing not to start at all.
if exist ".venv\Scripts\pythonw.exe" (
    start "" ".venv\Scripts\pythonw.exe" "%~dp0main.py"
    exit /b 0
)
".venv\Scripts\python.exe" "%~dp0main.py"
if errorlevel 1 (
    echo.
    echo   USUFU Prep stopped. See satprep-error.log in this folder.
    echo.
    pause
)
exit /b 0
