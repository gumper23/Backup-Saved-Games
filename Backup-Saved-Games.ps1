##############################################################################
# BackupGameSaves.ps1 <full-path-to-saved-game-file>
# Purpose: 
# Copies saved game files; intended to be ran with Task Scheduler
# The backups are stored in the game's save directory
#
# Arguments: 
# Can be called with -saveFile or -numBackups arguments
# -saveFile is a required argument
# -numBackups is the number of backups to keep
# 
# If this script is ran as intended, using Task Scheduler, the number of
# backups * the run interval (typically every 5 minutes) is the amount of
# time you can roll back to.
# For example, if this is scheduled to run every 5 minutes, and numBackups
# = 10, then the saved file can be rolled backup up to 50 minutes prior.
##############################################################################
param ($saveFile, [uint32]$numBackups=10)
$scriptName = $MyInvocation.MyCommand.Name

##############################################################################
# ShowUsageAndExit displays the usage message
##############################################################################
function ShowUsageAndExit {
    Write-Output "Usage:   ${scriptName} <full-path-to-saved-game> [num-backups-to-keep (default 10)]"
    Write-Output "Example: ${scriptName} C:\Users\<user>\AppData\Roaming\DarkSoulsIII\0110000102d59fe8\DS30000.sl2"
    exit 1
}

##############################################################################
# FilesAreEqual is a performant file comparison method
# https://keestalkstech.com/2013/01/comparing-files-with-powershell/
##############################################################################
function FilesAreEqual {
    param(
        [System.IO.FileInfo] $first,
        [System.IO.FileInfo] $second, 
        [uint32] $bufferSize = 524288) 

    if ($first.Length -ne $second.Length) { 
        return $false
    }

    if ( $bufferSize -eq 0 ) { 
        $bufferSize = 524288
    }

    $fs1 = $first.OpenRead()
    $fs2 = $second.OpenRead()

    $one = New-Object byte[] $bufferSize
    $two = New-Object byte[] $bufferSize
    $equal = $true

    do {
        $bytesRead = $fs1.Read($one, 0, $bufferSize)
        $fs2.Read($two, 0, $bufferSize) | out-null

        if ( -Not [System.Linq.Enumerable]::SequenceEqual($one, $two)) {
            $equal = $false
        }

    } while ($equal -and $bytesRead -eq $bufferSize)

    $fs1.Close()
    $fs2.Close()

    return $equal
}

##############################################################################
# GetTimestamp returns the current date/time as a 14 digit string
##############################################################################
function GetTimestamp {
    return "{0:yyyyMMddHHmmss}" -f (Get-Date)
}

##############################################################################
# GetLogTimestamp returns date/time in human-readable form for logging:
# Ex: [2021-09-12 06:00:00]:
##############################################################################
function GetLogTimeStamp {
    return "[{0:yyyy-MM-dd} {0:HH:mm:ss}]:" -f (Get-Date)
}

##############################################################################
# BackupGameFile copies $savedGameFile to a backup file with the name:
# $savedFileName.YYYYMMDDHHMMSS (14 digit date/time stamp)
##############################################################################
function BackupGameFile {
    param(
        [string] $savedGameFile
    ) 

    ##########################################################################
    # Ensure savedGameFile exists
    ##########################################################################
    if (-Not (Test-Path -Path $savedGameFile -PathType Leaf)) {
        throw "$(GetTimestamp): ERROR -  ${savedGameFile} does not exist"
    }

    ##########################################################################
    # Ensure backupFile does NOT exist
    ##########################################################################
    $savedGameFilePath = Split-Path -Path $savedGameFile
    $savedGameFileName = Split-Path -Leaf $savedGameFile
    $backupFile = Join-Path $savedGameFilePath "${savedGameFileName}.$(GetTimestamp)"
    if (Test-Path -Path $backupFile -PathType Leaf) {
        throw "$(GetTimestamp): ERROR - ${backupFile} exists"
    }
    Copy-Item $savedGameFile -Destination $backupFile
}

##############################################################################
# Validate script arguments
# Save file name is a required argument 
# numBackups must be > 0 
##############################################################################
if (-Not $saveFile) {
    Write-Output "saveFile argument missing"
    ShowUsageAndExit
}
if (-Not (Test-Path -Path $saveFile -PathType Leaf)) {
    Write-Output "${saveFile} saveFile must exist"
    ShowUsageAndExit
}
if (-Not $numBackups -gt 0) {
    Write-Output "numBackups must be > 0"
    ShowUsageAndExit
}

##############################################################################
# Backup the saved game file if a backup doesn't exist or the most
# recent backup file doesn't match the saved game file
##############################################################################
$saveFileName = Split-Path -Leaf $saveFile
$saveFilePath = Split-Path -Path $saveFile
$logFileName  = $scriptName + ".log"
$logFilePath = Join-Path $saveFilePath $logFileName
$newestFile = Get-ChildItem -Path $saveFilePath | Where-Object { $_.Name -match "^${saveFileName}\.[0-9]{14}$" } | Sort-Object CreationTime | Select-Object -Last 1
$needsCopy = $false
if (-Not $newestFile) {
    $needsCopy = $true
} else {
    $newestFile = Join-Path $saveFilePath $newestFile
    if (-Not (FilesAreEqual $saveFile $newestFile)) {
        $needsCopy = $true
    }
}
if ($needsCopy) {
    Write-Output "$(GetLogTimeStamp) COPYING [${saveFile}]" | Out-File -FilePath $logFilePath -Append
    BackupGameFile $saveFile  
}

##############################################################################
# Delete oldest backup file(s)
# Used a for loop instead of a while loop to reduce risk of infinite loop
##############################################################################
$backupFileCount = (Get-ChildItem -Path $saveFilePath | Where-Object { $_.Name -match "^${saveFileName}\.[0-9]{14}$" }).count
$filesToDeleteCount = $backupFileCount - $numBackups
for ($i = 0; $i -lt $filesToDeleteCount; $i++) {
    ##########################################################################
    # Find the oldest file that matches the backup pattern and delete it
    ##########################################################################
    $oldestFile = Get-ChildItem -Path $saveFilePath | Where-Object { $_.Name -match "^${saveFileName}\.[0-9]{14}$" } | Sort-Object CreationTime | Select-Object -First 1
    $oldestFile = Join-Path $saveFilePath $oldestFile
    Write-Output "$(GetLogTimeStamp) DELETING [${oldestFile}]" | Out-File -FilePath $logFilePath -Append
    Remove-Item -Path $oldestFile
}
