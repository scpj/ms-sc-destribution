#!/bin/sh

MS_BASE_PATH="/opt/miaospeed"
MS_VERSION="v0.0.1"

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'
export PATH=$PATH:/usr/local/bin

os_arch=""
[ -e /etc/os-release ] && grep -i "PRETTY_NAME" /etc/os-release | grep -qi "alpine" && os_alpine='1'

sudo() {
    myEUID=$(id -ru)
    if [ "$myEUID" -ne 0 ]; then
        if command -v sudo > /dev/null 2>&1; then
            command sudo "$@"
        else
            err "错误: 您的系统未安装 sudo，因此无法进行该项操作。"
            exit 1
        fi
    else
        "$@"
    fi
}

check_systemd() {
    if [ "$os_alpine" != 1 ] && ! command -v systemctl >/dev/null 2>&1; then
        echo "不支持此系统：未找到 systemctl 命令"
        exit 1
    fi
}

err() {
    printf "${red}$*${plain}\n" >&2
}

geo_check() {
    api_list="https://blog.cloudflare.com/cdn-cgi/trace https://dash.cloudflare.com/cdn-cgi/trace https://cf-ns.com/cdn-cgi/trace"
    ua="Mozilla/5.0 (X11; Linux x86_64; rv:60.0) Gecko/20100101 Firefox/81.0"
    set -- $api_list
    for url in $api_list; do
        text="$(curl -A "$ua" -m 10 -s $url)"
        endpoint="$(echo $text | sed -n 's/.*h=\([^ ]*\).*/\1/p')"
        if echo $text | grep -qw 'CN'; then
            isCN=true
            break
        elif echo $url | grep -q $endpoint; then
            break
        fi
    done
}

pre_check() {
    ## os_arch
    if uname -m | grep -q 'x86_64'; then
        os_arch="amd64"
    elif uname -m | grep -q 'aarch64\|armv8b\|armv8l'; then
        os_arch="arm64"
    elif uname -m | grep -q 'arm'; then
        os_arch="arm"
    fi

    ## China_IP
    if [ -z "$CN" ]; then
        geo_check
        if [ ! -z "$isCN" ]; then
            echo "根据geoip api提供的信息，当前IP可能在中国"
            printf "是否选用中国镜像完成安装? [Y/n] (自定义镜像输入 3):"
            read -r input
            case $input in
            [yY][eE][sS] | [yY])
                echo "使用中国镜像"
                CN=true
                ;;

            [nN][oO] | [nN])
                echo "不使用中国镜像"
                ;;

            [3])
                echo "使用自定义镜像"
                printf "请输入自定义镜像 (例如:dn-dao-github-mirror.daocloud.io),留空为不使用: "
                read -r input
                case $input in
                *)
                    CUSTOM_MIRROR=$input
                    ;;
                esac

                ;;
            *)
                echo "使用中国镜像"
                CN=true
                ;;
            esac
        fi
    fi

    if [ -n "$CUSTOM_MIRROR" ]; then
        GITHUB_RAW_URL="github.com/scpj/ms-sc-destribution/raw/master"
        GITHUB_URL=$CUSTOM_MIRROR
    else
        if [ -z "$CN" ]; then
            GITHUB_RAW_URL="raw.githubusercontent.com/scpj/ms-sc-destribution/master"
            GITHUB_URL="github.com"
        else
            GITHUB_RAW_URL="ghp.ci/raw.githubusercontent.com/scpj/ms-sc-destribution/raw/master"
            GITHUB_URL="ghp.ci/https://github.com"
        fi
    fi
}

before_show_menu() {
    echo && printf "${yellow}* 按回车返回主菜单 *${plain}" && read temp
    show_menu
}

install_base() {
    (command -v curl >/dev/null 2>&1 && command -v wget >/dev/null 2>&1 && command -v unzip >/dev/null 2>&1 && command -v getenforce >/dev/null 2>&1) ||
        (install_soft curl wget unzip)
}

install_soft() {
    (command -v yum >/dev/null 2>&1 && sudo yum makecache && sudo yum install $* selinux-policy -y) ||
        (command -v apt >/dev/null 2>&1 && sudo apt update && sudo apt install $* selinux-utils -y) ||
        (command -v pacman >/dev/null 2>&1 && sudo pacman -Syu $* base-devel --noconfirm && install_arch) ||
        (command -v apt-get >/dev/null 2>&1 && sudo apt-get update && sudo apt-get install $* selinux-utils -y) ||
        (command -v apk >/dev/null 2>&1 && sudo apk update && sudo apk add $* -f)
}

