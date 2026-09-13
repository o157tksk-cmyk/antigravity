$sshDir = Join-Path $env:USERPROFILE ".ssh"
$keyPath = Join-Path $sshDir "id_rsa"
$pubPath = Join-Path $sshDir "id_rsa.pub"

if (-not (Test-Path $sshDir)) {
    New-Item -ItemType Directory -Path $sshDir -Force | Out-Null
}

if (-not (Test-Path $keyPath)) {
    cmd.exe /c "ssh-keygen -t rsa -P `"`" -f `"$keyPath`""
}

if (Test-Path $pubPath) {
    Get-Content $pubPath
}
