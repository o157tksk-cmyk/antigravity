# ==============================================================================
# 無人インストール用仮想ディスク (Unattended.vhdx) 作成 & VM 割り当てスクリプト
#
# 目的: autounattend.xml および ks.cfg をルートに含む FAT32 ディスクを作成し、VM にアタッチ
# 実行環境: Windows の PowerShell (管理者権限)
# ==============================================================================

# 管理者権限チェック
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Error "エラー: 本スクリプトは管理者権限で実行する必要があります。"
    exit 1
}

$VhdPath = "C:\HyperV\ISO\Unattended.vhdx"
$WinXml  = "c:\Users\tomoy\.gemini\antigravity\scratch\antigravity\インフラ構築\unattended\autounattend.xml"
$LinuxKs = "c:\Users\tomoy\.gemini\antigravity\scratch\antigravity\インフラ構築\unattended\ks.cfg"

Write-Host "==========================================" -ForegroundColor Green
Write-Host " 無人応答ファイル用 VHDX の作成および割り当て" -ForegroundColor Green
Write-Host "==========================================" -ForegroundColor Green

# 1. 既存ディスクのアタッチ解除・削除
if (Test-Path $VhdPath) {
    Dismount-VHD -Path $VhdPath -ErrorAction SilentlyContinue | Out-Null
    Remove-Item $VhdPath -Force -ErrorAction SilentlyContinue | Out-Null
}

# 2. VHDX ディスクの作成・フォーマット (FAT32)
Write-Host "[1/3] 10MB の仮想ディスク ($VhdPath) を作成中..." -ForegroundColor Yellow
$vhd = New-VHD -Path $VhdPath -SizeBytes 10MB -Dynamic
$disk = $vhd | Mount-VHD -Passthru | Initialize-Disk -PartitionStyle MBR -PassThru | New-Partition -AssignDriveLetter -UseMaximumSize
Format-Volume -Partition $disk -FileSystem FAT32 -NewFileSystemLabel "UNATTENDED" -Confirm:$false | Out-Null

$driveLetter = "$($disk.DriveLetter):"

# 3. 応答ファイルのコピー
Write-Host "[2/3] autounattend.xml および ks.cfg をコピー中..." -ForegroundColor Yellow
Copy-Item $WinXml -Destination "$driveLetter\autounattend.xml" -Force
Copy-Item $LinuxKs -Destination "$driveLetter\ks.cfg" -Force

# 4. ディスクのアンマウント
Dismount-VHD -Path $VhdPath | Out-Null

# 5. VM へのアタッチ (Win2022-DC / Rocky10-Web)
Write-Host "[3/3] VM へ仮想ディスクをアタッチ中..." -ForegroundColor Yellow

# Win2022-DC
$winDrive = Get-VMHardDiskDrive -VMName "Win2022-DC" | Where-Object { $_.Path -eq $VhdPath }
if (-not $winDrive) {
    Add-VMHardDiskDrive -VMName "Win2022-DC" -Path $VhdPath | Out-Null
}

# Rocky10-Web
$linuxDrive = Get-VMHardDiskDrive -VMName "Rocky10-Web" -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $VhdPath }
if (-not $linuxDrive) {
    Add-VMHardDiskDrive -VMName "Rocky10-Web" -Path $VhdPath -ErrorAction SilentlyContinue | Out-Null
}

Write-Host "==========================================" -ForegroundColor Green
Write-Host " 割り当て完了！VM を再起動すると無人インストールが自動認識されます。" -ForegroundColor Green
Write-Host "==========================================" -ForegroundColor Green
