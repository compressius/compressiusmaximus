# Compressius Maximus downloads

This repository is the public download mirror for Compressius Maximus. It
contains the Unix installer, release metadata, and links to published binary
archives. Core source code is maintained in the private core repository.

Install on Linux or macOS:

```sh
curl -fsSL https://github.com/compressius/compressiusmaximus/releases/latest/download/install.sh | sh
```

Install on Windows from PowerShell:

```powershell
irm https://raw.githubusercontent.com/compressius/compressiusmaximus/main/install.ps1 | iex
```

Both installers download the matching archive and verify its SHA-256 value
from `latest.json` before installing it. Project documentation is available
at https://compressi.us.
