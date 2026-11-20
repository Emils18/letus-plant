#!/usr/bin/env bash
set -euo pipefail

# If launched from inside Antigravity/VS Code's integrated terminal, detach into
# the background so the integrated terminal immediately returns to an idle prompt.
if [[ "${1:-}" != "--worker" && "${TERM_PROGRAM:-}" == "vscode" ]]; then
  nohup bash "$0" --worker "$@" >/dev/null 2>&1 </dev/null &
  echo "Detached screenshot runner (PID $!). Keep Antigravity open and do not touch mouse/keyboard..."
  exit 0
fi

if [[ "${1:-}" == "--worker" ]]; then
  shift
fi

FILTER="${1:-UT_*.test.ts}"
OUTPUT_DIR="${2:-screenshots}"
WINDOW_TITLE="${3:-letus-plant}"
DELAY_OPEN_MS="${4:-700}"
DELAY_RUN_MS="${5:-1800}"

REPO_ROOT="$(pwd)"
TESTS_DIR="$REPO_ROOT/tests"
OUT_PATH="$REPO_ROOT/$OUTPUT_DIR"

if [[ ! -d "$TESTS_DIR" ]]; then
  echo "Error: tests/ folder not found in $REPO_ROOT. Run from the repository root." >&2
  exit 1
fi

mkdir -p "$OUT_PATH"

mapfile -t TEST_FILES < <(cd "$TESTS_DIR" && ls -1 $FILTER 2>/dev/null | sort)
if [[ ${#TEST_FILES[@]} -eq 0 ]]; then
  echo "Error: No test files matched '$FILTER' in $TESTS_DIR" >&2
  exit 1
fi

IDE_CLI=""
if command -v agy >/dev/null 2>&1; then
  IDE_CLI="agy"
elif command -v code >/dev/null 2>&1; then
  IDE_CLI="code"
fi

echo "Found ${#TEST_FILES[@]} test file(s). Starting in 3 seconds — do not touch mouse/keyboard..."
sleep 3

TOTAL=${#TEST_FILES[@]}
INDEX=0

for FILE in "${TEST_FILES[@]}"; do
  INDEX=$((INDEX + 1))
  REL_PATH="tests/$FILE"
  BASE_NAME="${FILE%.test.ts}"
  WIN_PNG_PATH="$(cygpath -w "$OUT_PATH/$BASE_NAME.png")"
  WIN_FILE_PATH="$(cygpath -w "$TESTS_DIR/$FILE")"
  DONE_FILE="$REPO_ROOT/.cap_done"
  rm -f "$DONE_FILE"

  if [[ -n "$IDE_CLI" ]]; then
    "$IDE_CLI" -r "$WIN_FILE_PATH" >/dev/null 2>&1 || true
    sleep "$(awk "BEGIN { printf \"%.3f\", $DELAY_OPEN_MS / 1000 }")"
  fi

  CAP_PNG_PATH="$WIN_PNG_PATH" \
  CAP_REL_PATH="$REL_PATH" \
  CAP_FILE_NAME="$FILE" \
  CAP_DONE_PATH="$(cygpath -w "$DONE_FILE")" \
  CAP_WINDOW_TITLE="$WINDOW_TITLE" \
  CAP_IDE_CLI="$IDE_CLI" \
  CAP_DELAY_OPEN="$DELAY_OPEN_MS" \
  CAP_DELAY_RUN="$DELAY_RUN_MS" \
  powershell.exe -NoProfile -ExecutionPolicy Bypass -Command '
    Add-Type -AssemblyName System.Windows.Forms, System.Drawing
    Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Win32Cap {
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
  public struct RECT { public int Left, Top, Right, Bottom; }
}
"@
    [Win32Cap]::SetProcessDPIAware() | Out-Null
    $proc = Get-Process |
      Where-Object {
        $_.MainWindowHandle -ne [IntPtr]::Zero -and
        $_.ProcessName -match "Antigravity|Code" -and
        $_.MainWindowTitle -match $env:CAP_WINDOW_TITLE
      } |
      Select-Object -First 1
    if (-not $proc) {
      $proc = Get-Process |
        Where-Object {
          $_.MainWindowHandle -ne [IntPtr]::Zero -and
          $_.ProcessName -match "Antigravity|Code" -and
          $_.MainWindowTitle.Length -gt 0
        } |
        Select-Object -First 1
    }
    if (-not $proc) { throw "Antigravity/VS Code window not found. Make sure it is open." }
    $hwnd = $proc.MainWindowHandle
    [Win32Cap]::ShowWindow($hwnd, 9) | Out-Null
    [Win32Cap]::SetForegroundWindow($hwnd) | Out-Null
    Start-Sleep -Milliseconds 350

    if ([string]::IsNullOrEmpty($env:CAP_IDE_CLI)) {
      [System.Windows.Forms.SendKeys]::SendWait("^+p")
      Start-Sleep -Milliseconds 350
      [System.Windows.Forms.SendKeys]::SendWait("View: Focus First Editor Group")
      Start-Sleep -Milliseconds 300
      [System.Windows.Forms.SendKeys]::SendWait("{ENTER}")
      Start-Sleep -Milliseconds 300

      [System.Windows.Forms.SendKeys]::SendWait("^p")
      Start-Sleep -Milliseconds 450
      [System.Windows.Forms.SendKeys]::SendWait($env:CAP_FILE_NAME)
      Start-Sleep -Milliseconds 500
      [System.Windows.Forms.SendKeys]::SendWait("{ENTER}")
      Start-Sleep -Milliseconds ([int]$env:CAP_DELAY_OPEN)
    }

    [Win32Cap]::SetForegroundWindow($hwnd) | Out-Null
    [System.Windows.Forms.SendKeys]::SendWait("^+p")
    Start-Sleep -Milliseconds 300
    [System.Windows.Forms.SendKeys]::SendWait("Terminal: Focus Terminal")
    Start-Sleep -Milliseconds 250
    [System.Windows.Forms.SendKeys]::SendWait("{ENTER}")
    Start-Sleep -Milliseconds 300

    $cmd = "clear && node --no-warnings --test --test-reporter=./tests/helpers/vitest-reporter.mjs $($env:CAP_REL_PATH) && touch .cap_done"
    [System.Windows.Forms.SendKeys]::SendWait($cmd)
    [System.Windows.Forms.SendKeys]::SendWait("{ENTER}")

    $waited = 0
    while (-not (Test-Path $env:CAP_DONE_PATH) -and $waited -lt 15000) {
      Start-Sleep -Milliseconds 100
      $waited += 100
    }
    Start-Sleep -Milliseconds 650
    if (Test-Path $env:CAP_DONE_PATH) { Remove-Item $env:CAP_DONE_PATH -Force }

    $rect = New-Object Win32Cap+RECT
    [Win32Cap]::GetWindowRect($hwnd, [ref]$rect) | Out-Null
    $w = $rect.Right - $rect.Left
    $h = $rect.Bottom - $rect.Top
    $bmp = New-Object System.Drawing.Bitmap $w, $h
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen($rect.Left, $rect.Top, 0, 0, $bmp.Size)
    $bmp.Save($env:CAP_PNG_PATH, [System.Drawing.Imaging.ImageFormat]::Png)
    $g.Dispose()
    $bmp.Dispose()
  '

  echo "[$INDEX/$TOTAL] Saved $OUT_PATH/$BASE_NAME.png"
done

echo "Done! All screenshots saved to $OUT_PATH"
