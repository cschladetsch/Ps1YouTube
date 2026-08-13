# ==============================================================================
# Ps1YouTube Full Setup & Deployment Script
# ==============================================================================
[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$RepoOwner = "cschladetsch"
$RepoName  = "Ps1YouTube"
$FullRepo  = "$RepoOwner/$RepoName"

Write-Host "[*] Initializing repository deployment for $FullRepo..." -ForegroundColor Cyan

# 1. Create GitHub Repository via GitHub CLI
try {
    & gh repo create $FullRepo --public 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "[+] GitHub repository $FullRepo created." -ForegroundColor Green
    } else {
        Write-Host "[!] GitHub repository creation skipped or repo already exists. Proceeding..." -ForegroundColor Yellow
    }
} catch {
    Write-Host "[!] GitHub CLI execution skipped. Proceeding..." -ForegroundColor Yellow
}

# 2. Initialize local Git repo if needed
if (-not (Test-Path ".git")) {
    & git init
    & git branch -M main
    & git remote add origin "https://github.com/$FullRepo.git" 2>$null
}

# 3. Configure Git LFS for example/ folder
Write-Host "[*] Setting up Git LFS..." -ForegroundColor Cyan
& git lfs install
& git lfs track "example/*"
if (-not (Test-Path "example")) {
    New-Item -ItemType Directory -Force -Path "example" | Out-Null
}

# 4. Configure .gitignore
Write-Host "[*] Updating .gitignore..." -ForegroundColor Cyan
$gitignorePath = ".gitignore"
$ignoreEntries = @("output/", "*.wav")

if (Test-Path $gitignorePath) {
    $existingContent = Get-Content $gitignorePath
    foreach ($entry in $ignoreEntries) {
        if ($existingContent -notcontains $entry) {
            Add-Content -Path $gitignorePath -Value $entry
        }
    }
} else {
    Set-Content -Path $gitignorePath -Value ($ignoreEntries -join [Environment]::NewLine) -Encoding UTF8
}

# 5. Generate yget.ps1
Write-Host "[*] Writing yget.ps1..." -ForegroundColor Cyan
$ygetScript = @'
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$Url,

    [switch]$Funky,
    [switch]$Wobble,
    [switch]$Pulsate,
    [switch]$Reverse,
    [switch]$NoAutoPlayback
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

# Safe initializations
$tempRaw   = $null
$tempOut   = $null
$id        = [guid]::NewGuid().ToString().Substring(0, 8)
$tempDir   = [System.IO.Path]::GetTempPath()
$outputDir = Join-Path (Get-Location) "output"

# Color Logging Helpers
function Write-Status  { param([string]$Message) Write-Host "[*] " -ForegroundColor Cyan -NoNewline; Write-Host $Message -ForegroundColor White }
function Write-Success { param([string]$Message) Write-Host "[+] " -ForegroundColor Green -NoNewline; Write-Host $Message -ForegroundColor White }
function Write-Warn    { param([string]$Message) Write-Host "[!] " -ForegroundColor Yellow -NoNewline; Write-Host $Message -ForegroundColor White }
function Write-Err     { param([string]$Message) Write-Host "[-] " -ForegroundColor Red -NoNewline; Write-Host $Message -ForegroundColor White }

# Thread-safe Process Runner with Terminal Spinner
function Invoke-WithSpinner {
    param(
        [string]$Executable,
        [string]$Arguments,
        [string]$Message
    )

    $spinFrames = @('⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏')

    $pinfo = New-Object System.Diagnostics.ProcessStartInfo
    $pinfo.FileName = $Executable
    $pinfo.Arguments = $Arguments
    $pinfo.UseShellExecute = $false
    $pinfo.RedirectStandardOutput = $true
    $pinfo.RedirectStandardError = $true
    $pinfo.CreateNoWindow = $true

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $pinfo

    try {
        [void]$process.Start()

        $stdOutTask = $process.StandardOutput.ReadToEndAsync()
        $stdErrTask = $process.StandardError.ReadToEndAsync()

        $i = 0
        while (-not $process.HasExited) {
            $frame = $spinFrames[$i % $spinFrames.Count]
            Write-Host -NoNewline "`r[$frame] " -ForegroundColor Cyan
            Write-Host -NoNewline $Message -ForegroundColor White
            Start-Sleep -Milliseconds 80
            $i++
        }

        $process.WaitForExit()
        [System.Threading.Tasks.Task]::WaitAll(@($stdOutTask, $stdErrTask))

        Write-Host -NoNewline ("`r" + " " * ($Message.Length + 10) + "`r")

        $stdout = $stdOutTask.Result.Trim()
        $stderr = $stdErrTask.Result.Trim()

        if ($process.ExitCode -ne 0) {
            throw "Process '$Executable' failed with exit code $($process.ExitCode): $stderr"
        }

        return $stdout
    }
    finally {
        $process.Dispose()
    }
}

