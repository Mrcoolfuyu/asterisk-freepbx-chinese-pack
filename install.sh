#!/usr/bin/env bash
# =============================================================================
#  asterisk-freepbx-chinese-pack  ——  一键安装脚本
#
#  目标：FreePBX 17 / Asterisk 22.x（Debian 12 bookworm，x86_64）中文语音本地化
#  特性：幂等 · 全程备份 · 分步可跳过 · 失败可回滚 · 安装后自检
#
#  用法：
#     sudo bash install.sh [选项]
#
#  选项：
#     --lang-dir NAME     语音语言目录名，默认 cn（同时建 zh_CN -> cn 软链接）
#     --timezone TZ       FreePBX PHPTIMEZONE，默认 Asia/Hong_Kong；传 "" 表示不改
#     --skip-sounds       跳过语音文件安装
#     --skip-so           跳过 app_voicemail.so 替换（不重编内核模块）
#     --skip-agi          跳过叫醒电话 AGI 补丁
#     --skip-kvstore      跳过 Hotelwakeup 中文消息（KVStore message_zh_CN）导入
#     --skip-dialplan     跳过 extensions_custom.conf 中文化片段
#     --skip-settings     跳过 FreePBX 设置（时区 / Soundlang 语言）
#     --no-reload         改完不做 module unload/load 与 dialplan reload（不推荐）
#     --dry-run           只打印将要做什么，不落盘
#     -h|--help           帮助
#
#  例：
#     sudo bash install.sh
#     sudo bash install.sh --skip-so --timezone Asia/Shanghai
#     sudo bash install.sh --dry-run
#
#  回滚：
#     sudo bash uninstall.sh            # 自动找最近一次备份
#     sudo bash uninstall.sh --from /root/zhpack-backup-20260924-140000
#
#  作者：Mr.cool（傅宇）· 舟 ⚓   许可：GPL-2.0（见 LICENSE）
# =============================================================================
set -euo pipefail

PACK_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# ---------------------------------------------------------------- 默认参数
LANG_DIR="cn"
LANG_ALIAS="zh_CN"
TIMEZONE="Asia/Hong_Kong"
DO_SOUNDS=1; DO_SO=1; DO_AGI=1; DO_KVSTORE=1; DO_DIALPLAN=1; DO_SETTINGS=1; DO_RELOAD=1
DRY=0
AST_USER="asterisk"
AST_GROUP="asterisk"
KVSTORE_TABLE="kvstore_FreePBX_modules_Hotelwakeup"

# 与 app_voicemail.so 一起发布的校验值（改模块必须同步改这里）
SO_SHA256_EXPECTED="206fc943c2473d241c9d0fed9333d2c58f641727a4d6063baa0d700f5483dbd3"
SO_MD5_EXPECTED="2592d691859105685ed22f563d7dcb17"

MARK_BEGIN="# >>> asterisk-freepbx-chinese-pack BEGIN >>>"
MARK_END="# <<< asterisk-freepbx-chinese-pack END <<<"

BK=""   # 备份目录（步骤 1 填充）

# ---------------------------------------------------------------- 小工具
c_r=$'\033[31m'; c_g=$'\033[32m'; c_y=$'\033[33m'; c_b=$'\033[36m'; c_0=$'\033[0m'
ok()   { printf '%s[ OK ]%s %s\n'  "$c_g" "$c_0" "$*"; }
warn() { printf '%s[WARN]%s %s\n'  "$c_y" "$c_0" "$*"; }
err()  { printf '%s[FAIL]%s %s\n'  "$c_r" "$c_0" "$*" >&2; }
step() { printf '\n%s==> %s%s\n'   "$c_b" "$*" "$c_0"; }
run()  { if [ "$DRY" = 1 ]; then printf '  (dry-run) %s\n' "$*"; else eval "$@"; fi; }

usage() { sed -n '2,40p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0; }

while [ $# -gt 0 ]; do
  case "$1" in
    --lang-dir)      LANG_DIR="$2"; shift 2;;
    --timezone)      TIMEZONE="$2"; shift 2;;
    --skip-sounds)   DO_SOUNDS=0; shift;;
    --skip-so)       DO_SO=0; shift;;
    --skip-agi)      DO_AGI=0; shift;;
    --skip-kvstore)  DO_KVSTORE=0; shift;;
    --skip-dialplan) DO_DIALPLAN=0; shift;;
    --skip-settings) DO_SETTINGS=0; shift;;
    --no-reload)     DO_RELOAD=0; shift;;
    --dry-run)       DRY=1; shift;;
    -h|--help)       usage;;
    *) err "未知参数：$1（用 --help 查看）"; exit 2;;
  esac
