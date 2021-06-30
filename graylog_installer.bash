#!/usr/bin/env bash

#graylog installer

yum update -y ;
yum upgrade -y ;
yum install epel-release -y;
yum install pwgen -y;
yum install java-11-openjdk-devel -y


#add the repo for mongodb
echo '[mongodb-org-4.2]
name=MongoDB Repository
baseurl=https://repo.mongodb.org/yum/redhat/$releasever/mongodb-org/4.2/x86_64/
gpgcheck=1
enabled=1
gpgkey=https://www.mongodb.org/static/pgp/server-4.2.asc
' > /etc/yum.repos.d/mongodb-org.repo;

yum install mongodb-org -y;

systemctl daemon-reload;
systemctl enable mongod.service;
systemctl start mongod.service;
systemctl --type=service --state=active | grep mongod;

#disable firewalld so it doesnt cause us problems.
systemctl disable firewalld;
systemctl stop firewalld;

#install greylog packages
rpm -Uvh https://packages.graylog2.org/repo/packages/graylog-4.0-repository_latest.rpm;
yum update -y;
yum install graylog-server graylog-enterprise-plugins graylog-integrations-plugins graylog-enterprise-integrations-plugins -y

################################################################################
#Graylog does NOT start automatically!

#Please run the following commands if you want to start Graylog automatically on system boot:

#    sudo systemctl enable graylog-server.service
#
#    sudo systemctl start graylog-server.service

################################################################################
echo -n "Enter Password: " && head -1 </dev/stdin | tr -d '\n' | sha256sum | cut -d" " -f1

#Enter Password: greylogpassword
#481e3c614b28b8f00bfca6f2942f604573fed335604b6b4ba91663667eeb47b9

#[root@greylogvm ~]# pwgen -N 1 -s 96
#xctGwpnBU461z3CX4TYrgdpVdfk9bgHdbPOmptuSJK14fFrlOF82iHEwyBbQZfbkRqNspnBSbOSV92FxmfDVf3n1jnILkcoo

#selinux stuff
setsebool -P httpd_can_network_connect 1;
semanage port -a -t http_port_t -p tcp 9000;
semanage port -a -t http_port_t -p tcp 9200;
semanage port -a -t mongod_port_t -p tcp 27017;

#enable graylog service to start when system restarts
systemctl daemon-reload;
systemctl enable graylog-server.service;
systemctl start graylog-server.service;
systemctl --type=service --state=active | grep graylog
