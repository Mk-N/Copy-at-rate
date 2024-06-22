param (
    [string]$sourceFilePath,
    [string]$destinationFilePath,
    [int]$bufferSizeMB = 10, # User-defined buffer size in MB
    [bool]$enableLogging = $false, # Enable or disable logging
    [string]$logFilePath = "copy_log.txt"  # Default log file path
)

# Function to write logs to both the console and the log file (if logging is enabled)
function Write-Log($message) {
    Write-Host $message
    if ($enableLogging) {
        Add-Content -Path $logFilePath -Value $message
    }
}

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

# Initialize or clear the log file if logging is enabled
if ($enableLogging) {
    if (Test-Path $logFilePath) {
        Clear-Content $logFilePath
    }
    else {
        New-Item -Path $logFilePath -ItemType File
    }
}

# Get the video duration in seconds
try {
    $videoDuration = Get-VideoDurationInSeconds $sourceFilePath
    Write-Log "Video duration: $videoDuration seconds"
}
catch {
    Write-Log $_
    exit 1
}

# Get the size of the file in bytes
$fileSize = (Get-Item $sourceFilePath).Length
Write-Log "File size: $fileSize bytes"

# Calculate the required rate in bytes per second
$rateBps = $fileSize / $videoDuration
Write-Log "Required rate: $rateBps bytes per second"

# Get the metadata size
try {
    $metadataSize = Get-MetadataSize $sourceFilePath
    Write-Log "Metadata size: $metadataSize bytes"
}
catch {
    Write-Log $_
    exit 1
}

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

Write-Log "Chunk size: $chunkSize bytes"
Write-Log "Delay: $delayMilliseconds milliseconds"

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
    Write-Log "Initial metadata and buffer of $initialBytes bytes copied quickly."
}
catch {
    Write-Log "Error occurred during initial buffer copy: $_"
    $sourceStream.Close()
    $destinationStream.Close()
    exit 1
}

# Timer to measure copy rate
$startTime = [System.Diagnostics.Stopwatch]::StartNew()

try {
    while (($bytesRead = $sourceStream.Read($buffer, 0, $buffer.Length)) -gt 0) {
        $destinationStream.Write($buffer, 0, $bytesRead)
        $totalBytesRead += $bytesRead

        # Calculate elapsed time and actual copy rate
        $elapsedTime = $startTime.Elapsed.TotalSeconds
        $actualRateBps = $totalBytesRead / $elapsedTime
        Write-Log "Copied $totalBytesRead bytes at $([math]::Round($actualRateBps / 1024, 2)) KBps..."

        # Sleep to maintain the target copy rate
        $targetTime = $totalBytesRead / $rateBps
        $sleepTime = $targetTime - $elapsedTime
        if ($sleepTime -gt 0) {
            Start-Sleep -Milliseconds ([math]::Round($sleepTime * 1000))
        }
    }
}
catch {
    Write-Log "Error occurred during file copy: $_"
}
finally {
    $sourceStream.Close()
    $destinationStream.Close()
}

Write-Log "File copy completed. Total bytes copied: $totalBytesRead"
Write-Log "Target copy duration: $videoDuration seconds"