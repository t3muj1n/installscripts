#!/usr/bin/env bash
#set -x
master_passwd="/etc/passwd"
master_shadow="/etc/shadow"
master_group="/etc/group"
master_gshadow="/etc/gshadow"
masternode="nlogin01"			#only node allowed to run script
myhostname="$(hostname)"
tmpdir="/tmp/useradd.${RANDOM}"

nodelist=( 'nosc01' 'nosc02' 'nosc03' 'ncomp01' 'ncomp02' 'ncomp03' 'ncomp04' 'ncomp05' 'ncomp06' 'ncomp07' 'ncomp08' 'ncomp09' 'ncomp10' 'ncomp11' 'ncomp12' 'ncomp13' 'ncomp14' 'ncomp15' 'ncomp16' 'ncomp17' 'ncomp18' 'ncomp19' 'ncomp20'  )
#nodelist=( 'ncomp07' 'ncomp08') #nodes used for testing


####################Some sanity checks#########################
#check that this is only run from the login node
if ! [[ "${myhostname}" = "${masternode}" ]]; then
	echo "this must be run from ${masternode} by an administrator."
	exit 1
fi
if ! [[ "$(whoami)" = "root" ]] ; then
	echo "this must be run by an administrator"
	exit 1
fi
if ! [[ -e "${master_passwd}" ]]; then
	echo "${master_passwd} not found"
	exit 1
fi
if ! [[ -e "${master_shadow}" ]]; then
	echo "${master_shadow} not found"
	exit 1
fi
if ! [[ -e "${master_group}" ]]; then
	echo "${master_group} not found"
	exit 1
fi
if ! [[ -e "${master_gshadow}" ]]; then
	echo "${master_gshadow} not found"
	exit 1
fi
#############################################################

usage () {
	echo "usage stubout"
}

myuseradd () {
	local userargs=("$@")
	local newuser=""
	cat "${master_passwd}" | sort >> "${tmpdir}/passwd.orig"
	chmod 0600 "${tmpdir}/passwd.orig"
	useradd "${userargs}"
	cat "${master_passwd}" | sort >> "${tmpdir}/passwd.new"
	chmod 0600 "${tmpdir}/passwd.new"
	read -r newuser <<< "$(comm -3 "${tmpdir}/passwd.orig" "${tmpdir}/passwd.new" | cut -d ':' -f1)";
	rm -f "${tmpdir}/passwd.orig"
	rm -f "${tmpdir}/passwd.new" 
	passwd "${newuser}"
}
getfilesfromnodes () {
	#split the hostname from the filedata, and store in files based on hostname
	while IFS=': ' read -r nodereply line; do
		if ! [[ -e "${tmpdir}/${nodereply}.passwd.orig" ]]; then
			touch "${tmpdir}/${nodereply}.passwd.orig"
			chmod 0600 "${tmpdir}/${nodereply}.passwd.orig"
		fi
		echo "$line" >> "${tmpdir}/${nodereply}.passwd.orig"
	done < <(pdsh -w "$(printf "%s," "${nodelist[@]}")" cat /etc/passwd )
	
	while IFS=': ' read -r nodereply line; do
		if ! [[ -e "${tmpdir}/${nodereply}.shadow.orig" ]]; then
			touch "${tmpdir}/${nodereply}.shadow.orig"
			chmod 0600 "${tmpdir}/${nodereply}.shadow.orig"
		fi
		echo "$line" >> "${tmpdir}/${nodereply}.shadow.orig"
	done < <(pdsh -w "$(printf "%s," "${nodelist[@]}")" cat /etc/shadow )

	while IFS=': ' read -r nodereply line; do
		if ! [[ -e "${tmpdir}/${nodereply}.group.orig" ]]; then
			touch "${tmpdir}/${nodereply}.group.orig"
			chmod 0600 "${tmpdir}/${nodereply}.group.orig"
		fi
		echo "$line" >> "${tmpdir}/${nodereply}.group.orig"
	done < <(pdsh -w "$(printf "%s," "${nodelist[@]}")" cat /etc/group )

	while IFS=': ' read -r nodereply line; do
		if ! [[ -e "${tmpdir}/${nodereply}.gshadow.orig" ]]; then
			touch "${tmpdir}/${nodereply}.gshadow.orig"
			chmod 0600 "${tmpdir}/${nodereply}.gshadow.orig"
		fi
		echo "$line" >> "${tmpdir}/${nodereply}.gshadow.orig"
	done < <(pdsh -w "$(printf "%s," "${nodelist[@]}")" cat /etc/gshadow )
}

