#!/usr/bin/env bash
#owner mirobins@amd.com
api_base='redfish/v1';

host="NOTSET";
ilo_user='NOTSET';
ilo_pass='NOTSET';
commstring='NOTSET';
snmp_version='NOTSET';

#snmpv3 variables
snmpv3_protocol='';
snmpv3_passphrase='';
snmpv3_level='';
snmpv3_username='';
snmpv3_encprotocol='';
snmpv3_encpassphrase='';

do_getopts () {
  if [[ $# -ge 1 ]]; then
    while getopts ":u:p:c:v:s:a:A:l:U:x:X:h" opt; do
      case $opt in

        u)  ilo_user="${OPTARG}";
            ;;
        p)  ilo_pass="${OPTARG}";
            ;;
        c)  commstring="${OPTARG}";
            ;;
        v)  snmp_version="${OPTARG}";
            ;;
        s)  host="${OPTARG}";
            ;;
        a)  snmpv3_protocol="${OPTARG}";
            ;;
        A)  snmpv3_passphrase="${OPTARG}";
            ;;
        l)  snmpv3_level="${OPTARG}";
            ;;
        U)  snmpv3_username="${OPTARG}";
            ;;
        x)  snmpv3_encprotocol="${OPTARG}";
            ;;
        X)  snmpv3_encpassphrase="${OPTARG}";
            ;;
        h)   do_usage;
            ;;
      esac
    done
  else
    do_usage;
    exit;
  fi;

}

do_usage () {
    echo " -u ilo user";
    echo " -p ilo password";
    echo " -c community string";
    echo " -v snmp version \"2c\" or \"3\"";
    echo " -s hostname";
    echo " -h help";
    echo " -a snmpv3 protocol. ex: -a SHA";
    echo " -A snmpv3 passphrase";
    echo " -l snmpv3 snmpv3 level. ex: authpriv";
    echo " -U snmpv3 username. ";
    echo " -x snmpv3 encryption protocol. ex: AES";
    echo " -X snmpv3 encryption passphrase";
    echo " ex: $0 -u admin -p password -c public -v 2c -s hostname.amd.com"
    echo " ex: $0 -u root -p IL0acces$ -c sGnEmSp% -v 3 -s plhwe-ae1-josh02-sp.amd.com -a SHA -A authpassword -l authpriv -U snmpuser -x AES -X encpassphrase";
    exit 1;
}

get_ilo_version () {
  echo "function get_ilo_version";
  curl -s --insecure -u ${ilo_user}:${ilo_pass} --header 'Content-Type: application/json' --request GET --location "https://${host}/${api_base}/" | jq '.Oem.Hpe.Manager[].ManagerType' ;
}

# enable SNMP
do_enable_main_snmp () {
  echo "function do_enable_main_snmp";
  curl -s --insecure -u ${ilo_user}:${ilo_pass} --request PATCH --location https://${host}/${api_base}/Managers/1/NetworkProtocol/ --header 'Content-Type: application/json' \
  --data '{
            "SNMP": {
              "ProtocolEnabled": true
            }
      }' | jq '.error["@Message.ExtendedInfo"][].MessageId';
}

# reboot ilo
do_reboot_ilo () {
  echo "function do_reboot_ilo";
  local timer=60;
  curl -s -u ${ilo_user}:${ilo_pass} \
  --location https://${host}/${api_base}/Managers/1/Actions/Manager.Reset/ --insecure --request POST --header 'Content-Type: application/json' --data '{"ResetType": "ForceRestart"}' | jq '.error["@Message.ExtendedInfo"][].MessageId';
  #this might need to change to 90 for ilo 7
  echo "sleeping for ${timer} seconds";
  sleep ${timer};
}

# enable the other SNMP settings
do_enable_snmpv2_settings () {
  echo "function do_enable_snmp_settings";
  curl -s --insecure -u ${ilo_user}:${ilo_pass} --request PATCH --location https://${host}/${api_base}/Managers/1/SnmpService/ --header 'Content-Type: application/json' \
  --data '{
            "SNMPv1Enabled": true,
            "SNMPv1Traps": true,
            "AlertsEnabled": true,
            "Oem": {
                    "Hpe": {
                    "SNMPColdStartTrapBroadcast": true
                    }
                }
        }' | jq '.error["@Message.ExtendedInfo"][].MessageId';
}

# set the community string
do_set_snmpv2_communitystring () {
  echo "function do_set_community_string";
  curl -s --insecure -u ${ilo_user}:${ilo_pass} --request PATCH --location https://${host}/${api_base}/Managers/1/SnmpService/ --header 'Content-Type: application/json' \
  --data "{ \"ReadCommunities\": [\"${commstring}\"] }" | jq '.error["@Message.ExtendedInfo"][].MessageId';
}


##### testing ######

do_enable_snmpv3_settings () {
  echo "enable snmp v3 settings"
  curl -s --insecure -u ${ilo_user}:${ilo_pass} --request PATCH --header 'Content-Type: application/json' --location https://${host}/${api_base}/Managers/1/SnmpService/ \
  --data '{
            "SNMPv3TrapEnabled": true
          }' | jq .
          #jq '.error["@Message.ExtendedInfo"][].MessageId';
}

#add a snmp user to ilo for snmpv3
do_enable_snmpv3_users () {
  echo "enable user for snmpv3 requests"
  curl -s --insecure -u ${ilo_user}:${ilo_pass} --header 'Content-Type: application/json' --request POST --location https://${host}/${api_base}/Managers/1/SnmpService/SNMPUsers/ \
  --data "{
    \"SecurityName\": \"${snmpv3_username}\",
    \"AuthProtocol\": \"${snmpv3_protocol}\",
    \"AuthPassphrase\": \"${snmpv3_passphrase}\",
    \"PrivacyProtocol\": \"${snmpv3_encprotocol}\",
    \"PrivacyPassphrase\": \"${snmpv3_encpassphrase}\",
    \"UserEngineID\": null
  }"  | jq .
}

do_set_snmpv3_communtystring () {
  echo "set snmpv3 community string"
  curl -s --insecure -u ${ilo_user}:${ilo_pass} --request PATCH --header 'Content-Type: application/json}' --location https://${host}/${api_base}/Managers/1/SnmpUsers/ \
  --data "{ \"ReadCommunities\": [\"${commstring}\"] }" | jq .
  #jq '.error["@Message.ExtendedInfo"][].MessageId';
}

##### testing #####
############### main #####################

echo;
#get_ilo_version;

echo "$0 $@";
do_getopts "$@";
shift $((OPTIND - 1 ));

if [[ -z $ilo_user || -z $ilo_pass || -z $commstring || -z $host ]]; then
  do_usage;
fi

if [[ $snmp_version == '2c' ]]; then
  do_enable_main_snmp;
  do_reboot_ilo;
  do_enable_snmpv2_settings;
  do_set_snmpv2_communitystring;
elif [[ $snmp_version == '3' ]]; then
  if ! [[ -z ${snmpv3_username} || -z ${snmpv3_protocol} || -z ${snmpv3_passphrase} || -z ${snmpv3_encprotocol} || -z ${snmpv3_encpassphrase} ]]; then
    echo "do snmp v3 discovery";
    do_enable_snmpv3_settings;
    do_enable_snmpv3_users;
  else
    echo "snmpv3 variables not set. aborting.";
    exit 1;
  fi
else
  echo "snmp version string incorrectly set."
  do_usage;

#  do_set_snmpv3_communtystring;

fi