done

# ---------------------------------------------------------------- 0. 前置检查
step "0/9  前置检查"

[ "$(id -u)" = "0" ] || { err "请用 root 运行（sudo bash install.sh）"; exit 1; }
ok "root 权限"

command -v asterisk >/dev/null || { err "找不到 asterisk 命令，本机不是 Asterisk/FreePBX？"; exit 1; }
AST_VER="$(asterisk -rx 'core show version' 2>/dev/null | sed -n '1p' || true)"
ok "Asterisk：${AST_VER:-未知}"

# 模块目录
AST_MOD_DIR="${AST_MOD_DIR:-/usr/lib/$(dpkg-architecture -qDEB_HOST_MULTIARCH 2>/dev/null || echo x86_64-linux-gnu)/asterisk/modules}"
[ -d "$AST_MOD_DIR" ] || AST_MOD_DIR="$(asterisk -rx 'core show settings' 2>/dev/null | awk -F': *' '/Module directory/{d=$2} END{if(d)print d}' || true)"
[ -n "${AST_MOD_DIR:-}" ] && [ -d "$AST_MOD_DIR" ] || { err "定位不到 Asterisk 模块目录，请设 AST_MOD_DIR=/path"; exit 1; }
ok "模块目录：$AST_MOD_DIR"

SOUNDS_DIR="/var/lib/asterisk/sounds"
AGI_DIR="/var/lib/asterisk/agi-bin"
CUSTOM_CONF="/etc/asterisk/extensions_custom.conf"
HW_AGI_DIR="/var/www/html/admin/modules/hotelwakeup/agi-bin"

[ -d "$SOUNDS_DIR" ] || { err "找不到 $SOUNDS_DIR"; exit 1; }
ok "语音目录：$SOUNDS_DIR"

HAVE_FWCONSOLE=0
if command -v fwconsole >/dev/null 2>&1 && [ -f /etc/freepbx.conf ]; then HAVE_FWCONSOLE=1; ok "检测到 FreePBX（fwconsole 可用）";
else warn "未检测到 FreePBX，将跳过 FreePBX 专属步骤"; fi

# 必需文件自检
for f in sounds/"$LANG_DIR" modules/app_voicemail.so agi/wakeup config/message_zh_CN.sql config/extensions_custom.conf.snippet; do
  [ -e "$PACK_DIR/$f" ] || { err "包里缺少 $f，仓库不完整？"; exit 1; }
done
ok "包内文件齐备"

# ---------------------------------------------------------------- 1. 备份
step "1/9  备份现有文件"
BK="/root/zhpack-backup-$(date +%Y%m%d-%H%M%S)"
if [ "$DRY" = 1 ]; then printf '  (dry-run) 将备份到 %s\n' "$BK"; else
  mkdir -p "$BK"
  # 语音
  [ -d "$SOUNDS_DIR/$LANG_DIR" ] && cp -a "$SOUNDS_DIR/$LANG_DIR" "$BK/sounds-$LANG_DIR" 2>/dev/null || true
  [ -d "$SOUNDS_DIR/custom" ]    && cp -a "$SOUNDS_DIR/custom"    "$BK/sounds-custom"   2>/dev/null || true
  # 模块
  [ -f "$AST_MOD_DIR/app_voicemail.so" ] && cp -a "$AST_MOD_DIR/app_voicemail.so" "$BK/app_voicemail.so.orig" || true
  # AGI
  [ -f "$AGI_DIR/wakeup" ]           && cp -a "$AGI_DIR/wakeup"           "$BK/agi-wakeup"        || true
  [ -f "$AGI_DIR/wakeglobal.php" ]   && cp -a "$AGI_DIR/wakeglobal.php"   "$BK/agi-wakeglobal.php" || true
  [ -f "$HW_AGI_DIR/wakeup" ]        && cp -a "$HW_AGI_DIR/wakeup"        "$BK/hwagi-wakeup"       || true
  # 拨号方案
  [ -f "$CUSTOM_CONF" ] && cp -a "$CUSTOM_CONF" "$BK/extensions_custom.conf" || true
  # 数据库
  if [ "$HAVE_FWCONSOLE" = 1 ]; then
    mysqldump --no-create-info --skip-extended-insert --skip-comments \
      --where="id='message_zh_CN'" asterisk "$KVSTORE_TABLE" \
      > "$BK/kvstore-message_zh_CN.sql" 2>/dev/null || true
    mysql -N -B asterisk -e "select * from soundlang_settings;"  > "$BK/soundlang_settings.txt" 2>/dev/null || true
    mysql -N -B asterisk -e "select * from soundlang_customlangs;" > "$BK/soundlang_customlangs.txt" 2>/dev/null || true
    fwconsole setting PHPTIMEZONE > "$BK/phptimezone.txt" 2>/dev/null || true
  fi
  # 环境快照
  { echo "asterisk=$AST_VER"; echo "module_dir=$AST_MOD_DIR"; echo "date=$(date '+%F %T %z')";
    echo "so_sha256_before=$(sha256sum "$AST_MOD_DIR/app_voicemail.so" 2>/dev/null | cut -d' ' -f1)"; } \
    > "$BK/ENV.txt"
  ok "已备份到 $BK"
