#!/bin/bash
ddoshome=$(cd "$(dirname "$0")";pwd)
nodeshome=$(cd "$(dirname "$0")";pwd)/nodes
masterhome=$(cd "$(dirname "$0")";pwd)/master
flowcheckhome=$(cd "$(dirname "$0")";pwd)/interface_check
www_root_path=$(cd "$(dirname "$0")";pwd)/nodes/nginx/html
ssl_dir_path=$(cd "$(dirname "$0")";pwd)/nodes/nginx/cert
conf_dir_path=$(cd "$(dirname "$0")";pwd)/nodes/nginx/conf.d

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
        echo -e "${OK} ${GreenBG} 当前用户是root用户，权限正常... ${Font}"
        sleep 2
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
        #input_gituser
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

check_ip() {
echo $1|grep -E  "^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\:[0-9]{1,5}$" > /dev/null;
    if [ $? -ne 0 ];then
        echo $1|grep -E  "^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\:[0-9]{1,5}$" > /dev/null
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

port_exist_check() {
    if [[ 0 -eq $(lsof -i:"$1" | grep -v docker | grep -i -c "listen") ]]; then
        echo -e "${OK} ${GreenBG} $1 端口未被占用 ${Font}"
        sleep 1
    else
        echo -e "${Error} ${RedBG} 检测到 $1 端口被占用，以下为 $1 端口占用信息 ${Font}"
        lsof -i:"$1"
        echo -e "${OK} ${GreenBG} 5s 后将尝试自动 kill 占用进程 ${Font}"
        sleep 5
        lsof -i:"$1" | awk '{print $2}' | grep -v "PID" | xargs kill -9
        echo -e "${OK} ${GreenBG} kill 完成 ${Font}"
        sleep 1
    fi
}

domain_check() {
    port_exist_check 80
    port_exist_check 443
    while [ -z "$domain" ]; do
        read -rp "请输入你的域名信息(例如:www.abc.com):" domain
    done
    domain_ip=$(ping "${domain}" -c 1 | sed '1{s/[^(]*(//;s/).*//;q}')
    echo -e "${OK} ${GreenBG} 正在获取 公网ip 信息，请耐心等待 ${Font}"
    local_ip=$(curl ip.sb)
    echo -e "域名dns解析IP：${domain_ip}"
    echo -e "本机IP: ${local_ip}"
    sleep 1
    if [[ $(echo "${local_ip}" | tr '.' '+' | bc) -eq $(echo "${domain_ip}" | tr '.' '+' | bc) ]]; then
        echo -e "${OK} ${GreenBG} 域名dns解析IP 与 本机IP 匹配 ${Font}"
        sleep 1
    else
        echo -e "${Error} ${RedBG} 域名dns解析IP 与 本机IP 不匹配 是否继续安装？（Y/n）${Font}"
        read -r dnscontinue_install
        [[ -z ${dnscontinue_install} ]] && dnscontinue_install="Y"
        case $dnscontinue_install in
        [yY][eE][sS] | [yY])
            echo -e "${GreenBG} 继续安装 ${Font}"
            sleep 1
            ;;
        *)
            echo -e "${RedBG} 安装终止 ${Font}"
            exit 2
            ;;
        esac
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
docker run  -itd --name ddos \
--privileged  \
-p 80:80 \
-p 443:443 \
--restart=always \
-v $nodeshome:$nodeshome \
-v /var/run/docker.sock:/var/run/docker.sock  \
-v /usr/bin/docker:/usr/bin/docker  \
-v $nodeshome/nginx/:/etc/nginx/  \
-v $nodeshome/nginx/html:/usr/share/nginx/html \
fabiocicerchia/nginx-lua:1.21.1-ubuntu20.04
sleep 1
docker exec -it -u 0 ddos bash -c 'rm -rf '$nodeshome'/ngx_waf/assets/ngx_http_waf_module.so && cd '$nodeshome'/ngx_waf/assets/ && sh '$nodeshome'/ngx_waf/assets/download.sh 1.21.1 lts' 
cp  $nodeshome/nginx.conf $nodeshome/nginx/nginx.conf
docker exec -it -u 0 ddos bash -c "sed -i '1 i\load_module "$nodeshome/ngx_waf/assets/ngx_http_waf_module.so";'  /etc/nginx/nginx.conf" 
docker exec -it -u 0 ddos bash -c 'nginx -T && nginx -t && nginx -s reload'
    if [[ 0 -eq $? ]]; then
        if [[ "${ID}" == "ubuntu" ]] ||  [[ "${ID}" == "debian" ]];then
            echo "*/5 * * * * /bin/sh $nodeshome/run.sh >> $nodeshome/logs/run.log" >> /var/spool/cron/crontabs/root
            echo "* */1 * * * /bin/sh $nodeshome/clean_iptable.sh >> $nodeshome/logs/clean_iptable.log" >> /var/spool/cron/crontabs/root
            systemctl enable cron &> /dev/null
            sleep 1
            systemctl restart cron  &> /dev/null 
        elif [[ "${ID}" == "centos" ]];then
            echo "*/5 * * * * /bin/sh $nodeshome/run.sh >> $nodeshome/logs/run.log" >> /var/spool/cron/root 
            echo "* */1 * * * /bin/sh $nodeshome/clean_iptable.sh >> $nodeshome/logs/clean_iptable.log" >> /var/spool/cron/root
            systemctl enable crond.service &> /dev/null
            sleep 1
            systemctl restart crond.service
        else
            echo -e "${Error} ${RedBG} 当前系统为 ${ID} ${VERSION_ID} 不在支持的系统列表内，安装中断 ${Font}"
            exit 1
        fi
        echo -e "${OK} ${GreenBG} 节点安装 完成！ ${Font}"
        sleep 1
    else
        rm -rf $nodeshome/nginx
        docker rm -f ddos &>/dev/null
        echo -e "${Error} ${RedBG} 节点安装失败 请重试！${Font}"
        exit 1
    fi
}

