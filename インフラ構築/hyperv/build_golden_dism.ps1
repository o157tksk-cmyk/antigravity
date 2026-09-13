# ==============================================================================
# DISM (WIM Direct Apply) によるゴールデンイメージ (GoldenImage.vhdx) 完全自動構築スクリプト
#
# 目的: config.json の設定に従い、ISO 内の install.wim から VHDX へ Windows Server 2022 を直接展開し、
#       Hyper-V マネージャー上に「Win2022-GoldenImage」(状態: オフ) として登録・保管
# 実行要件: 管理者権限で実行してください (Run as Administrator)
# ==============================================================================

# 1. 管理者権限のチェック
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Error "エラー: 本スクリプトは管理者権限で実行する必要があります。"
    exit 1
}

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ConfigFile = Join-Path $ScriptDir "config.json"

if (-not (Test-Path $ConfigFile)) {
    Write-Error "エラー: 設定ファイル '$ConfigFile' が存在しません。"
    exit 1
}

$cfg = Get-Content $ConfigFile -Raw -Encoding UTF8 | ConvertFrom-Json

Write-Host "==========================================" -ForegroundColor Green
Write-Host " DISM WIM Direct Apply によるマスター VHDX 完全自動構築" -ForegroundColor Green
Write-Host "==========================================" -ForegroundColor Green

$MasterDir  = $cfg.paths.masterDir
$IsoPath    = $cfg.paths.isoPath
$MasterVhdx = Join-Path $MasterDir "Win2022-GoldenImage.vhdx"
$UnattendSource = Join-Path (Split-Path -Parent $ScriptDir) "unattended\autounattend.xml"

# ディレクトリ準備
New-Item -ItemType Directory -Path $MasterDir -Force | Out-Null

if (-not (Test-Path $IsoPath)) {
    Write-Error "エラー: $IsoPath が存在しません。"
    exit 1
}

# 既存のマスター VM / VHDX のクリーンアップ
if (Get-VM -Name "Win2022-GoldenImage" -ErrorAction SilentlyContinue) {
    Stop-VM -Name "Win2022-GoldenImage" -TurnOff -ErrorAction SilentlyContinue | Out-Null
    Remove-VM -Name "Win2022-GoldenImage" -Force | Out-Null
}

if (Test-Path $MasterVhdx) {
    attrib -r $MasterVhdx
    Dismount-VHD -Path $MasterVhdx -ErrorAction SilentlyContinue | Out-Null
    Remove-Item $MasterVhdx -Force -ErrorAction SilentlyContinue | Out-Null
}

# 2. ISO のマウント
Write-Host "[1/7] Windows Server 2022 ISO のマウント中..." -ForegroundColor Yellow
$isoMount = Mount-DiskImage -ImagePath $IsoPath -PassThru
$isoDrive = ($isoMount | Get-Volume | Where-Object DriveLetter -ne $null).DriveLetter + ":"
$wimPath  = Join-Path $isoDrive "sources\install.wim"

if (-not (Test-Path $wimPath)) {
    $wimPath = Join-Path $isoDrive "sources\install.esd"
}

Write-Host "  -> ISO マウント成功 (Drive: $isoDrive, WIM: $wimPath)" -ForegroundColor Green

# 3. VHDX ディスクの作成 & GPT パーティション作成
Write-Host "[2/7] マスター VHDX (60GB) の作成および GPT パーティション構築中..." -ForegroundColor Yellow
$vhd = New-VHD -Path $MasterVhdx -SizeBytes 60GB -Dynamic
$disk = $vhd | Mount-VHD -Passthru | Initialize-Disk -PartitionStyle GPT -PassThru

# EFI パーティション (100MB)
$efiPart = $disk | New-Partition -Size 100MB -GptType '{c12a7328-f81f-11d2-ba4b-00a0c93ec93b}' -AssignDriveLetter
$efiVol  = $efiPart | Format-Volume -FileSystem FAT32 -NewFileSystemLabel "System" -Confirm:$false

# MSR パーティション (16MB)
$msrPart = $disk | New-Partition -Size 16MB -GptType '{e3c9e316-0b5c-4db8-817d-f92df00215ae}'

