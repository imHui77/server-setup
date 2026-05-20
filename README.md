# server-setup

Linux 雲端機器的一鍵設定腳本集，適用於 Ubuntu / Debian 系統。

## 腳本清單

| 腳本 | 用途 |
|------|------|
| `server-setup.sh` | 新機器一鍵初始化（套件更新、安全強化、Docker 清理排程） |
| `setup-deploy-user.sh` | 建立 GitHub Actions 專用 SSH 部署帳號 |

---

# server-setup.sh — 機器初始化

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

---

# setup-deploy-user.sh — GitHub Actions 部署帳號

在 VPS 上一鍵建立一個權限受限的 SSH 部署帳號，供 GitHub Actions 連線執行部署（pull、重啟服務等）。

## 功能

| 步驟 | 內容 |
|------|------|
| 1 | 建立專用帳號（停用密碼登入，只用金鑰） |
| 2 | （選用）將帳號加入 `docker` 群組 |
| 3 | 安裝 SSH 公鑰並修正 `.ssh` 權限（700 / 600） |
| 4 | 建立部署目錄並設定擁有者 |
| 5 | （選用）建立 sudoers 白名單，只允許 NOPASSWD 執行指定指令 |

特性：**冪等**（可重複執行，已存在的項目自動略過）、**參數化**、執行 `visudo -cf` 檢查 sudoers 語法、彩色輸出。

## 選項

| 選項 | 說明 |
|------|------|
| `-k <公鑰字串>` | 直接提供 SSH 公鑰內容 |
| `-f <檔案路徑>` | 從 `.pub` 檔案讀取公鑰 |
| `-u <帳號名稱>` | 部署帳號名稱（預設：`deploy`） |
| `-d <目錄路徑>` | 部署目錄（預設：`/home/<帳號>/app`） |
| `-D` | 將帳號加入 `docker` 群組 |
| `-s <指令>` | 建立 sudoers 白名單，只允許 NOPASSWD 執行此指令 |
| `-h` | 顯示說明 |

## 使用方式

### 步驟一：本機產生專用金鑰

不要重用既有金鑰，為此用途單獨產生一組：

```bash
ssh-keygen -t ed25519 -C "github-actions-deploy" -f ~/.ssh/gh_deploy_key -N ""
```

### 步驟二：上傳腳本與公鑰，在 VPS 執行

```bash
scp setup-deploy-user.sh ~/.ssh/gh_deploy_key.pub user@<VPS_IP>:~/
ssh user@<VPS_IP>

# 在 VPS 上
sudo ./setup-deploy-user.sh -f gh_deploy_key.pub -D
```

更多範例：

```bash
# 最簡:直接給公鑰字串
sudo ./setup-deploy-user.sh -k "ssh-ed25519 AAAA... github-actions-deploy"

# 完整:自訂帳號 + 目錄 + sudo 白名單
sudo ./setup-deploy-user.sh \
  -f gh_deploy_key.pub \
  -u github-deploy \
  -d /srv/myapp \
  -D \
  -s "/usr/bin/systemctl restart myapp"
```

### 步驟三：設定 GitHub Repo Secrets

到 **Repo → Settings → Secrets and variables → Actions** 新增：

| Secret | 內容 |
|--------|------|
| `SSH_PRIVATE_KEY` | `gh_deploy_key` 私鑰完整內容 |
| `SSH_HOST` | VPS 的 IP 或網域 |
| `SSH_USER` | 部署帳號名稱（預設 `deploy`） |

### 步驟四：Workflow 範例

```yaml
name: Deploy
on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - name: Deploy via SSH
        uses: appleboy/ssh-action@v1.2.0
        with:
          host: ${{ secrets.SSH_HOST }}
          username: ${{ secrets.SSH_USER }}
          key: ${{ secrets.SSH_PRIVATE_KEY }}
          script: |
            cd /home/deploy/app
            git pull
            sudo systemctl restart myapp
```

## 需求

- 作業系統：Ubuntu / Debian 系列
- 權限：需要 root 或 sudo
- 本機需有 `ssh-keygen`（產生金鑰用）

## 安全建議

- 每個用途獨立一把金鑰，外洩時可單獨撤銷（刪掉 `authorized_keys` 該行即可）
- 部署帳號停用密碼登入，只用金鑰
- sudo 權限白名單化，只開放必要指令
- 設定完成後刪除本機的私鑰備份（已存進 GitHub Secret 即可）
- 建議於 `/etc/ssh/sshd_config` 設定 `PasswordAuthentication no`