checkpasswdagainstmaster () {

	local nodeuserlist=();
	nodepasswdneedsupdating="no"
	local isinofflinenodes="no"
	for node in "${nodelist[@]}"; do
		cp "${master_passwd}" "${tmpdir}/masterpasswd.tmp"
		if [[ -e "${tmpdir}/${node}.passwd.orig" ]]; then
			echo "generating passwd file for ${node}"
			while read -r user ; do
				nodeuserlist+=("$user");
			done < <( cat "${tmpdir}/${node}.passwd.orig" | cut -d':' -f1 )
			while read -r line; do
				for user in "${nodeuserlist[@]}"; do
					if [[ "$line" = ${user}* ]]; then
						echo "${line}"
						break
					else
						continue;
					fi
				done
			done < "${tmpdir}/masterpasswd.tmp"  >> "${tmpdir}/toremove"
			nodepasswdneedsupdating="yes"
			nodepasswdneedsupdatinglist+=("$node");
			while read -r line ; do
				cat "${tmpdir}/masterpasswd.tmp" | grep -v "${line}" >> "${tmpdir}/masterpasswd.new"
				mv "${tmpdir}/masterpasswd.new" "${tmpdir}/masterpasswd.tmp"
			done < "${tmpdir}/toremove"
			rm -f "${tmpdir}/toremove"
			mv "${tmpdir}/masterpasswd.tmp" "${tmpdir}/${node}.passwd.new"
			cat "${tmpdir}/${node}.passwd.orig" >> "${tmpdir}/${node}.passwd.new"
			sort -t: -k3 -n "${tmpdir}/${node}.passwd.new" > "${tmpdir}/${node}.passwd.tmp"
			mv "${tmpdir}/${node}.passwd.tmp" "${tmpdir}/${node}.passwd.rdy"
		else
			offlinenodes+=("$node");
		fi
	done
}

checkshadowagainstmaster () {
	local nodeuserlist=();
	nodeshadowneedsupdating="no"
	for node in "${nodelist[@]}"; do
		cp "${master_shadow}" "${tmpdir}/mastershadow.tmp"
		if [[ -e "${tmpdir}/${node}.shadow.orig" ]]; then
			echo "generating shadow file for ${node}"
			while read -r user ; do 
				nodeuserlist+=("$user");
			done < <( cat "${tmpdir}/${node}.shadow.orig" | cut -d':' -f1 )
			while read -r line; do
				for user in "${nodeuserlist[@]}"; do
					if [[ "$line" = ${user}* ]]; then
						echo "${line}"
						break
					else
						continue;
					fi
				done
			done < "${tmpdir}/mastershadow.tmp" >> "${tmpdir}/toremove"
			nodeshadowneedsupdating="yes"
			nodeshadowneedsupdatinglist+=("$node");
			while read -r line ; do
				cat "${tmpdir}/mastershadow.tmp" | grep -v "${line}" >> "${tmpdir}/mastershadow.new"
				mv "${tmpdir}/mastershadow.new" "${tmpdir}/mastershadow.tmp"
			done < "${tmpdir}/toremove"
			rm -f "${tmpdir}/toremove"
			mv "${tmpdir}/mastershadow.tmp" "${tmpdir}/${node}.shadow.new"
			cat "${tmpdir}/${node}.shadow.orig" >> "${tmpdir}/${node}.shadow.new"
			sort -t: -k3 -n "${tmpdir}/${node}.shadow.new" > "${tmpdir}/${node}.shadow.tmp"
			mv "${tmpdir}/${node}.shadow.tmp" "${tmpdir}/${node}.shadow.rdy"
		else
			offlinenodes+=("$node");
		fi
	done
}

checkgroupagainstmaster () {
	local nodeuserlist=();
	nodegroupneedsupdating="no"
	for node in "${nodelist[@]}"; do
		cp "${master_group}" "${tmpdir}/mastergroup.tmp"
		if [[ -e "${tmpdir}/${node}.group.orig" ]]; then
			echo "generating group file for ${node}"
			while read -r user ; do
				nodeuserlist+=("$user")
			done < <( cat "${tmpdir}/${node}.group.orig" | cut -d':' -f1 )
			while read -r line; do
				for user in "${nodeuserlist[@]}"; do
					if [[ "$line" = ${user}* ]]; then
						echo "${line}"
						break
					else
						continue;
					fi
				done
			done < "${tmpdir}/mastergroup.tmp" >> "${tmpdir}/toremove"
			nodegroupneedsupdating="yes"
			nodegroupneedsupdatinglist+=("$node");
			while read -r line ; do 
				cat "${tmpdir}/mastergroup.tmp" |grep -v "${line}" >> "${tmpdir}/mastergroup.new"
				mv "${tmpdir}/mastergroup.new" "${tmpdir}/mastergroup.tmp"
			done < "${tmpdir}/toremove"
			rm -f "${tmpdir}/toremove"
			mv "${tmpdir}/mastergroup.tmp" "${tmpdir}/${node}.group.new"
			cat "${tmpdir}/${node}.group.orig" >> "${tmpdir}/${node}.group.new"
			sort -t: -k3 -n "${tmpdir}/${node}.group.new" > "${tmpdir}/${node}.group.tmp"
			mv "${tmpdir}/${node}.group.tmp" "${tmpdir}/${node}.group.rdy"
		else
			offlinenodes+=("$node");
		fi
	done
}

