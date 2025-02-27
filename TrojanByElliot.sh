#!/bin/bash
# 字体颜色
blue(){
    echo -e "\033[34m\033[01m$1\033[0m"
}
green(){
    echo -e "\033[32m\033[01m$1\033[0m"
}
red(){
    echo -e "\033[31m\033[01m$1\033[0m"
}
# 设置不同系统的包管理器
if [[ -f /etc/redhat-release ]]; then
    release="centos"
    systemPackage="yum"
    systempwd="/usr/lib/systemd/system/"
elif cat /etc/issue | grep -Eqi "debian"; then
    release="debian"
    systemPackage="apt-get"
    systempwd="/lib/systemd/system/"
elif cat /etc/issue | grep -Eqi "ubuntu"; then
    release="ubuntu"
    systemPackage="apt-get"
    systempwd="/lib/systemd/system/"
elif cat /etc/issue | grep -Eqi "centos|red hat|redhat"; then
    release="centos"
    systemPackage="yum"
    systempwd="/usr/lib/systemd/system/"
elif cat /proc/version | grep -Eqi "debian"; then
    release="debian"
    systemPackage="apt-get"
    systempwd="/lib/systemd/system/"
elif cat /proc/version | grep -Eqi "ubuntu"; then
    release="ubuntu"
    systemPackage="apt-get"
    systempwd="/lib/systemd/system/"
elif cat /proc/version | grep -Eqi "centos|red hat|redhat"; then
    release="centos"
    systemPackage="yum"
    systempwd="/usr/lib/systemd/system/"