# OS パーティション (残りの全領域)
$osPart  = $disk | New-Partition -UseMaximumSize -GptType '{ebd0a0a2-b9e5-4433-87c0-68b6b72699c7}' -AssignDriveLetter
$osVol   = $osPart | Format-Volume -FileSystem NTFS -NewFileSystemLabel "Windows" -Confirm:$false

$osDriveLetter  = (Get-Partition -DiskNumber $disk.DiskNumber | Where-Object PartitionNumber -eq $osPart.PartitionNumber).DriveLetter
$efiDriveLetter = (Get-Partition -DiskNumber $disk.DiskNumber | Where-Object PartitionNumber -eq $efiPart.PartitionNumber).DriveLetter

$osDrive  = "$($osDriveLetter):"
$efiDrive = "$($efiDriveLetter):"

Write-Host "  -> パーティション作成完了 (OS Drive: $osDrive, EFI Drive: $efiDrive)" -ForegroundColor Green

# 4. DISM による Windows イメ―ジ展開 (Index 2: Desktop Experience)
Write-Host "[3/7] DISM による Windows Server 2022 イメージ展開中..." -ForegroundColor Yellow
Expand-WindowsImage -ImagePath $wimPath -Index 2 -ApplyPath "$osDrive\" | Out-Null
Write-Host "  -> WIM イメージ展開完了。" -ForegroundColor Green

# 5. BCD ブートローダーの書き込み
Write-Host "[4/7] UEFI ブート設定 (bcdboot) の書き込み中..." -ForegroundColor Yellow
$bcdResult = bcdboot "$osDrive\Windows" /s "$efiDrive" /f UEFI
Write-Host "  -> $bcdResult" -ForegroundColor Green

# 6. 無人応答ファイル (unattend.xml) の注入
Write-Host "[5/7] unattend.xml のシステムインジェクション (パスワード自動更新)..." -ForegroundColor Yellow
$pantherDir = Join-Path "$osDrive\Windows" "Panther"
New-Item -ItemType Directory -Path $pantherDir -Force | Out-Null

if (Test-Path $UnattendSource) {
    [xml]$xmlContent = Get-Content $UnattendSource -Encoding UTF8
    $ns = New-Object System.Xml.XmlNamespaceManager($xmlContent.NameTable)
    $ns.AddNamespace("u", "urn:schemas-microsoft-com:unattend")
    
    $passNodes = $xmlContent.SelectNodes("//u:Value", $ns)
    foreach ($node in $passNodes) {
        if ($node.InnerText -eq "P@ssw0rd2022!" -or $node.InnerText -ne "") {
            $node.InnerText = $cfg.admin.password
        }
    }
    $xmlContent.Save((Join-Path $pantherDir "unattend.xml"))
    Write-Host "  -> $pantherDir\unattend.xml の自動配置完了。" -ForegroundColor Green
}

# 7. 解除および Hyper-V 登録 (オフ状態)
Write-Host "[6/7] ディスクおよび ISO のアンマウント..." -ForegroundColor Yellow
Dismount-VHD -Path $MasterVhdx | Out-Null
Dismount-DiskImage -ImagePath $IsoPath | Out-Null

Write-Host "[7/7] Hyper-V マネージャーへ 'Win2022-GoldenImage' (状態: オフ) として登録..." -ForegroundColor Yellow
icacls $MasterVhdx /grant 'NT VIRTUAL MACHINE\Virtual Machines:(F)' | Out-Null
New-VM -Name "Win2022-GoldenImage" -MemoryStartupBytes 4GB -Generation 2 -VHDPath $MasterVhdx -Path $MasterDir -SwitchName $cfg.network.switchName | Out-Null
Set-VMMemory -VMName "Win2022-GoldenImage" -DynamicMemoryEnabled $true -MinimumBytes 2GB -MaximumBytes 8GB | Out-Null
Set-VMProcessor -VMName "Win2022-GoldenImage" -Count 2 | Out-Null

Write-Host "==========================================" -ForegroundColor Green
Write-Host " ゴールデンイメージ (Win2022-GoldenImage) の作成・Hyper-V登録(オフ)が完了しました！" -ForegroundColor Green
Write-Host " 保存場所: $MasterVhdx" -ForegroundColor Yellow
Write-Host "==========================================" -ForegroundColor Green
