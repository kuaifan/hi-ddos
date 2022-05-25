#!/bin/bash
ddoshome=/root
nodeshome=$(cd "$(dirname "$0")";pwd)/nodes
masterhome=$(cd "$(dirname "$0")";pwd)/master
flowcheckhome=$(cd "$(dirname "$0")";pwd)/interface_check


#例子：git_url=github.com/OldTT/hitoprotect.git
git_url=https://github.com/kuaifan/hi-ddos.git

#fonts color
Green="\033[32m"
Red="\033[31m"
GreenBG="\033[42;37m"
RedBG="\033[41;37m"
Font="\033[0m"

#notification information
OK="${Green}[OK]${Font}"
Error="${Red}[错误]${Font}"

source /etc/os-release

is_root() {
    if [ 0 == $UID ]; then
        echo -e "${OK} ${GreenBG} 当前用户是root用户，进入安装流程 ${Font}"
        sleep 3
    else
        echo -e "${Error} ${RedBG} 当前用户不是root用户，请切换到root用户后重新执行脚本 ${Font}"
        exit 1
    fi
}

judge() {
    if [[ 0 -eq $? ]]; then
        echo -e "${OK} ${GreenBG} $1 完成 ${Font}"
        sleep 1
    else
        echo -e "${Error} ${RedBG} $1 失败${Font}"
        exit 1
    fi
}

check_docker() {
    echo -e "检查Docker......"
    docker -v &> /dev/null
    if [ $? -eq  0 ]; then
        echo -e "${OK} ${GreenBG} 检查到Docker已安装！ ${Font}"
    else
        echo -e "安装docker环境..."
        curl -sSL https://get.daocloud.io/docker | sh
        echo -e "${OK} ${GreenBG} Docker环境安装完成！ ${Font}"
    fi
    systemctl start docker
    judge "Docker 启动"
}

input_gituser() {
    if [ -z "$git_user" ]; then
        while [ -z "$uname" ]; do
            read -rp "请输入git用户名：" uname
        done
        while [ -z "$passw" ]; do
            stty -echo
            read -rp "请输入git密码：" passw; echo
            stty echo
        done
        git_user=$uname
        git_pass=$passw
        if [ -z "$git_user" ]; then
            echo -e "${Error} ${RedBG} git用户名不能为空${Font}"
            exit 1
        fi
        if [ -z "$git_pass" ]; then
            echo -e "${Error} ${RedBG} git密码不能为空${Font}"
            exit 1
        fi
    fi
}

web_clone_install() {
        cd $ddoshome
        input_gituser
            git clone https://${git_user}:${git_pass}@${git_url}
}

check_system() {
    if [[ "${ID}" == "centos" && ${VERSION_ID} -ge 7 ]]; then
        echo -e "${OK} ${GreenBG} 当前系统为 Centos ${VERSION_ID} ${VERSION} ${Font}"
        INS="yum"
    elif [[ "${ID}" == "debian" && ${VERSION_ID} -ge 8 ]]; then
        echo -e "${OK} ${GreenBG} 当前系统为 Debian ${VERSION_ID} ${VERSION} ${Font}"
        INS="apt"
        $INS update
    elif [[ "${ID}" == "ubuntu" && $(echo "${VERSION_ID}" | cut -d '.' -f1) -ge 16 ]]; then
        echo -e "${OK} ${GreenBG} 当前系统为 Ubuntu ${VERSION_ID} ${UBUNTU_CODENAME} ${Font}"
        INS="apt"
        $INS update
    else
        echo -e "${Error} ${RedBG} 当前系统为 ${ID} ${VERSION_ID} 不在支持的系统列表内，安装中断 ${Font}"
        exit 1
    fi
}

