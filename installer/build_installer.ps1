param(
    [string]$PubspecPath = "..\path_extractor_browser\pubspec.yaml",
    [string]$IssPath = ".\path_extractor_browser.iss",
    [string]$IsccPath = "C:\Program Files (x86)\Inno Setup 6\ISCC.exe"
)

$pubspecFullPath = Resolve-Path $PubspecPath
$issFullPath = Resolve-Path $IssPath

if (-not (Test-Path $IsccPath)) {
    throw "找不到 Inno Setup 编译器：$IsccPath"
}

$versionLine = Get-Content $pubspecFullPath | Where-Object { $_ -match '^version:\s*' } | Select-Object -First 1
if (-not $versionLine) {
    throw "未在 pubspec.yaml 中找到 version 字段"
}

$versionValue = ($versionLine -replace '^version:\s*', '').Trim()
$appVersion = $versionValue.Split('+')[0]

& $IsccPath "/DMyAppVersion=$appVersion" $issFullPath
if ($LASTEXITCODE -ne 0) {
    throw "安装包编译失败，退出码：$LASTEXITCODE"
}