selinux() {
    #判断当前的状态
    command -v getenforce >/dev/null 2>&1
    if [ $? -eq 0 ]; then
        getenforce | grep '[Ee]nfor'
        if [ $? -eq 0 ]; then
            echo "SELinux是开启状态，正在关闭！"
            sudo setenforce 0 &>/dev/null
            find_key="SELINUX="
            sudo sed -ri "/^$find_key/c${find_key}disabled" /etc/selinux/config
        fi
    fi
}

update_script() {
    echo "> 更新脚本"

    curl -sL https://${GITHUB_RAW_URL}/script/install.sh -o /tmp/miaospeed.sh
    new_version=$(grep "MS_VERSION" /tmp/miaospeed.sh | head -n 1 | awk -F "=" '{print $2}' | sed 's/\"//g;s/,//g;s/ //g')
    if [ ! -n "$new_version" ]; then
        echo "脚本获取失败，请检查本机能否链接 https://${GITHUB_RAW_URL}/script/install.sh"
        return 1
    fi
    echo "当前最新版本为: ${new_version}"
    mv -f /tmp/miaospeed.sh ./miaospeed.sh && chmod a+x ./miaospeed.sh

    echo "3s后执行新脚本"
    sleep 3s
    clear
    exec ./miaospeed.sh
    exit 0
}

