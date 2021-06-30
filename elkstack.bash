#! /usr/bin/env bash

#elasticsearch installer

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
yum install elasticsearch -y ; 
rpm -qi elasticsearch ;

#/etc/elasticsearch/jvm.options to modify jvm options
#-Xms1g
#-Xms256m

#start the  service
systemctl enable --now elasticsearch.service ;

####################################################
#create a test index.

curl -X PUT "http://127.0.0.1:9200/mytest_index"

#for some reason the default config needs reformatted into yml proper.
#see below for proper 

#config files
#node1
echo \
'network:
	host: 192.168.1.189
http:
	port: 9200
cluster:
	name: my-elasticsearch
	master: true
	initial_master_nodes: ["192.168.1.189"]
node:
	name: elkstack1
path:
	data: /var/lib/elasticsearch
	logs: /var/log/elasticsearch
discovery:
	seed_hosts: ["192.168.1.189", "192.168.1.190", "192.168.1.191"]
action:
        auto_create_index: .watches,.triggered_watches,.watcher-history-*'

#node2

echo \
'network:
	host: 192.168.1.190
http:
	port: 9200
cluster:
	name: my-elasticsearch
	initial_master_nodes: ["192.168.1.189"] 
node:
	name: elkstack2
path:
	data: /var/lib/elasticsearch
	logs: /var/log/elasticsearch
discovery:
	seed_hosts: ["192.168.1.191", "192.168.1.190", "192.168.1.189"]
action:
        auto_create_index: .watches,.triggered_watches,.watcher-history-*'

#node3

echo \
'network:
	host: 192.168.1.191
http:
	port: 9200
cluster:
	name: my-elasticsearch
	initial_master_nodes: ["192.168.1.189"]
node:
	name: elkstack3
path:
	data: /var/lib/elasticsearch
	logs: /var/log/elasticsearch
discovery:
	seed_hosts: ["192.168.1.191", "192.168.1.189", "192.168.1.190"]
action:
        auto_create_index: .watches,.triggered_watches,.watcher-history-*'

#end of config files

#open firewall ports. note, i ended up disabling the firewall.
#firewall-cmd --add-port=5601/tcp --permanent
#firewall-cmd --reload
systemctl disable firewalld.service

####################################################
####################################################
#install kibana
#note elasticsearch.url needs to be changes to elasticsearch.hosts. see below
yum install kibana -y

echo 'server.port: 5601
server.host: "kibanavm"
server.name: "kibanavm"
elasticsearch.hosts: "http://elkstack1:9200"
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
#install logstash
#custom configurations can be placed in /etc/logstash/conf.d

yum install logstash -y;

#install the elk addons.
yum install filebeat auditbeat metricbeat packetbeat heartbeat-elastic -y
#
