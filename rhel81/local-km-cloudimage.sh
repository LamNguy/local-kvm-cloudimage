#!/bin/bash
#
# Takes RHEL KVM cloud image and creates VM configured with cloud-init
# 
# uses snapshot and increases size of root filesystem so base image not affected
# inserts cloud-init user, network, metadata into disk
# creates 2nd data disk
# then uses cloud-init to configure OS
#
set -x

# image should be downloaded from ubuntu site
os_variant="rhel7" # osinfo-query os | grep rhel
baseimg=rhel-8.1-x86_64-kvm.qcow2
if [ ! -f ~/Downloads/$baseimg ]; then
  echo "ERROR did not find ~/Downloads/$baseimg"
  echo "Get the RHEL KVM cloud image manually at:"
  echo "https://access.redhat.com/downloads/content/479/ver=/rhel---8/8.1/x86_64/product-software"
  exit 2
fi


hostname=rhel8cloud1
if [ ! -f id_rsa ]; then
  echo "ERROR did not find ssh public/private key, generating now"
  ssh-keygen -t rsa -b 4096 -f id_rsa -C $hostname -N "" -q
  echo ""
  echo "The contents of id_rsa.pub need to be manually copied into cloud_init.cfg"
  exit 3
fi


snapshot=$hostname-snapshot-cloudimg.qcow2
seed=$hostname-seed.img
disk2=$hostname-extra.qcow2
# vnc|none
graphicsType=vnc


# create working snapshot, increase size from 10G to 12G
sudo rm $snapshot
qemu-img create -b ~/Downloads/$baseimg -f qcow2 $snapshot 12G
qemu-img info $snapshot

# insert metadata into seed image
echo "instance-id: $(uuidgen || echo i-abcdefg)" > $hostname-metadata
cloud-localds -v --network-config=network_config_static.cfg $seed cloud_init.cfg $hostname-metadata

# ensure file permissions belong to kvm group
sudo chmod 666 $baseimg
sudo chmod 666 $snapshot
sudo chown $USER:kvm $snapshot $seed

# create 2nd data disk, 20G sparse
sudo rm $disk2
qemu-img create -f qcow2 $disk2 20G
chmod 666 $disk2
chown $USER:kvm $disk2

# create VM using libvirt
virt-install --name $hostname \
  --virt-type kvm --memory 2048 --vcpus 4 \
  --boot hd,menu=on \
  --disk path=$seed,device=cdrom \
  --disk path=$snapshot,device=disk \
  --disk path=$disk2,device=disk \
  --graphics $graphicsType \
  --os-type Linux --os-variant $os_variant \
  --network network:default \
  --noautoconsole 