nodesuninstall(){
    docker ps | grep ddos
    if [[ 0 -eq $? ]]; then
        docker rm -f ddos
        rm -rf ${ssl_dir_path}/*
        rm -rf "$HOME/.acme.sh/*"
        rm -rf ${conf_dir_path}/*
        rm -rf ${nodeshome}/ngx_waf
        rm -rf ${nodeshome}/logs
        if [[ "${ID}" == "centos" ]]; then
            sed -i '/update.sh/d' /var/spool/cron/root
            sed -i '/run.sh/d' /var/spool/cron/root
            sed -i '/clean_iptable.sh/d' /var/spool/cron/root
        else
            sed -i '/update.sh/d' /var/spool/cron/crontabs/root
            sed -i '/run.sh/d' /var/spool/cron/crontabs/root
            sed -i '/clean_iptable.sh/d' /var/spool/cron/crontabs/root
        fi
        echo -e "${OK} ${GreenBG} 已卸载节点并已清理所有数据${Font}"
    else
        echo -e "${Error} ${RedBG} 未发现有节点部署，请检查后重试${Font}"
        exit 1
    fi  
}

nginxproxy() {
    domain_check
    while [ -z "$nginxproxy" ]; do
        echo -e "${OK} ${GreenBG} 注：支持多域名代理多网站功能 ${Font}"
        read -rp "请输入所需代理服务器的域名或ip(例如:https://www.abc.com,10.10.10.2):" nginxproxy
    done
    [ $? -ne 0 ] && exit
    curl $nginxproxy
    if [[ 0 -eq $? ]]; then
        echo -e "${OK} ${GreenBG} 是否是您想代理的网站？[Y/n] ${Font}"
        read -r nginxproxystatus
        [[ -z ${nginxproxystatus} ]] && nginxproxystatus="Y"
        case $nginxproxystatus in
        [yY][eE][sS] | [yY])
            echo -e "${GreenBG} 继续安装 ${Font}"
            sleep 1
            ;;
        *)
            echo -e "${RedBG} 安装终止 ${Font}"
            exit 2
            ;;
        esac
        echo -e "${OK} ${GreenBG} 是否为网站安装https证书？[Y/n] ${Font}"
        read -r cert_install
        [[ -z ${cert_install} ]] && cert_install="Y"
        case $cert_install in
        [yY][eE][sS] | [yY])
            sleep 1
            ssl_judge_and_install
            ;;
        *)
            setupconf
            ;;
        esac
    else
        echo -e "${Error} ${RedBG} 获取网页失败，无法访问 $nginxproxy ,请检查网络连通性或网站存活性！ 是否继续安装？（Y/n）${Font}"
        read -r continue_install
        [[ -z ${continue_install} ]] && continue_install="Y"
        case $continue_install in
        [yY][eE][sS] | [yY])
            echo -e "${GreenBG} 继续安装 ${Font}"
            sleep 1
            ssl_judge_and_install
            ;;
        *)
            echo -e "${RedBG} 安装终止 ${Font}"
            exit 2
            ;;
        esac
    fi
}

setupconf(){
    mkdir -p $ssl_dir_path
        cat >${conf_dir_path}/$domain.conf <<EOF
        server {
        listen      80;
        server_name  $domain;
        waf on;
        waf_rule_path $nodeshome/ngx_waf/assets/rules/;
        access_log   $nodeshome/logs/cloudcom.log main;
        access_log  $nodeshome/logs/waf.yml     yaml  if=\$waf_blocking_log;
        waf_mode STD;
        waf_cc_deny rate=1000r/m duration=120m;
        waf_cache capacity=50;
        location / {
            proxy_pass $nginxproxy;
            proxy_redirect off;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        }
    }
EOF

    cat >${conf_dir_path}/domainreturn.conf <<EOF
    server {
    listen      80;
#    listen      443;
    server_name  _;
        location / {
            #stub_status on;
            return 444;
            #auth_basic "NginxStatus";
            #auth_basic_user_file confpasswd;
        }
    }
EOF
    docker exec  ddos /bin/bash -c "nginx -s reload"
    curl $domain && curl localhost
    if [[ 0 -eq $? ]]; then
        echo -e "${OK} ${GreenBG} 域名与反向代理 已成功 ${Font}"
    else
        echo -e "${Error} ${RedBG} 域名与反向代理 失败！${Font}"
        rm -rf ${conf_dir_path}/$domain.conf
        exit 1
    fi
}

ssl_judge_and_install() {
    if [[ -f "$ssl_dir_path/$domain.key" || -f "$ssl_dir_path/$domain.crt" ]]; then
        echo "$ssl_dir_path 目录下证书文件已存在"
        echo -e "${OK} ${GreenBG} 是否删除 [Y/n]? ${Font}"
        read -r ssl_delete  
        [[ -z ${ssl_delete} ]] && ssl_delete="Y"
        case $ssl_delete in
        [yY][eE][sS] | [yY])
            rm -rf ${ssl_dir_path}/$domain*
            rm -rf "$HOME/.acme.sh/${domain}_ecc"
            echo -e "${OK} ${GreenBG} 已删除 ${Font}"
            ;;
        *) 
        "$HOME"/.acme.sh/acme.sh --installcert -d "${domain}" --fullchainpath "${ssl_dir_path}/$domain.crt" --keypath "${ssl_dir_path}/$domain.key" --ecc
        judge "证书应用"
        ;;
        esac
    else
        ssl_install
        acme
        acme_cron_update
    fi

    cat >${conf_dir_path}/$domain.conf <<EOF
        server {
        listen      80;
        listen 443 ssl http2;
        server_name  $domain;
        waf on;
        waf_rule_path $nodeshome/ngx_waf/assets/rules/;
        access_log   $nodeshome/logs/cloudcom.log main;
        access_log  $nodeshome/logs/waf.yml     yaml  if=\$waf_blocking_log;
        waf_mode STD;
        waf_cc_deny rate=1000r/m duration=120m;
        waf_cache capacity=50;
        ssl_certificate       ${ssl_dir_path}/$domain.crt;
        ssl_certificate_key   ${ssl_dir_path}/$domain.key;
        ssl_protocols TLSv1.1 TLSv1.2 TLSv1.3;
        ssl_ciphers ECDHE-RSA-AES128-GCM-SHA256:HIGH:!aNULL:!MD5:!RC4:!DHE;
        ssl_prefer_server_ciphers on;
        ssl_session_cache shared:SSL:10m;
        ssl_session_timeout 10m;
        error_page 497  https://\$host\$request_uri;
        location / {
            proxy_pass $nginxproxy;
            proxy_redirect off;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        }
    }
EOF

    cat >${conf_dir_path}/domainreturn.conf <<EOF
    server {
    listen      80;
#    listen      443;
    server_name  _;
        location / {
            #stub_status on;
            return 444;
            #auth_basic "NginxStatus";
            #auth_basic_user_file confpasswd;
        }
    }
EOF
    docker exec  ddos /bin/bash -c "nginx -s reload"
}

ssl_install() {
    if [[ "${ID}" == "centos" ]]; then
        yum install socat nc  -y
    else
        apt install socat netcat -y
    fi
    judge "安装 SSL 证书生成脚本依赖"

    curl https://get.acme.sh | sh
    judge "安装 SSL 证书生成脚本"
}

acme() {
    if "$HOME"/.acme.sh/acme.sh --issue -d "${domain}" -w ${www_root_path} --standalone -k ec-256 --force --test; then
        echo -e "${OK} ${GreenBG} SSL 证书测试签发成功，开始正式签发 ${Font}"
        rm -rf "$HOME/.acme.sh/${domain}_ecc"
        sleep 1
    else
        echo -e "${Error} ${RedBG} SSL 证书测试签发失败,已还原环境,请检查后重试  ${Font}"
        rm -rf "$HOME/.acme.sh/${domain}_ecc"
        exit 1
    fi

    if "$HOME"/.acme.sh/acme.sh --issue -d "${domain}" -w ${www_root_path} --server letsencrypt --standalone -k ec-256 --force; then
        echo -e "${OK} ${GreenBG} SSL 证书生成成功 ${Font}"
        sleep 1
        mkdir -p $ssl_dir_path
        if "$HOME"/.acme.sh/acme.sh --installcert -d "${domain}" --fullchainpath "${ssl_dir_path}/$domain.crt" --keypath "${ssl_dir_path}/$domain.key" --ecc --force; then
            echo -e "${OK} ${GreenBG} 证书配置成功 ${Font}"
            echo -e "${OK} ${GreenBG} 欢迎访问：https://$domain ${Font}"
            sleep 1
        fi
    else
        echo -e "${Error} ${RedBG} SSL 证书生成失败,已还原环境,请检查后重试 ${Font}"
        rm -rf "$HOME/.acme.sh/${domain}_ecc"
    fi
}

acme_cron_update() {
    ssl_update_file="$ssl_dir_path/$domain.update.sh"
    cat >$ssl_update_file <<EOF
#!/usr/bin/env bash
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH

"/root/.acme.sh"/acme.sh --cron --home "/root/.acme.sh" &> /dev/null
"/root/.acme.sh"/acme.sh --installcert -d ${domain} --fullchainpath ${ssl_dir_path}/$domain.crt --keypath ${ssl_dir_path}/$domain.key --ecc
EOF
    chmod +x $ssl_update_file
    if [[ $(crontab -l | grep -c "$domain.update.sh") -lt 1 ]]; then
      if [[ "${ID}" == "centos" ]]; then
          sed -i "/acme.sh/c 0 3 * * 0 bash ${ssl_update_file}" /var/spool/cron/root
      else
          sed -i "/acme.sh/c 0 3 * * 0 bash ${ssl_update_file}" /var/spool/cron/crontabs/root
      fi
    fi
    judge "安装证书自动更新 "
}


uninstall_proxy(){
    while [ -z "$domainun" ]; do
        read -rp "请输入你的域名信息(例如:www.abc.com):" domainun
    done
        ls ${conf_dir_path} | grep $domainun.conf
    if [[ 0 -eq $? ]]; then
        echo -e "${Error} ${RedBG} 确定解除代理并清理所有数据？（Y/n）${Font}"
        read -r uninstallproxy
        [[ -z ${uninstallproxy} ]] && uninstallproxy="Y"
        case $uninstallproxy in
        [yY][eE][sS] | [yY])
            rm -rf ${ssl_dir_path}/$domainun*
            rm -rf "$HOME/.acme.sh/${domainun}_ecc"
            rm -rf ${conf_dir_path}/$domainun.conf
            if [[ "${ID}" == "centos" ]]; then
                sed -i '/'$domainun'/d' /var/spool/cron/root
            else
                sed -i '/'$domainun'/d' /var/spool/cron/crontabs/root
            fi
        docker exec  ddos /bin/bash -c "nginx -s reload"
        echo -e "${OK} ${GreenBG} 已解除代理并已清理所有数据${Font}"
            ;;
        *)
            exit 1
            ;;
        esac
    else
        echo -e "${Error} ${RedBG} 未发现该域名代理配置文件，请检查后重试${Font}"
        exit 1
    fi
}

###主控环境安装
masterinstall(){
    echo -e "回车webhook程序运行端口默认为：9000"
    read -rp "请输入webhook程序运行端口：" webhookport
    if [ -z "$webhookport" ]; then
            webhookport=9000
    fi
$INS install sqlite -y
$INS install jq -y
chmod +X $masterhome/run.sh
chmod +X $masterhome/import_exist_blocked_ip_from_api.sh
chmod +X $masterhome/hooks/*.sh
#首次运行或者本地数据缺失情况下， 需要从接口导入已封禁的数据
/bin/bash $masterhome/import_exist_blocked_ip_from_api.sh &> /dev/null
chmod 777 $ddoshome/webhook
nohup $ddoshome/webhook/webhook -port $webhookport -hotreload -hooks $masterhome/hooks/hooks.json -verbose &
ps -ef | grep -v grep |grep $webhookport
    if [[ 0 -eq $? ]]; then
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
            cat >${masterhome}/hooks/hook.json <<EOF
[
  {
    "id": "ipreport",
    "execute-command": "$masterhome/hooks/ipreport.sh",
    "http-methods": ["POST"],
    "include-command-output-in-response":true,
    "include-command-output-in-response-on-error":true,
    "trigger-rule-mismatch-http-response-code": 400,
    "pass-arguments-to-command": [
      {
        "source": "payload",
        "name": "report_ips"
      }
    ]
  },
  {
    "id": "release",
    "execute-command": "$masterhome/hooks/release.sh",
    "http-methods": ["POST"],
    "include-command-output-in-response":true,
    "include-command-output-in-response-on-error":true,
    "trigger-rule-mismatch-http-response-code": 400,
    "pass-arguments-to-command": [
      {
        "source": "payload",
        "name": "ip"
      }
    ]
  },
  {
    "id": "search",
    "execute-command": "$masterhome/hooks/search.sh",
    "http-methods": ["GET"],
    "include-command-output-in-response":true,
    "include-command-output-in-response-on-error":true,
    "trigger-rule-mismatch-http-response-code": 400,
    "pass-arguments-to-command": [
      {
        "source": "url",
        "name": "ac"
      }
    ]
  }
]
EOF
        echo -e "${OK} ${GreenBG} webhook程序启动完成！ ${Font}"
        sleep 1
    else
        $INS remove -y sqlite
        $INS remove -y jq
        echo -e "${Error} ${RedBG} 主控程序安装失败，已还原环境，请重试！${Font}"
        exit 1
    fi
}

masteruninstall(){
    ps -ef |grep -v grep | grep $ddoshome/webhook || grep $masterhome/run.sh /var/spool/cron/root || grep $masterhome/run.sh /var/spool/cron/crontabs/root
    if [[ 0 -eq $? ]]; then
        webhook_port=`ps -ef |grep -v grep | grep $ddoshome/webhook  | awk '{print $2}'`
        kill -9 $webhook_port
        $INS remove -y sqlite
        $INS remove -y jq
        if [[ "${ID}" == "centos" ]]; then
            sed -i '/run.sh/d' /var/spool/cron/root
            sed -i '/clean_iptable.sh/d' /var/spool/cron/root
        else
            sed -i '/run.sh/d' /var/spool/cron/crontabs/root
            sed -i '/auto_release.sh/d' /var/spool/cron/crontabs/root
        fi
        rm -rf $masterhome/db
            echo -e "${OK} ${GreenBG} 已卸载主控程序并已清理所有数据${Font}"
    else
        echo -e "${Error} ${RedBG} 未发现主控程序的安装运行${Font}"
        exit 1
    fi
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
    if [[ 0 -eq $? ]]; then
        if [[ "${ID}" == "ubuntu" ]] ||  [[ "${ID}" == "debian" ]];then
                echo "*/1 * * * * $flowcheckhome/check_interface.sh" >>/var/spool/cron/crontabs/root 
                systemctl enable cron &> /dev/null
                sleep 1
                systemctl restart cron  &> /dev/null 
            elif [[ "${ID}" == "centos" ]];then
                echo "*/1 * * * * $flowcheckhome/check_interface.sh" >>/var/spool/cron/root
                systemctl enable crond.service &> /dev/null
                sleep 1
                systemctl restart crond.service
            else
                echo -e "${Error} ${RedBG} 当前系统为 ${ID} ${VERSION_ID} 不在支持的系统列表内，安装中断 ${Font}"
                exit 1
        fi
        echo -e "${OK} ${GreenBG} 网络检测程序安装 完成！ ${Font}"
        sleep 1
    else
        rm -rf $flowcheckhome/logs
        echo -e "${Error} ${RedBG} 节点安装失败,已还原环境,请重试！${Font}"
        exit 1
    fi
}   

