#Requires -Version 7.0
<#
.SYNOPSIS
    Character Sheet Pipeline - converts RPG character sheet images/PDFs into interactive HTML.
.DESCRIPTION
    Three Claude Code agents work in a loop:
    1. Analyzer - extracts fields into a JSON spec
    2. Builder  - builds interactive HTML from the spec
    3. Tester   - opens HTML in Chrome, scores it, lists flaws
    If score < 80, feedback loops back to Builder (max 3 rounds).
.PARAMETER Path
    Path to a specific character sheet file. If omitted, processes all files in input/.
.EXAMPLE
    .\run.ps1 input\my_sheet.png
    .\run.ps1
#>
param(
    [Parameter(Position = 0)]
    [string]$Path
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$MAX_ITERATIONS = 3
$PASS_THRESHOLD = 80
$ScriptDir = $PSScriptRoot

# ── Logging helpers ──
function Write-Log    { param($Msg) Write-Host "[pipeline] $Msg" -ForegroundColor Cyan }
function Write-Ok     { param($Msg) Write-Host "[+] $Msg" -ForegroundColor Green }
function Write-Warn   { param($Msg) Write-Host "[!] $Msg" -ForegroundColor Yellow }
function Write-Fail   { param($Msg) Write-Host "[x] $Msg" -ForegroundColor Red }

# ── Process a single character sheet ──
function Process-Sheet {
    param([string]$File)

    $name = [System.IO.Path]::GetFileNameWithoutExtension($File)
    $absFile = (Resolve-Path $File).Path

    Write-Log "Processing: $name"
    Write-Log ("=" * 40)

    # ── AGENT 1: ANALYZER ──
    Write-Log "Agent 1 (Analyzer): Extracting character sheet data..."

    $analyzerPrompt = Get-Content "$ScriptDir\agents\analyzer_prompt.md" -Raw
    $specPath = "$ScriptDir\specs\$name.json"

    claude -p `
        --system-prompt $analyzerPrompt `
        --output-file $specPath `
        --max-turns 5 `
        "Analyze this character sheet image and output a complete JSON spec. Be exhaustive - every field, every section, every value. The image file is at: $absFile"

    if (-not (Test-Path $specPath)) {
        Write-Fail "Analyzer failed to produce spec for $name"
        return
    }
    Write-Ok "Spec created: specs\$name.json"

    # ── ITERATION LOOP ──
    $iteration = 0
    $passed = $false
    $score = 0
    $feedback = ""

    while ($iteration -lt $MAX_ITERATIONS) {
        $iteration++
        Write-Log "Build iteration $iteration/$MAX_ITERATIONS"

        # ── AGENT 2: BUILDER ──
        Write-Log "Agent 2 (Builder): Generating interactive HTML..."

        $specContent = Get-Content $specPath -Raw
        $builderPrompt = Get-Content "$ScriptDir\agents\builder_prompt.md" -Raw
        $buildPath = "$ScriptDir\builds\$name.html"

        $builderInput = @"
Build an interactive HTML character sheet from this spec.

SPEC:
$specContent

ORIGINAL IMAGE: $absFile
"@

        if ($feedback) {
            $builderInput += @"

TESTER FEEDBACK FROM PREVIOUS ITERATION (fix these issues):
$feedback
"@
        }

        claude -p `
            --system-prompt $builderPrompt `
            --output-file $buildPath `
            --max-turns 10 `
            $builderInput

        if (-not (Test-Path $buildPath)) {
            Write-Fail "Builder failed to produce HTML for $name (iteration $iteration)"
            continue
        }
        Write-Ok "HTML built: builds\$name.html"

        # ── AGENT 3: TESTER ──
        Write-Log "Agent 3 (Tester): Testing build quality..."

        $testerPrompt = Get-Content "$ScriptDir\agents\tester_prompt.md" -Raw
        $reportPath = "$ScriptDir\reports\${name}_report.json"
        $absBuildPath = (Resolve-Path $buildPath).Path

        claude -p `
            --system-prompt $testerPrompt `
            --output-file $reportPath `
            --max-turns 10 `
            --allowedTools "mcp__chrome-devtools" `
            "Test this character sheet build.

ORIGINAL IMAGE: $absFile
BUILT HTML FILE: $absBuildPath
SPEC: $specContent

Open the HTML file in Chrome using the DevTools MCP, visually inspect it, and compare against the original image. Output your test report as JSON."

        if (-not (Test-Path $reportPath)) {
            Write-Warn "Tester failed to produce report, using build as-is"
            break
        }

        # Parse test results
        try {
            $report = Get-Content $reportPath -Raw | ConvertFrom-Json
            $score = [int]($report.score ?? 0)
            $passedResult = $report.pass ?? $false

            if ($report.flaws) {
                $feedback = ($report.flaws | ForEach-Object {
                    "- [$($_.severity)] $($_.description): $($_.fix)"
                }) -join "`n"
            } else {
                $feedback = ""
            }
        } catch {
            Write-Warn "Could not parse test report: $_"
            $score = 0
            $passedResult = $false
            $feedback = ""
        }

        Write-Log "Score: $score/100 | Pass: $passedResult"

        if ($passedResult -eq $true -or $score -ge $PASS_THRESHOLD) {
            Write-Ok "Approved after $iteration iteration(s) with score $score"
            $passed = $true
            break
        } else {
            Write-Warn "Failed (score: $score). Flaws found:"
            $feedback -split "`n" | Select-Object -First 10 | ForEach-Object { Write-Host "  $_" }
        }
    }

    # Copy best build to output
    Copy-Item "$ScriptDir\builds\$name.html" "$ScriptDir\output\$name.html" -Force

    if ($passed) {
        Write-Ok "Final output: output\$name.html"
    } else {
        Write-Warn "Max iterations reached. Best attempt saved: output\$name.html"
    }

    Write-Host ""
}

# ── Main ──
function Main {
    Write-Log "Character Sheet Pipeline"
    Write-Log ("=" * 40)

    # Check for Claude Code
    if (-not (Get-Command claude -ErrorAction SilentlyContinue)) {
        Write-Fail "Claude Code CLI not found. Install it first: https://docs.anthropic.com/en/docs/claude-code"
        exit 1
    }

    # Process specific file or all files in input/
    if ($Path) {
        if (-not (Test-Path $Path)) {
            Write-Fail "File not found: $Path"
            exit 1
        }
        Process-Sheet -File $Path
    } else {
        $extensions = @("*.png", "*.jpg", "*.jpeg", "*.pdf", "*.webp")
        $files = @()
        foreach ($ext in $extensions) {
            $files += Get-ChildItem "$ScriptDir\input\$ext" -ErrorAction SilentlyContinue
        }

        if ($files.Count -eq 0) {
            Write-Warn "No files found in input\. Drop character sheet images or PDFs there first."
            exit 0
        }

        foreach ($file in $files) {
            Process-Sheet -File $file.FullName
        }

        Write-Ok "Pipeline complete. Processed $($files.Count) file(s)."
    }

    # Optional: deploy
    $deployScript = "$ScriptDir\deploy.ps1"
    if (Test-Path $deployScript) {
        $choice = Read-Host "Deploy output files to server? (y/N)"
        if ($choice -match '^[Yy]$') {
            & $deployScript
        }
    }
}

Main