fi
# 1 初始安装
function install_trojan(){
systemctl stop nginx
$systemPackage -y install net-tools socat
# 1.1 检测端口情况
Port80=`netstat -tlpn | awk -F '[: ]+' '$1=="tcp"{print $5}' | grep -w 80`
Port443=`netstat -tlpn | awk -F '[: ]+' '$1=="tcp"{print $5}' | grep -w 443`
if [ -n "$Port80" ]; then
    process80=`netstat -tlpn | awk -F '[: ]+' '$5=="80"{print $9}'`
    red "检测到80端口被占用，占用进程为：${process80}，本次安装结束"
    exit 1
fi
if [ -n "$Port443" ]; then
    process443=`netstat -tlpn | awk -F '[: ]+' '$5=="443"{print $9}'`
    red "检测到443端口被占用，占用进程为：${process443}，本次安装结束"
    exit 1
fi
# 1.2 检测SELinux
CHECK=$(grep SELINUX= /etc/selinux/config | grep -v "#")
if [ "$CHECK" == "SELINUX=enforcing" ]; then
    red "检测到SELinux为开启状态，为防止申请证书失败，请先重启VPS后，再执行本脚本"
    read -p "是否现在重启 ?请输入 [Y/n] :" yn
        [ -z "${yn}" ] && yn="y"
        if [[ $yn == [Yy] ]]; then
            sed -i 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/selinux/config
            setenforce 0
            echo -e "VPS 重启中..."
            reboot
        fi
    exit
fi
if [ "$CHECK" == "SELINUX=permissive" ]; then
    red "检测到SELinux为宽容状态，为防止申请证书失败，请先重启VPS后，再执行本脚本"
    read -p "是否现在重启 ?请输入 [Y/n] :" yn
        [ -z "${yn}" ] && yn="y"
        if [[ $yn == [Yy] ]]; then
            sed -i 's/SELINUX=permissive/SELINUX=disabled/g' /etc/selinux/config
            setenforce 0
            echo -e "VPS 重启中..."
            reboot
        fi
    exit
fi
# 1.3 设置nginx的包仓库
if [ "$release" == "centos" ]; then
    if  [ -n "$(grep ' 6\.' /etc/redhat-release)" ] ;then
    red "当前系统不受支持"
    exit
    fi
    if  [ -n "$(grep ' 5\.' /etc/redhat-release)" ] ;then
    red "当前系统不受支持"
    exit
    fi
    systemctl stop firewalld
    systemctl disable firewalld
    rpm -Uvh http://nginx.org/packages/centos/7/noarch/RPMS/nginx-release-centos-7-0.el7.ngx.noarch.rpm
elif [ "$release" == "ubuntu" ]; then
    if  [ -n "$(grep ' 14\.' /etc/os-release)" ] ;then
    red "当前系统不受支持"
    exit
    fi
    if  [ -n "$(grep ' 12\.' /etc/os-release)" ] ;then
    red "当前系统不受支持"
    exit
    fi
    systemctl stop ufw
    systemctl disable ufw
    apt-get update
elif [ "$release" == "debian" ]; then
    apt-get update
fi
# 1.4 安装必备软件
$systemPackage -y install  nginx wget unzip zip curl tar >/dev/null 2>&1
systemctl enable nginx
systemctl stop nginx
# 1.5 绑定域名
blue "请输入绑定到本VPS的域名，如：www.xxx.com"
read your_domain
real_addr=`ping ${your_domain} -c 1 | sed '1{s/[^(]*(//;s/).*//;q}'`
local_addr=`curl ipv4.icanhazip.com`
if [ $real_addr == $local_addr ] ; then
        green "       域名解析正常，开始安装trojan"
        sleep 1s
# 1.6 处理nginx配置
cat > /etc/nginx/nginx.conf <<-EOF
user  root;
worker_processes  1;
error_log  /var/log/nginx/error.log warn;
pid        /var/run/nginx.pid;
events {
    worker_connections  1024;
}
http {
    include       /etc/nginx/mime.types;
    default_type  application/octet-stream;
    log_format  main  '\$remote_addr - \$remote_user [\$time_local] "\$request" '
                      '\$status \$body_bytes_sent "\$http_referer" '
                      '"\$http_user_agent" "\$http_x_forwarded_for"';
    access_log  /var/log/nginx/access.log  main;
    sendfile        on;
    #tcp_nopush     on;
    keepalive_timeout  120;
    client_max_body_size 20m;
    #gzip  on;
    server {
        listen       80;
        server_name  $your_domain;
        root /var/www/html;
        index index.php index.html index.htm;
    }
}
EOF
        # 设置伪装站
        [ ! -d "/var/www/html" ] && mkdir -p /var/www/html
        rm -rf /var/www/html/* && cd /var/www/html/
        wget https://github.com/a16888861/trojan/raw/main/web.zip && unzip web.zip && rm -rf web.zip
        systemctl stop nginx
        sleep 5
        #申请https证书
        mkdir /usr/src/trojan-cert /usr/src/trojan-temp
        curl https://get.acme.sh | sh
    ~/.acme.sh/acme.sh --set-default-ca --server letsencrypt
        ~/.acme.sh/acme.sh  --issue  -d $your_domain  --standalone
        ~/.acme.sh/acme.sh  --installcert  -d  $your_domain   \
        --key-file   /usr/src/trojan-cert/private.key \
        --fullchain-file /usr/src/trojan-cert/fullchain.cer
        if test -s /usr/src/trojan-cert/fullchain.cer; then
        systemctl start nginx
        cd /usr/src
        wget https://api.github.com/repos/trojan-gfw/trojan/releases/latest -O latest-trojan
        latest_version=`grep tag_name latest-trojan| awk -F '[:,"v]' '{print $6}'`
        # 下载trojan并解压
        # wget https://github.com/trojan-gfw/trojan/releases/download/v${latest_version}/trojan-${latest_version}-linux-amd64.tar.xz && tar xf trojan-${latest_version}-linux-amd64.tar.xz
        wget https://github.com/a16888861/trojan/raw/main/trojan-1.16.0-linux-amd64.tar.xz && tar xf trojan-${latest_version}-linux-amd64.tar.xz && rm -rf ./trojan-${latest_version}-linux-amd64.tar.xz ./latest-trojan

        # 处理密码和配置文件
        trojan_passwd=$(cat /dev/urandom | head -1 | md5sum | head -c 8)
        rm -rf /usr/src/trojan/server.conf
        cat > /usr/src/trojan/server.conf <<-EOF
{
    "run_type": "server",
    "local_addr": "0.0.0.0",
    "local_port": 443,
    "remote_addr": "127.0.0.1",
    "remote_port": 80,
    "password": [
       "TOBENO.1",
       "$trojan_passwd"
    ],
    "log_level": 2,
    "ssl": {
        "cert": "/usr/src/trojan-cert/fullchain.cer",
        "key": "/usr/src/trojan-cert/private.key",
        "key_password": "",
        "cipher_tls13":"TLS_AES_128_GCM_SHA256:TLS_CHACHA20_POLY1305_SHA256:TLS_AES_256_GCM_SHA384",
        "prefer_server_cipher": true,
        "alpn": [
            "http/1.1",
            "h2",
            "quic"
        ],
        "reuse_session": true,
        "session_ticket": false,
        "session_timeout": 600,
        "plain_http_response": "",
        "curves": "",
        "dhparam": ""
    },
    "tcp": {
        "no_delay": true,
        "keep_alive": true,
        "fast_open": false,
        "fast_open_qlen": 20
    },
    "udp": {
        "enabled": true,
        "prefer_ipv6": false,
        "forward_addr": "127.0.0.1",
        "forward_port": 53
    },
    "mysql": {
        "enabled": false,
        "server_addr": "127.0.0.1",
        "server_port": 3306,
        "database": "trojan",
        "username": "trojan",
        "password": ""
    }
}
EOF

    #增加启动脚本
cat > ${systempwd}trojan.service <<-EOF
[Unit]  
Description=trojan  
After=network.target  
   
[Service]  
Type=simple  
PIDFile=/usr/src/trojan/trojan/trojan.pid
ExecStart=/usr/src/trojan/trojan -c "/usr/src/trojan/server.conf"  
ExecReload=  
ExecStop=/usr/src/trojan/trojan  
PrivateTmp=true  
   
[Install]  
WantedBy=multi-user.target
EOF

        chmod +x ${systempwd}trojan.service
    # 使修改生效
    systemctl daemon-reload
    systemctl start trojan.service
    # 开机启动
    systemctl enable trojan.service
    blue "==========================Trojan已安装完成================================"
    green "你的配置信息，已有客户端直接新增Trojan配置即可！"
    red "服务器地址：${your_domain}"
    red "服务器端口：443"
    red "密码：${trojan_passwd}"
    green "======================================================================"
    else
    red "==================================="
    red "https证书没有申请成果，自动安装失败"
    green "不要担心，你可以手动修复证书申请"
    green "1. 重启VPS"
    green "2. 重新执行脚本，使用修复证书功能"
    red "==================================="
    fi

else
        red "================================"
        red "域名解析地址与本VPS IP地址不一致"
        red "本次安装失败，请确保域名解析正常"
        red "================================"
fi
}

function repair_cert(){
systemctl stop nginx
Port80=`netstat -tlpn | awk -F '[: ]+' '$1=="tcp"{print $5}' | grep -w 80`
if [ -n "$Port80" ]; then
    process80=`netstat -tlpn | awk -F '[: ]+' '$5=="80"{print $9}'`
    red "==========================================================="
    red "检测到80端口被占用，占用进程为：${process80}，本次安装结束"
    red "==========================================================="
    exit 1
fi
green "======================="
blue "请输入绑定到本VPS的域名，如：www.xxx.com"
blue "务必与之前失败使用的域名一致"
green "======================="
read your_domain
real_addr=`ping ${your_domain} -c 1 | sed '1{s/[^(]*(//;s/).*//;q}'`
local_addr=`curl ipv4.icanhazip.com`
if [ $real_addr == $local_addr ] ; then
    ~/.acme.sh/acme.sh  --issue  -d $your_domain  --standalone
    ~/.acme.sh/acme.sh  --installcert  -d  $your_domain   \
        --key-file   /usr/src/trojan-cert/private.key \
        --fullchain-file /usr/src/trojan-cert/fullchain.cer
    if test -s /usr/src/trojan-cert/fullchain.cer; then
        green "证书申请成功"
        green "请将/usr/src/trojan-cert/下的fullchain.cer下载放到客户端trojan-cli文件夹"
        systemctl restart trojan
        systemctl start nginx
    else
        red "申请证书失败"
    fi
