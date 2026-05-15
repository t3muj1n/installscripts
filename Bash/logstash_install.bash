#! /usr/bin/env bash

#logstash installer

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
#install logstash
#custom configurations can be placed in /etc/logstash/conf.d

yum install logstash -y;

#install the elk addons.
yum install filebeat auditbeat metricbeat packetbeat heartbeat-elastic -y

# Sample Logstash configuration for creating a simple stream
# Beats -> Logstash -> Elasticsearch pipeline.

#input {
#  beats {
#    port => 5044
#  }
#}
#
#output {
#  elasticsearch {
#    hosts => ["http://localhost:9200"]
#    index => "%{[@metadata][beat]}-%{[@metadata][version]}-%{+YYYY.MM.dd}"
#    #user => "elastic"
#    #password => "changeme"
#  }
#}

###################################################################
