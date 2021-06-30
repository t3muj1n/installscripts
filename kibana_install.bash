#! /usr/bin/env bash

#kibana installer

#install elastic search prereqs
yum update -y && yum upgrade -y
yum install java-11-openjdk-devel -y

# setup ES repo
echo '[elasticsearch-7.x]
name=Elasticsearch repository for 7.x packages
baseurl=https://artifacts.elastic.co/packages/7.x/yum
gpgcheck=1
gpgkey=https://artifacts.elastic.co/GPG-KEY-elasticsearch
enabled=1
autorefresh=1
type=rpm-md
' >> /etc/yum.repos.d/elasticsearch.repo;

# install ES
rpm --import https://artifacts.elastic.co/GPG-KEY-elasticsearch ;

####################################################
#install kibana
#note elasticsearch.url needs to be changes to elasticsearch.hosts. see below
yum install kibana -y

echo 'server.port: 5601
server.host: "localhost"
server.name: "localhost"
elasticsearch.hosts: "http://localhost:9200"
kibana.index: ".kibana"
pid.file: /var/run/kibana.pid
logging.dest: /var/log/kibana.log
logging.verbose: true
' >> /etc/kibana/kibana.yml;

touch /var/log/kibana.log;
chown kibana:kibana /var/log/kibana.log;
touch /var/run/kibana.pid;
chown kibana:kibana /var/run/kibana.pid;

systemctl enable kibana ;
systemctl start kibana;
systemctl status kibana;

####################################################
#test if kibana is working
curl http://localhost:5601
echo "$?";

####################################################
