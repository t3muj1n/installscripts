#!/usr/bin/env bash 

#install_stuff_dir="/mnt/external/install_stuff/"

#intel firmware for my laptop
client_nfs=(
	nfs-common
)
server_nfs=(
	nfs-kernel-server nfs-common
)

firmware_intel=(
	firmware-realtek firmware-iwlwifi 
)
#common tools and such 
newinstall=(
	snmp tcpdump smbclient usbutils dnsutils vim netcat rdiff
	htop irssi nmap curl git screen links alsa-utils aptitude 
)
#xfce4 desktop base install
desktop_xfce4_base=(
	xfce4 xfce4-terminal
)
#internet browser
desktop_browser_arm=(
	iceweasel chromium-browser adblock-plus
)
desktop_browser_std=(
	chromium
)
#file manager plus samba shares
desktop_filemanager=(
	thunar gvfs* sshfs
)
#common and useful X desktop tools
desktop_tools=(
	arandr vlc gkrellm xchat vim-gtk xterm
)
#gui zipfile and such handler
desktop_archive_program=(
	ark 
)
#tiling window manager im experementing with
desktop_i3wm=(
	xinit i3 dmenu
)
#serial gps viewer
server_gps=(
	gpsd
)
#hamradio stuff
hamradio=(
	gpredict ax25*
)
#libs needed my xastir if compiling
dev_xastir_libs=(
	libgeographiclib-dev* graphicsmagick-libmagick-dev-compat 
	libproj-dev pcre* libtiff-dev libgraphicsmagick1-dev
	libgraphicsmagick++1-dev libxt-dev lesstif2 libmotif-dev
)
#compiling tools and such
dev_make_tools=(
	automake gcc make
)
#common dhcp server
server_dhcp=(
	isc-dhcp-server
	
)
#windows shared folder server
server_samba=(
	samba
)
#remote desktop
server_vnc=(
	tightvnc*
)
vm_openvswitch_base=(
	openvswitch-switch
	openvswitch-common
	openvswitch-dbg
	openvswitch-test
)
vm_deps=(
	"${dev_make_tools[@]}" libssl-dev "linux-headers-$(uname -r)"
)


####################################################################
do_install_vnc () {
	set -x
	apt-get install "${server_vnc[@]}" -y
set +x
}
do_install_samba () {
	set -x
#installs and sets up samba and a share. 
#mostly used for my fileserver filebian

	local myfstab="/etc/fstab"
	local smbmountpoint="/mnt/external"
	local smbgroup="external"
	local smbuser="smb"
	local mysmbconf="/etc/samba/smb.conf"
	local smbconf_global=(
		'[global]'
		'workgroup = WORKGROUP'
		'server string = %h server'
		'dns proxy = no'
		'log file = /var/log/samba/log.%m'
		'max log size = 1000'
		'syslog = 0'
		'panic action = /usr/share/samba/panic-action %d'
		'encrypt passwords = true'
		'passdb backend = tdbsam'
		'obey pam restrictions = yes'
		'unix password sync = yes'
		'passwd program = /usr/bin/passwd %u'
		'passwd chat = *Enter\snew\s*\spassword:* %n\n *Retype\snew\s*\spassword:* %n\n *password\supdated\ssuccessfully* .'
		'pam password change = yes'
		'map to guest = bad user'
		'usershare allow guests = yes'
	)
	local smbconf_homes=(
		'[homes]'
		'comment = Home Directories'
		'browseable = no'
		'read only = no'
		'create mask = 0700'
		'directory mask = 0700'
		'valid users = %S'
	)
	local smbconf_printers=(
		'[printers]'
		'comment = All Printers'
		'browseable = no'
		'path = /var/spool/samba'
		'printable = yes'
		'guest ok = no'
		'read only = yes'
		'create mask = 0700'
		''
		'[print$]'
		'comment = Printer Drivers'
		'path = /var/lib/samba/printers'
		'browseable = yes'
		'read only = yes'
		'guest ok = no'
	)
	local smbconf_2tbshare=(
		'[2TB Share]'
		'comment = "networked storage"'
		'read only = no'
		'locking = no'
		'path = /mnt/external'
		'guest ok = no'
		'directory mask = 0755'
		'create mask = 0775'
		'force create mode = 0755'
		'force directory mode = 0755'
		'valid users = @external'
		'force group = external'
	)
	
	
	echo "installing samba"
	echo
	apt-get install "${server_samba[@]}" -y
	echo "setting up smb.conf"
	echo
	mv "${mysmbconf}" "${mysmbconf}.bak"
	printf "%s\n" "${smbconf_global[@]}" >> "${mysmbconf}" 
	printf "%s\n" "${smbconf_homes[@]}" >> "${mysmbconf}"
	printf "%s\n" "${smbconf_printers[@]}" >> "${mysmbconf}" 
	printf "%s\n" "${smbconf_2tbshare[@]}" >> "${mysmbconf}"
	printf "%b" "\n" >> "${myfstab}"
	cat "${mysmbconf}"

	groupadd -g 1100 "${smbgroup}"
	read -r _ myblockid _ <<< "$( blkid | grep sda1 | tr -d \" )"
	smbmount_infstab='no'
	while read -r line ; do
		if [[ "${line}" = ${myblockid}* ]] ; then
			smbmount_infstab='yes'
			break;
		else
			continue;
		fi;
	done < "${myfstab}"
	if ! [[ "${smbmount_infstab}" = 'yes' ]] ; then
		echo "${myblockid} ${smbmountpoint} ext4 defaults,nodev,nosuid,auto 0 2" >> "$myfstab"
	fi
	mkdir "${smbmountpoint}"
	mount "${smbmountpoint}"
	echo "adding user smb"
	echo
	useradd -M -d "${smbmountpoint}" -g "${smbgroup}" -s /bin/bash -u 1001 -N "${smbuser}" 
	smbpasswd -a -n "${smbuser}" 
	smbpasswd -e -a "${smbuser}"
	/etc/init.d/samba restart
 	echo "install samba complete"
	echo
	set +x
}

