#!/bin/bash

abspath=$(cd "$(dirname "$0")";pwd)
source $abspath/init.sh

YML_FILE=$LOG_PATH"/waf.yml"
SWAP_FILE=$LOG_PATH"/swap1"

if [ ! -f "$YML_FILE" ]; then
	echo "not exist $YML_FILE"
	exit 0
fi

#复制/root/ddos/logs/waf.yml到/root/ddos/logs/swap1
cp $YML_FILE $SWAP_FILE

#清空/root/ddos/logs/waf.yml
: > $YML_FILE

valid_ip () {
    local  ip=$1
    local  stat=1

    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        OIFS=$IFS
        IFS='.'
        ip=($ip)
        IFS=$OIFS
        [[ ${ip[0]} -le 255 && ${ip[1]} -le 255 \
        && ${ip[2]} -le 255 && ${ip[3]} -le 255 ]]
        stat=$?
    fi
    return $stat
}

echo "downloading whilelist"
result=`wget -q -N --connect-timeout=$DOWNLOAD_TIMEOUT -O $WHILELIST_FILE $WHILELIST_DOWNLOAD_URL  2>&1`
if [ $? -eq 0 ]; then
    echo "success, whilelist has updated!"
else
    echo "download fialed, use local file"
fi

echo ""
echo "ip checking..."
echo ""

declare -a swap_ips

#读取白名单
declare -a whilelist_ips
if [ -f "$WHILELIST_LOCAL_FILE" ]; then
    whilelist_ips=`cat -n "$WHILELIST_LOCAL_FILE"`
fi

#读取waf.yml中的ip,去重复
remote_uniq_ips=`cat -n "$SWAP_FILE" | grep "remote_addr"  | awk '{print $4}' | sed 's/"//g' | uniq`
for ip in ${remote_uniq_ips[*]}
do
	if [ -z "$ip" ]; then
		continue
	fi

    if ! valid_ip "$ip" ; then
    	echo "$ip valid fialed, continue"
    	continue
    fi

    #是否在白名单里
	if [[ -n $whilelist_ips  && "${whilelist_ips[@]}"  =~ "$ip" ]] ; then
		echo "$ip has in whilelist, ignored"
    	continue
	fi

	swap_ips+=($ip)
done

if [ ! $swap_ips ]; then
	echo "no ip found, exit"
	exit 0
fi

#echo ""
#echo "swap_ips ${#swap_ips[@]} ips founded"
#echo ${swap_ips[*]}
#echo ""


if [ ! -f $BLOCKED_STORE_FILE ]; then
	touch $BLOCKED_STORE_FILE
fi


#查询已封ip
blocked_ips=$(cat $BLOCKED_STORE_FILE)
exist_ips=($(comm -12 <(printf '%s\n' "${blocked_ips[@]}" | LC_ALL=C sort) <(printf '%s\n' "${swap_ips[@]}" | LC_ALL=C sort)))
new_ips=($(comm -13 <(printf '%s\n' "${exist_ips[@]}" | LC_ALL=C sort) <(printf '%s\n' "${swap_ips[@]}" | LC_ALL=C sort)))

#本地封锁
if [ -n "$new_ips" ];then
	for ip in ${new_ips[*]}
	do
		res=`iptables -I DOCKER-USER -p tcp -s $ip --dport 80 -j DROP`
		echo "iptables -I DOCKER-USER -p tcp -s $ip --dport 80 -j DROP"
		if [ $? -eq 0 ]; then
		    echo $ip >> $BLOCKED_STORE_FILE
		fi
	done
else
	echo "nothing to do , exit"
fi

#echo ""
#echo "blocked_ips:"
#echo ${blocked_ips[*]}
#echo ""
#echo "new_ips:"
#echo ${new_ips[*]}

#echo ""
#echo "exist_ips:"
#echo ${exist_ips[*]}
#echo ""

#提交ip
ips_str=$(IFS=,; echo "${new_ips[*]}")
json_body="{\"report_ips\":\"$ips_str\"}"
ret=`curl -X "POST" "$WEBHOOK_URL" -H "Content-Type: application/json"  -d "$json_body"`
echo $ret


