#!/usr/bin/env bash
# =============================================================================
#  asterisk-freepbx-chinese-pack  ——  回滚脚本
#
#  用法：
#     sudo bash uninstall.sh                    # 自动选取最近一次 install 的备份
#     sudo bash uninstall.sh --from /root/zhpack-backup-20260924-140000
#     sudo bash uninstall.sh --list             # 列出所有可用备份
#     sudo bash uninstall.sh --keep-sounds      # 只回滚代码/配置，保留语音文件
#     sudo bash uninstall.sh --dry-run
#
#  说明：回滚只恢复【本包安装时覆盖过的文件】，不做任何脑补删除。
#        备份里没有的项目就跳过，并在结尾列出「未回滚项」。
#
#  作者：Mr.cool（傅宇）· 舟 ⚓   许可：GPL-2.0
# =============================================================================
set -euo pipefail

SOUNDS_DIR="/var/lib/asterisk/sounds"
AGI_DIR="/var/lib/asterisk/agi-bin"
CUSTOM_CONF="/etc/asterisk/extensions_custom.conf"
HW_AGI_DIR="/var/www/html/admin/modules/hotelwakeup/agi-bin"
KVSTORE_TABLE="kvstore_FreePBX_modules_Hotelwakeup"
LANG_DIR="cn"
AST_USER="asterisk"; AST_GROUP="asterisk"

MARK_BEGIN="# >>> asterisk-freepbx-chinese-pack BEGIN >>>"
MARK_END="# <<< asterisk-freepbx-chinese-pack END <<<"
LAST_FILE="/tmp/zhpack-last-backup"

c_r=$'\033[31m'; c_g=$'\033[32m'; c_y=$'\033[33m'; c_b=$'\033[36m'; c_0=$'\033[0m'
ok()   { printf '%s[ OK ]%s %s\n' "$c_g" "$c_0" "$*"; }
warn() { printf '%s[WARN]%s %s\n' "$c_y" "$c_0" "$*"; }
err()  { printf '%s[FAIL]%s %s\n' "$c_r" "$c_0" "$*" >&2; }
step() { printf '\n%s==> %s%s\n'  "$c_b" "$*" "$c_0"; }
run()  { if [ "$DRY" = 1 ]; then printf '  (dry-run) %s\n' "$*"; else eval "$@"; fi; }

FROM=""; DO_SOUNDS=1; DRY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --from)        FROM="$2"; shift 2;;
    --list)        ls -1d /root/zhpack-backup-* 2>/dev/null | sort || echo "（无备份）"; exit 0;;
    --keep-sounds) DO_SOUNDS=0; shift;;
    --dry-run)     DRY=1; shift;;
    -h|--help)     sed -n '2,25p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0;;
    *) err "未知参数：$1"; exit 2;;
  esac
done

[ "$(id -u)" = "0" ] || { err "请用 root 运行"; exit 1; }

step "定位备份"
if [ -z "$FROM" ]; then
  [ -f "$LAST_FILE" ] && FROM="$(cat "$LAST_FILE")"
fi
if [ -z "$FROM" ] || [ ! -d "$FROM" ]; then
  FROM="$(ls -1d /root/zhpack-backup-* 2>/dev/null | sort | tail -1 || true)"
fi
[ -n "$FROM" ] && [ -d "$FROM" ] || { err "找不到任何备份目录，请用 --from 指定"; exit 1; }
ok "使用备份：$FROM"
ls -la "$FROM"

AST_MOD_DIR="${AST_MOD_DIR:-/usr/lib/$(dpkg-architecture -qDEB_HOST_MULTIARCH 2>/dev/null || echo x86_64-linux-gnu)/asterisk/modules}"
[ -d "$AST_MOD_DIR" ] || AST_MOD_DIR="$(asterisk -rx 'core show settings' 2>/dev/null | awk -F': *' '/Module directory/{print $2; exit}')"
HAVE_FWCONSOLE=0; command -v fwconsole >/dev/null 2>&1 && [ -f /etc/freepbx.conf ] && HAVE_FWCONSOLE=1
UNROLLED=""

# ---------------------------------------------------------------- 1. 语音
step "1/6  语音文件"
if [ "$DO_SOUNDS" = 1 ]; then
  if [ -d "$FROM/sounds-$LANG_DIR" ]; then
    run "rm -rf '$SOUNDS_DIR/$LANG_DIR' && cp -a '$FROM/sounds-$LANG_DIR' '$SOUNDS_DIR/$LANG_DIR' && chown -R $AST_USER:$AST_GROUP '$SOUNDS_DIR/$LANG_DIR'"
    ok "已恢复 $SOUNDS_DIR/$LANG_DIR"
  else warn "备份里没有 sounds-$LANG_DIR，跳过"; UNROLLED="$UNROLLED 语音目录"; fi
  if [ -d "$FROM/sounds-custom" ]; then
    run "rm -rf '$SOUNDS_DIR/custom' && cp -a '$FROM/sounds-custom' '$SOUNDS_DIR/custom' && chown -R $AST_USER:$AST_GROUP '$SOUNDS_DIR/custom'"
    ok "已恢复 $SOUNDS_DIR/custom"
  else warn "备份里没有 sounds-custom，跳过"; UNROLLED="$UNROLLED custom目录"; fi
