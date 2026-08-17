<#
.SYNOPSIS
    Downloads audio from a YouTube URL, applies custom DSP filters, and plays the result as an MP3.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$Url,

    [switch]$Funky,
    [switch]$Wobble,
    [switch]$Reverse,
    [switch]$NoPlay
)

$ErrorActionPreference = 'Stop'

# Ensure output directory exists
$OutputDir = "$PSScriptRoot\output"
if (-not (Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir | Out-Null
}

Write-Host "Fetching metadata via yt-dlp..." -ForegroundColor Cyan

# Fetch raw JSON metadata to extract clean title and ID
$jsonOutput = yt-dlp --no-playlist --print "%(id)s`t%(title)s" $Url
if (-not $jsonOutput) {
    Write-Error "Failed to retrieve metadata from URL: $Url"
    exit 1
}

$parts = $jsonOutput.Split("`t")
$id = $parts[0]
$rawTitle = if ($parts.Length -gt 1) { $parts[1] } else { "" }

if (-not $rawTitle) { $rawTitle = "Audio_$id"; [void](Write-Warning "Could not extract title, falling back to ID.") }

# Sanitize title for filename safety
$safeTitle = $rawTitle -replace '[\\/?:*<>|"=]', '' -replace '\s+', ' '
$safeTitle = $safeTitle.Trim()
$baseName = "$safeTitle"
$rawAudioPath = "$OutputDir\$baseName-raw.webm"
$finalAudioPath = "$OutputDir\$baseName.mp3"

Write-Host "Target Title: $safeTitle" -ForegroundColor Green
Write-Host "Downloading audio stream..." -ForegroundColor Cyan

# Download best audio stream
yt-dlp --no-playlist -f "bestaudio" -o "$rawAudioPath" $Url

if (-not (Test-Path $rawAudioPath)) {
    Write-Error "Download failed. Raw audio file not found."
    exit 1
}

# Build FFmpeg filter graph based on switches
$filters = @()

if ($Funky) {
    $filters += "aformat=sample_rates=44100:channel_layouts=stereo"
    $filters += "vibrato=f=6:d=0.5"
}

if ($Wobble) {
    $filters += "tremolo=f=4:d=0.7"
}

if ($Reverse) {
    $filters += "areverse"
}

Write-Host "Processing audio through FFmpeg (192kbps MP3)..." -ForegroundColor Cyan

if ($filters.Count -gt 0) {
    $filterString = $filters -join ","
    ffmpeg -y -i "$rawAudioPath" -af "$filterString" -b:a 192k "$finalAudioPath"
} else {
    # Convert directly to 192kbps MP3 if no effects requested
    ffmpeg -y -i "$rawAudioPath" -b:a 192k "$finalAudioPath"
}

# Cleanup raw download
if (Test-Path $rawAudioPath) {
    Remove-Item $rawAudioPath
}

Write-Host "Saved to: $finalAudioPath" -ForegroundColor Green

# Auto-play unless suppressed
if (-not $NoPlay) {
    Write-Host "Playing output..." -ForegroundColor Cyan
    & "$finalAudioPath"
}
