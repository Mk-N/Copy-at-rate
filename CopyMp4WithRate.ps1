param (
    [string]$sourceFilePath,
    [string]$destinationFilePath,
    [int]$bufferSizeMB = 10, # User-defined buffer size in MB
    [int]$minChunkSizeKB = 1, # Minimum chunk size in KB
    [switch]$logToFile = $false, # Switch to enable/disable logging to file
    [string]$logFilePath = "logs\Log.txt", # Path to the log file
    [string]$CSVlogFilePath = "logs\CSVLog.csv", # Path to the log file
    [switch]$enableGraphs = $false, # Switch to enable/disable graphs
    [string]$graphDirectory = "", # Directory to save graphs
    [string]$graphDirectory2 = "", # Optional second directory for second graph
    [string]$dataRateGraphName = "data_rate_vs_bytes_copied.svg", # Name of the data rate vs bytes copied graph
    [string]$sleepChunkGraphName = "sleep_time_chunk_size_vs_bytes_copied.svg", # Name of the sleep time and chunk size vs bytes copied graph
    [string]$pythonScriptFilePath = ""
)

# Function to perform accurate division of a numerator by a denominator
function AccurateDivision {
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [System.Object]$numerator,

        [Parameter(Mandatory = $true)]
        [System.Object]$denominator
    )

    # Convert inputs to strings if they are not already strings
    $numerator_str = $numerator.ToString()
    $denominator_str = $denominator.ToString()

    # Validate numerator and denominator as numeric strings
    if (-not $numerator_str -match '^\d+$') {
        throw "Numerator must be a positive integer string."
    }

    if (-not $denominator_str -match '^\d+(\.\d+)?$') {
        throw "Denominator must be a numeric string."
    }

    # Parse numerator to [System.Numerics.BigInteger]
    try {
        $bigIntNumerator = [System.Numerics.BigInteger]::Parse($numerator_str)
    }
    catch {
        throw "Error parsing numerator '$numerator_str' to BigInteger."
    }

    # Parse denominator to [decimal]
    try {
        $decimalDenominator = [decimal]::Parse($denominator_str)
    }
    catch {
        throw "Error parsing denominator '$denominator_str' to decimal."
    }

    # Convert decimalDenominator to scaled integer
    $decimalPlaces = 0
    if ($denominator_str -match '\.') {
        $decimalPlaces = $denominator_str.Split('.')[1].Length
    }
    $scaledDenominator = [decimal]::Round($decimalDenominator * [decimal]::Parse("1" + ("0" * $decimalPlaces)))

    # Perform division
    if ($scaledDenominator -eq 0) {
        throw "Division by zero."
    }
    $result = [decimal]::Round($bigIntNumerator / $scaledDenominator, $decimalPlaces)

    return $result
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
        $fileInfo = Get-Item $filePath
        return $fileInfo.Length
    }
    catch {
        throw "Error occurred while determining file size: $_"
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

# Function to log messages to console and optionally to a file
function Write-Log($message) {
    Write-Host $message
    if ($logToFile) {
        Add-Content -Path $logFilePath -Value $message
    }
}

# Function to log data to CSV
function Write-CSVLog($bytesCopied, $dataRate, $targetDataRate, $sleepTime, $chunkSize) {
    $csvLine = "$bytesCopied,$dataRate,$targetDataRate,$sleepTime,$chunkSize"
    Add-Content -Path $CSVlogFilePath -Value $csvLine
}

try {
    # Check and load System.Numerics assembly if necessary
    if (-not ([System.Management.Automation.PSTypeName]'System.Numerics.BigInteger').Type) {
        Add-Type -AssemblyName System.Numerics
    }
}
catch {
    Write-Error "An error occurred: $_"
}

# Initialize CSV log
if ($logToFile) {
    $csvHeader = "BytesCopied,DataRateKBps,TargetDataRateKBps,SleepTimeMs,ChunkSize"
    Set-Content -Path $CSVlogFilePath -Value $csvHeader
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
try {
    $fileSize = Get-FileSize $sourceFilePath
    Write-Log "File size: $fileSize bytes"
}
catch {
    Write-Log $_
    exit 1
}

# Get the metadata size
try {
    $metadataSize = Get-MetadataSize $sourceFilePath
    Write-Log "Metadata size: $metadataSize bytes"
}
catch {
    Write-Log $_
    exit 1
}

# Calculate the required rate in bytes per second
Write-Log "line 116"
[decimal]$rateBps = ($fileSize - $metadataSize) / $videoDuration
Write-Log "line 119"
[decimal]$targetRateKBps = $rateBps / 1024
Write-Log "Required rate: $rateBps bytes per second ($targetRateKBps KBps)"

# Convert user-defined buffer size to bytes
$bufferSizeBytes = $bufferSizeMB * 1024 * 1024

# Set the initial chunk size to 1024 bytes (1 KB) or user min, whichever is greater, and calculate the delay based on the rate
$chunkSize = [math]::Max(($minChunkSizeKB * 1024), 1024)
Write-Log "line 128"
$delayMilliseconds = [math]::Round((1000 * $chunkSize) / $rateBps)

# Adjust chunk size if the delay is less than 1 millisecond
if ($delayMilliseconds -lt 1) {
    $delayMilliseconds = 1
    Write-Log "line 134"
    $chunkSize = [math]::Round($rateBps / 1000)  # Adjust chunk size so rate per ms is approximately the specified rate
}

Write-Log "Initial chunk size: $chunkSize bytes"
Write-Log "Initial delay: $delayMilliseconds milliseconds"

# Open the source stream for reading and the destination stream for writing
$sourceStream = [System.IO.File]::OpenRead($sourceFilePath)
$destinationStream = [System.IO.File]::Open($destinationFilePath, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write, [System.IO.FileShare]::Read)

$buffer = New-Object byte[] $chunkSize
[decimal]$totalBytesRead = 0

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
    [decimal]$totalBytesRead += CopyInitialBuffer $initialBytes
    Write-Log "Initial metadata and buffer of $initialBytes bytes copied quickly."
}
catch {
    Write-Log "Error occurred during initial buffer copy: $_"
    $sourceStream.Close()
    $destinationStream.Close()
    exit 1
}

# Separating the bytes of non-metadata and metadata data apart, so that target time and actual rate is calculated accurately.
[decimal]$totalBytesAtRateRead = 0

if ($enableGraphs) {
    # Create an array of arguments
    $arguments = @($logFilePath, $graphDirectory, $graphDirectory2, $dataRateGraphName, $sleepChunkGraphName)

    # Join arguments into a single string separated by spaces
    $argumentString = $arguments -join " "

    # Start the Python script using Start-Process
    Start-Process python -ArgumentList "$pythonScriptFilePath $argumentString" -Wait
}

# Timer to measure copy rate of non-metadata data
$startTime = [System.Diagnostics.Stopwatch]::StartNew()

try {
    while (($bytesRead = $sourceStream.Read($buffer, 0, $buffer.Length)) -gt 0) {
        $destinationStream.Write($buffer, 0, $bytesRead)
        [decimal]$totalBytesAtRateRead += $bytesRead
        [decimal]$totalBytesRead += $totalBytesAtRateRead

        # Calculate elapsed time and actual copy rate
        [decimal]$elapsedTime = $startTime.Elapsed.TotalSeconds
        Write-Log "line 187"
        Write-Log "$elapsedTime"
        Write-Log "$totalBytesAtRateRead"
        [decimal]$actualRateBps = $totalBytesAtRateRead / $elapsedTime
        Write-Log "line 190"
        [decimal]$actualRateKBps = $actualRateBps / 1024

        # Sleep to maintain the target copy rate
        Write-Log "line 193"
        [decimal]$targetTime = $totalBytesAtRateRead / $rateBps
        [decimal]$sleepTime = $targetTime - $elapsedTime
        if ($sleepTime -gt 0) {
            Start-Sleep -Milliseconds ([math]::Floor($sleepTime * 1000))
        }
        else {
            # Adjust chunk size if falling behind
            $chunkSize = $chunkSize * 2
            $buffer = New-Object byte[] $chunkSize
            Write-Log "Falling behind, increasing chunk size to $chunkSize bytes"
        }

        # Reduce chunk size if too far ahead
        if ($sleepTime -gt 1000) {
            if ($chunkSize -gt ($minChunkSizeKB * 1024)) {
                Write-Log "line 210"
                $chunkSize = [math]::Max([math]::Round($chunkSize / 2), ($minChunkSizeKB * 1024)) # round now because this tends to overshoot
                $buffer = New-Object byte[] $chunkSize
                Write-Log "Too far ahead, reducing chunk size to $chunkSize bytes"
            }
            else {
                $extraSleepTime = [math]::Min([math]::Floor($sleepTime - 1000), 1000) # Cap the extra sleep time to 1 second
                Write-Log "Too far ahead, already at minimum chunk size. Adding extra sleep time of $extraSleepTime milliseconds."
                Start-Sleep -Milliseconds $extraSleepTime
            }
        }

        #log data
        Write-Log "Copied $totalBytesRead bytes at $actualRateKBps KBps with sleep time $($sleepTime * 1000) ms"

        # Log data to CSV
        if ($logToFile) {
            Write-CSVLog $totalBytesRead $actualRateKBps $targetRateKBps $delayMilliseconds $chunkSize
        }
    }
}
catch {
    Write-Log "Error occurred during file copy: $_"
}
finally {
    $startTime.Stop()
    $startTime.Reset()
    $sourceStream.Close()
    $destinationStream.Close()
}

Write-Log "File copy completed. Total bytes copied: $totalBytesRead"
Write-Log "Target copy duration: $videoDuration seconds"