fi
echo "$BK" > /tmp/zhpack-last-backup 2>/dev/null || true

# ---------------------------------------------------------------- 2. 语音文件
step "2/9  安装中文语音文件"
if [ "$DO_SOUNDS" = 1 ]; then
  run "mkdir -p '$SOUNDS_DIR/$LANG_DIR'"
  run "cp -a '$PACK_DIR/sounds/$LANG_DIR/.' '$SOUNDS_DIR/$LANG_DIR/'"
  run "mkdir -p '$SOUNDS_DIR/custom'"
  run "cp -a '$PACK_DIR/sounds/custom/.' '$SOUNDS_DIR/custom/'"
  # ★ 关键：语言目录下的 custom 必须是软链接，否则 languageprefix 场景下 custom/xxx 找不到
  run "ln -sfn '$SOUNDS_DIR/custom' '$SOUNDS_DIR/$LANG_DIR/custom'"
  # zh_CN -> cn
  if [ "$LANG_DIR" != "$LANG_ALIAS" ] && [ ! -e "$SOUNDS_DIR/$LANG_ALIAS" ]; then
    run "ln -sfn '$SOUNDS_DIR/$LANG_DIR' '$SOUNDS_DIR/$LANG_ALIAS'"
  fi
  run "chown -R $AST_USER:$AST_GROUP '$SOUNDS_DIR/$LANG_DIR' '$SOUNDS_DIR/custom'"
  ok "语音已安装（cn 593 个 WAV + custom 39 个 WAV）"
else
  warn "已跳过（--skip-sounds）"
fi

# ---------------------------------------------------------------- 3. app_voicemail.so
step "3/9  替换 app_voicemail.so（去掉 *97 登录后多播的英文语序菜单）"
if [ "$DO_SO" = 1 ]; then
  if [ -n "${BK:-}" ] && [ -f "$PACK_DIR/modules/app_voicemail.so" ] && [ "$DRY" = 0 ]; then
    # 校验包的 .so
    SO_SHA="$(sha256sum "$PACK_DIR/modules/app_voicemail.so" | cut -d' ' -f1)"
    if [ "$SO_SHA" != "$SO_SHA256_EXPECTED" ]; then
      err "包内 app_voicemail.so 校验失败（期望 $SO_SHA256_EXPECTED，实际 $SO_SHA）"; exit 1
    fi
    ok "包内 .so sha256 校验通过"
    # ★ 别把 .so 拷到与目标机 glibc 不兼容的机器上（见 INSTALL.md「glibc 对齐」）
    SO_FILE_INFO="$(file -b "$PACK_DIR/modules/app_voicemail.so" 2>/dev/null || true)"
    case "$SO_FILE_INFO" in
      *x86-64*) ok "架构 x86-64";;
      *) err "app_voicemail.so 不是 x86_64 ELF（file 报告：$SO_FILE_INFO）"; exit 1;;
    esac
  fi
  run "install -m 644 -o root -g root '$PACK_DIR/modules/app_voicemail.so' '$AST_MOD_DIR/app_voicemail.so'"
  if [ "$DO_RELOAD" = 1 ]; then
    # ★ unload 与 load 之间必须有间隔：无间隔时 load 会撞上尚未完成的 unload，
    #   报 "Unable to load module"（实测踩过），模块会停留在未加载状态
    run "asterisk -rx 'module unload app_voicemail.so' >/dev/null 2>&1 || true"
    run "sleep 1"
    run "asterisk -rx 'module load   app_voicemail.so' >/dev/null 2>&1 || true"
    run "sleep 1"
    if [ "$DRY" = 0 ]; then
      SO_OK=0
      for _try in 1 2 3; do
        # ★ 不用 `| grep -q`：grep -q 命中即退出，pipefail 下会把整个管道判为失败（踩过）
        MOD_OUT="$(asterisk -rx 'module show like app_voicemail' 2>/dev/null || true)"
        case "$MOD_OUT" in *Running*) SO_OK=1; break;; esac
        warn "第 $_try 次未确认加载成功，重试 module load…"
        asterisk -rx 'module load app_voicemail.so' >/dev/null 2>&1 || true
        sleep 2
      done
      if [ "$SO_OK" = 1 ]; then
        ok "app_voicemail.so 已重新加载并运行"
      else
        err "模块加载失败！立刻回滚：install -m644 '$BK/app_voicemail.so.orig' '$AST_MOD_DIR/app_voicemail.so' && sleep 1 && asterisk -rx 'module load app_voicemail.so'"
        err "回滚后请检查：file '$PACK_DIR/modules/app_voicemail.so' 与目标机 glibc 是否匹配（见 INSTALL.md 2.4）"
      fi
    fi
  fi
