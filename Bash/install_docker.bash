#!/usr/bin/env bash

yum remove docker docker-client docker-client-latest \
	docker-common docker-latest docker-latest-logrotate \
	docker-logrotate docker-engine -y;

yum install yum-utils -y;
yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo -y;
yum install --allowerasing docker-ce docker-ce-cli containerd.io;
systemctl start docker;
docker run hello-world;
systemctl enable docker;


#uninstall docker engine
#yum remove docker-ce docker-ce-cli containerd.io -y;
#next line removes all stored data.
#rm -rf /var/lib/docker