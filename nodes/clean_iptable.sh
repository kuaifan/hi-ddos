#!/bin/bash

abspath=$(cd "$(dirname "$0")";pwd)
source $abspath/init.sh

if [ -f "$BLOCKED_STORE_FILE" ]; then
    blocked_ips=`cat -n "$BLOCKED_STORE_FILE"`

	for ip in ${blocked_ips[*]}
	do
		res=`iptables -D DOCKER-USER -p tcp -s $ip --dport 80 -j DROP`
	done

	echo /dev/null > $BLOCKED_STORE_FILE
fi