checkgshadowagainstmaster () {
	local nodeuserlist=();
	nodegshadowneedsupdating="no"
	for node in "${nodelist[@]}"; do
		cp "${master_gshadow}" "${tmpdir}/mastergshadow.tmp"
		if [[ -e "${tmpdir}/${node}.gshadow.orig" ]]; then
			echo "generating gshdadow file for ${node}"
			while read -r user ; do
				nodeuserlist+=("$user");
			done < <( cat "${tmpdir}/${node}.gshadow.orig" | cut -d':' -f1 )
			while read -r line; do
				for user in "${nodeuserlist[@]}"; do
					if [[ "$line" = ${user}* ]]; then
						echo "${line}"
						break
					else
						continue;
					fi
				done
			done < "${tmpdir}/mastergshadow.tmp" >> "${tmpdir}/toremove"
			nodegshadowneedsupdating="yes"
			nodegshadowneedsupdatinglist+=("$node");
			while read -r line ; do 
				cat "${tmpdir}/mastergshadow.tmp" |grep -v "${line}" >> "${tmpdir}/mastergshadow.new"
				mv "${tmpdir}/mastergshadow.new" "${tmpdir}/mastergshadow.tmp"
			done < "${tmpdir}/toremove"
			rm -f "${tmpdir}/toremove"
			mv "${tmpdir}/mastergshadow.tmp" "${tmpdir}/${node}.gshadow.new"
			cat "${tmpdir}/${node}.gshadow.orig" >> "${tmpdir}/${node}.gshadow.new"
			#sort -t: -k3 -n "${tmpdir}/${node}.gshadow.new"> "${tmpdir}/${node}.passwd.tmp"
			mv "${tmpdir}/${node}.gshadow.new" "${tmpdir}/${node}.gshadow.rdy"
		else
			offlinenodes+=("$node");
		fi
	done
}

checkifneedsync () {
	getfilesfromnodes;
	checkpasswdagainstmaster;
	checkshadowagainstmaster;
	checkgroupagainstmaster;
	checkgshadowagainstmaster;
}	

syncnodes () {
echo "sync nodes"

if [[ "${nodepasswdneedsupdating}"  = yes ]]; then
	for node in "${nodepasswdneedsupdatinglist[@]}"; do
		( scp "${tmpdir}/${node}.passwd.rdy" "$(whoami)@${node}:${master_passwd}" ||
		echo "${node} failed updating"
		)& 
	done
fi

if [[ "${nodeshadowneedsupdating}" = yes ]]; then
	for node in "${nodeshadowneedsupdatinglist[@]}"; do
		( scp "${tmpdir}/${node}.shadow.rdy" "$(whoami)@${node}:${master_shadow}" ||
		echo "${node} failed updating"
		)& 
	done
fi

if [[ "${nodegroupneedsupdating}" = yes ]]; then
	for node in "${nodegroupneedsupdatinglist[@]}"; do
		( scp "${tmpdir}/${node}.group.rdy" "$(whoami)@${node}:${master_group}" ||
		echo "${node} failed updating"
		)& 
	done
fi

if [[ "${nodegshadowneedsupdating}" = yes ]]; then 
	for node in "${nodegshadowneedsupdatinglist[@]}"; do
		( scp "${tmpdir}/${node}.gshadow.rdy" "$(whoami)@${node}:${master_gshadow}" ||
		echo "${node} failed updating"  
		)& 
	done

fi
echo "syncing nodes complete."
}

reportofflinenodes () {
	local node=""
	for node in "${offlinenodes[@]}"; do
		printf "%s is unresponsive and cannot be updated!.\n" "${node}"
	done | sort -u
}

cleanup () {
#	rm -rf "${tmpdir}"
#	exit 0
#this diddnt work as expected, because some of the ssh bg jobs
#have not exited yet before this is called. 
	chmod -R 0600 "${tmpdir}"
}
############################################################

mkdir "${tmpdir}"
chmod 0600 "${tmpdir}"
cd "${tmpdir}"

if [[ "$#" -eq 0 ]]; then
	usage;
	exit 0
else
#add the user from the command line.
#optins are passed to the useradd command.
	myuseradd "$@";
	checkifneedsync;
	syncnodes;
	reportofflinenodes;
fi

#cleanup; #remove the tempdir.. this diddnt work as expected, because some of the ssh clients havnt exited yet.....

