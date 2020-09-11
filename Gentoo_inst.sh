#BOOT usb key part
partBOOT(){
    (
        echo mklabel gpt
        echo yes
        echo mkpart primary fat32 0% 100%
        echo set 1 BOOT on
        echo quit
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
cd /mnt/gentoo 
wget -c http://distfiles.gentoo.org/releases/amd64/autobuilds/20200909T214504Z/stage3-amd64-20200909T214504Z.tar.xz
wget -c http://distfiles.gentoo.org/releases/amd64/autobuilds/20200909T214504Z/stage3-amd64-20200909T214504Z.tar.CONTENTS.gz
wget -c http://distfiles.gentoo.org/releases/amd64/autobuilds/20200909T214504Z/stage3-amd64-20200909T214504Z.tar.xz.DIGESTS.asc
tar xvJpf stage3-amd64-*.tar.xz --xattrs-include='*.*' --numeric-owner
rm -v -f stage3-amd64-* 
cd ~

touch /mnt/gentoo/root/.bashrc 
echo 'export NUMCPUS=$(nproc)
export NUMCPUSPLUSONE=$(( NUMCPUS + 1 ))
export MAKEOPTS="-j${NUMCPUSPLUSONE} -l${NUMCPUS}"
export EMERGE_DEFAULT_OPTS="--jobs=${NUMCPUSPLUSONE} --load-average=${NUMCPUS}"' >> /mnt/gentoo/root/.bashrc 

cp -v /mnt/gentoo/etc/skel/.bash_profile /mnt/gentoo/root/ 

touch /mnt/gentoo/etc/portage/make.conf 
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
mount -v -t proc none /mnt/gentoo/proc
mount -v --rbind /sys /mnt/gentoo/sys 
mount -v --rbind /dev /mnt/gentoo/dev 
mount -v --make-rslave /mnt/gentoo/sys 
mount -v --make-rslave /mnt/gentoo/dev

touch gentooille.sh
echo 'source /etc/profile
export PS1="(chroot) $PS1" 
emaint sync --auto 
eselect profile set "default/linux/amd64/17.1" 
emerge -a --verbose --oneshot portage
echo "Europe/Paris" > /etc/timezone 
emerge -a -v --config sys-libs/timezone-data 
echo "fr_FR ISO-8859-1
fr_FR.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
eselect locale set "C"
env-update && source /etc/profile && export PS1="(chroot) $PS1"' >> gentooille.sh

echo "sed -i 's/keymap=\"qwerty\"/keymap=\"azerty\"/'" >> gentooille.sh

echo 'emerge -a --verbose --oneshot app-portage/cpuid2cpuflags' >> gentooille.sh

echo "sed -i 's/CPU_FLAGS_X86=\"mmx mmxext sse sse2\"\/CPU_FLAGS_X86=\"aes avx avx2 fma3 mmx mmxext popcnt sse sse2 sse3 sse4_1 sse4_2 ssse3\"/'" >> gentooille.sh

echo 'mkdir -p -v /etc/portage/package.use
touch /etc/portage/package.use/zzz_via_autounmask
emerge -a --verbose dev-vcs/git
touch /etc/portage/repos.conf/sakaki-tools.conf
echo "[sakaki-tools]

# Various utility ebuilds for Gentoo on EFI
# Maintainer: sakaki (sakaki@deciban.com)

location = /var/db/repos/sakaki-tools
sync-type = git
sync-uri = https://github.com/sakaki-/sakaki-tools.git
priority = 50
auto-sync = yes" >> /etc/portage/repos.conf/sakaki-tools.conf
emaint sync --repo sakaki-tools
mkdir -p -v /etc/portage/package.mask
echo "*/*::sakaki-tools" >> /etc/portage/package.mask/sakaki-tools-repo
mkdir -p -v /etc/portage/package.unmask
touch /etc/portage/package.unmask/zzz_via_autounmask
echo "app-portage/showem::sakaki-tools" >> /etc/portage/package.unmask/showem
echo "sys-kernel/buildkernel::sakaki-tools" >> /etc/portage/package.unmask/buildkernel
echo "app-portage/genup::sakaki-tools" >> /etc/portage/package.unmask/genup
echo "app-crypt/staticgpg::sakaki-tools" >> /etc/portage/package.unmask/staticgpg
echo "app-crypt/efitools::sakaki-tools" >> /etc/portage/package.unmask/efitools
echo "sys-kernel/genkernel-next::sakaki-tools" >> /etc/portage/package.unmask/genkernel-next
mkdir -p -v /etc/portage/package.accept_keywords
touch /etc/portage/package.accept_keywords/zzz_via_autounmask
echo "*/*::sakaki-tools ~amd64" >> /etc/portage/package.accept_keywords/sakaki-tools-repo
echo -e "# all versions of efitools currently marked as ~ in Gentoo tree\napp-crypt/efitools ~amd64" >> /etc/portage/package.accept_keywords/efitools
echo "~sys-apps/busybox-1.32.0 ~amd64" >> /etc/portage/package.accept_keywords/busybox
emerge -a --verbose app-portage/showem ' >> gentooille.sh

chmod 777 gentooille.sh
chroot /mnt/gentoo ./gentouille.sh