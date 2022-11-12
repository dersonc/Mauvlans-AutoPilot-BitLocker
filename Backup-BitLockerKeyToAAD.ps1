# ***************************************************************************
#
# Purpose: This script will back up all BitLocker recovery keys to Azure AD.
#
# ------------- DISCLAIMER -------------------------------------------------
# This script code is provided as is with no guarantee or waranty concerning
# the usability or impact on systems and may be used, distributed, and
# modified in any way provided the parties agree and acknowledge the 
# Microsoft or Microsoft Partners have neither accountabilty or 
# responsibility for results produced by use of this script.
#
# Microsoft will not provide any support through any means.
# ------------- DISCLAIMER -------------------------------------------------
#
# ***************************************************************************

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
                Write-Output "Started backup of recovery key with protector ID [$KeyProtectorId] from drive [$MountPoint] to Azure AD."
            } Catch {
                Write-Error "Failed to backup recovery key with protector ID [$KeyProtectorId] from drive [$MountPoint] to Azure AD."
            }
        }
    }
} Catch {
    Write-Error "Error backing up BitLocker recovery key."
}
