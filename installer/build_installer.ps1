param(
    [string]$PubspecPath = "..\path_extractor_browser\pubspec.yaml",
    [string]$IssPath = ".\path_extractor_browser.iss",
    [string]$IsccPath = "C:\Program Files (x86)\Inno Setup 6\ISCC.exe",
    [string]$FfmpegDir = "G:\data\ffmpeg"
)

$pubspecFullPath = Resolve-Path $PubspecPath
$issFullPath = Resolve-Path $IssPath
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$releaseDir = Join-Path $scriptDir "..\path_extractor_browser\build\windows\x64\runner\Release"

if (-not (Test-Path $IsccPath)) {
    throw "找不到 Inno Setup 编译器：$IsccPath"
}

if (-not (Test-Path $releaseDir)) {
    throw "找不到 Windows Release 目录：$releaseDir"
}

$versionLine = Get-Content $pubspecFullPath | Where-Object { $_ -match '^version:\s*' } | Select-Object -First 1
if (-not $versionLine) {
    throw "未在 pubspec.yaml 中找到 version 字段"
}

$versionValue = ($versionLine -replace '^version:\s*', '').Trim()
$appVersion = $versionValue.Split('+')[0]

function Resolve-FfmpegBinaryDirectory {
    param([string]$BasePath)

    if (-not (Test-Path $BasePath)) {
        throw "找不到 ffmpeg 目录：$BasePath"
    }

    $candidate = Join-Path $BasePath "bin\ffmpeg.exe"
    if (Test-Path $candidate) {
        return (Split-Path -Parent $candidate)
    }

    $candidate = Join-Path $BasePath "ffmpeg.exe"
    if (Test-Path $candidate) {
        return $BasePath
    }

    throw "在 $BasePath 中未找到 ffmpeg.exe"
}

function Copy-FfmpegRuntime {
    param(
        [string]$BinaryDirectory,
        [string]$TargetDirectory
    )

    $ffmpegBinary = Join-Path $BinaryDirectory "ffmpeg.exe"
    Copy-Item -LiteralPath $ffmpegBinary -Destination (Join-Path $TargetDirectory "ffmpeg.exe") -Force

    $licenseCandidates = @(
        (Join-Path (Split-Path -Parent $BinaryDirectory) "LICENSE"),
        (Join-Path (Split-Path -Parent $BinaryDirectory) "LICENSE.txt"),
        (Join-Path (Split-Path -Parent $BinaryDirectory) "COPYING"),
        (Join-Path (Split-Path -Parent $BinaryDirectory) "COPYING.txt")
    )

    $licenseFile = $licenseCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
    if ($licenseFile) {
        Copy-Item -LiteralPath $licenseFile -Destination (Join-Path $TargetDirectory "ffmpeg-LICENSE.txt") -Force
    } else {
        Write-Warning "未找到 ffmpeg 许可证文件，将继续构建安装包。"
    }
}

$ffmpegBinaryDirectory = Resolve-FfmpegBinaryDirectory -BasePath $FfmpegDir
Copy-FfmpegRuntime -BinaryDirectory $ffmpegBinaryDirectory -TargetDirectory $releaseDir

& $IsccPath "/DMyAppVersion=$appVersion" $issFullPath
if ($LASTEXITCODE -ne 0) {
    throw "安装包编译失败，退出码：$LASTEXITCODE"
}
