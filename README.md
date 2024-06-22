# Copy-at-rate
 Predominantly for video copying at the same rate that it is played to ensure that ssd usage is optimised in playback from a source

## How to run
Open PowerShell and run the script with the following command, replacing the parameters with your actual file paths, desired buffer size, and log file path. Enable logging if needed:

> .\CopyMp4WithRate.ps1 -sourceFilePath "C:\path\to\source\video.mp4" -destinationFilePath "C:\path\to\destination\video.mp4" -bufferSizeMB 10 -enableLogging $true -logFilePath "C:\path\to\copy_log.txt"