install_miaospeed() {
    install_base
    selinux

    echo "> 安装miaospeed"

    echo "正在获取miaospeed版本号"

    local version=$(curl -m 10 -sL "https://api.github.com/repos/scpj/ms-sc-destribution/releases/latest" | grep "tag_name" | head -n 1 | awk -F ":" '{print $2}' | sed 's/\"//g;s/,//g;s/ //g')
    if [ ! -n "$version" ]; then
        version=$(curl -m 10 -sL "https://pserv.wmxwork.top/api/fd?url=https://api.github.com/repos/scpj/ms-sc-destribution/releases/latest" | awk -F '"' '{for(i=1;i<=NF;i++){if($i=="tag_name"){print $(i+2)}}}')
    fi

    if [ ! -n "$version" ]; then
        err "获取版本号失败，请检查本机能否链接 https://api.github.com/repos/scpj/ms-sc-destribution/releases/latest"
        return 1
    else
        echo "当前最新版本为: ${version}"
    fi

    # miaospeed文件夹
    sudo mkdir -p $MS_BASE_PATH
    sudo chmod -R 700 $MS_BASE_PATH

    echo "正在下载miaospeed"
    MS_URL="https://${GITHUB_URL}/scpj/ms-sc-destribution/releases/download/${version}/miaospeed-sc-linux-${os_arch}"
    wget -t 2 -T 60 -O miaospeed-sc-linux-${os_arch} $MS_URL >/dev/null 2>&1
    if [ $? != 0 ]; then
        err "Release 下载失败，请检查本机能否连接 ${GITHUB_URL}"
        return 1
    fi

    sudo mv miaospeed-sc-linux-${os_arch} $MS_BASE_PATH/miaospeed
    chmod +x $MS_BASE_PATH/miaospeed

    if [ $# -ge 1 ]; then
        modify_miaospeed_config "$@"
    else
        modify_miaospeed_config 0
    fi

    if [ $# = 0 ]; then
        before_show_menu
    fi
}

modify_miaospeed_config() {
    echo "> 修改miaospeed配置"
    if [ $1 = 0 ]; then
        echo "请先记录下后端token"
            printf "请输入后端token: "
            read -r miaospeed_secret
        if [ -z "$miaospeed_secret" ]; then
            err "选项不能为空"
            before_show_menu
            return 1
        fi
    else
        miaospeed_secret=$1
        shift 1
    fi

    args=""

    if [ $2 = 0 ]; then
        echo "请先记录下FRP密钥"
            printf "请输入FRP密钥: "
            read -r miaospeed_frpkey
        if [ -z "$miaospeed_frpkey" ]; then
            err "选项不能为空"
            before_show_menu
            return 1
        fi
    else
        miaospeed_frpkey=$2
        shift 1
        if [ $# -gt 0 ]; then
            args="$*"
        fi

    cat > "/etc/systemd/system/miaospeed.service" <<EOF
[Unit]
Description=miaospeed
ConditionFileIsExecutable=${MS_BASE_PATH}/miaospeed


[Service]
StartLimitInterval=5
StartLimitBurst=10
ExecStart=${MS_BASE_PATH}/miaospeed server --token ${miaospeed_secret} --frpkey ${miaospeed_frpkey} -mtls
WorkingDirectory=/root
Restart=always

RestartSec=120
EnvironmentFile=-/etc/sysconfig/miaospeed

[Install]
WantedBy=multi-user.target
EOF
    printf "miaospeed配置 ${green}修改成功，请稍等重启生效${plain}\n"
    systemctl daemon-reload
    systemctl enable miaospeed
    systemctl restart miaospeed
}

start_miaospeed() {
    echo "> 启动miaospeed"

    sudo systemctl start miaospeed

    if [ $? = 0 ]; then
        printf "${green}miaospeed 启动成功${plain}\n"
    else
        err "启动失败，请稍后查看日志信息"
    fi

    if [ $# = 0 ]; then
        before_show_menu
    fi
}

stop_miaospeed() {
    echo "> 停止miaospeed"

    sudo systemctl stop miaospeed

    if [ $? = 0 ]; then
        printf "${green}miaospeed 停止成功${plain}\n"
    else
        err "停止失败，请稍后查看日志信息"
    fi

    if [ $# = 0 ]; then
        before_show_menu
    fi
}

restart_miaospeed() {
    echo "> 重启miaospeed"

    sudo systemctl restart miaospeed

    if [ $? = 0 ]; then
        printf "${green}miaospeed 停止成功${plain}\n"
    else
        err "停止失败，请稍后查看日志信息"
    fi

    if [ $# = 0 ]; then
        before_show_menu
    fi
}

show_miaospeed_log() {
    echo "> 获取miaospeed日志"

    if [ "$os_alpine" != 1 ]; then
        sudo journalctl -xf -u miaospeed.service
    else
        sudo tail -n 10 /var/log/miaospeed.err
    fi

    if [ $# = 0 ]; then
        before_show_menu
    fi
}

clean_all() {
    if [ -z "$(ls -A ${MS_BASE_PATH})" ]; then
        sudo rm -rf ${MS_BASE_PATH}
    fi
}

uninstall_miaospeed() {
    echo "> 卸载miaospeed"

    sudo systemctl stop miaospeed
    sudo systemctl disable miaospeed
    sudo rm -rf /etc/systemd/system/miaospeed.service
    sudo systemctl daemon-reload

    clean_all

    if [ $# = 0 ]; then
        before_show_menu
    fi
}

show_usage() {
    echo "miaospeed 管理脚本使用方法: "
    echo "--------------------------------------------------------"
    echo "./miaospeed.sh                            - 显示管理菜单"
    echo "./miaospeed.sh install_miaospeed          - 安装miaospeed"
    echo "./miaospeed.sh modify_miaospeed_config    - 修改miaospeed配置"
    echo "./miaospeed.sh start_miaospeed            - 启动miaospeed"
    echo "./miaospeed.sh stop_miaospeed             - 停止miaospeed"
    echo "./miaospeed.sh restart_miaospeed         - 重启miaospeed"
    echo "./miaospeed.sh show_miaospeed_log         - 查看miaospeed日志"
    echo "./miaospeed.sh uninstall_miaospeed        - 卸载miaospeed"
    echo "./miaospeed.sh update_script              - 更新脚本"
    echo "--------------------------------------------------------"
}

show_menu() {
    printf "
    ${green}miaospeed-speedcentre管理脚本${plain} ${red}${MS_VERSION}${plain}
    ${green}1.${plain}  安装miaospeed
    ${green}2.${plain}  修改miaospeed启动密钥
    ${green}3.${plain}  启动miaospeed
    ${green}4.${plain}  停止miaospeed
    ${green}5.${plain}  重启miaospeed
    ${green}6.${plain}  查看miaospeed日志
    ${green}7.${plain}  卸载miaospeed
    ————————————————-
    ${green}8.${plain} 更新脚本
    ————————————————-
    ${green}0.${plain}  退出脚本
    "
    echo && printf "请输入选择 [0-8]: " && read -r num
    case "${num}" in
        0)
            exit 0
            ;;
        1)
            install_miaospeed 0
            ;;
        2)
            modify_miaospeed_config 0
            ;;
        3)
            start_miaospeed
            ;;
        4)
            stop_miaospeed
            ;;
        5)
            restart_miaospeed
            ;;
        6)
            show_miaospeed_log
            ;;
        7)
            uninstall_miaospeed
            ;;
        8)
            update_script
            ;;
        *)
            err "请输入正确的数字 [0-13]"
            ;;
    esac
}

pre_check

if [ $# -gt 0 ]; then
    case $1 in
        "install_miaospeed")
            shift
            if [ $# -ge 3 ]; then
                install_miaospeed "$@"
            else
                install_miaospeed 0
            fi
            ;;
        "modify_miaospeed_config")
            modify_miaospeed_config 0
            ;;
        "start_miaospeed")
            start_miaospeed 0
            ;;
        "stop_miaospeed")
            stop_miaospeed 0
            ;;
        "restart_miaospeed")
            restart_miaospeed 0
            ;;
        "show_miaospeed_log")
            show_miaospeed_log 0
            ;;
        "uninstall_miaospeed")
            uninstall_miaospeed 0
            ;;
        "update_script")
            update_script 0
            ;;
        *) show_usage ;;
    esac
else
    select_version
    show_menu
fi
