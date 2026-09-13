Import-Module Posh-SSH -ErrorAction SilentlyContinue

$sec = ConvertTo-SecureString "P@ssw0rd2022!" -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential("root", $sec)

$s = New-SSHSession -ComputerName "192.168.10.20" -Credential $cred -AcceptKey

Write-Host "--- Service Statuses (named / httpd / postfix / dovecot) ---" -ForegroundColor Cyan
(Invoke-SSHCommand -SessionId $s.SessionId -Command "systemctl is-active named httpd postfix dovecot").Output | ForEach-Object { Write-Host $_ }

Write-Host "`n--- Web Server Response (Public / Secure) ---" -ForegroundColor Cyan
(Invoke-SSHCommand -SessionId $s.SessionId -Command "curl -s -I http://localhost/ | head -n 1; curl -s -I http://localhost/secure/ | head -n 1").Output | ForEach-Object { Write-Host $_ }

Write-Host "`n--- DNS Test (Resolve google.com via Local BIND) ---" -ForegroundColor Cyan
(Invoke-SSHCommand -SessionId $s.SessionId -Command "dig @127.0.0.1 google.com +short").Output | ForEach-Object { Write-Host $_ }

Remove-SSHSession -SessionId $s.SessionId | Out-Null
