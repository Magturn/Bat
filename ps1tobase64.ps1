$script = Get-Content -Raw -Path "C:\Users\day96\OneDrive\Desktop\shelly\mainpsc.ps1"
$bytes = [Text.Encoding]::Unicode.GetBytes($script)
$encodedCommand = [Convert]::ToBase64String($bytes)
$encodedCommand
