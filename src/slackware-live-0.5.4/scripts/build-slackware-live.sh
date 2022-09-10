#!/bin/sh
#Dimitris Tzemos <dijemos@gmail.com> (changes for salix)
# Eric Hameleers <alien@slackware.com> (encryption support)

LIVELABEL="LIVE" #edit in init script too
#SALIX_FLAVOR="Salix-kde-15.0"
#SALIX_FLAVOR_LILO="Salix-kde"
SALIX_FLAVOR="Salix-xfce-15.0"
SALIX_FLAVOR_LILO="Salix-xfce"
#SALIX_FLAVOR="Salix-mate-15.0"
#SALIX_FLAVOR_LILO="Salix-mate"

#LIVEFSOPTS="-O ^has_journal"

CMDERROR=1
PARTITIONERROR=2
FORMATERROR=3
BOOTERROR=4
INSUFFICIENTSPACE=5

if [ `uname -m` == "x86_64" ]
then grublibdir="/usr/lib64/grub"
else grublibdir="/usr/lib/grub"
fi

function add_packages() {
	packagesdirectory=$1
	rootdirectory=$2
	packageslistfile=$3
	
	if ! echo $packageslistfile | grep -q "^/"; then
		packageslistfile="`pwd`/$packageslistfile"
	fi
	
	for package in `cat "$packageslistfile" | sed 's/ *#.*//' | sed /=/d`; do
		installpkg -root $rootdirectory $packagesdirectory/$package*.t?z || return $CMDERROR
	done
	
	IFS=$'\n'; 
	pushd $rootdirectory >/dev/null
	for action in `cat "$packageslistfile" | sed 's/^#.*//' | sed -n '/postinstall/p' | cut -f2- -d=`; do
		eval $action
	done
	popd >/dev/null
	
	return 0
}


