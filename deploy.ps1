#Requires -Version 7.0
<#
.SYNOPSIS
    Deploy built character sheets to a remote server.
.DESCRIPTION
    Copies all HTML files from output/ to a configured remote server via SCP.
    Edit the $Server and $RemotePath variables below to configure your target.
#>

# ── Configure your server here ──
$Server     = "you@yourserver.com"
$RemotePath = "/var/www/sheets/"
$Method     = "scp"  # Options: scp, rsync

$ScriptDir  = $PSScriptRoot
$OutputDir  = "$ScriptDir\output"

Write-Host "Deploying character sheets..."

$count = 0
$files = Get-ChildItem "$OutputDir\*.html" -ErrorAction SilentlyContinue

if (-not $files -or $files.Count -eq 0) {
    Write-Host "  No files to deploy in output\"
    exit 0
}

foreach ($file in $files) {
    switch ($Method) {
        "scp" {
            scp $file.FullName "${Server}:${RemotePath}"
        }
        "rsync" {
            rsync -avz $file.FullName "${Server}:${RemotePath}"
        }
    }
    Write-Host "  + Deployed: $($file.Name)" -ForegroundColor Green
    $count++
}

Write-Host "Done. Deployed $count file(s) to ${Server}:${RemotePath}"
