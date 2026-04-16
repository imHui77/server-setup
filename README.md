# server-setup

新 Linux 雲端機器的一鍵初始化設定腳本，適用於 Ubuntu / Debian 系統。

## 功能

| 步驟 | 內容 |
|------|------|
| 1 | 系統套件更新 |
| 2 | 安裝常用工具（fail2ban、curl、wget、git、htop、unzip） |
| 3 | 設定 fail2ban，防止 SSH 暴力破解 |
| 4 | 清理 log 檔（btmp、journal，只保留 7 天） |
| 5 | Docker 清理（build cache、未使用 image/volume），並設定每週自動清理 |
| 6 | 設定 rclone logrotate（偵測到 rclone log 才執行） |

## 使用方式

### 方法一：直接從 GitHub 執行（推薦）

```bash
curl -fsSL https://raw.githubusercontent.com/imHui77/server-setup/main/server-setup.sh | bash
```

### 方法二：下載後執行

```bash
wget https://raw.githubusercontent.com/imHui77/server-setup/main/server-setup.sh
chmod +x server-setup.sh
bash server-setup.sh
```

### 方法三：從本機上傳到遠端伺服器

```bash
scp server-setup.sh root@<伺服器IP>:~/
ssh root@<伺服器IP> "bash ~/server-setup.sh"
```

## 需求

- 作業系統：Ubuntu 20.04 / 22.04 / 24.04 或 Debian 系列
- 權限：需要 root 或 sudo
- 套件管理：apt

## 執行後建議手動設定

```bash
# 修改 SSH Port（提高安全性）
nano /etc/ssh/sshd_config
# 找到 #Port 22，改成其他 port（例如 2222）
systemctl restart sshd

# 查看目前被 fail2ban 封鎖的 IP
fail2ban-client status sshd

# 查看磁碟使用狀況
df -h
docker system df
```

## fail2ban 預設規則

| 參數 | 設定值 | 說明 |
|------|--------|------|
| `maxretry` | 3 | 1 小時內失敗 3 次即封鎖 |
| `findtime` | 1h | 觀察時間窗口 |
| `bantime` | 24h | 封鎖時間 |

## Docker 自動清理排程

每週日凌晨 03:00 自動執行 `docker builder prune -af`，防止 build cache 堆積。

紀錄檔位置：`/var/log/docker-prune.log`
