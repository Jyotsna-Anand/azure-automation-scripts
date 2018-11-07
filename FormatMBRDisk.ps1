Get-Disk | Where-Object PartitionStyle -eq "RAW" | Initialize-Disk -PartitionStyle MBR -Confirm:$False -PassThru | New-Partition -AssignDriveLetter -UseMaximumSize | Format-Volume -FileSystem NTFS -Confirm:$False
