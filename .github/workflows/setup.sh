#!/bin/sh

set -e
set -x

sudo apt install gnupg pandoc fakeroot
sudo apt install texlive-base texlive-latex-base texlive-latex-extra texlive-fonts-recommended texlive-latex-recommended
sudo apt install lmodern libxml2-utils traceroute ipset

#
# Set up to ensure tests run:
#  - Ensure unprivileged user namespaces enabled 
#  - Install required kernel modules
#  - Get latest version of iprange from firehol project
sudo sysctl kernel.unprivileged_userns_clone=1
sudo modprobe iptable_mangle
sudo modprobe ip6table_mangle
sudo modprobe iptable_raw
sudo modprobe ip6table_raw
sudo modprobe iptable_nat
sudo modprobe ip6table_nat
sudo modprobe iptable_filter
sudo modprobe ip6table_filter

orig=`pwd`
mkdir iprange
cd iprange
curl -s -o json https://api.github.com/repos/firehol/iprange/releases/latest
dl=$(sed -ne '/"browser_download_url":.*.tar.gz"/{s/.*"browser_download_url": *//;s/{.*//;s/",*//g;p;q}' json)

if [ "$dl" = "" ]
then
  echo "Could not find download for latest iprange"
  exit 1
fi

curl -s -L -o iprange.tar.gz "$dl"
if [ $? -ne 0 ]
then
  echo "Could not download $dl"
  exit 1
else
  echo "Building $dl"
fi

mkdir build
tar xfzC iprange.tar.gz build

cd build/iprange*
./configure --disable-man
sudo make install
cd $orig
rm -rf iprange
