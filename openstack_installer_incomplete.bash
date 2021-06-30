#!/usr/bin/env bash

#openstack installer --incomplete

yum install centos-release-openstack-ussuri ;
yum install dnf-plugins-core ;
# have problems. download my repo list from desktop
# disable all the cert repos they are causing conflicts.
scp tem@192.168.1.72:/etc/pki/*
scp -r tem@192.168.1.72:/etc/pki/* /etc/pki/*
yum config-manager --set-enabled PowerTools ; 
yum upgrade -y ;
dnf install https://www.rdoproject.org/repos/rdo-release.el8.rpm ;
yum upgrade -y ;
yum install python3-openstackclient ;
yum install openstack-selinux ;
#
systemctl disable NetworkManager
systemctl stop NetworkManager
dnf install network-scripts -y
#hostname configuration
openstackcontrol.localdomain
echo -e "192.168.1.188\topenstackcontrol.localdomain" >> /etc/hosts
#
vim /etc/sysconfig/network-scripts/ifcfg-ens192 #fix which device
#fix up file as per below
	TYPE=Ethernet
	PROXY_METHOD=none
	BROWSER_ONLY=no
	BOOTPROTO=static
	DEFROUTE=yes
	IPV4_FAILURE_FATAL=no
	IPV6INIT=yes
	IPV6_AUTOCONF=yes
	IPV6_DEFROUTE=yes
	IPV6_FAILURE_FATAL=no
	IPV6_ADDR_GEN_MODE=stable-privacy
	NAME=ens192
	UUID=1cb7ca00-fa6c-4f53-9f91-a3021851891a
	DEVICE=ens192
	ONBOOT=yes
	IPADDR=192.168.1.188
	PREFIX=24
	GATEWAY=192.168.1.254
	DNS=8.8.8.8

systemctl start network
systemctl enable network
ip a s ens192

openssl rand -hex 10
#6232225f10728bb05ca2
ens224