function init_live() {
	rootdirectory=$1
	livedirectory=$2
	moduleslist=$3
	
	initscriptbasepath=$(dirname $(dirname $0))
	
	mkdir -p $livedirectory/boot
	touch $livedirectory/boot/liveboot
	mkdir -p $livedirectory/boot/modules #don't remove previously created modules
	mkdir -p $livedirectory/boot/optional
	cp -f $rootdirectory/boot/vmlinuz $livedirectory/boot/
	
	#create InitRD
	kv=`ls -l $rootdirectory/boot/vmlinuz | cut -f2 -d'>' | sed s/^[^0-9]*//`
	if [ ! -h $rootdirectory/boot/vmlinuz ] || [ ! -d $rootdirectory/lib/modules/$kv ]; then
		kv=`basename $rootdirectory/lib/modules/*`
	fi

	mount --bind /proc $rootdirectory/proc
	chroot $rootdirectory mkinitrd -c -o /tmp/initrd.gz -s /tmp/initrd-tree -k $kv -m $moduleslist -C dummy >/dev/null 2>&1
	cd $rootdirectory/tmp/initrd-tree
	find . -name "*.ko"
	cd - >/dev/null
	umount $rootdirectory/proc
	rm -f $rootdirectory/tmp/initrd.gz
	rm -f $rootdirectory/tmp/initrd-tree/{initrd-name,keymap,luksdev,resumedev,rootfs,rootdev,wait-for-root}
	cp $initscriptbasepath/share/slackware-live/{init,keymaps} $rootdirectory/tmp/initrd-tree/
	chmod +x $rootdirectory/tmp/initrd-tree/init

	cp $initscriptbasepath/sbin/build-slackware-live.sh $rootdirectory/tmp/initrd-tree/
	
	#for prg in unionfs ; do
	#	cp `which $prg` $rootdirectory/tmp/initrd-tree/bin/ #UnionFS
	#	ldd `which $prg` | sed 's/[^\/]*\(\/[^ ]*\) .*/\1/' | sed 's/[^\/]*\(\/[^ ]*\) .*/\1/' | sed -n /^\\//p | sort -u | while read lib; do
	#		if [ -d $rootdirectory/tmp/initrd-tree/lib64 ]
	#		then cp $lib $rootdirectory/tmp/initrd-tree/lib64/
	#		else cp $lib $rootdirectory/tmp/initrd-tree/lib/
	#		fi
	#	done
	#done
	unionfs=`which unionfs 2>/dev/null`
	if [ ! -z "$unionfs" ]; then
		cp $unionfs $rootdirectory/tmp/initrd-tree/bin/
		ldd $unionfs | sed -n '/=>/p' | cut -f2 -d'>' | cut -f2 -d ' ' | while read lib; do
			if [ -d $rootdirectory/tmp/initrd-tree/lib64 ]
			then cp $lib $rootdirectory/tmp/initrd-tree/lib64/
			else cp $lib $rootdirectory/tmp/initrd-tree/lib/
			fi
		done
	fi
	
	find $rootdirectory/tmp/initrd-tree/lib/modules/ -name "*.ko" | xargs strip --strip-unneeded
	cwd=`pwd`
	cd $rootdirectory/tmp/initrd-tree
	rm -f $livedirectory/boot/initrd.gz
	if [ ! -d $livedirectory ]
	then find . | cpio -o -H newc 2>/dev/null | gzip -9c > $cwd/$livedirectory/boot/initrd.gz
	else find . | cpio -o -H newc 2>/dev/null | gzip -9c > $livedirectory/boot/initrd.gz
	fi
	cd - >/dev/null
	rm -rf $rootdirectory/tmp/initrd-tree
	
	#BIOS/syslinux
	mkdir -p $livedirectory/boot/syslinux
	cp /usr/share/syslinux/menu.c32 $livedirectory/boot/syslinux/
	cp /usr/share/syslinux/vesamenu.c32 $livedirectory/boot/syslinux/
	if [ ! -f  $livedirectory/boot/syslinux/syslinux.cfg ]; then
		cat > $livedirectory/boot/syslinux/syslinux.cfg << EOF
INCLUDE /boot/menus/mainmenu.cfg
EOF
	fi
	
	#Copy menus,splash image
	if [ -d menus ]; then
		cp -r menus $livedirectory/boot/
		cp salix.png relinfo.msg $livedirectory/boot/syslinux/
	fi
	
#	if [ -d install_on_usb ]; then
#		cp install_on_usb/* $livedirectory/boot/syslinux/
#	fi
	
	#UEFI/elilo
	if [ `uname -m` == "x86_64" ]; then
		mkdir -p $livedirectory/EFI/BOOT
		cp $initscriptbasepath/../boot/elilo-x86_64.efi $livedirectory/EFI/BOOT/bootx64.efi
		cp $livedirectory/boot/initrd.gz $livedirectory/EFI/BOOT/
		cp $livedirectory/boot/vmlinuz $livedirectory/EFI/BOOT/
		if [ ! -f $livedirectory/EFI/BOOT/elilo.conf ]; then
			if [ -d ../common/elilo ]; then
				cp ../common/elilo/* $livedirectory/EFI/BOOT/
			fi	
		fi
		
#		if [ ! -f $livedirectory/EFI/BOOT/elilo.conf ]; then
#			cat > $livedirectory/EFI/BOOT/elilo.conf << EOF
#prompt
#timeout=10
#default=$SALIX_FLAVOR
#
#image=vmlinuz
#	label=$SALIX_FLAVOR
#	initrd=initrd.gz
#	append="max_loop=255 runlevel=4"
#EOF
#		fi
		#dd if=/dev/zero of=/tmp/efi.img bs=1k count=32768
		dd if=/dev/zero of=/tmp/efi.img bs=1M count=30
		mkdosfs -n "EFIBOOT" /tmp/efi.img
		mount -o loop /tmp/efi.img /mnt/floppy
		cp -dpR $livedirectory/EFI /mnt/floppy/
		umount /mnt/floppy
		mv /tmp/efi.img $livedirectory/
	fi
}


function sys_prep() {
	rwdirectory=$1
	shift
	for rodirectory in $*; do rodirectories="$rodirectories:$rodirectory=ro"; done
	
	mkdir /mnt/union
	mount -t aufs -o br=$rwdirectory=rw$rodirectories none /mnt/union 2>/dev/null ||
	unionfs -o allow_other,suid,dev,use_ino,cow,max_files=524288 $rwdirectory=rw$rodirectories /mnt/union
	if [ -x /mnt/union/bin/sh ]; then
		#not done by stock Slackware startup scripts, but by PkgTool during install:
		cat > /mnt/union/sysprep.sh << EOF
#!/bin/sh
if [ -x /usr/bin/update-desktop-database ] && [ -d /usr/share/applications ]; then
	update-desktop-database /usr/share/applications/
fi
if [ -x /usr/bin/mkfontdir ] && [ -d /usr/share/fonts ]; then
	mkfontdir /usr/share/fonts/*
	rm -f /fonts.dir
fi
if [ -x /usr/bin/mkfontscale ] && [ -d /usr/share/fonts ]; then
	mkfontscale /usr/share/fonts/*
	rm -f /fonts.scale
fi
EOF
		#done by stock Slackware startup scripts, but disabled on live startup (for speed improvement)
		cat >> /mnt/union/sysprep.sh << EOF
depmod \`basename /lib/modules/*\`
ldconfig

if [ -x /usr/bin/fc-cache ]; then
	fc-cache -f
fi

if [ -x /usr/bin/gtk-update-icon-cache ] && [ -d /usr/share/icons ]; then
	for theme in /usr/share/icons/*; do gtk-update-icon-cache -t -f \$theme; done
	rm -f /usr/share/icons/icon-theme.cache
fi
if [ -x /usr/bin/update-mime-database ] && [ -d /usr/share/mime ]; then
	update-mime-database /usr/share/mime
fi

if [ -x /usr/bin/update-gtk-immodules ]; then
	update-gtk-immodules #--verbose
fi
if [ -x /usr/bin/update-gdk-pixbuf-loaders ]; then
	update-gdk-pixbuf-loaders #--verbose
fi
if [ -x /usr/bin/update-pango-querymodules ]; then
	update-pango-querymodules #--verbose
fi
EOF
		chmod +x /mnt/union/sysprep.sh
		chroot /mnt/union /sysprep.sh
		rm -f /mnt/union/sysprep.sh
	fi
	umount /mnt/union
	rmdir /mnt/union
	rm -rf $rwdirectory/.wh..wh.* #for AUFS
	
	#merge passwd, group and ld.so.conf
	mkdir -p $rwdirectory/etc
	if (( `find $rwdirectory $* -name passwd | grep etc/passwd | wc -l` > 1 )); then
		find $rwdirectory $* -name passwd | grep etc/passwd | xargs cat | sort -u >> $rwdirectory/etc/passwd.new
		mv -f $rwdirectory/etc/passwd.new $rwdirectory/etc/passwd
		passwdfile="$rwdirectory/etc/passwd"
	else passwdfile=`find $rwdirectory $* -name passwd | grep etc/passwd`
	fi
	if (( `find $rwdirectory $* -name group | grep etc/group | wc -l` > 1 )); then
		find $rwdirectory $* -name group | grep etc/group | xargs cat | sort -u >> $rwdirectory/etc/group.new
		mv -f $rwdirectory/etc/group.new $rwdirectory/etc/group
		groupfile="$rwdirectory/etc/group"
	else groupfile=`find $rwdirectory $* -name group | grep etc/group`
	fi
	if (( `find $rwdirectory $* -name ld.so.conf | wc -l` > 1 )); then
		find $rwdirectory $* -name ld.so.conf | xargs cat | sort -u >> $rwdirectory/etc/ld.so.conf.new
		mv -f $rwdirectory/etc/ld.so.conf.new $rwdirectory/etc/ld.so.conf
	fi
	
	#install profiles
	mkdir -p $rwdirectory/home
	gid=`cat $groupfile | grep "^users:" | cut -f3 -d:`
	find $rwdirectory $* -name skel | grep etc/skel | while read skel; do
		cp -dpR $skel/{*,.??*} $rwdirectory/root 2>/dev/null
		for user in `cat $passwdfile | grep ":$gid:" | cut -f3,6 -d:`; do
			uid=`echo $user | cut -f1 -d:`
			homedir=`echo $user | cut -f2 -d:`
			if echo $homedir | grep -q "/home"; then
				mkdir -p $rwdirectory/$homedir
				cp -dpR $skel/{*,.??*} $rwdirectory/$homedir/ 2>/dev/null
				chown -R $uid:$gid $rwdirectory/$homedir
			fi
		done
	done
}


function add_module() {
	rootdirectory=$1
	livedirectory=$2
	modulename=$3
	if [ "$4" == "-xz" ] || [ "$4" == "-gzip" ]; then
		if [ "$4" == "-gzip" ]
		then compoption="-comp gzip"
		else compoption="-comp xz -b 1M"
		fi
	else compoption=""
		option=$4
	fi
	
	if [ "$option" == "-optional" ]
	then modulepath=$livedirectory/boot/optional/$modulename
	else modulepath=$livedirectory/boot/modules/$modulename
	fi
	mkdir -p `dirname $modulepath`
	rm -f $modulepath
	mksquashfs $rootdirectory $modulepath $compoption -e tmp dev proc sys $livedirectory
}


function create_iso() {
	livedirectory=$1
	imagefilename=$2
	ISOHYBRID_MBR=/usr/share/syslinux/isohdpfx.bin

	if [ ! -f $ISOHYBRID_MBR ]; then
		echo "syslinux is not installed"
		exit 1
	fi

	if [ ! -x /usr/bin/xorriso ]; then
		echo "libisoburn is not installed"
		exit 1
	fi
	cp /usr/share/syslinux/isolinux.bin $livedirectory/boot/syslinux/
	if [ `uname -m` == "x86_64" ]; then
		#UEFI_OPTS="-eltorito-alt-boot -no-emul-boot -eltorito-platform efi -eltorito-boot efi.img"
		UEFI_OPTS="-eltorito-alt-boot -e efi.img -no-emul-boot"
	fi
	#mkisofs -J -d -N -l -r -V "$LIVELABEL" -hide-rr-moved -o $imagefilename \
	#	-b boot/syslinux/isolinux.bin -boot-load-size 4 -boot-info-table -no-emul-boot \
	#	-c boot/syslinux/boot.catalog -hide boot.catalog -hide-joliet boot.catalog $altboot \
	#   $livedirectory
	
	(
	cd $livedirectory
	
	xorriso -as mkisofs \
    -isohybrid-mbr $ISOHYBRID_MBR \
    -isohybrid-gpt-basdat \
    -hide-rr-moved \
    -U \
    -V "$LIVELABEL" \
    -J \
    -joliet-long \
    -r \
    -v -d -N \
    -o $imagefilename \
    -b boot/syslinux/isolinux.bin \
    -c boot/syslinux/boot.catalog \
    --boot-load-size 32 -boot-info-table -no-emul-boot $UEFI_OPTS \
     .
    )
}


function install_usb() {
	livedirectory=$1
	installmedia=$2
	LIVEFS=$3
	
	device=`echo $installmedia | cut -c6-8`
	sectorscount=`cat /sys/block/$device/size`
	sectorsize=`cat /sys/block/$device/queue/hw_sector_size`
	let mediasize=$sectorscount*$sectorsize/1048576 #in MB
	installdevice="/dev/$device"
	livesystemsize=`du -s -m $livedirectory | sed 's/\t.*//'`

	if [ "$installdevice" == "$installmedia" ]; then #install on whole disk: partition and format media
		if [ `uname -m` == "x86_64" ]; then #EFI/GPT
			partitionnumber=1
			installmedia="$installdevice$partitionnumber"
			dd if=/dev/zero of=$installdevice bs=512 count=34 >/dev/null 2>&1
			if [ "$LIVEFS" == "vfat" ]; then
				partitionnumber=1
				installmedia="$installdevice$partitionnumber"
				echo -e "2\nn\n\n\n\n0700\nr\nh\n1 2\nn\n\ny\n\nn\n\nn\nwq\ny\n" | gdisk $installdevice || return $PARTITIONERROR
				#echo -e "2\nn\n\n\n+32M\nef00\nn\n\n\n\n0700\nr\nh\n1 2\nn\n\ny\n\nn\n\nn\nwq\ny\n" | gdisk $installdevice || return $PARTITIONERROR
				#hybrid MBR with BIOS boot partition (1007K) EFI partition (32M) and live partition
				#echo -e "2\nn\n\n\n+32M\nef00\nn\n\n\n\n0700\nn\n128\n\n\nef02\nr\nh\n1 2\nn\n\ny\n\nn\nn\nwq\ny\n" | gdisk $installdevice || return $PARTITIONERROR
				partprobe $installdevice >/dev/null 2>&1; sleep 3
				fat32option="-F 32"
				mkfs.vfat $fat32option -n "$LIVELABEL" $installmedia || return $FORMATERROR
				sleep 3
			else
				efipartition="$installdevice""1"
				installmedia="$installdevice""2"
				#hybrid MBR with BIOS boot partition (1007K) EFI partition (300M) and live partition
				echo -e "2\nn\n\n\n+300M\nef00\nn\n\n\n\n\nr\nh\n1 2\nn\n\ny\n\nn\n\nn\nwq\ny\n" | gdisk $installdevice || return $PARTITIONERROR
				#echo -e "2\nn\n\n\n+32M\nef00\nn\n\n\n\n\nn\n128\n\n\nef02\nr\nh\n1 2\nn\n\ny\n\nn\nn\nwq\ny\n" | gdisk $installdevice || return $PARTITIONERROR
				# set the linux partition bootable
				sgdisk -p -A 2:set:2 $installdevice
				# confirm it was indeed set correctly
				sgdisk -p -A 2:show $installdevice
				partprobe $installdevice; sleep 3
				echo "*** Formating EFI partition $efipartition ..."
				mkfs.vfat -n "EFI" $efipartition || return $FORMATERROR
				echo "*** Formating system partition $installmedia ..."
				mkfs.ext3 -F -L "$LIVELABEL" $installmedia || return $FORMATERROR
				sleep 3
			fi
		else #BIOS/MBR
			partitionnumber=1
			installmedia="$installdevice$partitionnumber"
			if (( $mediasize < 2048 ))
			then heads=128; sectors=32
			else heads=255; sectors=63
			fi
			mkdiskimage $installdevice 1 $heads $sectors || return $PARTITIONERROR
			dd if=/dev/zero of=$installdevice bs=1 seek=446 count=64 >/dev/null 2>&1
			if [ "$LIVEFS" = "vfat" ]; then
				#echo -e ',0\n,0\n,0\n,,83,*' | sfdisk $installdevice || return $PARTITIONERROR
				#echo -e ',0\n,0\n,0\n,,b,*' | sfdisk $installdevice || return $PARTITIONERROR
				echo -e ',,b,*' | sfdisk $installdevice || return $PARTITIONERROR
				partprobe $installdevice; sleep 3
				fat32option="-F 32"
				mkfs.vfat $fat32option -n "$LIVELABEL" $installmedia || return $FORMATERROR
			else
				echo -e ',,83,*' | sfdisk $installdevice || return $PARTITIONERROR
				partprobe $installdevice; sleep 3
				mkfs.ext3 -L "$LIVELABEL" $installmedia || return $FORMATERROR
			fi
			sleep 3
		fi
	
	else #install on partition: filesystem check and format if needed
		partitionnumber=`echo $installmedia | cut -c9-`
		mkdir -p /mnt/tmp
		if mount $installmedia /mnt/tmp >/dev/null 2>&1; then
			sleep 1
			umount /mnt/tmp
			fsck -fy $installmedia >/dev/null 2>&1
		else #format partition
			if fdisk -l $installdevice 2>/dev/null | grep -q 'GPT\|gpt' ; then
				partitiontype=`gdisk -l $installdevice | grep "^  *$partitionnumber " | sed 's/  */:/g' | cut -f7 -d:`
			else
				partitiontype=`fdisk -l $installdevice 2>/dev/null | grep "^$installmedia " | sed -e 's/\*//' -e 's/  */:/g' | cut -f5 -d:`
			fi
			case $partitiontype in
			83|8300) 
				mkfs.ext3 -L "$LIVELABEL" $installmedia || return $FORMATERROR
				;;
			*)
				partition=`echo $installmedia | cut -c6-`
				size=`cat /proc/partitions | grep " $partition$" | sed 's/  */:/g' | cut -f4 -d:`
				let size=$size/1024
				if (( $size > 1024 )); then
					fat32option="-F 32"
				fi
				mkfs.fat $fat32option -n "$LIVELABEL" $installmedia || return $FORMATERROR
			esac
			sleep 3
		fi
	fi
	
	#live system files copy
