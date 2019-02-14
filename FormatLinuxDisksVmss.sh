DISKS=$( ls /dev/disk/azure/scsi1/* )
for i in $DISKS; do
   DISK=$i
done

echo "y" | mkfs.ext4 $DISK
mkdir /datadrive
echo "$DISK /datadrive ext4 defaults,nofail 0 0" >>/etc/fstab
mount -a