else
  warn "已跳过（--skip-so）；不改这一项时，*97 零按键仍会多播 6 段英文语序菜单"
fi

# ---------------------------------------------------------------- 4. 叫醒电话 AGI
step "4/9  安装叫醒电话 AGI 补丁"
if [ "$DO_AGI" = 1 ]; then
  run "install -m 755 -o $AST_USER -g $AST_GROUP '$PACK_DIR/agi/wakeup' '$AGI_DIR/wakeup'"
  run "install -m 755 -o $AST_USER -g $AST_GROUP '$PACK_DIR/agi/wakeglobal.php' '$AGI_DIR/wakeglobal.php'"
  if [ -d "$HW_AGI_DIR" ]; then
    run "install -m 755 -o $AST_USER -g $AST_GROUP '$PACK_DIR/agi/wakeup' '$HW_AGI_DIR/wakeup'"
    ok "已同步到模块目录（防止 fwconsole ma upgrade hotelwakeup 后被回退）"
  else
    warn "未找到 $HW_AGI_DIR，跳过模块目录同步"
  fi
else
  warn "已跳过（--skip-agi）；输入 4 位 HHMM 时仍可能丢失第 4 位而报「输入无效」"
fi

# ---------------------------------------------------------------- 5. KVStore 中文消息
step "5/9  导入叫醒电话中文消息（KVStore message_zh_CN）"
if [ "$DO_KVSTORE" = 1 ]; then
  if [ "$HAVE_FWCONSOLE" = 1 ]; then
    # ★ 表上有 uniqueindex(key,id)，重复导入会主键冲突 → 先删同 id 的旧行，保证幂等
    run "mysql asterisk -e \"delete from $KVSTORE_TABLE where id='message_zh_CN';\""
    run "mysql asterisk < '$PACK_DIR/config/message_zh_CN.sql'"
    if [ "$DRY" = 0 ]; then
      N="$(mysql -N -B asterisk -e "select count(*) from $KVSTORE_TABLE where id='message_zh_CN';" 2>/dev/null || echo 0)"
      [ "$N" -ge 20 ] && ok "已导入 $N 条中文消息" || warn "导入后仅 $N 条，请检查 hotelwakeup 模块是否已安装"
    fi
  else
    warn "无 FreePBX，跳过"
  fi
else
  warn "已跳过（--skip-kvstore）；*68 叫醒电话提示仍是英文片段拼装"
fi

