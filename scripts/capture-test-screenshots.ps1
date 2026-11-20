param(
    [string]$Filter = "UT_*.test.ts",
    [string]$OutputDir = "screenshots",
    [string]$WindowTitlePattern = "letus-plant",
    [int]$DelayAfterOpenMs = 700,
    [int]$DelayAfterRunMs = 1800
)

$ErrorActionPreference = "Stop"

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

Add-Type @"
using System;
using System.Runtime.InteropServices;

public class Win32Window {
    [DllImport("user32.dll")]
    public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);

    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

    public struct RECT {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }
}
"@

function Escape-SendKeys([string]$text) {
    return ($text -replace '([+^%~(){}\[\]])', '{$1}')
}

$repoRoot = (Get-Location).Path
$testsPath = Join-Path $repoRoot "tests"
$outPath = Join-Path $repoRoot $OutputDir

if (-not (Test-Path $testsPath)) {
    throw "Tests folder not found at $testsPath. Run this script from the repository root."
}

New-Item -ItemType Directory -Path $outPath -Force | Out-Null

$testFiles = Get-ChildItem -Path $testsPath -Filter $Filter | Sort-Object Name
if ($testFiles.Count -eq 0) {
    throw "No test files matched '$Filter' in $testsPath."
}

$proc = Get-Process |
    Where-Object { $_.MainWindowHandle -ne [IntPtr]::Zero -and $_.MainWindowTitle -match $WindowTitlePattern } |
    Select-Object -First 1

if (-not $proc) {
    throw "Could not find an open Antigravity window matching '$WindowTitlePattern'. Make sure the workspace is open."
}

$ideCli = $null
foreach ($candidate in @("agy", "code")) {
    $cmd = Get-Command $candidate -ErrorAction SilentlyContinue
    if ($cmd) {
        $ideCli = $cmd.Source
        break
    }
}

Write-Host "Found window: $($proc.MainWindowTitle)" -ForegroundColor Cyan
Write-Host "Found $($testFiles.Count) test file(s). Starting in 3 seconds — do not touch mouse/keyboard..." -ForegroundColor Yellow
Start-Sleep -Seconds 3

$hwnd = $proc.MainWindowHandle
[Win32Window]::ShowWindow($hwnd, 9) | Out-Null
[Win32Window]::SetForegroundWindow($hwnd) | Out-Null
Start-Sleep -Milliseconds 400

$index = 0
foreach ($file in $testFiles) {
    $index++
    $relPath = "tests/$($file.Name)"
    $baseName = $file.BaseName -replace '\.test$', ''
    $pngPath = Join-Path $outPath "$baseName.png"

    # 1. Open the test file in the editor
    if ($ideCli) {
        & $ideCli -r $file.FullName | Out-Null
        Start-Sleep -Milliseconds $DelayAfterOpenMs
    } else {
        [Win32Window]::SetForegroundWindow($hwnd) | Out-Null
        [System.Windows.Forms.SendKeys]::SendWait("^p")
        Start-Sleep -Milliseconds 300
        [System.Windows.Forms.SendKeys]::SendWait((Escape-SendKeys $relPath))
        Start-Sleep -Milliseconds 300
        [System.Windows.Forms.SendKeys]::SendWait("{ENTER}")
        Start-Sleep -Milliseconds $DelayAfterOpenMs
    }

    # 2. Focus the integrated terminal via Command Palette (never toggles it closed)
    [Win32Window]::SetForegroundWindow($hwnd) | Out-Null
    [System.Windows.Forms.SendKeys]::SendWait("^+p")
    Start-Sleep -Milliseconds 300
    [System.Windows.Forms.SendKeys]::SendWait("Terminal: Focus Terminal")
    Start-Sleep -Milliseconds 250
    [System.Windows.Forms.SendKeys]::SendWait("{ENTER}")
    Start-Sleep -Milliseconds 300

    # 3. Clear terminal and run the single test file
    $cmdText = "cls; node --test $relPath"
    [System.Windows.Forms.SendKeys]::SendWait((Escape-SendKeys $cmdText))
    [System.Windows.Forms.SendKeys]::SendWait("{ENTER}")
    Start-Sleep -Milliseconds $DelayAfterRunMs

    # 4. Capture the Antigravity window screenshot
    $rect = New-Object Win32Window+RECT
    [Win32Window]::GetWindowRect($hwnd, [ref]$rect) | Out-Null
    $width = $rect.Right - $rect.Left
    $height = $rect.Bottom - $rect.Top

    if ($width -le 0 -or $height -le 0) {
        throw "Invalid window dimensions ($width x $height). Make sure the Antigravity window is not minimized."
    }

    $bmp = New-Object System.Drawing.Bitmap $width, $height
    $graphics = [System.Drawing.Graphics]::FromImage($bmp)
    $graphics.CopyFromScreen($rect.Left, $rect.Top, 0, 0, $bmp.Size)
    $bmp.Save($pngPath, [System.Drawing.Imaging.ImageFormat]::Png)
    $graphics.Dispose()
    $bmp.Dispose()

    Write-Host "[$index/$($testFiles.Count)] Saved $pngPath" -ForegroundColor Green
}

Write-Host "Done! All screenshots saved to $outPath" -ForegroundColor Cyan
