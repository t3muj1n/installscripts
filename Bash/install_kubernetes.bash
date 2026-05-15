#!/usr/bin/env bash
echo '[kubernetes]
name=Kubernetes
baseurl=https://packages.cloud.google.com/yum/repos/kubernetes-el7-x86_64
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://packages.cloud.google.com/yum/doc/yum-key.gpg https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg' > /etc/yum.repos.d/kubernetes.repo;


if ! setenforce 0; then
	return 1;
fi

if ! sed -i 's/^SELINUX=enforcing$/SELINUX=permissive/' /etc/selinux/config ; then
	return 1;
fi
if ! dnf upgrade -y; then
	return 1;
fi
if ! dnf install -y kubelet kubeadm kubectl --disableexcludes=kubernetes ; then 
	return 1;
fi

if ! systemctl disable firewalld; then
	return 1;
fi
if ! systemctl stop firewalld; then
	return 1;
fi

if ! swapoff -a ; then 
	return 1;
fi
if ! cat /etc/fstab |grep -v swap  >> /etc/fstab.tmp; then
	return 1;
fi
if ! mv /etc/fstab /etc/fstab.bak; then
	return 1;
fi



##open the necessary ports used by Kubernetes.
#firewall-cmd --zone=public --permanent --add-port={6443,2379,2380,10250,10251,10252}/tcp
## Allow docker access from another node, replace the worker-IP-address with yours.
#firewall-cmd --zone=public --permanent --add-rich-rule 'rule family=ipv4 source address=worker-IP-address/32 accept'
##Allow access to the host’s localhost from the docker container.
#firewall-cmd --zone=public --permanent --add-rich-rule 'rule family=ipv4 source address=172.17.0.0/16 accept'
#firewall-cmd --reload

#make sure br netfilter is found and loaded
modprobe br_netfilter
echo 'br_netfilter
overlay
' > /etc/modules-load.d/kubernetess.conf

echo 'net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward =1' > /etc/sysctl.d/kubernetes.conf
echo '1' > /proc/sys/net/bridge/bridge-nf-call-iptables

# fix docker cgroups by adding this file
echo '{
  "exec-opts": ["native.cgroupdriver=systemd"],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m"
  },
  "storage-driver": "overlay2",
  "storage-opts": [
    "overlay2.override_kernel_check=true"
  ]
}
' > /etc/docker/daemon.json
mkdir -p /etc/systemd/system/docker.service.d
systemctl daemon-reload
systemctl restart docker

#install cri-o
export OS=CentOS_8
export VERSION=1.18
curl -L -o /etc/yum.repos.d/devel:kubic:libcontainers:stable:cri-o:$VERSION.repo https://download.opensuse.org/repositories/devel:kubic:libcontainers:stable:cri-o:$VERSION/$OS/devel:kubic:libcontainers:stable:cri-o:$VERSION.repo
curl -L -o /etc/yum.repos.d/devel:kubic:libcontainers:stable.repo https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/$OS/devel:kubic:libcontainers:stable.repo
curl -L -o /etc/yum.repos.d/devel:kubic:libcontainers:stable:cri-o:$VERSION.repo https://download.opensuse.org/repositories/devel:kubic:libcontainers:stable:cri-o:$VERSION/$OS/devel:kubic:libcontainers:stable:cri-o:$VERSION.repo
yum install cri-o -y
#fix bug in install that fails to link the file
ln -s $(which conmon) /usr/libexec/crio/conmon
#restart services 
systemctl enable --now kubelet;
systemctl start kubelet;
systemctl enable cri-o 
systemctl start cri-o

### do this as normal user
echo "do this as a normal user"
echo 'mkdir -p $HOME/.kube'
echo 'cp -i /etc/kubernetes/admin.conf $HOME/.kube/config'
echo 'sudo chown $(id -u):$(id -g) $HOME/.kube/config'


### do this on the master node only
echo
echo 'do this on the master node only. you need to capture a command in this file'
echo 'kubeadm init | tee /home/tem/kubeadm.out ;'

###the  output was saved. a line like tihs should be in the output. 
###do this on the worker nodes
echo 
echo 'do this on the worker nodes to join them. get the commands from the output from the above command'

echo 'kubeadm join 192.168.1.200:6443 --token 3zdx5p.rcesbis354sq113n \'
echo '   --discovery-token-ca-cert-hash sha256:f68cc62ed343c244a4915514773feafc938d3ea371a2f851fb7ce07dff1560c1 '

#i didnt need to do this , but...
#kubectl taint nodes --all node-role.kubernetes.io/master-

#'you can proxy the api out so you can see if its working with a web browser.'
#kubectl proxy --address=tem.attlocal.net --port=80 --disable-filter=true
#kubectl delete namespace kubernetes-dashboard
