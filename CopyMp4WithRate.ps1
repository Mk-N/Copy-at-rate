param (
    [string]$sourceFilePath,
    [string]$destinationFilePath,
    [int]$bufferSizeMB = 10  # User-defined buffer size in MB
)

# Function to get the video duration in seconds using ffmpeg
function Get-VideoDurationInSeconds($filePath) {
    try {
        $ffmpegOutput = & ffmpeg -i $filePath 2>&1 | Out-String
        if ($ffmpegOutput -match "Duration: (\d{2}):(\d{2}):(\d{2})\.(\d{2})") {
            $hours = [int]$matches[1]
            $minutes = [int]$matches[2]
            $seconds = [int]$matches[3]
            $milliseconds = [int]$matches[4]
            return ($hours * 3600) + ($minutes * 60) + $seconds + ($milliseconds / 100)
        }
        elseif ($ffmpegOutput -match "Duration: (\d+):(\d{2}):(\d{2})") {
            $hours = [int]$matches[1]
            $minutes = [int]$matches[2]
            $seconds = [int]$matches[3]
            return ($hours * 3600) + ($minutes * 60) + $seconds
        }
        else {
            throw "Could not determine video duration."
        }
    }
    catch {
        throw "Error occurred while determining video duration: $_"
    }
}

# Function to get the size of the metadata
function Get-MetadataSize($filePath) {
    try {
        $ffmpegOutput = & ffmpeg -i $filePath -f ffmetadata - 2>&1 | Out-String
        return [System.Text.Encoding]::UTF8.GetBytes($ffmpegOutput).Length
    }
    catch {
        throw "Error occurred while determining metadata size: $_"
    }
}

# Get the video duration in seconds
try {
    $videoDuration = Get-VideoDurationInSeconds $sourceFilePath
    Write-Host "Video duration: $videoDuration seconds"
}
catch {
    Write-Host $_
    exit 1
}

# Get the size of the file in bytes
$fileSize = (Get-Item $sourceFilePath).Length
Write-Host "File size: $fileSize bytes"

# Get the metadata size
try {
    $metadataSize = Get-MetadataSize $sourceFilePath
    Write-Host "Metadata size: $metadataSize bytes"
}
catch {
    Write-Host $_
    exit 1
}

# Calculate the required rate in bytes per second
$rateBps = ($fileSize - $metadataSize) / $videoDuration
Write-Host "Required rate: $rateBps bytes per second"

# Convert user-defined buffer size to bytes
$bufferSizeBytes = $bufferSizeMB * 1024 * 1024

# Set the initial chunk size to 1024 bytes (1 KB) and calculate the delay based on the rate
$chunkSize = 1024
$delayMilliseconds = [math]::Round((1000 * $chunkSize) / $rateBps)

# Adjust chunk size if the delay is less than 1 millisecond
if ($delayMilliseconds -lt 1) {
    $delayMilliseconds = 1
    $chunkSize = [math]::Round($rateBps / 1000)  # Adjust chunk size so rate per ms is approximately the specified rate
}

Write-Host "Chunk size: $chunkSize bytes"
Write-Host "Delay: $delayMilliseconds milliseconds"

# Open the source stream for reading and the destination stream for writing
$sourceStream = [System.IO.File]::OpenRead($sourceFilePath)
$destinationStream = [System.IO.File]::Open($destinationFilePath, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write, [System.IO.FileShare]::Read)

$buffer = New-Object byte[] $chunkSize
$totalBytesRead = 0

# Function to copy the initial metadata quickly
function CopyInitialBuffer($initialBytes) {
    $initialBuffer = New-Object byte[] $initialBytes
    $bytesRead = $sourceStream.Read($initialBuffer, 0, $initialBytes)
    $destinationStream.Write($initialBuffer, 0, $bytesRead)
    return $bytesRead
}

# Copy the metadata and initial buffer (user-defined)
$initialBytes = $metadataSize + $bufferSizeBytes
try {
    $totalBytesRead += CopyInitialBuffer $initialBytes
    Write-Host "Initial metadata and buffer of $initialBytes bytes copied quickly."
}
catch {
    Write-Host "Error occurred during initial buffer copy: $_"
    $sourceStream.Close()
    $destinationStream.Close()
    exit 1
}

# Separating the bytes of non-metadata and metadata data apart, so that target time and actal rate is calculated accurately.
$totalBytesAtRateRead = 0

# Timer to measure copy rate of non-metadata data
$startTime = [System.Diagnostics.Stopwatch]::StartNew()

try {
    while (($bytesRead = $sourceStream.Read($buffer, 0, $buffer.Length)) -gt 0) {
        $destinationStream.Write($buffer, 0, $bytesRead)
        $totalBytesAtRateRead += $bytesRead
        $totalBytesRead += $totalBytesAtRateRead

        # Calculate elapsed time and actual copy rate
        $elapsedTime = $startTime.Elapsed.TotalSeconds
        $actualRateBps = $totalBytesAtRateRead / $elapsedTime
        Write-Host "Copied $totalBytesRead bytes at $([math]::Round($actualRateBps / 1024, 2)) KBps... with sleep time $($sleepTime * 1000)"

        # Sleep to maintain the target copy rate
        [decimal]$targetTime = $totalBytesAtRateRead / $rateBps
        [decimal]$sleepTime = $targetTime - $elapsedTime
        if ($sleepTime -gt 0) {
            Start-Sleep -Milliseconds ([math]::Floor($sleepTime * 1000))
        }
    }
}
catch {
    Write-Host "Error occurred during file copy: $_"
}
finally {
    $sourceStream.Close()
    $destinationStream.Close()
}

Write-Host "File copy completed. Total bytes copied: $totalBytesRead"
Write-Host "Target copy duration: $videoDuration seconds"