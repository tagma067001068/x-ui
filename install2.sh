#!/bin/bash

red() {
    echo -e "\033[31m\033[01m$1\033[0m"
}

green() {
    echo -e "\033[32m\033[01m$1\033[0m"
}

yellow() {
    echo -e "\033[33m\033[01m$1\033[0m"
}

RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
PLAIN="\033[0m"

REGEX=("debian" "ubuntu" "centos|red hat|kernel|oracle linux|alma|rocky" "'amazon linux'")
RELEASE=("Debian" "Ubuntu" "CentOS" "CentOS")
PACKAGE_UPDATE=("apt -y update" "apt -y update" "yum -y update" "yum -y update")
PACKAGE_INSTALL=("apt -y install" "apt -y install" "yum -y install" "yum -y install")
PACKAGE_UNINSTALL=("apt -y autoremove" "apt -y autoremove" "yum -y autoremove" "yum -y autoremove")

[[ $EUID -ne 0 ]] && red "请在root用户下运行脚本" && exit 1

CMD=("$(grep -i pretty_name /etc/os-release 2>/dev/null | cut -d \" -f2)" "$(hostnamectl 2>/dev/null | grep -i system | cut -d : -f2)" "$(lsb_release -sd 2>/dev/null)" "$(grep -i description /etc/lsb-release 2>/dev/null | cut -d \" -f2)" "$(grep . /etc/redhat-release 2>/dev/null)" "$(grep . /etc/issue 2>/dev/null | cut -d \\ -f1 | sed '/^[ ]*$/d')")

for i in "${CMD[@]}"; do
    SYS="$i" && [[ -n $SYS ]] && break
done

