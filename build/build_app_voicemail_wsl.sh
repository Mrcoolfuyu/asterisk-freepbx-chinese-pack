#!/bin/bash
# =============================================================================
# 为 FreePBX / Asterisk 22.x 打补丁重编 app_voicemail.so（去除 *97 登录后多播的英文语序菜单）
#
# 环境：Windows + WSL(Ubuntu) 编译，目标机 Debian 12 (glibc 2.36)
# 用法：用 Git Bash 执行；若文件是 CRLF 换行，请先 `dos2unix` 或 `tr -d '\r'`
#
# 产出：app_voicemail.so（已上线验证，sha256 206fc943...8dbd3）
# 实测：8514 零按键 → 只播 1-12 段后等按键，vm-advopts...vm-helpexit 全消失
#
# 关联 skill：asterisk-voicemail-zh-locale / debootstrap-glibc-matched-build
# =============================================================================
set -e

# ---------- 可调参数 ----------
WSL_DISTRO="Ubuntu-24.04"          # 本机 WSL 发行版
CHROOT=/opt/deb12                  # chroot 根目录（Debian 12 = bookworm）
AST_VER=22.8.2                     # ★ 必须与目标机 asterisk -rx 'core show version' 完全一致
DEB_VER=bookworm                   # 目标机 Debian 代号（bookworm/jammy/noble...）
TARGET=root@192.168.50.15          # FreePBX 目标机
SSHKEY=~/.ssh/id_ed25519_256
SRC_URL="https://downloads.asterisk.org/pub/telephony/asterisk/releases/asterisk-${AST_VER}.tar.gz"
# ★ 注意：必须走 releases/ 子目录；顶层目录只放最新版，写死版本号会 404
SO_TARGET="/lib/x86_64-linux-gnu/asterisk/modules/app_voicemail.so"
# ------------------------------

