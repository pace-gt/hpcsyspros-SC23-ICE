#!/bin/bash

#grab uid for use in mount path
uidN=$(id -u $1)
#provide direct path to homedir in netapp w/ nfs settings
echo "-fstype=nfs,vers=3,rw,nosuid,noatime,noacl,soft,tcpretrans=5,wsize=32768,rsize=32768 127.0.0.1:/ice/ice_home/${uidN: -2:1}/${uidN: -1}/${1}"
