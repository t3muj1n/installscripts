#!/usr/bin/env bash

yum install epel-release -y
yum install ansible -y
ansible --version
ssh-keygen

#ssh-copy-id tem@host

#ansible -i hosts.docker --list-hosts all
#ansible -i hosts.docker --list-hosts -m ping all
#ansible -i hosts.docker --list-hosts -m ping all
#ansible -i hosts.docker  -m ping all