echo "### 1. 造与目标机 glibc 同版的 chroot（WSL 免密 root）"
wsl.exe -d "$WSL_DISTRO" -u root -- bash -lc "
  export PATH=/usr/sbin:\$PATH
  [ -d $CHROOT/etc ] || { apt-get update -qq && apt-get install -y -qq debootstrap; \
    debootstrap --variant=minbase --arch=amd64 $DEB_VER $CHROOT https://deb.debian.org/debian; }
  ldd $CHROOT/lib/x86_64-linux-gnu/libc.so.6 | head -1
"

echo "### 2. mount + resolv.conf + apt 源 + 依赖 + 源码 + 打补丁"
wsl.exe -d "$WSL_DISTRO" -u root -- bash -lc "
  set -e; R=$CHROOT
  mkdir -p \$R/proc \$R/sys \$R/dev \$R/dev/pts
  mountpoint -q \$R/proc    || mount -t proc proc \$R/proc
  mountpoint -q \$R/sys     || mount -t sysfs sys \$R/sys
  mountpoint -q \$R/dev     || mount --bind /dev \$R/dev
  mountpoint -q \$R/dev/pts || mount --bind /dev/pts \$R/dev/pts
  cp -f /etc/resolv.conf \$R/etc/resolv.conf
  cat > \$R/etc/apt/sources.list <<EOF
deb http://deb.debian.org/debian $DEB_VER main contrib non-free-firmware
deb http://deb.debian.org/debian ${DEB_VER}-updates main contrib non-free-firmware
deb http://security.debian.org/debian-security ${DEB_VER}-security main contrib non-free-firmware
EOF
  chroot \$R bash -lc 'export DEBIAN_FRONTEND=noninteractive; apt-get update -qq && apt-get install -y -qq \
    --no-install-recommends build-essential pkg-config ca-certificates wget xz-utils python3 bison flex \
    libssl-dev libxml2-dev libncurses-dev libsqlite3-dev uuid-dev libjansson-dev libedit-dev libcurl4-openssl-dev \
    libsrtp2-dev libspandsp-dev libspeex-dev libspeexdsp-dev libopus-dev libgsm1-dev libvorbis-dev libogg-dev \
    libsndfile1-dev libasound2-dev libpq-dev libldap2-dev libical-dev liburiparser-dev libxslt1-dev libnewt-dev \
    libneon27-gnutls-dev libunbound-dev libsnmp-dev libgmime-3.0-dev'
  # 源码在 WSL 主机下载（chroot 里 wget 偶发静默失败），再拷进 chroot
  cd /tmp && { [ -f asterisk-${AST_VER}.tar.gz ] || curl -sSL --max-time 900 -o asterisk-${AST_VER}.tar.gz '$SRC_URL'; }
  cp -f asterisk-${AST_VER}.tar.gz \$R/usr/src/
  chroot \$R bash -lc 'cd /usr/src && rm -rf asterisk-${AST_VER} && tar xzf asterisk-${AST_VER}.tar.gz'
"

# 拷贝补丁脚本并应用
cp -f "$(dirname "$0")/patch_avm.py" /tmp/patch_avm.py
cat /tmp/patch_avm.py | wsl.exe -d "$WSL_DISTRO" -u root -- bash -lc "cat > $CHROOT/root/patch_avm.py"
wsl.exe -d "$WSL_DISTRO" -u root -- bash -lc \
  "chroot $CHROOT bash -lc 'cd /usr/src/asterisk-${AST_VER} && cp -n apps/app_voicemail.c /root/app_voicemail.c.orig; python3 /root/patch_avm.py'"

echo "### 3. configure + 编译"
wsl.exe -d "$WSL_DISTRO" -u root -- bash -lc "
  chroot $CHROOT bash -lc 'cd /usr/src/asterisk-${AST_VER} && \
    ./configure --without-pjproject-bundled --without-imap --without-unixodbc --without-iodbc && \
    make menuselect.makeopts && make -j\$(nproc)'
"

echo "### 4. 出厂自检（架构 / glibc 符号 / NEEDED）"
wsl.exe -d "$WSL_DISTRO" -u root -- bash -lc "
  S=/usr/src/asterisk-${AST_VER}/apps/app_voicemail.so
  strip --strip-debug \$S
  file \$S
  echo '--- GLIBC 符号（最高必须 <= 目标机）---'
  readelf -V \$S | grep -oE 'GLIBC_[0-9.]+' | sort -uV
  echo '--- NEEDED（须与官方一致）---'
  readelf -d \$S | grep NEEDED
  sha256sum \$S
  cp -f \$S /mnt/c/Users/\$USER/AppData/Local/Temp/astsrc/app_voicemail.so 2>/dev/null || true
"

echo "### 5. 上传 + 备份 + 替换 + 热重载（无需重启 Asterisk）"
NEW_SO="/mnt/c/Users/Mrcool-Joan/AppData/Local/Temp/astsrc/app_voicemail.so"
SHA_NEW=$(wsl.exe -d "$WSL_DISTRO" -u root -- bash -lc "sha256sum $CHROOT/usr/src/asterisk-${AST_VER}/apps/app_voicemail.so" | tr -d '\000\r' | cut -d' ' -f1)
echo "本地产物 sha256 = $SHA_NEW"
cat "$NEW_SO" | ssh -i "$SSHKEY" "$TARGET" "set -e
  SO='$SO_TARGET'
  mkdir -p /root/sobak
  echo \"ORIG_SHA=\$(sha256sum \$SO | cut -d' ' -f1)\"
  cp -a \"\$SO\" \"/root/sobak/app_voicemail.so.orig-\$(date +%Y%m%d-%H%M%S)\"
  cat > /tmp/app_voicemail.so.new
  echo \"UP_SHA=\$(sha256sum /tmp/app_voicemail.so.new | cut -d' ' -f1)\"
  [ \"\$(sha256sum /tmp/app_voicemail.so.new | cut -d' ' -f1)\" = '$SHA_NEW' ] || { echo 'SHA MISMATCH!'; exit 1; }
  install -m 644 -o root -g root /tmp/app_voicemail.so.new \"\$SO\"
  asterisk -rx 'module unload app_voicemail.so'
  sleep 1
  asterisk -rx 'module load app_voicemail.so'
" 2>&1 | tail -12

echo
echo "### 完成。回滚：ssh $TARGET \"install -m644 /root/sobak/app_voicemail.so.orig-<ts> $SO_TARGET && asterisk -rx 'module unload app_voicemail.so' && asterisk -rx 'module load app_voicemail.so'\""
echo "### 验证：拨 *97 一个键都不按，应只播 1-12 段后进入等待"