flowcheckuninstall(){
    grep $flowcheckhome/check_interface.sh /var/spool/cron/root || grep $flowcheckhome/check_interface.sh /var/spool/cron/crontabs/root
    if [[ 0 -eq $? ]]; then
        rm -rf $flowcheckhome/logs
        rm -rf $flowcheckhome/interface_example.txt
        if [[ "${ID}" == "centos" ]]; then
            sed -i '/check_interface.sh/d' /var/spool/cron/root
        else
            sed -i '/check_interface.sh/d' /var/spool/cron/crontabs/root
        fi
            echo -e "${OK} ${GreenBG} 已卸载网络检测程序并已清理所有数据${Font}"
    else
        echo -e "${Error} ${RedBG} 未发现网络检测程序，请检查后重试${Font}"
    fi
}

webhook_url(){
    while true; do
      read -rp "请输入主控webhook的ip地址和端口(ip:主控端口号):" webhook_ip
      check_ip $webhook_ip
      [ $? -eq 0 ] && break
    done
    s_webhook=$(cat $nodeshome/init.sh | grep 'WEBHOOK_URL')
    sed -i 's#'$s_webhook'#WEBHOOK_URL="http://'$webhook_ip'/hooks/ipreport"#g' $nodeshome/init.sh
    if [ $? -eq 0 ];then
        echo -e "${OK} ${GreenBG} WEBHOOK地址修改完成！ ${Font}"        
    else
        echo -e "${Error} ${RedBG} $1 失败${Font}"
        exit 1
    fi
}



update_cmd(){
    curl -Ok https://raw.githubusercontent.com/kuaifan/hi-ddos/master/cmd >/dev/null 2>&1
    if [ $? -eq  0 ];then
        echo -e "${OK} ${GreenBG} 更新完成！ ${Font}"
    else
        echo -e "${Error} ${RedBG} 更新失败，请检查网络！ ${Font}"
    fi
}

show_menu() {
#    web_clone_install
    echo -e "—————————— 安装向导 ——————————"
    echo -e "${Green}A.${Font}  安装并启动cdn节点程序"
    echo -e "${Green}B.${Font}  卸载cdn节点程序"
    echo -e "${Green}C.${Font}  开启节点网页代理功能"
    echo -e "${Green}D.${Font}  关闭节点网页代理功能"
    echo -e "${Green}E.${Font}  更新cmd脚本"
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
            nodesuninstall
            ;;
        C)
            is_root
            check_system
            nginxproxy
            ;;
        D)
            is_root
            check_system
            uninstall_proxy
            ;;  
        E)
            update_cmd
            ;;
        *)
            echo -e "${RedBG}请输入正确的操作代码${Font}"
            ;;
        esac
    done
}

show_menu