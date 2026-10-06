param(
    [string]$OutputDirectory = (Join-Path $PSScriptRoot "dist")
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

$AutoHotkeyVersion = "2.0.26"
$Ahk2ExeVersion = "1.1.37.02a2"
$AutoHotkeySha256 = "43522aa3122a57784ac5db30abf85c2244475c36acd7796e2c993355f9e926ae"
$Ahk2ExeSha256 = "c29b8c3a5124850d79fc9e66e2ca79677c377d7f31631ad3022ba159c5d9e3be"

$SourceScript = Join-Path $PSScriptRoot "Smooth-Scroll-Acceleration_Smooth_v_15.ahk"
$OutputExe = Join-Path $OutputDirectory "Smooth-Scroll-Acceleration.exe"
$ToolsDirectory = Join-Path ([System.IO.Path]::GetTempPath()) "SmoothScrollBuildTools"
$AutoHotkeyArchive = Join-Path $ToolsDirectory "AutoHotkey_$AutoHotkeyVersion.zip"
$Ahk2ExeArchive = Join-Path $ToolsDirectory "Ahk2Exe_$Ahk2ExeVersion.zip"
$AutoHotkeyDirectory = Join-Path $ToolsDirectory "AutoHotkey_$AutoHotkeyVersion"
$Ahk2ExeDirectory = Join-Path $ToolsDirectory "Ahk2Exe_$Ahk2ExeVersion"

function Get-VerifiedDownload {
    param(
        [Parameter(Mandatory = $true)][string]$Uri,
        [Parameter(Mandatory = $true)][string]$Destination,
        [Parameter(Mandatory = $true)][string]$ExpectedSha256
    )

    if (Test-Path $Destination) {
        $ExistingHash = (Get-FileHash -Algorithm SHA256 $Destination).Hash.ToLowerInvariant()
        if ($ExistingHash -eq $ExpectedSha256) {
            return
        }
        Remove-Item -Force $Destination
    }

    Write-Host "Downloading $Uri"
    Invoke-WebRequest -UseBasicParsing -Uri $Uri -OutFile $Destination

    $ActualHash = (Get-FileHash -Algorithm SHA256 $Destination).Hash.ToLowerInvariant()
    if ($ActualHash -ne $ExpectedSha256) {
        Remove-Item -Force $Destination
        throw "SHA-256 mismatch for $Uri. Expected $ExpectedSha256, received $ActualHash."
    }
}

if (-not (Test-Path $SourceScript)) {
    throw "Source script was not found: $SourceScript"
}

New-Item -ItemType Directory -Force -Path $ToolsDirectory | Out-Null
New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null

Get-VerifiedDownload `
    -Uri "https://github.com/AutoHotkey/AutoHotkey/releases/download/v$AutoHotkeyVersion/AutoHotkey_$AutoHotkeyVersion.zip" `
    -Destination $AutoHotkeyArchive `
    -ExpectedSha256 $AutoHotkeySha256

Get-VerifiedDownload `
    -Uri "https://github.com/AutoHotkey/Ahk2Exe/releases/download/Ahk2Exe$Ahk2ExeVersion/Ahk2Exe$Ahk2ExeVersion.zip" `
    -Destination $Ahk2ExeArchive `
    -ExpectedSha256 $Ahk2ExeSha256

New-Item -ItemType Directory -Force -Path $AutoHotkeyDirectory | Out-Null
Expand-Archive -Force -Path $AutoHotkeyArchive -DestinationPath $AutoHotkeyDirectory

New-Item -ItemType Directory -Force -Path $Ahk2ExeDirectory | Out-Null
Expand-Archive -Force -Path $Ahk2ExeArchive -DestinationPath $Ahk2ExeDirectory

$Compiler = Join-Path $Ahk2ExeDirectory "Ahk2Exe.exe"
$BaseExecutable = Join-Path $AutoHotkeyDirectory "AutoHotkey64.exe"

if (Test-Path $OutputExe) {
    Remove-Item -Force $OutputExe
}

Write-Host "Compiling 64-bit Windows executable..."
$CompilerArguments = @(
    "/in", ('"{0}"' -f $SourceScript),
    "/out", ('"{0}"' -f $OutputExe),
    "/base", ('"{0}"' -f $BaseExecutable),
    "/cp", "65001",
    "/silent", "verbose"
)
$CompilerProcess = Start-Process -FilePath $Compiler -ArgumentList $CompilerArguments -Wait -PassThru
if ($CompilerProcess.ExitCode -ne 0) {
    throw "Ahk2Exe failed with exit code $($CompilerProcess.ExitCode)."
}

if (-not (Test-Path $OutputExe)) {
    throw "The compiler completed without producing $OutputExe."
}

$OutputHash = (Get-FileHash -Algorithm SHA256 $OutputExe).Hash
Write-Host ""
Write-Host "Build completed: $OutputExe"
Write-Host "SHA-256: $OutputHash"
