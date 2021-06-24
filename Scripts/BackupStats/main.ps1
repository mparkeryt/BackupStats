param([switch]$DebugMode)
function Debug-Out {
    param (
        [Parameter(Mandatory,
            ParameterSetName='Message')]
        [string]$Message,
        [switch]$Pause
    )
    Write-Verbose $Message
    if ($Pause -and $DebugMode) {
        Read-Host -Prompt "Press any key to continue..."
    }
}

#TODO SCRIPT INFO
$scriptVersion = "0.4"
Write-Host "Script Ver. $scriptVersion"

$VerbosePreference = "Continue"

#Import customer specific config file
[xml]$configFile = Get-Content C:\Scripts\BackupStats\config.xml
Debug-Out -Message "Config file imported"

#Get Machine Name and trim whitespace
$machineName = Out-String -InputObject $([System.Net.Dns]::GetHostName())
$machineName = $machineName.Trim()
Debug-Out -Message "machineName set to $machineName"

#Get Customer Name
$customer = $configFile.configuration.customer.name
Debug-Out -Message "customer set to $customer"

#Get System Time
$time = Get-Date -Format "MM/dd/yyyy HH:mm:ss"
Debug-Out -Message "time set to $time"

#Get Windows Version
$OSVersion = [Environment]::OSVersion.Version -join '.'
Debug-Out -Message "OSVersion set to $OSVersion"

#Write previous values to json string
$json = @"
{
    "machineName": "$machineName",
    "customer": "$customer",
    "time": "$time",
    "OSVersion": "$OSVersion",
    "scriptVersion": "$scriptVersion",
    "iDrive": {
"@
Debug-Out -Message "json currently contains:"
Debug-Out -Message "$json" -Pause

#Import latest iDrive Backup information if enabled in config
if ($configFile.configuration.iDrive.logPath -ne "") {
    Debug-Out -Message "iDrive Path not empty, marking enabled"

    #Use customer defined path for iDrive log files
    $iDriveLogPath = $configFile.configuration.iDrive.logPath
    Debug-Out -Message "iDriveLogPath set to $iDriveLogPath"

    $iDriveExePath = $configFile.configuration.iDrive.exePath
    Debug-Out -Message "iDriveExePath set to $iDriveExePath"

    $logFile = Get-ChildItem $iDriveLogPath -Exclude "$machineName.xml" | Sort-Object LastWriteTime | Select-Object -Last 1
    [xml]$iDriveFile = Get-Content $logFile

    #Get currently installed iDrive program version
    $iDriveVersion = (Get-ItemProperty "$iDriveExePath").VersionInfo.FileVersion
    Debug-Out -Message "iDriveVersion set to $iDriveVersion"

    #Grab time, status and duration from the XML log file
    $iDriveDateTime = $iDriveFile.records.record.DateTime
    $iDriveStatus = $iDriveFile.records.record.status
    $iDriveDuration = $iDriveFile.records.record.duration
    Debug-Out -Message "iDriveDateTime set to $iDriveDateTime"
    Debug-Out -Message "iDriveStatus set to $iDriveStatus"
    Debug-Out -Message "iDriveDuration set to $iDriveDuration"

    #Append json string with new values
    $json += @"

        "enabled": "true",
        "version": "$iDriveVersion",
        "dateTime": "$iDriveDateTime",
        "status": "$iDriveStatus",
        "duration": "$iDriveDuration"
    },
    "windowsServerBackup": {
"@
    Debug-Out -Message "Json data now contains:"   
    Debug-Out -Message "$json" -Pause

} else {
    Debug-Out -Message "iDrive Path not specified, marking disabled"

    #Append JSON data indicating iDrive is not enabled on the unit
    $json += @"

        "enabled": "false"
    },
    "windowsServerBackup": {
"@
    Debug-Out -Message "Json data now contains:"
    Debug-Out -Message "$json" -Pause

}

#Check if Windows Server Backup module is installed on the server and get the policy
if (Get-Command Get-WBPolicy -errorAction SilentlyContinue) {
    Debug-Out -Message "Windows Server Backup installed, checking if enabled..."

    $windowsBackupPolicy = Get-WBPolicy
    #Now check if a policy has been set
    if ($windowsBackupPolicy) {
        Debug-Out -Message "Windows Server Backup is scheduled, grabbing last job info..."

        #Grab last completed job
        $windowsBackupJob = Get-WBJob -Previous 1

        #Grab relevant job data
        $windowsBackupJobType = $windowsBackupJob.JobType
        $windowsBackupStartTime = $windowsBackupJob.StartTime
        $windowsBackupEndTime = $windowsBackupJob.EndTime
        $windowsBackupJobState = $windowsBackupJob.JobState
        $windowsBackupError = $windowsBackupJob.ErrorDescription
        
        #Append more JSON data for the previous backup job
        $json += @"

        "enabled": "true",
        "jobType": "$windowsBackupJobType",
        "startTime": "$windowsBackupStartTime",
        "endTime": "$windowsBackupEndTime",
        "jobState": "$windowsBackupJobState",
        "errorDescription": "$windowsBackupError"
    }
"@
        Debug-Out -Message "Json data now contains:"
        Debug-Out -Message "$json" -Pause

    } else {
        Debug-Out -Message "Windows Server Backup is installed but not scheduled"

        $json += @"

        "enabled": "false"
    }
"@
        Debug-Out -Message "Json data now contains:"
        Debug-Out -Message "$json" -Pause

    }
} else {
    Debug-Out -Message "Windows Server Backup not installed"

    $json += @"

        "enabled": "false"
    }
"@
    Debug-Out -Message "Json data now contains:"
    Debug-Out -Message "$json" -Pause

}

#Cap off the json
$json += @"

}
"@
Debug-Out -Message "Json data now contains:"
Debug-Out -Message "$json"
Debug-Out -Message "Script complete" -Pause

Invoke-WebRequest -Uri http://fn-backuplogger.azurewebsites.net/api/jsonFile?code=lmHol5L9Gbkje5P6zJXjDauN9a08P4u98fIwfCULYKF/0SPHiR68hg== -Method POST -Body $json -ContentType 'application/json'