#	if [ `uname -m` == "x86_64" ]; then #EFI/GPT
#		efipartition="$installdevice"`gdisk -l $installdevice 2>/dev/null | grep " EF00 " | sed 's/  */:/g' | cut -f2 -d:`
#		if [ ! -z "$efipartition" ] && [ "$efipartition" != "$installmedia" ]; then
#			mkdir -p /mnt/tmp
#			if mount $efipartition /mnt/tmp >/dev/null 2>&1; then
#				sleep 1
#				umount /mnt/tmp
#			else
#				mkfs.fat -n  "efi" $efipartition || return $FORMATERROR
#			fi
#			mkdir -p /mnt/efi
#			mount $efipartition /mnt/efi
#			cp -r $livedirectory/EFI /mnt/efi/
#			umount /mnt/efi
#			rmdir /mnt/efi
#		fi
#	fi
	
	mkdir -p /mnt/install
	mount $installmedia /mnt/install
	cp -r $livedirectory/boot /mnt/install/
	if [ `uname -m` == "x86_64" ]; then #EFI/GPT
		if [ "$LIVEFS" == "vfat" ]; then
			cp -r $livedirectory/EFI /mnt/install/
			cp $livedirectory/efi.img /mnt/install/
		else
			echo "*** Installing EFI on $efipartition ..."
			mkdir -p /mnt/efi
			mount $efipartition /mnt/efi; sleep 1
			cp -r $livedirectory/EFI /mnt/efi/
			cp $livedirectory/efi.img /mnt/efi
			umount /mnt/efi
			rmdir /mnt/efi
		fi
	fi
	if fdisk -l $installdevice 2>/dev/null | grep -q "^$installmedia "; then #legacy / CSM (Compatibility Support Module) boot, if $installmedia present in MBR (or hybrid MBR)
		sfdisk --force $installdevice -A $partitionnumber 2>/dev/null
		if mount | grep -q "^$installmedia .* vfat "; then #FAT32
			umount /mnt/install
			# Use syslinux to make the USB device bootable:
			echo "--- Making the USB drive '$installdevice' bootable using syslinux..."
			syslinux -d /boot/syslinux $installmedia || return $BOOTERROR
			cat /usr/share/syslinux/mbr.bin > $installdevice
		else #ext3
			#mv /mnt/install/boot/syslinux /mnt/install/boot/extlinux
			#mv /mnt/install/boot/extlinux/syslinux.cfg /mnt/install/boot/extlinux/extlinux.conf
			#rm -f /mnt/install/boot/extlinux/isolinux.*
			#rm -f /mnt/install/boot/extlinux/boot.catalog
			#/sbin/extlinux --install /mnt/install/boot/extlinux
			# Use extlinux to make the USB device bootable:
			echo "--- Making the USB drive '$installdevice' bootable using extlinux..."
			extlinux -i /mnt/install/boot/syslinux || return $BOOTERROR
			umount /mnt/install
			if fdisk -l $installdevice 2>/dev/null | grep -q 'GPT\|gpt'; then
				cat /usr/share/syslinux/gptmbr.bin > $installdevice
			else
				cat /usr/share/syslinux/mbr.bin > $installdevice
			fi
		fi
	else
		umount /mnt/install
	fi
	rmdir /mnt/install
	
	return 0
}


