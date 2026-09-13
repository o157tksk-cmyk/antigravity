# ==============================================================================
# ゴールデンイメージ作成用 VM & 全自動 Sysprep 準備スクリプト (FAT32版)
# 
# 目的: Win2022-Template VM を作成し、FAT32応答ディスクから autounattend.xml を自動読み込み
# 実行要件: 管理者権限で実行してください (Run as Administrator)
# ==============================================================================

# 1. 管理者権限のチェック
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Error "エラー: 本スクリプトは管理者権限で実行する必要があります。"
    exit 1
}

Write-Host "==========================================" -ForegroundColor Green
Write-Host " ゴールデンイメージ用 VM & FAT32 無人応答ディスク構築" -ForegroundColor Green
Write-Host "==========================================" -ForegroundColor Green

# 設定パラメーター
$MasterDir     = "C:\HyperV\Master"
$IsoDir        = "C:\HyperV\ISO"
$VmDir         = "C:\HyperV\VMs"
$SwitchName    = "LabInternalSwitch"
$WinIsoPath    = Join-Path $IsoDir "WindowsServer2022.iso"
$VmName        = "Win2022-Template"
$VmPath        = Join-Path $VmDir $VmName
$UnattendedVhd = Join-Path $IsoDir "Unattended_Golden.vhdx"

# ディレクトリ作成
New-Item -ItemType Directory -Path $MasterDir -Force | Out-Null
New-Item -ItemType Directory -Path $IsoDir -Force    | Out-Null
New-Item -ItemType Directory -Path $VmDir -Force     | Out-Null

# 2. ISO の確認
if (-not (Test-Path $WinIsoPath)) {
    Write-Error "エラー: $WinIsoPath が存在しません。"
    exit 1
}

# 3. 全自動 Sysprep 用 autounattend.xml の内容
$XmlContent = @"
<?xml version="1.0" encoding="utf-8"?>
<unattend xmlns="urn:schemas-microsoft-com:unattend">
    <settings pass="windowsPE">
        <component name="Microsoft-Windows-International-Core-WinPE" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
            <SetupUILanguage><UILanguage>ja-JP</UILanguage></SetupUILanguage>
            <InputLocale>0411:00000411</InputLocale>
            <SystemLocale>ja-JP</SystemLocale>
            <UserLocale>ja-JP</UserLocale>
            <UILanguage>ja-JP</UILanguage>
        </component>
        <component name="Microsoft-Windows-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
            <DiskConfiguration>
                <Disk wcm:action="add">
                    <CreatePartitions>
                        <CreatePartition wcm:action="add"><Order>1</Order><Type>Primary</Type><Size>300</Size></CreatePartition>
                        <CreatePartition wcm:action="add"><Order>2</Order><Type>EFI</Type><Size>100</Size></CreatePartition>
                        <CreatePartition wcm:action="add"><Order>3</Order><Type>MSR</Type><Size>128</Size></CreatePartition>
                        <CreatePartition wcm:action="add"><Order>4</Order><Type>Primary</Type><Extend>true</Extend></CreatePartition>
                    </CreatePartitions>
                    <ModifyPartitions>
                        <ModifyPartition wcm:action="add"><Order>1</Order><PartitionID>1</PartitionID><Format>NTFS</Format><Label>System</Label></ModifyPartition>
                        <ModifyPartition wcm:action="add"><Order>2</Order><PartitionID>2</PartitionID><Format>FAT32</Format><Label>System</Label></ModifyPartition>
                        <ModifyPartition wcm:action="add"><Order>3</Order><PartitionID>3</PartitionID></ModifyPartition>
                        <ModifyPartition wcm:action="add"><Order>4</Order><PartitionID>4</PartitionID><Format>NTFS</Format><Label>Windows</Label></ModifyPartition>
                    </ModifyPartitions>
                    <DiskID>0</DiskID>
                    <WillWipeDisk>true</WillWipeDisk>
                </Disk>
            </DiskConfiguration>
            <ImageInstall>
                <OSImage>
                    <InstallTo><DiskID>0</DiskID><PartitionID>4</PartitionID></InstallTo>
                    <InstallFrom><MetaData wcm:action="add"><Key>/IMAGE/INDEX</Key><Value>2</Value></MetaData></InstallFrom>
                    <WillShowUI>OnError</WillShowUI>
                </OSImage>
            </ImageInstall>
            <UserData><AcceptEula>true</AcceptEula></UserData>
        </component>
    </settings>
    <settings pass="oobeSystem">
        <component name="Microsoft-Windows-Shell-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
            <UserAccounts>
                <AdministratorPassword><Value>P@ssw0rd2022!</Value><PlainText>true</PlainText></AdministratorPassword>
            </UserAccounts>
            <AutoLogon>
                <Password><Value>P@ssw0rd2022!</Value><PlainText>true</PlainText></Password>
                <Enabled>true</Enabled>
                <LogonCount>1</LogonCount>
                <Username>Administrator</Username>
            </AutoLogon>
            <FirstLogonCommands>
                <SynchronousCommand wcm:action="add">
                    <Order>1</Order>
                    <CommandLine>C:\Windows\System32\sysprep\sysprep.exe /oobe /generalize /shutdown /quiet</CommandLine>
                    <Description>Auto Sysprep Generalize and Shutdown</Description>
                </SynchronousCommand>
            </FirstLogonCommands>
        </component>
    </settings>
