#!/usr/bin/env bash
#
# setup-deploy-user.sh
# 在 VPS 上一鍵建立 GitHub Actions 專用 SSH 部署帳號。
#
# 用法(在 VPS 上以具備 sudo 權限的帳號執行):
#   chmod +x setup-deploy-user.sh
#   sudo ./setup-deploy-user.sh -k "ssh-ed25519 AAAA... github-actions-deploy"
#
#   或從檔案讀取公鑰:
#   sudo ./setup-deploy-user.sh -f gh_deploy_key.pub
#
# 選項:
#   -k <公鑰字串>   直接提供 SSH 公鑰內容
#   -f <檔案路徑>   從 .pub 檔案讀取公鑰
#   -u <帳號名稱>   部署帳號名稱        (預設: deploy)
#   -d <目錄路徑>   部署目錄            (預設: /home/<帳號>/app)
#   -D              將帳號加入 docker 群組
#   -s <指令>       建立 sudoers 白名單,只允許 NOPASSWD 執行此指令
#                   例如: -s "/usr/bin/systemctl restart myapp"
#   -h              顯示說明
#
set -euo pipefail

# ---- 預設值 -----------------------------------------------------------------
DEPLOY_USER="deploy"
DEPLOY_DIR=""
PUBKEY=""
PUBKEY_FILE=""
ADD_DOCKER=false
SUDO_CMD=""

# ---- 顏色輸出 ---------------------------------------------------------------
info()  { printf '\033[1;34m[INFO]\033[0m  %s\n' "$*"; }
ok()    { printf '\033[1;32m[ OK ]\033[0m  %s\n' "$*"; }
warn()  { printf '\033[1;33m[WARN]\033[0m  %s\n' "$*"; }
die()   { printf '\033[1;31m[FAIL]\033[0m  %s\n' "$*" >&2; exit 1; }

usage() { sed -n '2,28p' "$0" | sed 's/^# \{0,1\}//'; exit 0; }

# ---- 解析參數 ---------------------------------------------------------------
while getopts "k:f:u:d:Ds:h" opt; do
  case "$opt" in
    k) PUBKEY="$OPTARG" ;;
    f) PUBKEY_FILE="$OPTARG" ;;
    u) DEPLOY_USER="$OPTARG" ;;
    d) DEPLOY_DIR="$OPTARG" ;;
    D) ADD_DOCKER=true ;;
    s) SUDO_CMD="$OPTARG" ;;
    h) usage ;;
    *) die "未知選項,使用 -h 查看說明" ;;
  esac
done

# ---- 前置檢查 ---------------------------------------------------------------
[[ $EUID -eq 0 ]] || die "請使用 sudo 執行此腳本"

if [[ -n "$PUBKEY_FILE" ]]; then
  [[ -f "$PUBKEY_FILE" ]] || die "找不到公鑰檔案: $PUBKEY_FILE"
  PUBKEY="$(cat "$PUBKEY_FILE")"
fi
[[ -n "$PUBKEY" ]] || die "未提供 SSH 公鑰,請用 -k 或 -f 指定"
[[ "$PUBKEY" == ssh-* ]] || die "公鑰格式不正確(應以 ssh- 開頭)"

[[ -n "$DEPLOY_DIR" ]] || DEPLOY_DIR="/home/${DEPLOY_USER}/app"
SSH_DIR="/home/${DEPLOY_USER}/.ssh"
AUTH_KEYS="${SSH_DIR}/authorized_keys"

info "部署帳號 : ${DEPLOY_USER}"
info "部署目錄 : ${DEPLOY_DIR}"
info "docker群組: $($ADD_DOCKER && echo 加入 || echo 略過)"
info "sudo白名單: ${SUDO_CMD:-略過}"
echo

# ---- 1. 建立帳號 ------------------------------------------------------------
if id "$DEPLOY_USER" &>/dev/null; then
  warn "帳號 ${DEPLOY_USER} 已存在,略過建立"
else
  adduser --disabled-password --gecos "" "$DEPLOY_USER"
  ok "已建立帳號 ${DEPLOY_USER}(停用密碼登入)"
fi

# ---- 2. docker 群組(選用) --------------------------------------------------
if $ADD_DOCKER; then
  if getent group docker &>/dev/null; then
    usermod -aG docker "$DEPLOY_USER"
    ok "已將 ${DEPLOY_USER} 加入 docker 群組"
  else
    warn "系統無 docker 群組,略過(尚未安裝 Docker?)"
  fi
fi

# ---- 3. 安裝 SSH 公鑰 -------------------------------------------------------
mkdir -p "$SSH_DIR"
touch "$AUTH_KEYS"
if grep -qF "$PUBKEY" "$AUTH_KEYS"; then
  warn "公鑰已存在於 authorized_keys,略過"
else
  printf '%s\n' "$PUBKEY" >> "$AUTH_KEYS"
  ok "已寫入 SSH 公鑰"
fi
chown -R "${DEPLOY_USER}:${DEPLOY_USER}" "$SSH_DIR"
chmod 700 "$SSH_DIR"
chmod 600 "$AUTH_KEYS"
ok "已修正 .ssh 權限(700 / 600)"

# ---- 4. 建立部署目錄 --------------------------------------------------------
mkdir -p "$DEPLOY_DIR"
chown -R "${DEPLOY_USER}:${DEPLOY_USER}" "$DEPLOY_DIR"
ok "已建立部署目錄 ${DEPLOY_DIR}"

# ---- 5. sudoers 白名單(選用) ----------------------------------------------
if [[ -n "$SUDO_CMD" ]]; then
  SUDOERS_FILE="/etc/sudoers.d/${DEPLOY_USER}"
  echo "${DEPLOY_USER} ALL=(ALL) NOPASSWD: ${SUDO_CMD}" > "$SUDOERS_FILE"
  chmod 440 "$SUDOERS_FILE"
  if visudo -cf "$SUDOERS_FILE" &>/dev/null; then
    ok "已建立 sudoers 白名單: ${SUDOERS_FILE}"
  else
    rm -f "$SUDOERS_FILE"
    die "sudoers 語法檢查失敗,已移除該檔"
  fi
fi

# ---- 完成 -------------------------------------------------------------------
echo
ok "設定完成!"
echo
info "下一步:"
echo "  1. 本機測試連線:  ssh -i <私鑰> ${DEPLOY_USER}@<VPS_IP>"
echo "  2. 到 GitHub Repo → Settings → Secrets and variables → Actions 新增:"
echo "       SSH_PRIVATE_KEY = 私鑰完整內容"
echo "       SSH_HOST        = VPS 的 IP 或網域"
echo "       SSH_USER        = ${DEPLOY_USER}"
echo "  3. 推一次 commit 觸發 workflow 驗證"
