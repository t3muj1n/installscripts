#!/usr/bin/env bash
turnfirewalloff () {
		
	service iptables save
	service iptables stop
	chkconfig iptables off
	service ip6tables save
	service ip6tables stop
	chkconfig ip6tables off
}

disableselinux () {
	selinuxconfigfile='/etc/selinux/config'
	mv "${selinuxconfigfile}" "${selinuxconfigfile}.bak"
	while read -r line ; do # redone untested.
			if [[ "$line" = SELINUX\=enabled ]]
				printf "%s\n" "${line/enabled/disabled/}"
			else
				printf "%s\n" "${line}"
			fi;
	done < "${selinuxconfigfile}.bak" > "${selinuxconfigfile}"
}
