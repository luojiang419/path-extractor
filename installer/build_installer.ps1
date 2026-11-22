param(
    [string]$PubspecPath = "..\path_extractor_browser\pubspec.yaml",
    [string]$IssPath = ".\path_extractor_browser.iss",
    [string]$IsccPath = "C:\Program Files (x86)\Inno Setup 6\ISCC.exe",
    [string]$FfmpegDir = "",
    [string]$FfmpegSourceUrl = "",
    [string]$FfmpegReleaseUrl = ""
)

$pubspecFullPath = Resolve-Path $PubspecPath
$issFullPath = Resolve-Path $IssPath
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$releaseDir = Join-Path $scriptDir "..\path_extractor_browser\build\windows\x64\runner\Release"

. "$scriptDir\Resolve-FfmpegRuntime.ps1"

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

function Copy-FfmpegRuntime {
    param(
        [pscustomobject]$Runtime,
        [string]$TargetDirectory,
        [string]$SourceUrl = "",
        [string]$ReleaseUrl = ""
    )

    $licenseDir = Join-Path $TargetDirectory "licenses\ffmpeg"
    if (Test-Path -LiteralPath $licenseDir) {
        Remove-Item -LiteralPath $licenseDir -Recurse -Force
    }
    New-Item -ItemType Directory -Path $licenseDir -Force | Out-Null

    foreach ($stalePath in @(
        (Join-Path $TargetDirectory "ffmpeg.exe"),
        (Join-Path $TargetDirectory "ffprobe.exe")
    )) {
        if (Test-Path -LiteralPath $stalePath) {
            Remove-Item -LiteralPath $stalePath -Force
        }
    }
    foreach ($dllPattern in @(
        "avcodec-*.dll",
        "avdevice-*.dll",
        "avfilter-*.dll",
        "avformat-*.dll",
        "avutil-*.dll",
        "postproc-*.dll",
        "swresample-*.dll",
        "swscale-*.dll"
    )) {
        Get-ChildItem -LiteralPath $TargetDirectory -Filter $dllPattern -ErrorAction SilentlyContinue |
            Remove-Item -Force
    }

    foreach ($binaryPath in @($Runtime.FfmpegPath, $Runtime.FfprobePath)) {
        Copy-Item -LiteralPath $binaryPath -Destination (Join-Path $TargetDirectory (Split-Path -Leaf $binaryPath)) -Force
    }

    Get-ChildItem -LiteralPath $Runtime.BinaryDirectory -Filter "*.dll" -ErrorAction SilentlyContinue |
        ForEach-Object {
            Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $TargetDirectory $_.Name) -Force
        }

    $licenseCandidates = @(
        (Join-Path $Runtime.RootDirectory "LICENSE"),
        (Join-Path $Runtime.RootDirectory "LICENSE.txt"),
        (Join-Path $Runtime.RootDirectory "LICENSE.md"),
        (Join-Path $Runtime.RootDirectory "COPYING"),
        (Join-Path $Runtime.RootDirectory "COPYING.txt"),
        (Join-Path $Runtime.RootDirectory "COPYING.LGPLv2.1"),
        (Join-Path $Runtime.RootDirectory "COPYING.LGPLv3"),
        (Join-Path $Runtime.RootDirectory "README"),
        (Join-Path $Runtime.RootDirectory "README.md"),
        (Join-Path $Runtime.RootDirectory "README.txt")
    ) | Select-Object -Unique

    $copiedLicenseFile = $false
    foreach ($licensePath in $licenseCandidates) {
        if (Test-Path -LiteralPath $licensePath) {
            Copy-Item -LiteralPath $licensePath -Destination (Join-Path $licenseDir (Split-Path -Leaf $licensePath)) -Force
            $copiedLicenseFile = $true
        }
    }

    if (-not $copiedLicenseFile) {
        Write-Warning "No FFmpeg license/readme files were found next to the runtime package."
    }

    (& $Runtime.FfmpegPath -hide_banner -version 2>&1) |
        Set-Content -Path (Join-Path $licenseDir "ffmpeg-version.txt") -Encoding utf8
    (& $Runtime.FfmpegPath -hide_banner -buildconf 2>&1) |
        Set-Content -Path (Join-Path $licenseDir "ffmpeg-buildconf.txt") -Encoding utf8

    $upstreamLines = @(
        "FFmpeg runtime package information",
        "Binary: $($Runtime.FfmpegPath)",
        "ffprobe: $($Runtime.FfprobePath)"
    )
    if ($SourceUrl) {
        $upstreamLines += "Asset URL: $SourceUrl"
    }
    if ($ReleaseUrl) {
        $upstreamLines += "Release URL: $ReleaseUrl"
    }
    $upstreamLines | Set-Content -Path (Join-Path $licenseDir "UPSTREAM.txt") -Encoding utf8
}

$ffmpegRuntime = Resolve-FfmpegRuntime -BasePath $FfmpegDir
Copy-FfmpegRuntime `
    -Runtime $ffmpegRuntime `
    -TargetDirectory $releaseDir `
    -SourceUrl $FfmpegSourceUrl `
    -ReleaseUrl $FfmpegReleaseUrl

& $IsccPath "/DMyAppVersion=$appVersion" $issFullPath
if ($LASTEXITCODE -ne 0) {
    throw "安装包编译失败，退出码：$LASTEXITCODE"
}