###cdn节点环境安装
nodeinstall(){
mkdir -p $nodeshome/cert/
mkdir -p $nodeshome/logs/
docker run --name tmp-nginx-container -d fabiocicerchia/nginx-lua:1.21.1-ubuntu20.04
docker cp tmp-nginx-container:/etc/nginx $nodeshome/
docker rm -f tmp-nginx-container
cd $nodeshome
git clone https://github.com/ADD-SP/ngx_waf.git
###
docker rm -f ddos >/dev/null
docker run  -itd --name ddos \
--privileged  \
-p 80:80 \
-p 443:443 \
--restart=always \
-v $nodeshome:$nodeshome \
-v /var/run/docker.sock:/var/run/docker.sock  \
-v /usr/bin/docker:/usr/bin/docker  \
-v $nodeshome/nginx/:/eth/nginx/  \
fabiocicerchia/nginx-lua:1.21.1-ubuntu20.04
docker cp  $nodeshome/nginx.conf ddos:/etc/nginx/nginx.conf
docker exec -it -u 0 ddos bash -c 'rm -rf '$nodeshome'/nodes/ngx_waf/assets/ngx_http_waf_module.so && cd '$nodeshome'/ngx_waf/assets/ && sh '$nodeshome'/ngx_waf/assets/download.sh 1.21.1 lts && cat /etc/nginx/nginx.conf && nginx -t && nginx -s reload'
if [[ "${ID}" == "ubuntu" ]] ||  [[ "${ID}" == "debian" ]];then
        echo "*/5 * * * * /bin/sh $nodeshome/run.sh >> $nodeshome/logs/run.log" >> /var/spool/cron/crontabs/root
        echo "* */1 * * * /bin/sh $nodeshome/clean_iptable.sh >> $nodeshome/logs/clean_iptable.log" >> /var/spool/cron/crontabs/root  
    elif [[ "${ID}" == "centos" ]];then
        echo "*/5 * * * * /bin/sh $nodeshome/run.sh >> $nodeshome/logs/run.log" >> /var/spool/cron/root 
        echo "* */1 * * * /bin/sh $nodeshome/clean_iptable.sh >> $nodeshome/logs/clean_iptable.log" >> /var/spool/cron/root 
    else
        echo -e "${Error} ${RedBG} 当前系统为 ${ID} ${VERSION_ID} 不在支持的系统列表内，安装中断 ${Font}"
        exit 1
fi
systemctl enable cron 
systemctl restart cron 
}

###主控环境安装
masterinstall(){
    echo -e "回车webhook程序运行端口默认为：9000"
    read -rp "请输入webhook程序运行端口：" webhookport
    if [ -z "$webhookport" ]; then
            webhookport=9000
    fi
$INS install sqlite
$INS install jq
chmod +X $masterhome/run.sh
chmod +X $masterhome/import_exist_blocked_ip_from_api.sh
chmod +X $masterhome/hooks/*.sh

if [[ "${ID}" == "ubuntu" ]] ||  [[ "${ID}" == "debian" ]];then
        #处理nodes提交的ip，默认每5分钟执行一次
        echo "*/5 * * * * /bin/sh $masterhome/run.sh" >>/var/spool/cron/crontabs/root 
        #自动检查到期解封，默认每分钟执行一次
        echo "*/1 * * * * /bin/sh $masterhome/auto_release.sh" >>/var/spool/cron/crontabs/root
    elif [[ "${ID}" == "centos" ]];then
        #处理nodes提交的ip，默认每5分钟执行一次    
        echo "*/5 * * * * /bin/sh $masterhome/run.sh" >>/var/spool/cron/root
        #自动检查到期解封，默认每分钟执行一次
        echo "*/1 * * * * /bin/sh $masterhome/auto_release.sh" >>/var/spool/cron/root
    else
        echo -e "${Error} ${RedBG} 当前系统为 ${ID} ${VERSION_ID} 不在支持的系统列表内，安装中断 ${Font}"
        exit 1
fi

#首次运行或者本地数据缺失情况下， 需要从接口导入已封禁的数据
/bin/bash $masterhome/import_exist_blocked_ip_from_api.sh
chmod 777 $ddoshome/ddos/webhook
nohup $ddoshome/ddos/webhook/webhook -port $webhookport -hotreload -hooks $masterhome/hooks/hooks.json -verbose &
judge "webhook程序启动"
}


#网络检测封禁安装
flowcheckinstall(){
mkdir -p $flowcheckhome
cd $flowcheckhome/
mkdir $flowcheckhome/logs
echo "" >$flowcheckhome/logs/bgp.log
cd $flowcheckhome/
echo 0 > $flowcheckhome/logs/status.log

chmod 777 *
$flowcheckhome/check_interface.sh

if [[ "${ID}" == "ubuntu" ]] ||  [[ "${ID}" == "debian" ]];then
        echo "*/1 * * * * $flowcheckhome/check_interface.sh" >>/var/spool/cron/crontabs/root 
        systemctl restart crond.service
    elif [[ "${ID}" == "centos" ]];then
        echo "*/1 * * * * $flowcheckhome/check_interface.sh" >>/var/spool/cron/root
        systemctl restart crond.service
    else
        echo -e "${Error} ${RedBG} 当前系统为 ${ID} ${VERSION_ID} 不在支持的系统列表内，安装中断 ${Font}"
        exit 1
fi
}   