# ---------------------------------------------------------------- 6. 拨号方案
step "6/9  追加拨号方案片段（*60 中文报时 + 自建报时上下文）"
if [ "$DO_DIALPLAN" = 1 ]; then
  if [ "$DRY" = 1 ]; then
    printf '  (dry-run) 将把 config/extensions_custom.conf.snippet 追加到 %s（带 %s 幂等标记）\n' "$CUSTOM_CONF" "$MARK_BEGIN"
  else
    # 幂等：先删掉旧托管块
    if grep -qF "$MARK_BEGIN" "$CUSTOM_CONF" 2>/dev/null; then
      awk -v b="$MARK_BEGIN" -v e="$MARK_END" '
        index($0,b){skip=1} !skip{print} index($0,e){skip=0}' "$CUSTOM_CONF" > "$CUSTOM_CONF.tmp"
      mv -f "$CUSTOM_CONF.tmp" "$CUSTOM_CONF"
      ok "已移除旧的托管块（幂等替换）"
    elif grep -qE '^\[(sub-hr12format|sub-hr24format)-custom\]' "$CUSTOM_CONF" 2>/dev/null; then
      # ★ 已存在同名上下文但没有本包标记 = 之前是手工写的
      #   此时若再追加，会导致同一上下文重复定义（Asterisk 会告警、行为取决于顺序）→ 宁可不动
      warn "检测到 $CUSTOM_CONF 里已存在 [sub-hr12format-custom]（但无本包标记）"
      warn "  → 判定为手工配置，**跳过追加**以免重复定义。"
      warn "  → 若希望由本包接管：先手工删掉那段旧上下文，再重跑本脚本。"
      DO_DIALPLAN_WRITE=0
    fi
    if [ "${DO_DIALPLAN_WRITE:-1}" = 1 ]; then
      {
        printf '\n%s\n' "$MARK_BEGIN"
        cat "$PACK_DIR/config/extensions_custom.conf.snippet"
        printf '%s\n' "$MARK_END"
      } >> "$CUSTOM_CONF"
      chown "$AST_USER:$AST_GROUP" "$CUSTOM_CONF" 2>/dev/null || true
      ok "已写入托管块"
    fi
  fi
  if [ "$DO_RELOAD" = 1 ]; then
    run "asterisk -rx 'dialplan reload' >/dev/null"
    if [ "$DRY" = 0 ] && [ "${DO_DIALPLAN_WRITE:-1}" = 1 ]; then
      DP_OUT="$(asterisk -rx 'dialplan show sub-hr12format-custom' 2>/dev/null || true)"
      case "$DP_OUT" in
        *zh_CN*) ok "dialplan 已生效（sub-hr12format-custom/zh_CN 存在）";;
        *) warn "未确认到 sub-hr12format-custom/zh_CN，请手动执行 asterisk -rx 'dialplan show sub-hr12format-custom'";;
      esac
    fi
  fi
else
  warn "已跳过（--skip-dialplan）；*60 仍是英文句式报时"
fi

# ---------------------------------------------------------------- 7. FreePBX 设置
step "7/9  FreePBX 设置（时区 / Soundlang 语言）"
if [ "$DO_SETTINGS" = 1 ] && [ "$HAVE_FWCONSOLE" = 1 ]; then
  # 7.1 时区：★ PHPTIMEZONE 决定叫醒电话的触发时刻，必须是本地时区
  if [ -n "$TIMEZONE" ]; then
    CUR_TZ="$(php -r 'require "/etc/freepbx.conf"; echo date_default_timezone_get();' 2>/dev/null || echo '?')"
    if [ "$CUR_TZ" != "$TIMEZONE" ]; then
      warn "FreePBX PHP 时区目前为 $CUR_TZ（≠ $TIMEZONE）→ 叫醒电话会整体偏移"
      run "fwconsole setting PHPTIMEZONE '$TIMEZONE'"
    else
      ok "PHPTIMEZONE 已是 $TIMEZONE"
    fi
  fi
  # 7.2 Soundlang：默认语言 + 注册自定义语言
  #     注意真实列名：soundlang_settings(keyword,value)；soundlang_customlangs(id,language,description)
  run "mysql asterisk -e \"insert into soundlang_settings (\\\`keyword\\\`,\\\`value\\\`) values ('language','$LANG_ALIAS') on duplicate key update \\\`value\\\`='$LANG_ALIAS';\" >/dev/null 2>&1 || true"
  run "mysql asterisk -e \"insert into soundlang_customlangs (language,description) select '$LANG_ALIAS','Chinese' from dual where not exists (select 1 from soundlang_customlangs where language='$LANG_ALIAS');\" >/dev/null 2>&1 || true"
  ok "Soundlang 默认语言 = $LANG_ALIAS（自定义语言）"
  warn "GUI: Admin → Sound Languages 里确认 zh_CN 已启用；若分机单独设过语言，见 INSTALL.md「语言有两处源头」"
else
  warn "已跳过（无 FreePBX 或 --skip-settings）"
fi