else
  warn "已按要求保留语音文件（--keep-sounds）"
fi

# ---------------------------------------------------------------- 2. 模块
step "2/6  app_voicemail.so"
if [ -f "$FROM/app_voicemail.so.orig" ]; then
  run "install -m 644 -o root -g root '$FROM/app_voicemail.so.orig' '$AST_MOD_DIR/app_voicemail.so'"
  run "asterisk -rx 'module unload app_voicemail.so' >/dev/null 2>&1 || true"
  run "asterisk -rx 'module load   app_voicemail.so' >/dev/null 2>&1 || true"
  ok "已恢复原模块并重载（*97 会变回多播英文菜单，属预期）"
else
  warn "备份里没有 app_voicemail.so.orig，跳过（未替换过模块？）"
fi

# ---------------------------------------------------------------- 3. AGI
step "3/6  叫醒电话 AGI"
if [ -f "$FROM/agi-wakeup" ]; then
  run "install -m 755 -o $AST_USER -g $AST_GROUP '$FROM/agi-wakeup' '$AGI_DIR/wakeup'"; ok "wakeup 已恢复"
fi
if [ -f "$FROM/agi-wakeglobal.php" ]; then
  run "install -m 755 -o $AST_USER -g $AST_GROUP '$FROM/agi-wakeglobal.php' '$AGI_DIR/wakeglobal.php'"; ok "wakeglobal.php 已恢复"
fi
if [ -f "$FROM/hwagi-wakeup" ] && [ -d "$HW_AGI_DIR" ]; then
  run "install -m 755 -o $AST_USER -g $AST_GROUP '$FROM/hwagi-wakeup' '$HW_AGI_DIR/wakeup'"; ok "模块目录 wakeup 已恢复"
fi

# ---------------------------------------------------------------- 4. 数据库
step "4/6  KVStore message_zh_CN"
if [ "$HAVE_FWCONSOLE" = 1 ]; then
  run "mysql asterisk -e \"delete from $KVSTORE_TABLE where id='message_zh_CN';\""
  if [ -s "$FROM/kvstore-message_zh_CN.sql" ] && grep -q 'INSERT' "$FROM/kvstore-message_zh_CN.sql"; then
    run "mysql asterisk < '$FROM/kvstore-message_zh_CN.sql'"
    ok "已恢复安装前的 message_zh_CN"
  else
    ok "安装前就没有 message_zh_CN，已清空"
  fi
  if [ -f "$FROM/soundlang_settings.txt" ]; then
    OLD_LANG="$(awk -F'\t' '$1=="language"{print $2}' "$FROM/soundlang_settings.txt")"
    if [ -n "${OLD_LANG:-}" ]; then
      run "mysql asterisk -e \"update soundlang_settings set \\\`value\\\`='$OLD_LANG' where \\\`keyword\\\`='language';\" >/dev/null 2>&1 || true"
      ok "Soundlang 语言已还原为 $OLD_LANG"
    fi
  fi
else
  warn "无 FreePBX，跳过"
fi

# ---------------------------------------------------------------- 5. 拨号方案
step "5/6  extensions_custom.conf 托管块"
if [ -f "$FROM/extensions_custom.conf" ]; then
  run "cp -a '$FROM/extensions_custom.conf' '$CUSTOM_CONF'"
  ok "已整份还原 extensions_custom.conf（含你原有的自定义上下文）"
else
  if [ "$DRY" = 1 ]; then
    printf '  (dry-run) 将从 %s 移除托管块\n' "$CUSTOM_CONF"
  elif grep -qF "$MARK_BEGIN" "$CUSTOM_CONF" 2>/dev/null; then
    awk -v b="$MARK_BEGIN" -v e="$MARK_END" 'index($0,b){skip=1} !skip{print} index($0,e){skip=0}' \
      "$CUSTOM_CONF" > "$CUSTOM_CONF.tmp" && mv -f "$CUSTOM_CONF.tmp" "$CUSTOM_CONF"
    ok "已移除托管块"
  else
    warn "无备份且找不到托管块，未改动"
  fi
fi
run "asterisk -rx 'dialplan reload' >/dev/null" && ok "dialplan 已重载"

# ---------------------------------------------------------------- 6. 收尾
step "6/6  收尾"
if [ "$HAVE_FWCONSOLE" = 1 ] && [ -f "$FROM/phptimezone.txt" ]; then
  warn "PHPTIMEZONE 未自动回滚（安装前的值：$(cat "$FROM/phptimezone.txt")）"
  warn "  如需还原：fwconsole setting PHPTIMEZONE <值>"
  warn "  ⚠ 但保留 Asia/Hong_Kong 才是对的；还原成 UTC 会让叫醒电话偏 8 小时"
fi
[ -n "$UNROLLED" ] && warn "未回滚项：$UNROLLED（备份里缺这些）"
ok "回滚结束。建议拨 *97 / *68 确认行为已还原。"
