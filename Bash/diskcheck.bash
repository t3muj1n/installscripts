#!/usr/bin/env bash

#alert threshold variables
alert_threshold=50;
moderate_threshold=85
crit_threshold=95;

#email variables
message_subject='ALERT!'
message_body=
#msg_file="/path/to/msg.txt"
#mountpoints+=(); #mountpoint to monitor

#get disk usage
get_disk_usage () {

	while read -r _ _ _ _ percent_used _; do 
		percent_used="${percent_used/\%/}";
		if [[ ${percent_used} -lt ${alert_threshold} ]]; then
			continue;
		elif [[ ${percent_used} -ge ${alert_threshold} && ${percent_used} -lt ${moderate_threshold} ]]; then
			echo "Warning low: the mountpoint has reached the alert threshold ${alert_threshold}%";
		elif [[ ${percent_used} -ge ${moderate_threshold} && ${percent_used} -lt ${crit_threshold} ]]; then 
			echo "warning medium: mountpoint has reached alert condition ${moderate_threshold}%"
		elif [[ ${percent_used} -ge ${crit_threshold} ]]; then 
			echo "warning high: mountpoint has reached alert condition ${crit_threshold}";
		else 
			echo "error" ;
			return 1;		
		fi
	done < <(df)
}

#send alert through email
send_email_alert () {
	#this one is using a msg in a variable
	for i in "${!notify_email_address[@]}" ; do 
		echo mail -s "${message_subject}" ${notify_email_address[i]} <<< "${message_body}"; 
	done

	#this one uses a text file for the message
	#echo mail -s "${message_subject}" ${notify_email_address[0]} < "${msg_file}";
}

#check inpq and outpq fifos are not backing up
check_queue_functioning () {
	
	inputq_path="/siso/inpq"
	outputq_path=/siso/outpq

	#if fifos are greater than 8bytes, wait a few minutes, and check again
	#if it is still backing up, there is a problem and throw an alert.
	while read -r filesize _ ; do 
		if [[ ${filesize} -ge 8 ]]; then
			#
		fi
	done < <(du -sh "${inputq_path}" "${outputq_path}")

}

