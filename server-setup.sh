#!/bin/bash
# 新機器初始化設定腳本
set -e

echo "===== 開始初始化設定 ====="

# ── 1. 系統更新
echo "[1/6] 更新系統套件..."
apt update -y && apt upgrade -y

# ── 2. 安裝常用工具
echo "[2/6] 安裝常用工具..."
apt install -y fail2ban curl wget git htop unzip

# ── 3. fail2ban 設定
echo "[3/6] 設定 fail2ban..."
systemctl enable fail2ban --now

cat > /etc/fail2ban/jail.local << 'FAIL2BAN'
[sshd]
enabled = true
maxretry = 3
findtime = 1h
bantime = 24h
FAIL2BAN

systemctl restart fail2ban
echo "    fail2ban 已啟動，SSH 暴力破解防護生效"

# ── 4. 清理 log
echo "[4/6] 清理 log..."
truncate -s 0 /var/log/btmp 2>/dev/null || true
truncate -s 0 /var/log/btmp.1 2>/dev/null || true
journalctl --vacuum-time=7d
apt clean

# ── 5. Docker 清理（如果有安裝）
if command -v docker &> /dev/null; then
    echo "[5/6] 清理 Docker..."
    docker builder prune -af
    docker image prune -af
    docker volume prune -f

    # Docker 每週自動清理 crontab
    (crontab -l 2>/dev/null; echo "0 3 * * 0 docker builder prune -af > /var/log/docker-prune.log 2>&1") | crontab -
    echo "    Docker 清理完成，已設定每週日 03:00 自動清 build cache"
else
    echo "[5/6] Docker 未安裝，跳過"
fi

# ── 6. logrotate 設定（rclone，如果有使用）
echo "[6/6] 設定 logrotate..."
if ls /var/log/rclone*.log &> /dev/null; then
    cat > /etc/logrotate.d/rclone << 'LOGROTATE'
/var/log/rclone-mount.log /var/log/rclone-mount-nas.log {
    daily
    rotate 3
    compress
    missingok
    notifempty
    size 100M
    copytruncate
}
LOGROTATE
    echo "    rclone logrotate 已設定"
else
    echo "    未偵測到 rclone log，跳過"
fi

# ── 完成，顯示磁碟狀態
echo ""
echo "===== 設定完成 ====="
echo ""
df -h | grep -E "^/dev|Filesystem"
echo ""
echo "建議後續手動執行："
echo "  - 修改 SSH Port：nano /etc/ssh/sshd_config"
echo "  - 查看封鎖 IP：fail2ban-client status sshd"
