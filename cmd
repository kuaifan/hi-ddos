#!/bin/bash
ddoshome=/root
flowcheckhome=/root/ddos/interface_check
nodeshome=/root/ddos/nodes
masterhome=/root/ddos/master

#例子：git_url=github.com/OldTT/hitoprotect.git
git_url=

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
docker rm -f ddos
docker run  -itd --name ddos \
--privileged  \
-p 80:80 \
-p 443:443 \
--restart=always \
-v /root/ddos:/root/ddos \
-v /var/run/docker.sock:/var/run/docker.sock  \
-v /usr/bin/docker:/usr/bin/docker  \
-v $nodeshome/nginx/:/eth/nginx/  \
fabiocicerchia/nginx-lua:1.21.1-ubuntu20.04
docker cp  $nodeshome/nginx.conf ddos:/etc/nginx/nginx.conf
docker exec -it -u 0 ddos bash -c 'rm -rf /root/ddos/nodes/ngx_waf/assets/ngx_http_waf_module.so && cd  /root/ddos/nodes/ngx_waf/assets/ && sh /root/ddos/nodes/ngx_waf/assets/download.sh 1.21.1 lts && cat /etc/nginx/nginx.conf && nginx -s reload'
echo "*/1 * * * * /root/ddos/nodes/check.sh >> /root/ddos/nodes/logs/cron" >> /var/spool/cron/root 
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

#处理nodes提交的ip，默认每5分钟执行一次
echo "*/5 * * * * /bin/sh /$masterhome/run.sh" >>/var/spool/cron/root
#自动检查到期解封，默认每分钟执行一次
echo "*/1 * * * * /bin/sh $masterhome/auto_release.sh" >>/var/spool/cron/root
crontab -l

#首次运行或者本地数据缺失情况下， 需要从接口导入已封禁的数据
/bin/bash $masterhome/import_exist_blocked_ip_from_api.sh
chmod 777 $ddoshome/ddos/webhook
nohup $ddoshome/ddos/webhook/webhook -port $webhookport -hotreload -hooks $masterhome/hooks/hooks.json -verbose &
echo "webhook程序已启动"
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

echo "*/1 * * * * $flowcheckhome/check_interface.sh" >>/var/spool/cron/root
systemctl restart crond.service
crontab -l
}   

show_menu() {
#    web_clone_install
    echo -e "—————————— 安装向导 ——————————"
    echo -e "${Green}A.${Font}  安装并启动cdn节点程序"
    echo -e "${Green}B.${Font}  安装并启动 主控 程序"
    echo -e "${Green}C.${Font}  安装并启动网络检测程序"
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
        *)
            echo -e "${RedBG}请输入正确的操作代码${Font}"
            ;;
        esac
    done
}

show_menu

