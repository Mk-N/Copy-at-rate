param (
    [string]$sourceFilePath,
    [string]$destinationFilePath,
    [int]$rateKbps
)

# Convert rate from kilobits per second to bytes per second
$rateBps = $rateKbps * 1024 / 8

# Set the initial chunk size to 1024 bytes (1 KB)
$chunkSize = 1024
$delayMilliseconds = [math]::Round((1000 * $chunkSize) / $rateBps)

# Adjust chunk size if the delay is less than 1 millisecond
if ($delayMilliseconds -lt 1) {
    $delayMilliseconds = 1
    $chunkSize = [math]::Round(($rateBps * $delayMilliseconds) / 1000)
}

$sourceStream = [System.IO.File]::OpenRead($sourceFilePath)
$destinationStream = [System.IO.File]::OpenWrite($destinationFilePath)

$buffer = New-Object byte[] $chunkSize
$totalBytesRead = 0

try {
    while (($bytesRead = $sourceStream.Read($buffer, 0, $buffer.Length)) -gt 0) {
        $destinationStream.Write($buffer, 0, $bytesRead)
        $totalBytesRead += $bytesRead
        Write-Host "Copied $totalBytesRead bytes..."
        Start-Sleep -Milliseconds $delayMilliseconds
    }
}
finally {
    $sourceStream.Close()
    $destinationStream.Close()
}

Write-Host "File copy completed. Total bytes copied: $totalBytesRead"