function install_system() {
	rootdirectory=$1
	systempart=$2
	loadersetup=$3
	username=$4
	userpassword=$5
	installation_mode=$6
	bootloader=$7
	format_home=$8
	SYSINSTALLFS=$9
	home_dir=${10}
	locale=${11}
	keyboard=${12}
	
	#SYSINSTALLFS="ext4" # set default filesystem of root
	if [ "$SYSINSTALLFS" == "" ]; then
	 SYSINSTALLFS="ext4" # set default filesystem of root
	fi
	

	mkdir -p /mnt/install
		
	if mount $systempart /mnt/install 2>/dev/null; then  # if there is a filesystem find it
	#	fs=`mount | grep "$systempart" | cut -f5 -d' '`
	#	if echo $fs | grep -q "ext" || echo $fs | grep -q "btrfs" || echo $fs | grep -q "reiserfs"|| echo $fs | grep -q "jfs"|| echo $fs | grep -q "xfs"; then
	#		SYSINSTALLFS=$fs  # find filesystem type
	#	fi
		umount /mnt/install	
	else 
		umount /mnt/install	
	fi
	
	fs=$SYSINSTALLFS
	
	if [ "$fs" = "ext2" ]; then
	   flag=" -F "
	elif [ "$fs" = "ext3" ]; then
	   flag=" -F "
	elif [ "$fs" = "ext4" ]; then
	   flag=" -F "     
	elif [ "$fs" = "btrfs" ]; then
	   flag="-f -d single -m single"
	elif [ "$fs" = "jfs" ]; then
	   flag=" -c -q " 
	elif [ "$fs" = "reiserfs" ]; then
	   flag=" -f "
	elif [ "$fs" = "xfs" ]; then
	   flag=" -f -q "   
	fi
	echo "formatting linux partition in $SYSINSTALLFS"
	mkfs.$SYSINSTALLFS $flag $systempart || return $FORMATERROR  # format partition
    echo "mount linux partition to /mnt/install"
	mount $systempart /mnt/install
    
    #handles home partition
	if [ "$home_dir" != "" ] && [ "$home_dir" != "$systempart" ]; then
		mkdir -p /mnt/install/home
		if mount $home_dir /mnt/install/home 2>/dev/null; then  # if there is a filesystem find it
			fs=`mount | grep "$home_dir" | cut -f5 -d' '`
			if echo $fs | grep -q "ext" || echo $fs | grep -q "btrfs" || echo $fs | grep -q "reiserfs"|| echo $fs | grep -q "jfs"|| echo $fs | grep -q "xfs"; then
				SYSINSTALLFS=$fs  # find filesystem type
			fi
			umount /mnt/install/home	
		fi
		if [ "$format_home" = "yes" ]; then
			echo "formatting home partition in $SYSINSTALLFS"
			mkfs.$SYSINSTALLFS $flag $home_dir
		fi
		echo "mount home partition to /mnt/install/home"
		mount $home_dir /mnt/install/home
			
	#	if ! mount $home_dir /mnt/install/home 2>/dev/null; then
	#		mkfs.$SYSINSTALLFS $flag $home_dir
	#		mount $home_dir /mnt/install/home
	#	fi
		
    fi
    
	#Copy begin
	echo "Installing system"
	# core, basic or full mode
	if [ "$installation_mode" = "core" ]; then
		echo "core installation"
		modules=(01-core.slm 04-common.slm 05-kernel.slm 06-live.slm)
		for directory in ${modules[@]}; do
			cp -dpr $rootdirectory/$directory/* /mnt/install/
		done
	fi
	
	if [ "$installation_mode" = "basic" ]; then
		echo "basic installation"
		modules=(01-core.slm 02-basic.slm 04-common.slm 05-kernel.slm 06-live.slm)
		for directory in ${modules[@]}; do
			cp -dpr $rootdirectory/$directory/* /mnt/install/
		done
	fi
	
	if [ "$installation_mode" = "full" ]; then
		echo "full installation"
		modules=(01-core.slm 02-basic.slm 03-full.slm 04-common.slm 05-kernel.slm 06-live.slm)
		for directory in ${modules[@]}; do
			cp -dpr $rootdirectory/$directory/* /mnt/install/
		done
		
		#for directory in $rootdirectory/*; do
		#cp -dpr $directory /mnt/install/
		#done		
	fi
	
	mkdir -p /mnt/install/{dev,proc,sys,tmp}
	cp -dpr /dev/sd* /mnt/install/dev/ #create disk nodes needed for LiLo
	for dir in sys proc dev tmp; do mount --bind /$dir /mnt/install/$dir; done
	#if [ "$rootdirectory" = "/live/modules" ]; then
	#	cp -dpr /live/system/lib/udev/devices/* /mnt/install/dev/
	#fi
	#cp -dpr $rootdirectory/lib/udev/devices/* /mnt/install/dev/

	sed -i /^root:/d /mnt/install/etc/shadow #setup root password
	cat /etc/shadow | sed -n /^root:/p >> /mnt/install/etc/shadow
	
	if [ -f /etc/rc.d/rc.keymap ]; then
		cp -f /etc/rc.d/rc.keymap /mnt/install/etc/rc.d/
	fi
	cp -f /etc/profile.d/lang.sh /mnt/install/etc/profile.d/
	if [ -f /etc/X11/xorg.conf.d/10-keymap.conf ]; then
		cp -f /etc/X11/xorg.conf.d/10-keymap.conf /mnt/install/etc/X11/xorg.conf.d/
	fi
	if [ -f /etc/X11/xorg.conf ]; then
		cp -f /etc/X11/xorg.conf /mnt/install/etc/X11/
	fi
	
	# set clock
	if [ -x /etc/rc.d/rc.ntpd ]; then
		chmod +x /mnt/install/etc/rc.d/rc.ntpd
		cp -f /etc/ntp.conf /mnt/install/etc/
	fi

	if [ -f /etc/localtime ] &&  [ -h /etc/localtime-copied-from  ]; then
		cp -f /etc/localtime /mnt/install/etc/
		cp -df /etc/localtime-copied-from /mnt/install/etc/
	fi
	if [ -f /etc/hardwareclock ]; then
		cp -f /etc/hardwareclock /mnt/install/etc/
	fi
	#Copy end
	echo "Setting up fstab"
	#FSTab begin
	cat > /mnt/install/etc/fstab << EOF
proc /proc proc defaults 0 0
sysfs /sys sysfs defaults 0 0
tmpfs /dev/shm tmpfs defaults 0 0
$systempart / $SYSINSTALLFS defaults 1 1
EOF

	if [ "$home_dir" != "" ] && [ "$home_dir" != "$systempart" ]; then
		fs=`mount | grep "$home_dir" | cut -f5 -d' '` > /dev/null 2>&1
		if echo $fs | grep -q "ext" || echo $fs | grep -q "btrfs" || echo $fs | grep -q "reiserfs"|| echo $fs | grep -q "jfs"|| echo $fs | grep -q "xfs"; then
			echo "$home_dir /home $fs defaults 1 1" >> /mnt/install/etc/fstab
		fi
	fi
	
	#cat /etc/fstab | grep " swap " >> /mnt/install/etc/fstab
	
	#cat /etc/fstab | grep "/mnt" |  grep -v "$systempart" >> /mnt/install/etc/fstab
	#cat /etc/fstab | grep "/mnt" |  grep -v "$systempart" | cut -f2 -d' ' | while read mountpoint; do
	#	mkdir /mnt/install$mountpoint
	#done
	echo "$systempart / $SYSINSTALLFS defaults 1 1" > /mnt/install/etc/mtab
	#FSTab end
    
    # First, determine our slackware kernel name:
	for ELEMENT in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 ; do
	if $(cat /proc/cmdline | cut -f $ELEMENT -d ' ' | grep -q BOOT_IMAGE) ; then
		SLACK_KERNEL=$(cat /proc/cmdline | cut -f $ELEMENT -d ' ' | cut -f 2 -d = | sed "s/\/boot\///")
	fi
	done
	unset ELEMENT

	# Next, find the kernel's release version:
	VERSION=$(uname -r | tr - _)

	# Next find our initrd name
	for ELEMENT in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 ; do
	if $(cat /proc/cmdline | cut -f $ELEMENT -d ' ' | grep -q initrd) ; then
		SLACK_INITRD=$(cat /proc/cmdline | cut -f $ELEMENT -d ' ' | cut -f 2 -d = | sed "s/\/boot\///")
	fi
	done
	unset ELEMENT
	
	( cd /mnt/install/boot
	if [ "$SLACK_KERNEL" == "vmlinuz" ]; then
	 if [ -r vmlinuz-huge-smp-$VERSION ]; then
      ln -sf vmlinuz-huge-smp-$VERSION vmlinuz
      ln -sf config-huge-smp-$VERSION config
      ln -sf System.map-huge-smp-$VERSION System.map
     fi
    fi
    
    if [ "$SLACK_KERNEL" == "vmlinuznp" ]; then   
     if [ -r vmlinuz-huge-$VERSION ]; then
      ln -sf vmlinuz-huge-$VERSION vmlinuz
      ln -sf config-huge-$VERSION config
      ln -sf System.map-huge-$VERSION System.map
     fi
    fi
    
    if [ "$SLACK_INITRD" == "nosmp.gz" ]; then 
     cp initrd.gz smp.gz
     cp nosmp.gz initrd.gz
    fi 
    )

	#InitRD begin
	if [ ! -f /mnt/install/boot/initrd.gz ]; then
		echo "Setting initrd"
		#kv=`basename /mnt/install/lib/modules/*`
		kv=`ls -l /mnt/install/boot/vmlinuz | cut -f2 -d'>' | sed s/^[^0-9]*//`
		if lsmod | grep -q $SYSINSTALLFS; then
			moduleslist="$SYSINSTALLFS"
		fi
		for module in `lsmod | sed 1d | cut -f1 -d' '`; do 
			modulebis=`echo $module | sed 's/_/-/g'` #'_' -> '-'
			if [ -f /lib/modules/$kv/kernel/drivers/ata/$module.ko ] || [ -f /lib/modules/$kv/kernel/drivers/scsi/$module.ko ]; then
				moduleslist="$module:$moduleslist"
			fi
			if [ "$module" != "$modulebis" ]; then
				if [ -f /lib/modules/$kv/kernel/drivers/ata/$modulebis.ko ] || [ -f /lib/modules/$kv/kernel/drivers/scsi/$modulebis.ko ]; then
					moduleslist="$modulebis:$moduleslist"
				fi
			fi
		done
		moduleslist=`echo $moduleslist | sed 's/:$//'`
		if [ ! -z "$moduleslist" ] && [ "$moduleslist" != "sg" ]; then
			#chroot /mnt/install mount /proc
			chroot /mnt/install mkinitrd -c -f $SYSINSTALLFS -r $systempart -k $kv -m $moduleslist
			#chroot /mnt/install umount /proc
		fi
	fi
		
	#####
     installdevice=`echo $systempart | cut -c1-8`
     if [ "$installdevice" != "/dev/sda" ]; then 
		#if [ -f /live/media/boot/initrd-usb.gz ]; then 
			echo "Copying initrd"
			#kv=`basename /mnt/install/lib/modules/*`
			kv=`ls -l /mnt/install/boot/vmlinuz | cut -f2 -d'>' | sed s/^[^0-9]*//`
			MODULES="loop:xhci-pci:ohci-pci:ehci-pci:xhci-hcd:uhci-hcd:ehci-hcd:mmc-core:mmc-block:sdhci:sdhci-pci:sdhci-acpi:usb-storage:hid:usbhid:i2c-hid:hid-generic:hid-apple:hid-asus:hid-cherry:hid-logitech:hid-logitech-dj:hid-logitech-hidpp:hid-lenovo:hid-microsoft:hid_multitouch:crc32c-intel:fuse"
			chroot /mnt/install mkinitrd -c -f $SYSINSTALLFS -u -w 10 -o /boot/initrd.gz -r /dev/sdb1 -k $kv -m $MODULES
			chroot /mnt/install rm -rf /boot/initrd-tree/
			#cp /live/media/boot/initrd-usb.gz /mnt/install/boot/initrd.gz
		#fi	
     fi
     #####
	#InitRD end
   if [ "$bootloader" == "lilo" ]; then
	#LiLo begin
	if [ "$loadersetup" == "-auto" ]; then
		installdevice=`echo $systempart | cut -c1-8`
		echo "Setting (e)Lilo"
		if [ -d /sys/firmware/efi ]; then #UEFI
			modprobe efivars
			efipartnum=`gdisk -l $installdevice | grep "EF00" | sed 's/  \+/ /g' | cut -f2 -d' '`
			efipartition="$installdevice$efipartnum"
			if [ ! -z "$efipartition" ]; then
				mkdir -p /mnt/efi
				mount $efipartition /mnt/efi
				efilabel=$SALIX_FLAVOR
				if [ -d /mnt/efi/EFI/$efilabel ]; then
					conflictpart=`cat /mnt/efi/EFI/$efilabel/elilo.conf | grep "append" | sed 's/.*root=\([^ ]*\).*/\1/'`
					if [ "$conflictpart" == "$systempart" ]
					then efibootid=`efibootmgr | grep $efilabel | cut -b5-8`
						efibootmgr -q -B -b $efibootid
					else efilabel="$efilabel`ls /mnt/efi/EFI/ | grep "$efilabel" | wc -l`"
					fi
				fi
				mkdir -p /mnt/efi/EFI/$efilabel
				cp /mnt/install/boot/elilo-x86_64.efi /mnt/efi/EFI/$efilabel/elilo.efi
				cp /mnt/install/boot/vmlinuz /mnt/efi/EFI/$efilabel/
				cat > /mnt/efi/EFI/$efilabel/elilo.conf << EOF
timeout=1
default=$SALIX_FLAVOR

image=vmlinuz
    label=$SALIX_FLAVOR
    append="root=$systempart ro"
	read-only
EOF

				#####
				if [ "$installdevice" != "/dev/sda" ]; then
					if [ "$installdevice" != "/dev/sdb" ]; then
						real_device=`echo $installdevice | cut -c6-8`
						sed -i "s/$real_device/sdb/g" /mnt/efi/EFI/$efilabel/elilo.conf
					fi
				fi
				#####
				
				if [ -f /mnt/install/boot/initrd.gz ]; then
					echo "  initrd=/boot/initrd.gz" >> /mnt/efi/EFI/$efilabel/elilo.conf
					cp /mnt/install/boot/initrd.gz /mnt/efi/EFI/$efilabel/
				fi
				
				umount /mnt/efi
				rmdir /mnt/efi
				efibootmgr -q -c -d $installdevice -p $efipartnum -l "\\EFI\\$efilabel\\elilo.efi" -L "$SALIX_FLAVOR ($systempart)"
			fi
			
			# Add the EFI System Partition to /etc/fstab:
			mkdir -p /mnt/install/boot/efi
			echo "$efipartition /boot/efi vfat defaults 1 0 " >> /mnt/install/etc/fstab
			if [ "$installdevice" != "/dev/sda" ]; then
				mkdir -p /mnt/efi
				mount $efipartition /mnt/efi
				mkdir -p /mnt/efi/EFI/BOOT
				cp /mnt/efi/EFI/$efilabel/* /mnt/efi/EFI/BOOT/
				mv /mnt/efi/EFI/BOOT/elilo.efi /mnt/efi/EFI/BOOT/bootx64.efi
				cat > /mnt/efi/EFI/BOOT/elilo.conf << EOF
timeout=1
default=$SALIX_FLAVOR

image=/EFI/BOOT/vmlinuz
    label=$SALIX_FLAVOR
    append="root=$systempart ro"
	read-only
	initrd=/EFI/BOOT/initrd.gz
EOF

				if [ "$installdevice" != "/dev/sdb" ]; then
						real_device=`echo $installdevice | cut -c6-8`
						sed -i "s/$real_device/sdb/g" /mnt/efi/EFI/BOOT/elilo.conf
						sed -i "s/$real_device/sdb/g" /mnt/install/etc/fstab
				fi
				umount /mnt/efi
				rmdir /mnt/efi
			fi	
			
			
		else #BIOS
			echo "boot = $installdevice" > /mnt/install/etc/lilo.conf
			if [ -f /mnt/install/boot/salix.bmp ]; then
				cat >> /mnt/install/etc/lilo.conf << EOF

bitmap = /boot/salix.bmp
bmp-colors = 255,0,255,0,255,0
bmp-table = 60,6,1,16
bmp-timer = 65,27,0,255

vga = 791

EOF
			fi
			cat >> /mnt/install/etc/lilo.conf << EOF
lba32

prompt
timeout = 50
compact

image = /boot/vmlinuz
root = $systempart
label = $SALIX_FLAVOR_LILO
read-only
EOF
			
			if [ -f /mnt/install/boot/initrd.gz ]; then
				echo "initrd=/boot/initrd.gz" >> /mnt/install/etc/lilo.conf
			fi
			windowspartition=`fdisk -l $installdevice 2>/dev/null | grep "^$installdevice.*\*.*\(NTFS\|FAT32\)" | cut -f1 -d' '`
			if [ ! -z "$windowspartition" ]; then
				cat >> /mnt/install/etc/lilo.conf << EOF

other = $windowspartition
label = Windows
table = $installdevice
EOF
			fi
			#chroot /mnt/install mount /proc
			chroot /mnt/install lilo || return $BOOTERROR
			#chroot /mnt/install umount /proc
			#####
			if [ "$installdevice" != "/dev/sda" ]; then
				if [ "$installdevice" != "/dev/sdb" ]; then
					real_device=`echo $installdevice | cut -c6-8`
					sed -i "s/$real_device/sdb/g" /mnt/install/etc/lilo.conf
				fi
			fi
			#####	
			
		fi
	fi
   fi #LiLo end
  
   if [ "$bootloader" == "grub" ]; then
	#grub begin
	if [ "$loadersetup" == "-auto" ]; then
		grustatus=$GRUBERROR
		installdevice=`echo $systempart | cut -c1-8`
		echo "Installing Grub Boot Loader on $installdevice"
		efipartnum=`gdisk -l $installdevice 2>/dev/null | grep " EF00 " | sed 's/  */:/g' | cut -f2 -d:`
		#if [ -d /sys/firmware/efi ] && [ ! -z "$efipartnum" ]; then #EFI
		if [ ! -z "$efipartnum" ] && [ -d $grublibdir/x86_64-efi ]; then
			efipartition="$installdevice$efipartnum"
			#modprobe efivars #for efibootmgr; unneded here: done by grub install
			mkdir -p /mnt/efi
			mount $efipartition /mnt/efi
			if  [ `uname -m` != "x86_64" ] ; then #modprobe efivars fails on 32 bits Slackware
				mv /lib/modules/`uname -r`/kernel/drivers/firmware/efi/efivars.{ko,ok}
				#efidir="slackware-`cat /etc/slackware-version | cut -f2 -d' '`"
				efidir=$SALIX_FLAVOR
				echo "*** add boot entry for '\\EFI\\$efidir\\grubx64.efi' from UEFI setup ***"
			fi
			grub-install --efi-directory /mnt/efi --boot-directory /mnt/install/boot/ --target=x86_64-efi 2>/dev/null && grubstatus=0
			umount /mnt/efi
			rmdir /mnt/efi
			# Add the EFI System Partition to /etc/fstab:
			mkdir -p /mnt/install/boot/efi
			echo "$efipartition /boot/efi vfat defaults 1 0 " >> /mnt/install/etc/fstab
			if [ "$installdevice" != "/dev/sda" ]; then
				mkdir -p /mnt/efi
				mount $efipartition /mnt/efi
				mkdir -p /mnt/efi/EFI/BOOT
				cp /mnt/efi/EFI/salix/grubx64.efi /mnt/efi/EFI/BOOT/bootx64.efi
				umount /mnt/efi
				rmdir /mnt/efi
			fi	
		fi
		#else #CSM
		
			if echo -e "print\nquit" | parted $installdevice | grep -q ": msdos$" || 
				gdisk -l $installdevice 2>/dev/null | grep -q " EF02 "; then
				grub-install --target=i386-pc --boot-directory /mnt/install/boot --recheck --force $installdevice  && grubstatus=0 #grub-bios-setup
			else
				echo "Warning : GRUB can't be installed:"
				#if [ -d /sys/firmware/efi ]; then
				if [ -z "$efipartnum" ]; then
					echo "- UEFI boot: no 'ef00' - efi partition on $installdevice"
				else
					echo "- CSM (legacy) boot: no 'ef02' - BIOS boot partition on $installdevice (GPT)"
				fi
			fi
		#fi
		#for dir in sys proc dev; do mount --bind /$dir /mnt/install/$dir; done
		chroot /mnt/install grub-mkconfig -o /boot/grub/grub.cfg
		#for dir in sys proc dev; do umount /mnt/install/$dir; done
	fi
		#####
		if [ "$installdevice" != "/dev/sda" ]; then
			if [ "$installdevice" != "/dev/sdb" ]; then
				real_device=`echo $installdevice | cut -c6-8`
				sed -i "s/$real_device/sdb/g" /mnt/install/boot/grub/grub.cfg
				sed -i "s/hd2/hd1/g" /mnt/install/boot/grub/grub.cfg
				sed -i "s/ahci2/ahci1/g" /mnt/install/boot/grub/grub.cfg
			fi
		fi
		#####
   fi # end grub
	
	liveuser=$(cat /etc/passwd | grep /bin/bash | grep /home/| cut -d : -f 1)
	if [ "$liveuser" != "" ]; then 
		echo "Deleting liveuser $liveuser"
		#chroot /mnt/install mount /proc
		chroot /mnt/install /usr/sbin/userdel -r $liveuser  2>/dev/null
		#chroot /mnt/install umount /proc
	fi
	
	if [ "$username" != "" ]; then 
		echo "Creating user $username with password $userpassword"
		#chroot /mnt/install mount /proc
		chroot /mnt/install /usr/sbin/useradd -s /bin/bash -g users -m -k /etc/skel -G audio,video,cdrom,floppy,lp,plugdev,polkitd,power,pulse,netdev,scanner,wheel "$username"
		#chroot /mnt/install umount /proc
	fi
	
	if [ "$userpassword" != "" ]; then 
		echo "Setting password for user $username to $userpassword"
		#chroot /mnt/install mount /proc
		echo ${username}:${userpassword} | chroot /mnt/install chpasswd 
		#chroot /mnt/install umount /proc
	fi
	
    ##############
	# set locale
	if [ "$locale" ]; then
		sed -i "s/^ *\(export LANG=\).*$/\1$locale/" /mnt/install/etc/profile.d/lang.sh
	    locale_noutf8=`echo $locale | sed "s/.utf8//"`
	fi
	# set keyboard
	if [ "$keyboard" ]; then
		chroot /mnt/install /usr/sbin/keyboardsetup -k $keyboard  2>/dev/null
	fi
	#########
	
	if [ -f /mnt/install/etc/kde/kdm/kdmrc ]; then
	  sed -i "s/NoPassEnable=.*/NoPassEnable=/g" /mnt/install/etc/kde/kdm/kdmrc
	  sed -i "s/NoPassUsers=.*/NoPassUsers=/g" /mnt/install/etc/kde/kdm/kdmrc
	  sed -i "s/DefaultUser=.*/DefaultUser=/g" /mnt/install/etc/kde/kdm/kdmrc
	  sed -i "s/AllowNullPasswd=.*/AllowNullPasswd=/g" /mnt/install/etc/kde/kdm/kdmrc
	  sed -i "s/AutoLoginEnable=.*/AutoLoginEnable=/g" /mnt/install/etc/kde/kdm/kdmrc
	  sed -i "s/AutoLoginUser=.*/AutoLoginUser=/g" /mnt/install/etc/kde/kdm/kdmrc
	  if [ "$locale" ]; then
		locale_noutf8=`echo $locale | sed "s/.utf8//"`
		sed -i "s/^ *\(export LANG=\).*$/\1$locale/" /mnt/install/etc/profile.d/lang.sh
	  else  
		locale_noutf8=`cat /etc/kde/kdm/kdmrc | grep Language= | sed 's/\Language=//'`
		sed -i "s/\(^\|^#\)Language=.*/Language=$locale_noutf8/" /mnt/install/etc/kde/kdm/kdmrc
	  fi
	fi

	if [ -f /mnt/install/etc/gdm/custom.conf ]; then
	cat > /mnt/install/etc/gdm/custom.conf << EOF
# GDM Custom Configuration file.
#
# This file is the appropriate place for specifying your customizations to the
# GDM configuration.   If you run gdmsetup, it will automatically edit this
# file for you and will cause the daemon and any running GDM GUI programs to
# automatically update with the new configuration.  Not all configuration
# options are supported by gdmsetup, so to modify some values it may be
# necessary to modify this file directly by hand.
#
# This file overrides the default configuration settings.  These settings 
# are stored in the GDM System Defaults configuration file, which is found
# at the following location.
#
# /usr/share/gdm/defaults.conf.  
#
# This file contains comments about the meaning of each configuration option,
# so is also a useful reference.  Also refer to the documentation links at
# the end of this comment for further information.  In short, to hand-edit
# this file, simply add or modify the key=value combination in the
# appropriate section in the template below this comment section.
#
# For example, if you want to specify a different value for the Enable key
# in the "[debug]" section of your GDM System Defaults configuration file,
# then add "Enable=true" in the "[debug]" section of this file.  If the
# key already exists in this file, then simply modify it.
#
# Older versions of GDM used the "gdm.conf" file for configuration.  If your
# system has an old gdm.conf file on the system, it will be used instead of
# this file - so changes made to this file will not take effect.  Consider
# migrating your configuration to this file and removing the gdm.conf file.
#
# If you hand edit a GDM configuration file, you can run the following
# command and the GDM daemon will immediately reflect the change.  Any
# running GDM GUI programs will also be notified to update with the new
# configuration.
#
# gdmflexiserver --command="UPDATE_CONFIG <configuration key>"
#
# e.g, the "Enable" key in the "[debug]" section would be "debug/Enable".
#
# You can also run gdm-restart or gdm-safe-restart to cause GDM to restart and
# re-read the new configuration settings.  You can also restart GDM by sending
# a HUP or USR1 signal to the daemon.  HUP behaves like gdm-restart and causes
# any user session started by GDM to exit immediately while USR1 behaves like
# gdm-safe-restart and will wait until all users log out before restarting GDM.
#
# For full reference documentation see the gnome help browser under
# GNOME|System category.  You can also find the docs in HTML form on
# http://www.gnome.org/projects/gdm/
#
# NOTE: Lines that begin with "#" are considered comments.
#
# Have fun!

[daemon]

[security]

[xdmcp]

[gui]

[greeter]

[chooser]

[debug]

# Note that to disable servers defined in the GDM System Defaults
# configuration file (such as 0=Standard, you must put a line in this file
# that says 0=inactive, as described in the Configuration section of the GDM
# documentation.
#
[servers]

# Also note, that if you redefine a [server-foo] section, then GDM will
# use the definition in this file, not the GDM System Defaults configuration
# file.  It is currently not possible to disable a [server-foo] section
# defined in the GDM System Defaults configuration file.
#
EOF
	fi
	
	if [ -f /mnt/install/etc/slim.conf ]; then
	cat > /mnt/install/etc/slim.conf << EOF
# Path, X server and arguments (if needed)
# Note: -xauth $authfile is automatically appended
Salix_path        /bin:/usr/bin:/usr/local/bin
Salix_xserver     /usr/bin/X
#xserver_arguments   -dpi 75

# Commands for halt, login, etc.
halt_cmd            /sbin/shutdown -h now
reboot_cmd          /sbin/shutdown -r now
console_cmd         /usr/bin/xterm -C -fg white -bg black +sb -T "Console login" -e /bin/sh -c "/bin/cat /etc/issue; exec /bin/login"
#suspend_cmd        /usr/sbin/suspend
## slackware suspend command
suspend_cmd        /usr/sbin/pm-suspend

# Full path to the xauth binary
xauth_path         /usr/bin/xauth 

# Xauth file for server
authfile           /var/run/slim.auth


# Activate numlock when slim starts. Valid values: on|off
# numlock             on

# Hide the mouse cursor (note: does not work with some WMs).
# Valid values: true|false
# hidecursor          false

# This command is executed after a succesful login.
# you can place the %session and %theme variables
# to handle launching of specific commands in .xinitrc
# depending of chosen session and slim theme
#
# NOTE: if your system does not have bash you need
# to adjust the command according to your preferred shell,
# i.e. for freebsd use:
# login_cmd           exec /bin/sh - ~/.xinitrc %session
login_cmd           exec /bin/bash -login ~/.xinitrc %session

# Commands executed when starting and exiting a session.
# They can be used for registering a X11 session with
# sessreg. You can use the %user variable
#
# sessionstart_cmd	some command
# sessionstop_cmd	some command

# Start in daemon mode. Valid values: yes | no
# Note that this can be overriden by the command line
# options "-d" and "-nodaemon"
# daemon	yes

# Available sessions (first one is the Salix).
# The current chosen session name is replaced in the login_cmd
# above, so your login command can handle different sessions.
# see the xinitrc.sample file shipped with slim sources
sessions            xfce4,icewm-session,wmaker,blackbox

# Executed when pressing F11 (requires imagemagick)
screenshot_cmd      import -window root /slim.png

# welcome message. Available variables: %host, %domain
welcome_msg         Welcome to %host

# Session message. Prepended to the session name when pressing F1
# session_msg         Session: 

# shutdown / reboot messages
shutdown_msg       The system is halting...
reboot_msg         The system is rebooting...

# Salix user, leave blank or remove this line
# for avoid pre-loading the username.
#Salix_user        simone

# Focus the password field on start when Salix_user is set
# Set to "yes" to enable this feature
#focus_password      no

# Automatically login the Salix user (without entering
# the password. Set to "yes" to enable this feature
#auto_login          no


# current theme, use comma separated list to specify a set to 
# randomly choose from
current_theme       Salix

# Lock file
lockfile            /var/run/slim.lock

# Log file
logfile             /var/log/slim.log

EOF

	chmod 755 /mnt/install/usr/bin/slim
fi

	echo "Removing installer"
	#chroot /mnt/install rm -f /home/one/Desktop/salix-live-installer.desktop
	chroot /mnt/install rm -f /home/one/Desktop/sli*.desktop
	
	#chroot /mnt/install spkg -d salix-live-installer
	chroot /mnt/install /sbin/spkg -d sli
	
	chroot /mnt/install
	
	
	# Run various slackware install routines
	#echo "Run various slackware install routines"
	
	#echo "run mkfont"
	#if [ -f /mnt/install/var/log/setup/setup.04.mkfontdir ]; then
	#	chroot /mnt/install /var/log/setup/setup.04.mkfontdir
	#fi
	#echo " update-icon-cache"
	#if [ -f /mnt/install/var/log/setup/setup.08.gtk-update-icon-cache ]; then
	#	chroot /mnt/install /var/log/setup/setup.08.gtk-update-icon-cache
	#fi
	#echo "run update all"
	#if [ -f /mnt/install/usr/sbin/update-all ]; then
	#	chroot /mnt/install /usr/sbin/update-all
	#fi
	#echo "run setup services"
	#if [ -f /mnt/install/var/log/setup/setup.services ]; then
	#	chroot /mnt/install /var/log/setup/setup.services
	#fi
	
	# Set the hostname.echo "umount /mnt/install"
	chmod 777 /mnt/install/etc/HOSTNAME
	echo "salix.example.net" > /mnt/install/etc/HOSTNAME
	chmod 644 /mnt/install/etc/HOSTNAME  
		
	# Use any available swap device:
    for SWAPD in $(blkid |grep TYPE="\"swap\"" |cut -d: -f1) ; do
      echo "Enabling swapping to '$SWAPD'"
      echo "$SWAPD  swap  swap defaults  0  0" >> /mnt/install/etc/fstab
    done

	  #####
		if [ "$installdevice" != "/dev/sda" ]; then
			if [ "$installdevice" != "/dev/sdb" ]; then
				real_device=`echo $installdevice | cut -c6-8`
				sed -i "s/$real_device/sdb/g" /mnt/install/etc/fstab
				sed -i "s/$real_device/sdb/g" /mnt/install/etc/mtab
			fi
		fi
	   #####


	for dir in sys proc dev tmp; do umount /mnt/install/$dir; done

	if [ "$home_dir" != "" ] && [ "$home_dir" != "$systempart" ]; then
		echo "umount /mnt/instal/home"
		umount /mnt/install/home
	fi
	echo "umount /mnt/install"
	umount /mnt/install

	echo "remove /mnt/install"
	rmdir /mnt/install
	
	echo "end installation"
	return 0
}


function share_live() {
	livedirectory=$1
	listeniface=$2
	iprange=$3
	moduleslist=$4
	
	#backups
	if [ ! -f /etc/export.sl ]; then mv /etc/exports{,.sl}; fi
	if [ ! -f /etc/dhcpd.conf.sl ]; then mv /etc/dhcpd.conf{,.sl}; fi
	
	#retrieve network parameters
	serverip=`ifconfig $listeniface | sed -n 2p | sed 's/  */:/g' | cut -f3 -d:`
	netmask=`ifconfig $listeniface | sed -n 2p | sed 's/  */:/g' | cut -f5 -d:`
	gateway=`route -n | sed  -n /^0.0.0.0/p | sed s/\ \ */:/g | cut -f2 -d:`
	nameserver=`cat /etc/resolv.conf | grep nameserver | sed -n 1p | cut -f2 -d' '`
	if [ "$gateway" == "0.0.0.0" ]; then
		gateway=$serverip
		nameserver=$serverip
	fi
	network=`ifconfig $listeniface | sed -n 2p | sed 's/  */:/g' | cut -f7 -d: | sed 's/255/0/g'`
	
	#setup NFS server
	echo "$livedirectory $network/$netmask(ro,no_root_squash,no_all_squash,async,no_subtree_check)" > /etc/exports
	. /etc/rc.d/rc.nfsd start
	
	#setup TFTP booting
	mkdir -p /tftpboot/boot
	cp $livedirectory/boot/* /tftpboot/boot/ 2>/dev/null #copy only files
	cp /usr/share/syslinux/pxelinux.0 /tftpboot/
	cp -r $livedirectory/boot/syslinux /tftpboot/pxelinux.cfg
	rm -f /tftpboot/pxelinux.cfg/{ldlinux.sys,isolinux.bin}
	mv /tftpboot/pxelinux.cfg/{syslinux.cfg,default}
	for configfile in `find /tftpboot/pxelinux.cfg/* ! -name "*.png" ! -name "*.jpg" ! -name "*.c32"`; do
		sed -i "s@append @append nfsroot=$serverip:$livedirectory @" $configfile
		sed -i 's/\(timeout.*\)/\1\nipappend 1/' $configfile
	done
	mv /tftpboot/pxelinux.cfg/* /tftpboot/
	mv /tftpboot/default /tftpboot/pxelinux.cfg/
	
	sed -i s/^\#\ tftp/tftp/ /etc/inetd.conf
	. /etc/rc.d/rc.inetd start
	
	#append net drivers to InitRD
	if [ ! -z "$moduleslist" ]; then
		for initrd in /tftpboot/boot/*.gz; do #for each suspected initrd file
			mkdir /tmp/initrd-tree
			cd /tmp/initrd-tree
			if gunzip -c $initrd | cpio -i 2>/dev/null && [ -d lib/modules ]; then #if it is really an initrd
				kv=`basename lib/modules/*`
				mkinitrd -c -o /tmp/initrd.gz -s /tmp/initrd-tree-bis -k $kv -m $moduleslist
				rm -f /tmp/initrd.gz
				cp -r /tmp/initrd-tree-bis/lib/modules/* lib/modules/
				cat /tmp/initrd-tree-bis/load_kernel_modules >> load_kernel_modules
				rm -rf /tmp/initrd-tree-bis
				find lib/modules/ -name "*.ko" | xargs strip --strip-unneeded
				chroot . depmod $kv
				find . | cpio -o -H newc | gzip -9c > $initrd
			fi
			cd - >/dev/null
			rm -rf /tmp/initrd-tree
		done
	fi
	
	#setup DHCP server
	if ! dhcpcd -T -t 1 $listeniface 2>&1 | grep -q IPv4LL
	then rangeprefix=`echo $serverip | cut -f1-3 -d .` #only the last byte is used for network machine number
		rangebegin=`echo $iprange | cut -f1 -d-`
		rangeend=`echo $iprange | cut -f2 -d-`
		cat > /etc/dhcpd.conf << EOF
ddns-update-style none;
option routers $gateway;
option domain-name-servers $nameserver;

subnet $network netmask $netmask {
	range $rangeprefix.$rangebegin $rangeprefix.$rangeend;
	filename "pxelinux.0";
	next-server $serverip; #TFTP server
}
EOF
		rm -f /var/state/dhcp/dhcpd.leases; touch /var/state/dhcp/dhcpd.leases #needed on live system
		dhcpd $listeniface
	else echo "a DHCP server is already running - PXE parameters are:"
		echo -e "\tfilename \"pxelinux.0\"; #(option 67 on Windows)\n\tnext-server $serverip; #(option 66 on Windows)"
	fi
}


function unshare_live() {
	. /etc/rc.d/rc.nfsd stop
	. /etc/rc.d/rc.inetd stop
	killall dhcpd
	sed -i s/^tftp/\#\ tftp/ /etc/inetd.conf
	if [ -f /etc/export.sl ]; then mv /etc/exports{.sl,}; fi
	if [ -f /etc/dhcpd.conf.sl ]; then mv /etc/dhcpd.conf{.sl,}; fi
}


action=$1
case $action in
"--add")
	packagesdirectory=$2
	rootdirectory=$3
	packageslistfile=$4
	if [ -d "$packagesdirectory" ] && [ ! -z "$rootdirectory" ] && [ -f "$packageslistfile" ]; then
		add_packages $packagesdirectory $rootdirectory $packageslistfile
	else
		echo -e "`basename $0` --add packages_dir root_dir pkg_list_file"
		exit $CMDERROR
	fi
	;;
"--init")
	rootdirectory=$2
	livedirectory=$3
	moduleslist=$4
	if [ -d "$rootdirectory" ] && [ ! -z "$livedirectory" ]; then
		if [ -z "$moduleslist" ]; then
			#moduleslist="squashfs:fuse:loop:ehci-pci:xhci-hcd:usb-storage"
			#moduleslist="squashfs:fuse:loop:xhci-pci:ehci-pci:usb-storage:ext3:isofs"
			#moduleslist="squashfs:fuse:loop:xhci-pci:ohci-pci:ehci-pci:xhci-hcd:uhci-hcd:ehci-hcd:usb-storage:hid:usbhid:hid-generic:hid-cherry:hid-logitech:hid-logitech-dj:hid-logitech-hidpp:hid-lenovo:hid-microsoft:jbd:mbcache:ext3:ext4:isofs:fat:nls_cp437:nls_iso8859-1:msdos:vfat"
			#moduleslist="squashfs:fuse:loop:xhci-pci:ohci-pci:ehci-pci:xhci-hcd:uhci-hcd:ehci-hcd:usb-storage:hid:usbhid:i2c-hid:hid-generic:hid-cherry:hid-logitech:hid-logitech-dj:hid-logitech-hidpp:hid-lenovo:hid-microsoft:hid_multitouch:isofs:nls_cp437:nls_iso8859-1"
			#moduleslist="squashfs:overlay:loop:xhci-pci:ohci-pci:ehci-pci:xhci-hcd:uhci-hcd:ehci-hcd:usb-storage:hid:usbhid:i2c-hid:hid-generic:hid-cherry:hid-logitech:hid-logitech-dj:hid-logitech-hidpp:hid-lenovo:hid-microsoft:hid_multitouch:ext3:ext4:isofs:nls_cp437:nls_iso8859-1"
		    moduleslist="squashfs:overlay:loop:xhci-pci:ohci-pci:ehci-pci:xhci-hcd:uhci-hcd:ehci-hcd:usb-storage:hid:usbhid:i2c-hid:hid-generic:hid-cherry:hid-logitech:hid-logitech-dj:hid-logitech-hidpp:hid-lenovo:hid-microsoft:hid_multitouch:isofs:nls_cp437:nls_iso8859-1"
			#moduleslist="squashfs:overlay:loop:xhci-pci:ohci-pci:ehci-pci:xhci-hcd:uhci-hcd:ehci-hcd:mmc-core:mmc-block:sdhci:sdhci-pci:sdhci-acpi:usb-storage:hid:usbhid:i2c-hid:hid-generic:hid-apple:hid-asus:hid-cherry:hid-logitech:hid-logitech-dj:hid-logitech-hidpp:hid-lenovo:hid-microsoft:hid_multitouch:isofs:crc32c-intel:fuse"
			#moduleslist="squashfs:overlay:isofs:vfat:ext4:loop:xhci-pci:ehci-pci:usb-storage:usbhid:nls_cp437:nls_iso8859-1"
		fi
		init_live $rootdirectory $livedirectory $moduleslist
	else
		echo "`basename $0` --init root_dir live_dir [modules_list]"
		exit $CMDERROR
	fi
	;;
"--sysprep")
	rwdirectory=$2
	if [ -d "$rwdirectory" ]; then
		shift; shift 
		sys_prep "$rwdirectory" $*
	else
		echo "`basename $0` --sysprep root_dir_1(rw) root_dir_2(ro) ..."
		exit $CMDERROR
	fi
	;;
"--module")
	rootdirectory=$2
	livedirectory=$3
	modulename=$4
	if [ "$5" == "-xz" ] || [ "$5" == "-gzip" ]; then
		compression=$5
		option=$6
	else
		option=$5
	fi
	if [ -d "$rootdirectory" ] && [ -d "$livedirectory" ] && [ ! -z "$modulename" ]; then
		add_module $rootdirectory $livedirectory $modulename $compression $option
	else
		echo "`basename $0` --module root_dir live_dir module_file_name [-xz|-gzip] [-optional]"
		exit $CMDERROR
	fi
	;;
"--iso")
	livedirectory=$2
	imagefilename=$3
	if [ -d "$livedirectory" ] && [ -d "`dirname $imagefilename`" ] && [ ! -d "$imagefilename" ]; then
		create_iso $livedirectory $imagefilename
	else
		echo "`basename $0` --iso live_dir iso_file"
		exit $CMDERROR
	fi
	;;
"--usb")
	livedirectory=$2
	installmedia=$3
	if [ -d "$livedirectory" ] && [ -b "$installmedia" ]; then
		livesystemsize=`du -s -m $livedirectory | sed 's/\t.*//'`
		device=`echo $installmedia | cut -c6-8`
		partition=`echo $installmedia | cut -c6-`
		sectorscount=`cat /sys/block/$device/subsystem/$partition/size`
		sectorsize=`cat /sys/block/$device/queue/hw_sector_size`
		let destinationsize=$sectorscount*$sectorsize/1048576
		if (( $livesystemsize > $destinationsize)); then 
			echo "error: insufficant space on device '$installmedia'"
			exit $INSUFFICIENTSPACE
		else
			install_usb $livedirectory $installmedia
			exit $!
		fi
	else
		echo "`basename $0` --usb live_dir device"
		exit $CMDERROR
	fi
	;;
"--install")
	rootdirectory=$2
	systempart=$3
	loadersetup=$4
	username=$5
	userpassword=$6
	installation_mode=$7
	bootloader=$8
	format_home=$9
	SYSINSTALLFS=${10}
	home_dir=${11}
	locale=${12}
	keyboard=${13}
	
	if [ -d "$rootdirectory" ] && [ -b "$systempart" ]; then
		systemsize=`du -s -m $rootdirectory | sed 's/\t.*//'`
		device=`echo $systempart | cut -c6-8`
		partition=`echo $systempart | cut -c6-`
		sectorscount=`cat /sys/block/$device/subsystem/$partition/size`
		sectorsize=`cat /sys/block/$device/queue/hw_sector_size`
		let destinationsize=$sectorscount*$sectorsize/1048576
		if (( $systemsize > $destinationsize)); then 
			echo "error: insufficant space on device '$systempart'"
			exit $INSUFFICIENTSPACE
		else
		  if [ "$home_dir" == "" ]; then
			SYSINSTALLFS="ext4"
		  fi
			install_system $rootdirectory $systempart $loadersetup $username $userpassword $installation_mode $bootloader $format_home $SYSINSTALLFS $home_dir $locale $keyboard
			exit $!
		fi
	else
		echo "`basename $0` --install root_dir device [-auto|-z] username userpassword installation_mode bootloader format_home SYSINSTALLFS home_dir locale keyboard"
		exit $CMDERROR
	fi
	;;
