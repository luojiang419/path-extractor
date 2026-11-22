param(
    [string]$FfmpegDir = ""
)

. "$PSScriptRoot\Resolve-FfmpegRuntime.ps1"

$runtime = Resolve-FfmpegRuntime -BasePath $FfmpegDir

$requiredDlls = @(
    Get-ChildItem -LiteralPath $runtime.BinaryDirectory -Filter "avcodec-*.dll" -ErrorAction SilentlyContinue | Select-Object -First 1
    Get-ChildItem -LiteralPath $runtime.BinaryDirectory -Filter "avformat-*.dll" -ErrorAction SilentlyContinue | Select-Object -First 1
) | Where-Object { $_ }
if ($requiredDlls.Count -lt 2) {
    throw "Expected an LGPL shared FFmpeg runtime with avcodec/avformat DLLs in $($runtime.BinaryDirectory)."
}

$ffprobeVersion = & $runtime.FfprobePath -hide_banner -version 2>&1
if ($LASTEXITCODE -ne 0) {
    throw "ffprobe failed to start.`n$($ffprobeVersion | Out-String)"
}

$buildConfig = & $runtime.FfmpegPath -hide_banner -buildconf 2>&1
if ($LASTEXITCODE -ne 0) {
    throw "ffmpeg -buildconf failed.`n$($buildConfig | Out-String)"
}

$buildConfigText = $buildConfig | Out-String
if ($buildConfigText -match '--enable-gpl' -or $buildConfigText -match '--enable-version3') {
    throw "FFmpeg runtime is not LGPL-only.`n$buildConfigText"
}

$decoders = & $runtime.FfmpegPath -hide_banner -decoders 2>&1
if ($LASTEXITCODE -ne 0) {
    throw "ffmpeg -decoders failed.`n$($decoders | Out-String)"
}

$decodersText = $decoders | Out-String
foreach ($decoderName in @("dnxhd", "prores", "psd")) {
    if (-not ($decodersText | Select-String -Pattern "\b$decoderName\b" -Quiet)) {
        throw "Missing required decoder: $decoderName"
    }
}

$encoders = & $runtime.FfmpegPath -hide_banner -encoders 2>&1
if ($LASTEXITCODE -ne 0) {
    throw "ffmpeg -encoders failed.`n$($encoders | Out-String)"
}

$encodersText = $encoders | Out-String
if (-not ($encodersText | Select-String -Pattern "\bpng\b" -Quiet)) {
    throw "Missing required encoder: png"
}

$demuxers = & $runtime.FfmpegPath -hide_banner -demuxers 2>&1
if ($LASTEXITCODE -ne 0) {
    throw "ffmpeg -demuxers failed.`n$($demuxers | Out-String)"
}

$demuxersText = $demuxers | Out-String
foreach ($demuxerName in @("image2", "mov", "mxf")) {
    if (-not ($demuxersText | Select-String -Pattern "\b$demuxerName\b" -Quiet)) {
        throw "Missing required demuxer: $demuxerName"
    }
}

$muxers = & $runtime.FfmpegPath -hide_banner -muxers 2>&1
if ($LASTEXITCODE -ne 0) {
    throw "ffmpeg -muxers failed.`n$($muxers | Out-String)"
}

$muxersText = $muxers | Out-String
if (-not ($muxersText | Select-String -Pattern "\bimage2\b" -Quiet)) {
    throw "Missing required muxer: image2"
}

Write-Host "FFmpeg runtime smoke check passed."
