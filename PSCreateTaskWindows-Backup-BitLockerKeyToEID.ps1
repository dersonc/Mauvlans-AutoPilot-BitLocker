# *******************************************************************************************************************
#
# Purpose: This script creates a PowerShell script file on the device and configures a scheduled task 
# to start automatically on events:
# - 306 Automatic registration Succeeded.
# - 335 Automatic device join pre-check tasks completed. The device is already joined.
# - 768 BitLocker encryption started for volume.
#
# The scheduled task will run 10 seconds after creation and execute the PowerShell script file to back up all 
# BitLocker recovery keys found on the device to Entra ID.
#
# Requirement: the device must be Entra joined or Entra hybrid joined to copy the recovery key to Entra ID.
#
# ------------------------------------------- DISCLAIMER ------------------------------------------------------------
# This Sample Code is provided for the purpose of illustration only and is not intended to be used 
# in a production environment. THIS SAMPLE CODE AND ANY RELATED INFORMATION ARE PROVIDED "AS IS" 
# WITHOUT WARRANTY OF ANY KIND, EITHER EXPRESSED OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE IMPLIED 
# WARRANTIES OF MERCHANTABILITY AND/OR FITNESS FOR A PARTICULAR PURPOSE. We grant You a nonexclusive, 
# royalty-free right to use and modify the Sample Code and to reproduce and distribute the object code 
# form of the Sample Code, provided that You agree: (i) to not use Our name, logo, or trademarks to 
# market Your software product in which the Sample Code is embedded; (ii) to include a valid copyright 
# notice on Your software product in which the Sample Code is embedded; and (iii) to indemnify, hold 
# harmless, and defend Us and Our suppliers from and against any claims or lawsuits, including attorneys’ 
# fees, that arise or result from the use or distribution of the Sample Code.
#
# This sample script is not supported under any Microsoft standard support program or service. 
# The sample script is provided AS IS without warranty of any kind. Microsoft further disclaims 
# all implied warranties including, without limitation, any implied warranties of merchantability 
# or of fitness for a particular purpose. The entire risk arising out of the use or performance of 
# the sample scripts and documentation remains with you. In no event shall Microsoft, its authors, 
# or anyone else involved in the creation, production, or delivery of the scripts be liable for any 
# damages whatsoever (including, without limitation, damages for loss of business profits, business 
# interruption, loss of business information, or other pecuniary loss) arising out of the use of or 
# inability to use the sample scripts or documentation, even if Microsoft has been advised of the 
# possibility of such damages.
# ------------------------------------------- DISCLAIMER ------------------------------------------------------------
#
# *******************************************************************************************************************

# Script to copy all BitLocker recovery keys to Entra ID

#region Script
$content = @'
Try {
    Get-BitLockerVolume | ForEach-Object {
        $MountPoint = $_.MountPoint
        $ProtectionStatus = $_.ProtectionStatus
        $VolumeStatus = $_.VolumeStatus
        Write-Output "BitLocker is [$ProtectionStatus] for the drive [$MountPoint] and the current status is [$VolumeStatus]."
        $BitLockerVolume = Get-BitLockerVolume -MountPoint $MountPoint
        $BitLockerVolume.KeyProtector | Where-Object { $_.KeyProtectorType -eq 'RecoveryPassword' } | ForEach-Object {
            Try {
                $KeyProtectorId = $_.KeyProtectorId
                BackupToAAD-BitLockerKeyProtector -MountPoint $MountPoint -KeyProtectorId $KeyProtectorId -ErrorAction SilentlyContinue
                Write-Output "Started backup of recovery key with protector ID [$KeyProtectorId] from drive [$MountPoint] to Entra ID."
            } Catch {
                Write-Error "Failed to backup recovery key with protector ID [$KeyProtectorId] from drive [$MountPoint] to Entra ID."
            }
        }
    }
} Catch {
    Write-Error "Error backing up BitLocker recovery key."
}
'@
#endregion
 
