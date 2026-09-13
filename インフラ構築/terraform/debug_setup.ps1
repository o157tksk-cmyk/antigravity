Remove-Module Posh-SSH -ErrorAction SilentlyContinue
Import-Module "C:\Users\tomoy\OneDrive\ドキュメント\WindowsPowerShell\Modules\Posh-SSH\3.2.7\Posh-SSH.psd1" -Force
Write-Host "Loaded Posh-SSH version: $((Get-Module Posh-SSH).Version)" -ForegroundColor Green

$sec = ConvertTo-SecureString "P@ssw0rd2022!" -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential("root", $sec)

$s = New-SSHSession -ComputerName "192.168.10.20" -Credential $cred -AcceptKey
Write-Host "Session created: $($s.SessionId)" -ForegroundColor Green

$cmdResult = Invoke-SSHCommand -SessionId $s.SessionId -Command "restorecon -Rv /var/www/html && /root/test_all_services.sh"
$cmdResult.Output | ForEach-Object { Write-Host $_ }

Remove-SSHSession -SessionId $s.SessionId | Out-Null

