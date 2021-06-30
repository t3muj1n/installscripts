#!/bin/bash
common_tools=(sudo vim ntfs-3g git irssi netcat net-tools arp-scan arping ntp);
html_tools=(w3m curl wget);
sound_utils=(alsa-utils);
x_base=(x11-common xorg)
desktop_env=(xfce4 xfce4-terminal xfce4-goodies arandr gkrellm vim-gtk3);
x_archive_tools=(ark xarchiver);
x_video_tools=(vlc);
x_web_browsers=(chromium firefox-esr);
x_fs_explorer=(gvfs-backends gvfs-bin thunar thunar-volman);

#web_browsers=(firefox-esr);
#i3_desktop_env=(i3 i3status dmenu i3lock xbacklight feh conky);

packages=( "${common_tools[@]}" "${x_base[@]}" "${desktop_env[@]}" \
"${x_web_browsers[@]}" "${html_tools[@]}" "${x_fs_explorer[@]}" \
"${x_archive_tools[@]}" "${x_video_tools[@]}" "${sound_utils[@]}" ); 

############################################################################33
## this function has not been modified to work with this script.

do_getopts () {
  if [[ $# -ge 1 ]] ; then
    while getopts ":s:d:f:z:u:p:n:c:e:t:" opt; do
      case $opt in
        s ) subset="$OPTARG";  ;;
	    d ) datacenter="$OPTARG";  ;; 
	    f ) zipfilename="$OPTARG";  ;; 
	    z ) vmartzone="$OPTARG";  ;; 
	    u ) vdisclogin="$OPTARG";  ;; 
	    p ) vdiscpasswd="$OPTARG";  ;; 
	    n ) vdischostname="$OPTARG"; ;;
	    c ) customer="$OPTARG";  ;;
	    e ) externalintf="$OPTARG";  ;;
	    t ) portnum="$OPTARG";  ;;
	    h ) usage ;;
      esac
    done
  else 
    usage
  fi ;
}
#####################################################################

apt-get update;
apt-get upgrade -y;
apt-get install "${packages[@]}" 

systemctl get-default
systemctl set-default multi-user.target
systemctl get-default

#vim /etc/apt/sources.list
#vim /etc/sudoers

##stuff for sublime text editor
#get -qO - https://download.sublimetext.com/sublimehq-pub.gpg | sudo apt-key add -
#sudo apt-get install apt-transport-https
#echo "deb https://download.sublimetext.com/ apt/stable/" | sudo tee /etc/apt/sources.list.d/sublime-text.list
#sudo apt-get update
#sudo apt-get install sublime-text