# Creates custom folder and writes PS script to it

#region CreateScript
$scriptFolder = "$env:ProgramData\CustomScripts"
$scriptFullPath = Join-Path $scriptFolder \Backup-BitLockerKeyToAAD.ps1
if (!(Test-Path $scriptFolder)) { New-Item -Path $scriptFolder -ItemType Directory -Force -Confirm:$false }
Out-File -FilePath $scriptFullPath -Encoding unicode -Force -InputObject $content -Confirm:$false
#endregion
 
# Register the script as a scheduled task

#region ScheduledTask
$taskName = "Backup BitLocker Keys to Azure AD"
$Path = 'PowerShell.exe'
$Arguments = "-ExecutionPolicy Bypass -NonInteractive -WindowStyle Hidden -File `"$scriptFullPath`""

$Service = new-object -ComObject ("Schedule.Service")
$Service.Connect()
$RootFolder = $Service.GetFolder("\")
$TaskDefinition = $Service.NewTask(0) # TaskDefinition object https://msdn.microsoft.com/en-us/library/windows/desktop/aa382542(v=vs.85).aspx
$TaskDefinition.RegistrationInfo.Description = ''
$TaskDefinition.Settings.Enabled = $True
$TaskDefinition.Settings.AllowDemandStart = $True
$TaskDefinition.Settings.DisallowStartIfOnBatteries = $False
$Triggers = $TaskDefinition.Triggers

# 768 BitLocker encryption started for volume
$Trigger = $Triggers.Create(0) ## 0 is an event trigger https://msdn.microsoft.com/en-us/library/windows/desktop/aa383898(v=vs.85).aspx
$Trigger.Enabled = $true
$Trigger.Id = '768' # 768 BitLocker encryption started for volume
$Trigger.Subscription = "<QueryList><Query Id='0' Path='Microsoft-Windows-BitLocker/BitLocker Management'><Select Path='Microsoft-Windows-BitLocker/BitLocker Management'>*[System[Provider[@Name='Microsoft-Windows-BitLocker-API'] and EventID=768]]</Select></Query></QueryList>"

# 306 Automatic registration Succeeded
$Trigger = $Triggers.Create(0) ## 0 is an event trigger https://msdn.microsoft.com/en-us/library/windows/desktop/aa383898(v=vs.85).aspx
$Trigger.Enabled = $true
$Trigger.Id = '306' # 306 Automatic registration Succeeded
$Trigger.Subscription = "<QueryList><Query Id='0' Path='Microsoft-Windows-User Device Registration/Admin'><Select Path='Microsoft-Windows-User Device Registration/Admin'>*[System[Provider[@Name='Microsoft-Windows-User Device Registration'] and EventID=306]]</Select></Query></QueryList>"

# 335 Automatic device join pre-check tasks completed. The device is already joined.
$Trigger = $Triggers.Create(0) ## 0 is an event trigger https://msdn.microsoft.com/en-us/library/windows/desktop/aa383898(v=vs.85).aspx
$Trigger.Enabled = $true
$Trigger.Id = '335' # 335 Automatic device join pre-check tasks completed. The device is already joined.
$Trigger.Subscription = "<QueryList><Query Id='0' Path='Microsoft-Windows-User Device Registration/Admin'><Select Path='Microsoft-Windows-User Device Registration/Admin'>*[System[Provider[@Name='Microsoft-Windows-User Device Registration'] and EventID=335]]</Select></Query></QueryList>"

$Action = $TaskDefinition.Actions.Create(0)
$Action.Path = $Path
$action.Arguments = $Arguments
$RootFolder.RegisterTaskDefinition($taskName, $TaskDefinition, 6, "NT AUTHORITY\SYSTEM", $null, 5) | Out-Null

# Starts execution of the scheduled task
Start-Sleep 10
Start-ScheduledTask -TaskName $taskName
#endregion