try {
    # Ensure local output directory exists
    if (-not (Test-Path $outputDir)) {
        New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
    }

    # 1. Metadata Extraction
    if (-not $rawTitle) { $rawTitle = "Audio_$id" [void](Invoke-WithSpinner -Executable "yt-dlp" -Arguments "-q --no-playlist --no-part --no-warnings --cookies-from-browser chrome -f ""ba/b"" -x --audio-format wav -o ""$tempRaw"" ""$Url""" -Message "Downloading raw WAV stream...")
	    }

    $rawTitle = ($rawTitle -split "`r?\n")[0]
    $safeTitle = $rawTitle -replace '[\\/:*?"<>|]', '_'
    Write-Success "Target: $rawTitle"

    $tempRaw = Join-Path $tempDir "yget_temp_${id}.wav"
    $tempOut = Join-Path $tempDir "yget_out_${id}.wav"

    # 2. Download Raw WAV Stream
    [void](Invoke-WithSpinner -Executable "yt-dlp" -Arguments "-q --no-playlist --no-part --no-warnings -f ""ba/b"" -x --audio-format wav -o ""$tempRaw"" ""$Url""" -Message "Downloading raw WAV stream...")

    if (-not ($tempRaw -and (Test-Path $tempRaw))) {
        throw "Download failed or output file was not generated."
    }

    # 3. Construct FFmpeg Audio Filter Chain
    $filters = [System.Collections.Generic.List[string]]::new()

    if ($Funky)   { Write-Status "DSP: Funky (Vibrato & Sine Modulation)"; $filters.Add("vibrato=f=5.0:d=0.5,apulsator=hz=0.25") }
    if ($Wobble)  { Write-Status "DSP: Wobble (Flanger & Dynamic Feedback)"; $filters.Add("flanger=delay=10:depth=5:regen=25") }
    if ($Pulsate) { Write-Status "DSP: Pulsate (Tremolo LFO)"; $filters.Add("tremolo=f=4.0:d=0.7") }
    if ($Reverse) { Write-Status "DSP: Reverse (Phase Reversal)"; $filters.Add("areverse") }

    $finalDestination = Join-Path $outputDir "${safeTitle}.wav"

    if ($filters.Count -gt 0) {
        $filterGraph = $filters -join ","
        [void](Invoke-WithSpinner -Executable "ffmpeg" -Arguments "-hide_banner -loglevel error -y -i ""$tempRaw"" -af ""$filterGraph"" ""$tempOut""" -Message "Processing FFmpeg filter graph...")

        if (Test-Path $tempOut) {
            Move-Item -Path $tempOut -Destination $finalDestination -Force
        } else {
            throw "FFmpeg audio filter processing failed."
        }
    } else {
        Move-Item -Path $tempRaw -Destination $finalDestination -Force
        $tempRaw = $null
    }

    Write-Success "Saved to: $finalDestination"

    # Auto-play generated audio unless explicitly disabled
    if (-not $NoAutoPlayback) {
        Write-Status "Launching audio playback..."
        Start-Process -FilePath $finalDestination
    }

} catch {
    Write-Err "Error executing yget: $_"
} finally {
    foreach ($file in @($tempRaw, $tempOut)) {
        if ($file -and (Test-Path $file)) {
            $retries = 5
            while ($retries -gt 0 -and (Test-Path $file)) {
                try {
                    Remove-Item -Path $file -Force -ErrorAction Stop
                    break
                } catch {
                    Start-Sleep -Milliseconds 200
                    $retries--
                }
            }
            if (Test-Path $file) { Write-Warn "Could not immediately unlock temp file: $file" }
        }
    }
}
'@

Set-Content -Path "yget.ps1" -Value $ygetScript -Encoding UTF8

# 6. Generate README.md
Write-Host "[*] Writing README.md..." -ForegroundColor Cyan

$readmeLines = @(
    '# Ps1YouTube',
    '',
    'An asynchronous, colorized PowerShell audio extraction and DSP pipeline powered by `yt-dlp` and `ffmpeg`.',
    '',
    '## Overview',
    '',
    '`yget.ps1` downloads audio streams from YouTube URLs, extracts high-quality WAV files to `output/`, applies real-time DSP audio filters, and automatically initiates playback upon completion.',
    '',
    '## Key Features',
    '',
    '- **Automatic Playback**: Opens finished renders automatically in default system player (suppress with `-NoAutoPlayback`).',
    '- **Asynchronous Terminal Spinner**: Direct `.NET` task stream readers bypass runspace deadlocks.',
    '- **Isolated Audio Output**: Renders automatically output to `output/` (ignored by Git).',
    '- **Colorized Output**: Standard console indicators (`[*]`, `[+]`, `[!]`, `[-]`).',
    '- **Handle Safety**: Explicit process handle disposal and retry loops in `finally` blocks prevent stream locking.',
    '- **DSP Audio Filter Chain**:',
    '  - `-Funky`: Sine pitch modulation & vibrato (`vibrato`, `apulsator`).',
    '  - `-Wobble`: Stereo flanger effect with dynamic feedback (`flanger`).',
    '  - `-Pulsate`: LFO tremolo amplitude modulation (`tremolo`).',
    '  - `-Reverse`: Full audio phase/buffer reversal (`areverse`).',
    '',
    '## Usage Example',
    '',
    '```powershell',
    '# Downloads, applies DSP filters, and plays automatically',
    '.\yget.ps1 "[https://www.youtube.com/watch?v=E0ozmU9cJDg](https://www.youtube.com/watch?v=E0ozmU9cJDg)" -Funky -Reverse',
    '',
    '# Headless run without automatic playback',
    '.\yget.ps1 "[https://www.youtube.com/watch?v=E0ozmU9cJDg](https://www.youtube.com/watch?v=E0ozmU9cJDg)" -Funky -NoAutoPlayback',
    '```'
)

Set-Content -Path "README.md" -Value ($readmeLines -join [Environment]::NewLine) -Encoding UTF8

Write-Host "[+] Repository workspace initialized successfully." -ForegroundColor Green
