[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$Url,

    [switch]$Funky,
    [switch]$Wobble,
    [switch]$Pulsate,
    [switch]$Reverse
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
    $rawTitle = Invoke-WithSpinner -Executable "yt-dlp" -Arguments "--get-title --no-playlist --no-warnings ""$Url""" -Message "Extracting metadata via yt-dlp..."
    if (-not $rawTitle) { $rawTitle = "Audio_$id" }

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