do_install_fstab () { 
set -x
#expects one arguement, the hostname
	local myfstab="/etc/fstab"
	echo "installing fstab"
	echo	
	if [[ "$1" = "Filebian" ]] ; then
		mountpoint="/mnt/external"
		mkdir /mnt/nand
		echo '/dev/nand	/mnt/nand ext4 defaults,nodev,nosuid,auto,sync 0 2' >> "$myfstab"
		mount /mnt/nand 
	fi

	echo "install fstab complete"
	echo
set +x
}

do_install_xastir () {
set -x
#install xastir
	echo "installing xastir"
	echo
	local myxastir="xastir-2.0.6"
	local xastirurl="http://sourceforge.net/projects/xastir/files/xastir-stable/${myxastir}/${myxastir}.tar.gz"
	read -r machinetype <<< "$( uname -m )"
	if [[ "${machinetype}" = armv* ]]; then
		local tmpdir="/tmp/installscript.${RANDOM}"
		
		apt-get install "${dev_make_tools[@]}" -y
		apt-get install "${dev_xastir_libs[@]}" -y
		if ! mkdir "${tmpdir}"; then 
			echo "mkdir failed"; exit 1; fi
		if ! cd "${tmpdir}"; then
			echo "cd tmpdir failed"; exit 1; fi
		if ! wget "${xastirurl}" && sync ; then	
			echo "wget xastir failed"; exit 1; fi
		if ! tar xfvz "${myxastir}.tar.gz" && sync; then 
			echo "untaring xastir failed."; exit 1; fi
		if ! cd  ./"${myxastir}"; then 
			echo "cd failed."; exit 1; fi
		if ! ./configure --with-geotiff=/usr/include/geotiff ; then 
			echo " failed."; exit 1; fi
		if ! make install ; then 
			echo "make install failed."; exit 1; fi
		cd -
	else
		apt-get install xastir -y
	fi

		

echo "installing xastir complete"
echo
set +x
}

do_turnpacketforwardingon () {
set -x
	echo "Turning on packet forwarding."
	echo
        local sysctlfile="/etc/sysctl.conf"

        if ! [[ -f "${sysctlfile}" ]] ; then
                echo "sysctl not found"
        else
                echo "file found "
        while read -r line ; do
               if [[ "$line" = '#net.ipv4.ip_forward=1' ]] ; then
                        echo 'net.ipv4.ip_forward=1' ;
                else
                        echo "$line"
                fi
        done < "${sysctlfile}" > /tmp/sysctl.conf.tmp
        mv "${sysctlfile}"  "${sysctlfile}.bak" &&
        mv /tmp/sysctl.conf.tmp "${sysctlfile}"
        fi
        echo "packet forwarding on complete!"
	echo
set +x
}

do_update_system () {
set -x
	echo "updating system"
	echo
	apt-get autoclean
	apt-get update
	apt-get upgrade -y
	echo "updating system complete"
	echo
set +x
}

do_install_newinstall () {
set -x
	echo "do new install"
	echo
	apt-get install "${newinstall[@]}" -y
	echo "do new install complete"
	echo
set +x
}

do_install_desktop_std () {
set -x
	echo "do install standard desktop"
	echo
	apt-get install "${desktop_xfce4_base[@]}" -y
	apt-get install "${desktop_tools[@]}" -y
	
	read -r machinetype <<< "$( uname -m )"
	if [[ "${machinetype}" = armv* ]]; then
		apt-get install "${desktop_browser_arm[@]}" -y;
	else
		apt-get install "${desktop_browser_std[@]}" -y;
	fi
	apt-get install "${desktop_filemanager[@]}" -y
	apt-get install "${desktop_archive_program[@]}" -y
	echo "do install standard desktop complete"
	echo
set +x
}



#######################################################3

do_install_firmware () {
set -x 
	apt-get install "${firmware_intel[@]}" -y
set +x
}
do_install_openvswitch () {
set -x 
	apt-get install "${vm_openvswitch_base[@]}" -y
set +x
}

do_install_client_nfs () {
set -x
	apt-get inatall "${client_nfs[@]}" -y
set +x
}
do_install_server_nfs () {
set -x
	apt-get install "${server_nfs[@]}" -y
set +x
}
do_install_dev_openvswitch () {
set -x	
	#apt-get install "${ovs_deps[@]}" -y
	#mkdir "/tmp/ovs"
	#cd /tmp/ovs
	#wget http://openvswitch.org/releases/openvswitch-1.9.3.tar.gz
	#tar xfvz openvswitch-1.9.3.tar.gz
	#cd openvswitch-1.9.3
	#./configure --with-linux=/lib/modules/"$(uname -r)"/build
	#make && make install
	#insmod ./datapath/linux/openvswitch.ko
	#if  lsmod | grep openvswitch ; then
	#	make modules_install
	#fi
#	ovsdb-server --remote=punix:/usr/local/var/run/openvswitch/db.sock - remote=db:Open_vSwitch,manager_options --pidfile --detach
#ovs-vsctl --no-wait init
#ovs-vswitchd --pidfile --detach
set +x
}