webhook_url(){
    while true; do
      read -rp "请输入主控webhook的ip地址和端口(ip:主控端口号):" webhook_ip
      check_ip $webhook_ip
      [ $? -eq 0 ] && break
    done
    s_webhook=$(cat /root/hi-ddos/nodes/init.sh | grep 'WEBHOOK_URL')
    sed -i 's#'$s_webhook'#WEBHOOK_URL="http://'$webhook_ip'/hooks/ipreport"#g' $nodeshome/init.sh
    if [ $? -eq 0 ];then
        echo -e "${OK} ${GreenBG} WEBHOOK地址修改完成！ ${Font}"        
    else
        echo -e "${Error} ${RedBG} $1 失败${Font}"
        exit 1
    fi
}

check_ip() {
echo $1|grep -E  "^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\:[0-9]{1,5}$" > /dev/null;
    if [ $? -ne 0 ];then
        echo $1|grep -E  "^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\:[0-9]{1,5}$" > /dev/null;
        if [ $? -ne 0 ];then
            echo -e "${Error} ${RedBG} IP地址和端口必须全部为数字或符号错误!  ${Font}" 
            return 1
        fi
    fi
    ipaddr=$1
    a=`echo $ipaddr|awk -F . '{print $1}'`  #以"."分隔，取出每个列的值 
    b=`echo $ipaddr|awk -F . '{print $2}'`
    c=`echo $ipaddr|awk -F . '{print $3}'`
    d=`echo $ipaddr|awk -F . '{print $4}'|awk -F : '{print $1}'`
    e=`echo $ipaddr|awk -F : '{print $2}'`
    for num in $a $b $c $d
    do
        if [ $num -gt 255 ] || [ $num -lt 0 ]    #每个数值必须在0-255之间 
        then
            echo -e "${Error} ${RedBG} $ipaddr 中，字段"$num"错误 ${Font} ,范围在[1-255]" 
            return 1
        fi
   done

    for mask in $e
    do
        if [ $mask -gt 65535 ] || [ $mask -lt 1 ]    #每个数值必须在1-65535之间 
        then
            echo -e "${Error} ${RedBG} $ipaddr 中，字段"$mask"错误 ${Font} ,范围在[1-65535]" 
            return 1
        fi
   done
   e=`echo $e | sed -E 's/^0{1,5}//'`
   webhook_ip="$a.$b.$c.$d:$e"
   echo $webhook_ip
   return 0

}

update_cmd(){
    curl -Ok https://raw.githubusercontent.com/kuaifan/hi-ddos/master/cmd >/dev/null 2>&1
    if [ $? -eq  0 ]; then
        echo -e "${OK} ${GreenBG} 更新完成！ ${Font}"
    else
        echo -e "${Error} ${RedBG} 更新失败，请检查网络！ ${Font}"
    fi
}

show_menu() {
#    web_clone_install
    echo -e "—————————— 安装向导 ——————————"
    echo -e "${Green}A.${Font}  安装并启动cdn节点程序"
    echo -e "${Green}B.${Font}  安装并启动 主控 程序"
    echo -e "${Green}C.${Font}  安装并启动网络检测程序"
    echo -e "${Green}D.${Font}  更新cmd脚本"
    echo -e "${Green}Z.${Font}  退出脚本 \n"

    read -rp "请输入代码：" menu_num
    for menu_index in `seq 0 $((${#menu_num}-1))`
    do
        case $(echo "${menu_num:$menu_index:1}" | tr "a-z" "A-Z") in
        Z)
            exit 0
            ;;
        A)
            is_root
            check_docker
            webhook_url
            nodeinstall
            ;;
        B)
            is_root
            check_system
            masterinstall
            ;;
        C)
            is_root
            flowcheckinstall
            ;;
        D)
            update_cmd
            ;;
        *)
            echo -e "${RedBG}请输入正确的操作代码${Font}"
            ;;
        esac
    done
}

show_menu