</unattend>
"@

# 4. 無人応答用 VHDX の作成 (100MB FAT32)
Write-Host "[1/4] FAT32 無人応答ファイルディスクを作成中..." -ForegroundColor Yellow
if (Test-Path $UnattendedVhd) {
    Dismount-VHD -Path $UnattendedVhd -ErrorAction SilentlyContinue | Out-Null
    Remove-Item $UnattendedVhd -Force -ErrorAction SilentlyContinue | Out-Null
}

$vhd = New-VHD -Path $UnattendedVhd -SizeBytes 100MB -Dynamic
$disk = $vhd | Mount-VHD -Passthru | Initialize-Disk -PartitionStyle MBR -PassThru | New-Partition -AssignDriveLetter -UseMaximumSize
Format-Volume -Partition $disk -FileSystem FAT32 -NewFileSystemLabel "UNATTENDED" -Confirm:$false | Out-Null
$driveLetter = "$($disk.DriveLetter):"

Start-Sleep -Seconds 1
[System.IO.File]::WriteAllText("$driveLetter\autounattend.xml", $XmlContent, [System.Text.Encoding]::UTF8)
Dismount-VHD -Path $UnattendedVhd | Out-Null
Write-Host "  -> FAT32 ディスクへ autounattend.xml の配置成功。" -ForegroundColor Green

# 5. スイッチの作成
$existingSwitch = Get-VMSwitch -Name $SwitchName -ErrorAction SilentlyContinue
if (-not $existingSwitch) {
    Write-Host "[2/4] 仮想スイッチ '$SwitchName' を作成中..." -ForegroundColor Yellow
    New-VMSwitch -Name $SwitchName -SwitchType Internal | Out-Null
    $netAdapter = Get-NetAdapter -Name "*$SwitchName*" -ErrorAction SilentlyContinue
    if ($netAdapter) {
        New-NetIPAddress -InterfaceIndex $netAdapter.ifIndex -IPAddress "192.168.10.1" -PrefixLength 24 -ErrorAction SilentlyContinue | Out-Null
    }
}

# 6. VM の作成 (Win2022-Template)
Write-Host "[3/4] マスター VM '$VmName' を再構成中..." -ForegroundColor Yellow
$VhdxPath = Join-Path $VmPath "$VmName.vhdx"
if (Get-VM -Name $VmName -ErrorAction SilentlyContinue) {
    Stop-VM -Name $VmName -TurnOff -ErrorAction SilentlyContinue | Out-Null
    Remove-VM -Name $VmName -Force | Out-Null
}
if (Test-Path $VmPath) { Remove-Item $VmPath -Recurse -Force | Out-Null }

New-Item -ItemType Directory -Path $VmPath -Force | Out-Null
New-VHD -Path $VhdxPath -SizeBytes 60GB -Dynamic | Out-Null

New-VM -Name $VmName -MemoryStartupBytes 4GB -Generation 2 -VHDPath $VhdxPath -Path $VmDir -SwitchName $SwitchName | Out-Null
Set-VMMemory -VMName $VmName -DynamicMemoryEnabled $true -MinimumBytes 2GB -MaximumBytes 8GB | Out-Null
Set-VMProcessor -VMName $VmName -Count 2 | Out-Null

# ISO & VHDX アタッチ (UnattendedVhd を SCSI location 0 に割り当て)
Add-VMDvdDrive -VMName $VmName -Path $WinIsoPath | Out-Null
$dvd = Get-VMDvdDrive -VMName $VmName
Set-VMFirmware -VMName $VmName -FirstBootDevice $dvd | Out-Null
Add-VMHardDiskDrive -VMName $VmName -Path $UnattendedVhd | Out-Null

Write-Host "==========================================" -ForegroundColor Green
Write-Host " [4/4] FAT32 応答ディスク対応 VM の構築完了！" -ForegroundColor Green
Write-Host "==========================================" -ForegroundColor Green