# ---------------------------------------------------------------- 8. 校验
step "8/9  安装后自检"
if [ "$DRY" = 0 ]; then
  n_wav="$(find "$SOUNDS_DIR/$LANG_DIR" -maxdepth 1 -name '*.wav' 2>/dev/null | wc -l)"
  [ "$n_wav" -ge 380 ] && ok "cn/ 顶层 WAV $n_wav 个" || warn "cn/ 顶层 WAV 只有 $n_wav 个，疑似未拷全"
  [ -L "$SOUNDS_DIR/$LANG_DIR/custom" ] && ok "cn/custom 软链接存在" || warn "cn/custom 不是软链接"
  # ★ 不用 `| head -1`：set -o pipefail 下 head 提前退出会让 find 收到 SIGPIPE 而误判失败（踩过）
  f="$(find "$SOUNDS_DIR/$LANG_DIR" -maxdepth 1 -name '*.wav' -print -quit 2>/dev/null || true)"
  if [ -n "$f" ]; then
    f_info="$(file -b "$f" 2>/dev/null || true)"
    case "$f_info" in
      *"16 bit, mono 8000 Hz"*) ok "WAV 格式 = 16bit/mono/8000Hz";;
      *) warn "WAV 格式异常：$f_info";;
    esac
  fi
  # zh 专用 6 音
  miss=""
  for k in vm-you vm-have vm-tong vm-haveno vm-listen press; do
    [ -e "$SOUNDS_DIR/$LANG_DIR/$k.wav" ] || miss="$miss $k"
  done
  [ -z "$miss" ] && ok "zh 专用 6 个提示音齐全" || warn "缺少 zh 专用提示音：$miss"
  # 模块
  if [ -f "$AST_MOD_DIR/app_voicemail.so" ]; then
    s="$(sha256sum "$AST_MOD_DIR/app_voicemail.so" | cut -d' ' -f1)"
    [ "$s" = "$SO_SHA256_EXPECTED" ] && ok "app_voicemail.so = 补丁版" || warn "app_voicemail.so 非补丁版（sha256=$s）"
  fi
  # 日志：只统计「语音文件缺失」（file.c: File X does not exist）
  #   —— 不要用宽泛的 'does not exist'：那会把 AstDB 键探测告警（db.c: AstDB key ...）
  #      一并算进来，实测噪音占 50/51，会误导。
  #   也不要用 grep -c：计数为 0 时退出码是 1，会污染 `|| echo 0` 的输出。
  if [ -f /var/log/asterisk/full ]; then
    bad="$(awk '/file\.c: File .* does not exist/{n++} END{print n+0}' /var/log/asterisk/full 2>/dev/null || echo 0)"
    noise="$(awk '/does not exist/{n++} END{print n+0}' /var/log/asterisk/full 2>/dev/null || echo 0)"
    bad="${bad:-0}"; noise="${noise:-0}"
    if [ "$bad" = "0" ]; then
      ok "日志无缺音（'file.c ... does not exist' 0 条；另有 $noise 条 AstDB 键告警，属正常噪音）"
    else
      warn "日志里有 $bad 条缺音记录："
      awk '/file\.c: File .* does not exist/{print "       " $0}' /var/log/asterisk/full | tail -5
      warn "  缺音定位：asterisk -rx 'core set verbose 3' 后拨测，再 grep \"Playing '\" /var/log/asterisk/full"
    fi
  fi
fi

# ---------------------------------------------------------------- 9. 完成
step "9/9  完成"
cat <<EOF

  备份目录：${BK:-（dry-run 未备份）}

  请这样验证：
    1) 拨 *97      → 听中文提示；一个键都不按，应只播 1~12 段后进入等待，不再接英文菜单
    2) 拨 *98      → 听语音信箱中文提示
    3) 拨 *60      → 应播「北京时间 上午/下午 X 点 X 分 X 秒 / 整」
    4) 拨 *68 → 按 1 → 直接输入 4 位 24 小时制（22:30 = 2230，不用按 #）
       检查排程落点：stat -c '%y %n' /var/spool/asterisk/outgoing/wuc.*.call
       其 mtime 应等于你设定的挂钟时间（若差 8 小时 = PHPTIMEZONE 没设对）

  回滚：
    sudo bash "$PACK_DIR/uninstall.sh"
    # 或指定备份：sudo bash uninstall.sh --from ${BK:-/root/zhpack-backup-XXX}

EOF
ok "安装流程结束"
