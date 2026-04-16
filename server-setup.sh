#!/bin/bash
# 新機器初始化設定腳本
set -e

echo "===== 開始初始化設定 ====="

# ── 0. 選擇最快的 apt 鏡像站
pick_fastest_mirror() {
    # 偵測發行版
    local distro repo_path
    if grep -qi ubuntu /etc/os-release 2>/dev/null; then
        distro="ubuntu"
        repo_path="ubuntu"
    elif grep -qi debian /etc/os-release 2>/dev/null; then
        distro="debian"
        repo_path="debian"
    else
        echo "    未知發行版，跳過鏡像最佳化"
        return
    fi
    echo "[0/6] 偵測到 ${distro}，測試鏡像站速度..."

    # 依發行版選鏡像清單
    local mirrors=()
    if [ "$distro" = "ubuntu" ]; then
        mirrors=(
            "archive.ubuntu.com"
            "us.archive.ubuntu.com"
            "de.archive.ubuntu.com"
            "sg.archive.ubuntu.com"
            "mirrors.cloudflare.com"
            "free.nchc.org.tw"
            "ftp.jaist.ac.jp"
        )
        local probe_path="ubuntu/dists/jammy/Release"
    else
        mirrors=(
            "deb.debian.org"
            "ftp.de.debian.org"
            "ftp.us.debian.org"
            "ftp.jp.debian.org"
            "ftp.tw.debian.org"
            "mirrors.tuna.tsinghua.edu.cn"
        )
        local probe_path="debian/dists/bookworm/Release"
    fi

    local best_host=""
    local best_ms=99999

    for host in "${mirrors[@]}"; do
        # 同時取得 HTTP 狀態碼與 TTFB，timeout 5 秒
        local result http_code ms
        result=$(curl -o /dev/null -s -w "%{http_code} %{time_starttransfer}" \
            --connect-timeout 5 --max-time 5 \
            "http://${host}/${probe_path}" 2>/dev/null) || true
        http_code=$(echo "$result" | awk '{print $1}')
        ms=$(echo "$result" | awk '{print $2}')

        # 非 2xx/3xx 回應，或 TTFB 為 0（連線失敗的特徵）→ 視為不可用
        if [[ ! "$http_code" =~ ^[23] ]] || [[ "$ms" == "0.000000" ]] || [[ -z "$ms" ]]; then
            echo "    ${host}: 無法連線 (HTTP ${http_code:-N/A})"
            continue
        fi

        # 轉成毫秒（四捨五入到整數）方便比較，保留一位小數顯示
        local ms_int ms_display
        ms_int=$(awk "BEGIN {printf \"%.0f\", $ms * 1000}")
        ms_display=$(awk "BEGIN {printf \"%.1f\", $ms * 1000}")
        echo "    ${host}: ${ms_display}ms"
        if [ "$ms_int" -lt "$best_ms" ]; then
            best_ms=$ms_int
            best_host=$host
        fi
    done

    # 若所有鏡像都失敗，保留原設定
    if [ -z "$best_host" ]; then
        echo "    警告：所有鏡像測速失敗，保留原始 sources.list"
        return
    fi

    echo "    => 最快鏡像：${best_host} (${best_ms}ms)"

    # 若 sources.list 已是最佳鏡像則不動
    if ! grep -q "http://${best_host}/${repo_path}" /etc/apt/sources.list; then
        cp /etc/apt/sources.list /etc/apt/sources.list.bak
        sed -i "s|http://[a-zA-Z0-9._-]*/${repo_path}|http://${best_host}/${repo_path}|g" /etc/apt/sources.list
        echo "    sources.list 已更新（原始備份於 sources.list.bak）"
    fi
}

pick_fastest_mirror

# ── 1. 系統更新
echo "[1/6] 更新系統套件..."
apt update -y && apt upgrade -y

# ── 2. 安裝常用工具
echo "[2/6] 安裝常用工具..."
apt install -y fail2ban curl wget git htop unzip

# ── 3. fail2ban 設定
echo "[3/6] 設定 fail2ban..."
systemctl enable fail2ban --now || true

cat > /etc/fail2ban/jail.local << 'FAIL2BAN'
[sshd]
enabled = true
maxretry = 3
findtime = 1h
bantime = 24h
FAIL2BAN

systemctl restart fail2ban || true

# 確認服務真的在跑
sleep 2
if systemctl is-active --quiet fail2ban; then
    echo "    fail2ban 已啟動，SSH 暴力破解防護生效"
else
    echo "    ⚠️  警告：fail2ban 啟動失敗，請執行以下指令診斷："
    echo "      journalctl -u fail2ban -n 30 --no-pager"
fi

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