else
    red "================================"
    red "域名解析地址与本VPS IP地址不一致"
    red "本次安装失败，请确保域名解析正常"
    red "================================"
fi
}

function remove_trojan(){
    red "================================"
    red "即将卸载trojan"
    red "同时卸载安装的nginx"
    red "================================"
    systemctl stop trojan
    systemctl disable trojan
    rm -f ${systempwd}trojan.service
    if [ "$release" == "centos" ]; then
        yum remove -y nginx
    else
        apt autoremove -y nginx
    fi
    rm -rf /usr/src/trojan*
    rm -rf /var/www/html/*
    green "=============="
    green "trojan删除完毕"
    green "=============="
}

function bbr_boost_sh(){
    wget -N --no-check-certificate "https://raw.githubusercontent.com/chiakge/Linux-NetSpeed/master/tcp.sh" && chmod +x tcp.sh && ./tcp.sh
}

start_menu(){
    clear
    green " ------------------------------------ "
    green " Trojan 一键安装自动脚本 2025-02-11 更新"
    green " 系统：centos7+/debian9+/ubuntu16.04+"
    green " 网站：www.itblogcn.com （已开启禁止国内访问）"
    green " 此脚本基于atrandys编写的进行二开，集成BBRPLUS加速及MAC客户端"
    green "                 "
    green " ------------------------------------ "
    blue " 声明："
    red " *请不要在任何生产环境使用此脚本"
    red " *请不要有其他程序占用80和443端口"
    red " *若是第二次使用脚本，请先执行卸载trojan"
    green " ------------------------------------ "
    echo
    green " 1. 安装trojan"
    red " 2. 卸载trojan"
    green " 3. 修复证书"
    green " 4. 安装BBR-PLUS加速4合一脚本"
    blue " 0. 退出脚本"
    echo
    read -p "请输入数字:" num
    case "$num" in
    1)
    install_trojan
    ;;
    2)
    remove_trojan 
    ;;
    3)
    repair_cert 
    ;;
    4)
    bbr_boost_sh 
    ;;
    0)
    exit 1
    ;;
    *)
    clear
    red "请输入正确数字"
    sleep 1s
    start_menu
    ;;
    esac
}

start_menu