#BOOT usb key part
partBOOT(){
    (
        echo mklabel gpt
        echo yes
        mkpart primary fat32 0% 100%
        set 1 BOOT on
        quit
    ) | parted --script -a optimal /dev/sdc
}
partBOOT
mkfs.vfat -F32 /dev/sdc1
mkdir -v /tmp/efiboot
mount -v -t vfat /dev/sdc1 /tmp/efiboot
export GPG_TTY=$(tty)
dd if=/dev/urandom bs=8388607 count=1 | gpg --symmetric --cipher-algo AES256 --output /tmp/efiboot/luks-key.gpg 

#SDA part
partSDA(){
    (
        echo mkpart primary 2048s 250068992s
        quit
    ) | parted --script -a optimal /dev/sda
}
dd if=/dev/urandom of=/dev/sda1 bs=1M status=progress && sync 

#CryptSetup
gpg --decrypt /tmp/efiboot/luks-key.gpg | cryptsetup --cipher serpent-xts-plain64 --key-size 512 --hash whirlpool --key-file - luksFormat /dev/sda1

#LVM
gpg --decrypt /tmp/efiboot/luks-key.gpg | cryptsetup --key-file - luksOpen /dev/sda1 gentoo 
pvcreate /dev/mapper/gentoo
vgcreate vg1 /dev/mapper/gentoo 
lvcreate --size 10G --name swap vg1 
lvcreate --size 50G --name root vg1 
lvcreate --extents 95%FREE --name home vg1 
vgchange --available y 

#LVM Mount
mkswap -L "swap" /dev/mapper/vg1-swap 
mkfs.ext4 -L "root" /dev/mapper/vg1-root 
mkfs.ext4 -m 0 -L "home" /dev/mapper/vg1-home 
swapon -v /dev/mapper/vg1-swap 
mount -v -t ext4 /dev/mapper/vg1-root /mnt/gentoo 
mkdir -v /mnt/gentoo/{home,boot,boot/efi} 
mount -v -t ext4 /dev/mapper/vg1-home /mnt/gentoo/home 
umount -v /tmp/efiboot 

PARTUUIDSDA=$(blkid | grep ^/dev/sda1 | awk -F "\"" '{print $2}')
PARTUUIDSDC=$(blkid | grep ^/dev/sdc1 | awk -F "\"" '{print $2}')

#Gentoo Stage3
wget -c http://distfiles.gentoo.org/releases/amd64/autobuilds/20200909T214504Z/stage3-amd64-20200909T214504Z.tar.xz
wget -c http://distfiles.gentoo.org/releases/amd64/autobuilds/20200909T214504Z/stage3-amd64-20200909T214504Z.tar.CONTENTS.gz
wget -c http://distfiles.gentoo.org/releases/amd64/autobuilds/20200909T214504Z/stage3-amd64-20200909T214504Z.tar.xz.DIGESTS.asc
tar xvJpf stage3-amd64-*.tar.xz --xattrs-include='*.*' --numeric-owner
rm -v -f stage3-amd64-* 
cd ~

echo 'export NUMCPUS=$(nproc)
export NUMCPUSPLUSONE=$(( NUMCPUS + 1 ))
export MAKEOPTS="-j${NUMCPUSPLUSONE} -l${NUMCPUS}
export EMERGE_DEFAULT_OPTS="--jobs=${NUMCPUSPLUSONE} --load-average=${NUMCPUS}"' >> /mnt/gentoo/root/.bashrc 

cp -v /mnt/gentoo/etc/skel/.bash_profile /mnt/gentoo/root/ 

echo '# Build setup as of <add current date>

# C, C++ and FORTRAN options for GCC.
COMMON_FLAGS="-march=native -O2 -pipe"
CFLAGS="${COMMON_FLAGS}"
CXXFLAGS="${COMMON_FLAGS}"
FCFLAGS="${COMMON_FLAGS}"
FFLAGS="${COMMON_FLAGS}"

# Note: MAKEOPTS and EMERGE_DEFAULT_OPTS are set in .bashrc

# The following licence is required, in addition to @FREE, for GNOME.
ACCEPT_LICENSE="CC-Sampling-Plus-1.0"

# WARNING: Changing your CHOST is not something that should be done lightly.
# Please consult http://www.gentoo.org/doc/en/change-chost.xml before changing.
CHOST="x86_64-pc-linux-gnu"

# NB, amd64 is correct for both Intel and AMD 64-bit CPUs
ACCEPT_KEYWORDS="amd64"

# Additional USE flags supplementary to those specified by the current profile.
USE=""
CPU_FLAGS_X86="mmx mmxext sse sse2"

# Important Portage directories.
PORTDIR="/var/db/repos/gentoo"
DISTDIR="/var/cache/distfiles"
PKGDIR="/var/cache/binpkgs"

# This sets the language of build output to English.
# Please keep this setting intact when reporting bugs.
LC_MESSAGES=C

# Turn on logging - see http://gentoo-en.vfose.ru/wiki/Gentoo_maintenance.
PORTAGE_ELOG_CLASSES="info warn error log qa"
# Echo messages after emerge, also save to /var/log/portage/elog
PORTAGE_ELOG_SYSTEM="echo save"

# Ensure elogs saved in category subdirectories.
# Build binary packages as a byproduct of each emerge, a useful backup.
FEATURES="split-elog buildpkg"

# Settings for X11
VIDEO_CARDS="intel i965"
INPUT_DEVICES="libinput"' >> /mnt/gentoo/etc/portage/make.conf 

mirrorselect -i -o >> /mnt/gentoo/etc/portage/make.conf 

mkdir -p -v /mnt/gentoo/etc/portage/repos.conf 
cp -v /mnt/gentoo/usr/share/portage/config/repos.conf /mnt/gentoo/etc/portage/repos.conf/gentoo.conf 

echo '[DEFAULT]
main-repo = gentoo

[gentoo]
location = /var/db/repos/gentoo
sync-type = webrsync
#sync-type = rsync
sync-uri = rsync://rsync.gentoo.org/gentoo-portage
sync-webrsync-verify-signature = true
auto-sync = yes

sync-rsync-verify-jobs = 1
sync-rsync-verify-metamanifest = yes
sync-rsync-verify-max-age = 24
sync-openpgp-keyserver = hkps://keys.gentoo.org
sync-openpgp-key-path = /usr/share/openpgp-keys/gentoo-release.asc
sync-openpgp-key-refresh-retry-count = 40
sync-openpgp-key-refresh-retry-overall-timeout = 1200
sync-openpgp-key-refresh-retry-delay-exp-base = 2
sync-openpgp-key-refresh-retry-delay-max = 60
sync-openpgp-key-refresh-retry-delay-mult = 4' >> /mnt/gentoo/etc/portage/repos.conf/gentoo.conf 

cp -v -L /etc/resolv.conf /mnt/gentoo/etc/
cp -v /etc/wpa.conf /mnt/gentoo/etc/ 
mount -v -t proc none /mnt/gentoo/proc
mount -v --rbind /sys /mnt/gentoo/sys 
mount -v --rbind /dev /mnt/gentoo/dev 
mount -v --make-rslave /mnt/gentoo/sys 
mount -v --make-rslave /mnt/gentoo/dev