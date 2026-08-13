# Ps1YouTube

An asynchronous, colorized PowerShell audio extraction and DSP pipeline powered by `yt-dlp` and `ffmpeg`.

## Overview

`yget.ps1` downloads audio streams from YouTube URLs, extracts high-quality WAV files, and applies real-time DSP audio filters (pitch modulation, vibrato, flanger, tremolo, phase reversal) with smooth non-blocking terminal spinners.

## Key Features

- **Asynchronous Terminal Spinner**: Direct `.NET` process event handlers stream process pipes without pipeline buffer deadlocks.
- **Colorized Output**: Standard console indicators (`[*]`, `[+]`, `[!]`, `[-]`).
- **Handle Safety**: Explicit process handle disposal and retry loops in `finally` blocks prevent stream locking.
- **DSP Audio Filter Chain**:
  - `-Funky`: Sine pitch modulation & vibrato (`vibrato`, `apulsator`).
  - `-Wobble`: Stereo flanger effect with dynamic feedback (`flanger`).
  - `-Pulsate`: LFO tremolo amplitude modulation (`tremolo`).
  - `-Reverse`: Full audio phase/buffer reversal (`areverse`).

## Architecture & Workflow

```mermaid
graph TD
    A[User Input: yget URL -Switches] --> B[Parse Parameters & Init Temp Paths]
    B --> C[Invoke-WithSpinner: yt-dlp Metadata Extraction]
    C --> D[Sanitize Output Title & Output Path]
    D --> E[Invoke-WithSpinner: yt-dlp Audio Stream Download]
    E --> F{DSP Switches Provided?}
    F -- Yes --> G[Build FFmpeg Filter Graph]
    G --> H[Invoke-WithSpinner: ffmpeg Filter Pipeline]
    H --> I[Move Filtered File to Final Destination]
    F -- No --> J[Move Raw WAV File to Final Destination]
    I --> K[Finally Block: Temp File Cleanup with Retries]
    J --> K
```
