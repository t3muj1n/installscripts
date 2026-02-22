#!/usr/bin/env bash

host="$1";
api_base='redfish/v1';
ilo_user='hidden';
ilo_pass='hidden';
commstring='hidden';


get_ilo_version () {
	echo "function get_ilo_version";
       
    curl -s --insecure -u ${ilo_user}:${ilo_pass} \
		--header 'Content-Type: application/json' \
		--request GET \
		--location "https://${host}/${api_base}/" | \
		jq '.Oem.Hpe.Manager[].ManagerType';
		
}
# enable SNMP
do_enable_main_snmp () {
	echo "function do_enable_main_snmp";
	
	curl -s --insecure -u ${ilo_user}:${ilo_pass} \
		--request PATCH \
		--location https://${host}/${api_base}/Managers/1/NetworkProtocol/ \
		--header 'Content-Type: application/json' \
		--data '{
			"SNMP": {
			"ProtocolEnabled": true
			}
		}' | \
		jq '.error["@Message.ExtendedInfo"][].MessageId';
}

# reboot ilo
do_reboot_ilo () {
	echo "function do_reboot_ilo";
	local timer=60;
	
	curl -s -u ${ilo_user}:${ilo_pass} \
		--location https://${host}/${api_base}/Managers/1/Actions/Manager.Reset/ \
		--insecure \
		--request POST \
		--header 'Content-Type: application/json' \
		--data '{"ResetType": "ForceRestart"}' | \
	jq '.error["@Message.ExtendedInfo"][].MessageId';
	#this might need to change to 90 for ilo 7
	echo "sleeping for ${timer} seconds";
	sleep ${timer};
}

# enable the other SNMP settings
do_enable_snmp_settings () {
	echo "function do_enable_snmp_settings";
	
	curl -s --insecure -u ${ilo_user}:${ilo_pass} \
		--request PATCH \
		--location https://${host}/${api_base}/Managers/1/SnmpService/ \
		--header 'Content-Type: application/json' \
		--data '{
		"SNMPv1Enabled": true,
		"SNMPv1Traps": true,
		"AlertsEnabled": true,
		"Oem": {
			"Hpe": {
			"SNMPColdStartTrapBroadcast": true
			}
		}
	}' | \
	jq '.error["@Message.ExtendedInfo"][].MessageId';
}

# set the community string
do_set_community_string () {
	echo "function do_set_community_string";
	
	curl -s --insecure -u ${ilo_user}:${ilo_pass} \
		--request PATCH \
		--location https://${host}/${api_base}/Managers/1/SnmpService/ \
		--header 'Content-Type: application/json' \
		--data "{ \"ReadCommunities\": [\"${commstring}\"] }" | \
		jq '.error["@Message.ExtendedInfo"][].MessageId';
}

############### main #####################

echo;

get_ilo_version;
do_enable_main_snmp;
do_reboot_ilo;
do_enable_snmp_settings;
do_set_community_string;








