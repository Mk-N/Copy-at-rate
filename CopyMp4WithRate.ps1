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

# Function to get the size of the file in bytes
function Get-FileSize($filePath) {
    try {
        return (Get-Item $filePath).Length
    }
    catch {
        throw "Error occurred while determining file size: $_"
    }
}

# Function to copy the file with rate control
function Copy-WithRateControl {
    param (
        [System.IO.Stream]$sourceStream,
        [System.IO.Stream]$destinationStream,
        [long]$fileSize,
        [double]$rateBps
    )

    $chunkSize = 64 * 1024  # Starting chunk size
    $buffer = New-Object byte[] $chunkSize
    $totalBytesRead = 0
    $startTime = Get-Date

    try {
        while ($totalBytesRead -lt $fileSize) {
            $bytesToRead = [Math]::Min($chunkSize, $fileSize - $totalBytesRead)
            $bytesRead = $sourceStream.Read($buffer, 0, $bytesToRead)
            if ($bytesRead -eq 0) {
                break
            }
            $destinationStream.Write($buffer, 0, $bytesRead)
            $totalBytesRead += $bytesRead

            # Calculate elapsed time and adjust chunk size dynamically
            $elapsedSeconds = (Get-Date) - $startTime
            $currentRateBps = $totalBytesRead / $elapsedSeconds.TotalSeconds

            # Adjust chunk size based on current vs desired rate
            if ($currentRateBps -gt $rateBps) {
                $sleepTimeMs = [Math]::Ceiling(($totalBytesRead / $rateBps) * 1000) - [Math]::Ceiling($elapsedSeconds.TotalMilliseconds)
                if ($sleepTimeMs -gt 0) {
                    Start-Sleep -Milliseconds $sleepTimeMs
                }
            }
        }
    }
    catch {
        throw "Error occurred during file copy: $_"
    }
    finally {
        $sourceStream.Close()
        $destinationStream.Close()
    }
}

# Main script execution
try {
    # Get video duration and file size
    $videoDuration = Get-VideoDurationInSeconds $sourceFilePath
    Write-Log "Video duration: $videoDuration seconds"

    $fileSize = Get-FileSize $sourceFilePath
    Write-Log "File size: $fileSize bytes"

    # Calculate required rate in bytes per second
    $rateBps = $fileSize / $videoDuration
    Write-Log "Required rate: $rateBps bytes per second"

    # Open source and destination streams
    $sourceStream = [System.IO.File]::OpenRead($sourceFilePath)
    $destinationStream = [System.IO.File]::OpenWrite($destinationFilePath)

    # Copy file with rate control
    Copy-WithRateControl -sourceStream $sourceStream -destinationStream $destinationStream -fileSize $fileSize -rateBps $rateBps

    Write-Log "File copy completed successfully."
}
catch {
    Write-Log "Error: $_"
    exit 1
}