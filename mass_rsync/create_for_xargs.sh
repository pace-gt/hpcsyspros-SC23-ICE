#!/bin/bash

logdir=final_sync_logs
mkdir -p ${logdir}

function pace_copy() {

  acct=$2
  uidN=$3
  affil=$4
  home_loc=$1
  home_str=${home_loc#h}
  home_str=${home_str%ice1}

  if [[ ! ( "${home_loc}" == "hcocice1" || "${home_loc}" == "hpaceice1" ) ]]; then
    echo "BAD HOME LOCATION GIVEN: $home_loc"
    exit 2
  fi

  oldhomedir=/data/home/${home_loc}/$acct/
  homedir=/data/home/ICE/${uidN: -2:1}/${uidN: -1}/$acct

  GID=1111
  if [[ ${affil} =~ "student" ]]; then
    GID=2222
  fi
  if [[ ${affil} =~ "guest" ]]; then
    GID=3333
  fi
  if [[ ${affil} =~ "faculty" ]]; then
    GID=4444
  fi

  mkdir -p ${homedir}
  chmod 700 ${homedir}

  #echo rsync -avHAXESh --no-compress ${oldhomedir} ${homedir}/${home_str}-ice-home-data > ${logdir}/${acct}_${home_str}_sync.log
  # The -S flag is very important here, for dealing with sparse files correctly!
  rsync -avHAXESh --no-compress ${oldhomedir} ${homedir}/${home_str}-old-home >> ${logdir}/${acct}_sync.log

  #Make sure users have access! the '-a' flag in rsync should have taken care of the test, but top-level would be owned by root otherwise
  chown ${uidN}:${GID} ${homedir}/${home_str}-old-home

}

pace_copy $1 $2 $3 $4
