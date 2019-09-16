$version_major = [environment]::OSVersion.Version.Major
$version_minor = [environment]::OSVersion.Version.Minor

if ([int]$version_major -le 6 -and [int]$version_minor -le 1) # 2008R2 (6.1) or below
{
    foreach ($disk in get-wmiobject Win32_DiskDrive -Filter "Partitions = 0")
    { 
    $disk.DeviceID
    $disk.Index
    "select disk "+$disk.Index+"`r clean`r create partition primary`r format fs=ntfs quick`r active`r assign letter=V" | diskpart
    }
}
else
{
    Get-Disk | Where-Object PartitionStyle -eq "RAW" | Initialize-Disk -PartitionStyle MBR -Confirm:$False -PassThru | New-Partition -AssignDriveLetter -UseMaximumSize | Format-Volume -FileSystem NTFS -Confirm:$False
}
