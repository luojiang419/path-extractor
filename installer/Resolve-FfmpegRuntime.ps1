function Resolve-BinaryFromBasePath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ToolName,
        [string]$BasePath = ""
    )

    $candidates = @()
    if ($BasePath) {
        if (-not (Test-Path -LiteralPath $BasePath)) {
            throw "Path does not exist: $BasePath"
        }

        $resolvedBasePath = (Resolve-Path -LiteralPath $BasePath).Path
        $candidates += (Join-Path $resolvedBasePath "bin\$ToolName")
        $candidates += (Join-Path $resolvedBasePath $ToolName)
    }

    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }

    if ($BasePath) {
        throw "Unable to locate $ToolName under $BasePath."
    }

    $command = Get-Command $ToolName -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($command) {
        return $command.Source
    }

    throw "Unable to locate $ToolName."
}

function Resolve-FfmpegRuntime {
    param([string]$BasePath = "")

    $ffmpegPath = Resolve-BinaryFromBasePath -ToolName "ffmpeg.exe" -BasePath $BasePath
    $ffprobePath = Resolve-BinaryFromBasePath -ToolName "ffprobe.exe" -BasePath $BasePath
    $binaryDirectory = Split-Path -Parent $ffmpegPath
    $rootDirectory = if ((Split-Path -Leaf $binaryDirectory) -ieq "bin") {
        Split-Path -Parent $binaryDirectory
    } else {
        $binaryDirectory
    }

    [pscustomobject]@{
        FfmpegPath = $ffmpegPath
        FfprobePath = $ffprobePath
        BinaryDirectory = $binaryDirectory
        RootDirectory = $rootDirectory
    }
}