"--share")
	livedirectory=$2
	listeniface=$3
	iprange=$4
	moduleslist=$5
	if [ -d "$livedirectory" ] && ifconfig | grep -q "$listeniface:" && [ ! -z "$iprange" ]; then
		if [ "$moduleslist" == "auto" ]; then
			moduleslist=""
			for module in `lsmod | cut -f1 -d' '`; do 
				if [ ! -z `find /lib/modules/*/kernel/drivers/net -name "$module.ko"` ]; then
					moduleslist+=":$module"
				fi
			done
			moduleslist=`echo $moduleslist | cut -c2-`
		fi
		unshare_live
		share_live $livedirectory $listeniface $iprange $moduleslist
	else
		echo "`basename $0` --share live_system_dir listen_interface ip_range [modules_list|auto]"
		exit $CMDERROR
	fi
	;;
"--unshare")
	unshare_live
	;;
*)	echo "`basename $0` --add packages_dir root_dir pkg_list_file"
	echo "`basename $0` --sysprep root_dir_1(rw) root_dir_2(ro) ..."
	echo "`basename $0` --init root_dir live_dir [modules_list]"
	echo "`basename $0` --module root_dir live_dir module_file [-xz|-gzip] [-optional]"
	echo "`basename $0` --iso live_dir iso_file"
	echo "`basename $0` --usb live_dir device"
	echo "`basename $0` --install root_dir device [-auto|-expert] username userpassword [core|basic|full] [grub|lilo] [yes|no] filesystem_type home_dir"
	echo "`basename $0` --share live_dir listen_interface ip_range [modules_list|auto]"
	echo "`basename $0` --unshare"
	exit $CMDERROR
	;;
esac