for ((int = 0; int < ${#REGEX[@]}; int++)); do
    [[ $(echo "$SYS" | tr '[:upper:]' '[:lower:]') =~ ${REGEX[int]} ]] && SYSTEM="${RELEASE[int]}" && [[ -n $SYSTEM ]] && break
done

[[ -z $SYSTEM ]] && red "不支持当前VPS系统，请使用主流的操作系统" && exit 1

arch=$(arch)
os_version=$(grep -i version_id /etc/os-release | cut -d \" -f2 | cut -d . -f1)

if [[ $arch == "x86_64" || $arch == "x64" || $arch == "amd64" ]]; then
    arch="amd64"
    elif [[ $arch == "aarch64" || $arch == "arm64" ]]; then
    arch="arm64"
    elif [[ $arch == "s390x" ]]; then
    arch="s390x"
else
    echo -e "不支持的CPU架构！脚本将自动退出！"
    rm -f install.sh
    exit 1
fi

if [[ $(getconf WORD_BIT) != '32' ]] && [[ $(getconf LONG_BIT) != '64' ]]; then
    echo "目前x-ui面板不支持 32 位系统(x86)，请使用 64 位系统(x86_64)，如果检测有误，请联系作者"
    rm -f install.sh
    exit -1
fi

[[ $SYSTEM == "CentOS" ]] && [[ ${os_version} -lt 8 ]] && echo -e "请使用 CentOS 8 或更高版本的系统！" && exit 1
[[ $SYSTEM == "Ubuntu" ]] && [[ ${os_version} -lt 20 ]] && echo -e "请使用 Ubuntu 20 或更高版本的系统！" && exit 1
[[ $SYSTEM == "Debian" ]] && [[ ${os_version} -lt 10 ]] && echo -e "请使用 Debian 10 或更高版本的系统！" && exit 1

check_centos8(){
    if [[ -n $(cat /etc/os-release | grep "CentOS Linux 8") ]]; then
        yellow "检测到当前VPS系统为CentOS 8，是否升级为CentOS Stream 8以确保软件包正常安装？"
        read -rp "请输入选项 [y/n]：" comfirm
        if [[ $comfirm == "y" ]]; then
            yellow "正在为你升级到CentOS Stream 8，大概需要10-30分钟的时间"
            sleep 1
            sed -i -e "s|releasever|releasever-stream|g" /etc/yum.repos.d/CentOS-*
            yum clean all && yum makecache
            dnf swap centos-linux-repos centos-stream-repos distro-sync -y
        else
            red "已取消升级过程，脚本即将退出！"
            exit 1
        fi
    fi
}

check_status(){
    yellow "正在检查VPS系统配置环境，请稍等..."
    WgcfIPv4Status=$(curl -s4m8 https://www.cloudflare.com/cdn-cgi/trace -k | grep warp | cut -d= -f2)
    WgcfIPv6Status=$(curl -s6m8 https://www.cloudflare.com/cdn-cgi/trace -k | grep warp | cut -d= -f2)
    if [[ $WgcfIPv4Status =~ "on"|"plus" ]] || [[ $WgcfIPv6Status =~ "on"|"plus" ]]; then
        wg-quick down wgcf >/dev/null 2>&1
        v6=`curl -s6m8 https://ip.gs -k`
        v4=`curl -s4m8 https://ip.gs -k`
        wg-quick up wgcf >/dev/null 2>&1
    else
        v6=`curl -s6m8 https://ip.gs -k`
        v4=`curl -s4m8 https://ip.gs -k`
        if [[ -z $v4 && -n $v6 ]]; then
            yellow "检测到为纯IPv6 VPS，已自动添加DNS64解析服务器"
            echo -e "nameserver 2a01:4f8:c2c:123f::1" > /etc/resolv.conf
        fi
    fi
}

config_panel() {
    yellow "出于安全考虑，安装/更新完成后需要强制修改端口与账户密码"
    read -rp "确认是否继续 [Y/N]: " yn
    if [[ $yn =~ "Y"|"y" ]]; then
        read -rp "请设置您的账户名 [默认随机用户名]：" config_account
        [[ -z $config_account ]] && config_account=$(date +%s%N | md5sum | cut -c 1-8)
        read -rp "请设置您的账户密码 [默认随机密码]：" config_password
        [[ -z $config_password ]] && config_password=$(date +%s%N | md5sum | cut -c 1-8)
        read -rp "请设置面板访问端口 [默认随机端口]：" config_port
        [[ -z $config_port ]] && config_port=$(echo $RANDOM) && yellow "未设置端口，将使用随机端口号：$config_port"
        /usr/local/x-ui/x-ui setting -username ${config_account} -password ${config_password}
        /usr/local/x-ui/x-ui setting -port ${config_port}
    else
        red "已取消配置端口与账户密码，将使用默认的配置！"
        config_account="admin"
        config_password="admin"
        config_port=54321
    fi
}

install_base(){
    if [[ ! $SYSTEM == "CentOS" ]]; then
        ${PACKAGE_UPDATE[int]}
    fi
    
    if [[ -z $(type -P curl) ]]; then
        yellow "检测curl未安装，正在安装中..."
        ${PACKAGE_INSTALL[int]} curl
    fi

    if [[ -z $(type -P tar) ]]; then
        yellow "检测tar未安装，正在安装中..."
        ${PACKAGE_INSTALL[int]} tar
    fi

    check_status
}

show_login_info(){
    if [[ -n $v4 && -z $v6 ]]; then
        echo -e "x-ui面板的IPv4登录地址为：${GREEN}http://$v4:$config_port ${PLAIN}"
        elif [[ -n $v6 && -z $v4 ]]; then
        echo -e "x-ui面板的IPv6登录地址为：${GREEN}http://[$v6]:$config_port ${PLAIN}"
        elif [[ -n $v4 && -n $v6 ]]; then
        echo -e "x-ui面板的IPv4登录地址为：${GREEN}http://$v4:$config_port ${PLAIN}"
        echo -e "x-ui面板的IPv6登录地址为：${GREEN}http://[$v6]:$config_port ${PLAIN}"
    fi
    echo -e "x-ui面板登录用户名：${GREEN}$config_account ${PLAIN}"
    echo -e "x-ui面板登录密码：${GREEN}$config_password ${PLAIN}"
}

install_x-ui() {
    install_base
    systemctl stop x-ui
    if [ $# == 0 ]; then
        last_version=$(curl -Ls "https://api.github.com/repos/Misaka-blog/x-ui/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
        if [[ ! -n "$last_version" ]]; then
            red "检测 x-ui 版本失败，可能是超出 Github API 限制，请稍后再试，或手动指定 x-ui 版本安装"
            rm -f install.sh
            exit 1
        fi
        yellow "检测到 x-ui 最新版本：${last_version}，开始安装"
        wget -N --no-check-certificate -O /usr/local/x-ui-linux-${arch}.tar.gz https://github.com/Misaka-blog/x-ui/releases/download/${last_version}/x-ui-linux-${arch}.tar.gz
        if [[ $? -ne 0 ]]; then
            red "下载 x-ui 失败，请确保你的服务器能够连接并下载 Github 的文件"
            rm -f install.sh
            exit 1
        fi
    else
        last_version=$1
        url="https://github.com/Misaka-blog/x-ui/releases/download/${last_version}/x-ui-linux-${arch}.tar.gz"
        yellow "开始安装 x-ui v$1"
        wget -N --no-check-certificate -O /usr/local/x-ui-linux-${arch}.tar.gz ${url}
        if [[ $? -ne 0 ]]; then
            red "下载 x-ui v$1 失败，请确保此版本存在"
            rm -f install.sh
            exit 1
        fi
    fi
    if [[ -e /usr/local/x-ui/ ]]; then
        rm -rf /usr/local/x-ui/
    fi
    cd /usr/local/
    tar zxvf x-ui-linux-${arch}.tar.gz
    rm x-ui-linux-${arch}.tar.gz -f
    cd x-ui
    chmod +x x-ui bin/xray-linux-${arch}
    cp -f x-ui.service /etc/systemd/system/
    wget --no-check-certificate -O /usr/bin/x-ui https://raw.githubusercontents.com/Misaka-blog/x-ui/main/x-ui.sh
    chmod +x /usr/local/x-ui/x-ui.sh
    chmod +x /usr/bin/x-ui
    config_panel
    systemctl daemon-reload
    systemctl enable x-ui
    systemctl start x-ui
    cd /root
    rm -f install.sh
    green "x-ui v${last_version} 安装完成，面板已启动"
    echo -e ""
    show_login_info
    echo -e ""
    echo -e "x-ui 管理脚本使用方法: "
    echo -e "----------------------------------------------"
    echo -e "x-ui              - 显示管理菜单 (功能更多)"
    echo -e "x-ui start        - 启动 x-ui 面板"
    echo -e "x-ui stop         - 停止 x-ui 面板"
    echo -e "x-ui restart      - 重启 x-ui 面板"
    echo -e "x-ui status       - 查看 x-ui 状态"
    echo -e "x-ui enable       - 设置 x-ui 开机自启"
    echo -e "x-ui disable      - 取消 x-ui 开机自启"
    echo -e "x-ui log          - 查看 x-ui 日志"
    echo -e "x-ui v2-ui        - 迁移本机器的 v2-ui 账号数据至 x-ui"
    echo -e "x-ui update       - 更新 x-ui 面板"
    echo -e "x-ui install      - 安装 x-ui 面板"
    echo -e "x-ui uninstall    - 卸载 x-ui 面板"
    echo -e "----------------------------------------------"
    echo -e ""
}

check_centos8
install_x-ui $1