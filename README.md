# Ps1YouTube

An asynchronous, colorized PowerShell audio extraction and DSP pipeline powered by `yt-dlp` and `ffmpeg`.

## LookAt

![Image](Images/Untitled.png)

## Overview

`yget.ps1` downloads audio streams from YouTube URLs, extracts high-quality WAV files to `output/`, applies real-time DSP audio filters, and automatically initiates playback upon completion.

## Key Features

- **Automatic Playback**: Opens finished renders automatically in default system player (suppress with `-NoAutoPlayback`).
- **Asynchronous Terminal Spinner**: Direct `.NET` task stream readers bypass runspace deadlocks.
- **Isolated Audio Output**: Renders automatically output to `output/` (ignored by Git).
- **Colorized Output**: Standard console indicators (`[*]`, `[+]`, `[!]`, `[-]`).
- **Handle Safety**: Explicit process handle disposal and retry loops in `finally` blocks prevent stream locking.
- **DSP Audio Filter Chain**:
  - `-Funky`: Sine pitch modulation & vibrato (`vibrato`, `apulsator`).
  - `-Wobble`: Stereo flanger effect with dynamic feedback (`flanger`).
  - `-Pulsate`: LFO tremolo amplitude modulation (`tremolo`).
  - `-Reverse`: Full audio phase/buffer reversal (`areverse`).

## Usage Example

```powershell
# Downloads, applies DSP filters, and plays automatically
.\yget.ps1 "[https://www.youtube.com/watch?v=E0ozmU9cJDg](https://www.youtube.com/watch?v=E0ozmU9cJDg)" -Funky -Reverse

# Headless run without automatic playback
.\yget.ps1 "[https://www.youtube.com/watch?v=E0ozmU9cJDg](https://www.youtube.com/watch?v=E0ozmU9cJDg)" -Funky -NoAutoPlayback
```
