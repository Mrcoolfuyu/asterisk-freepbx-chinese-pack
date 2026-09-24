# INSTALL.md —— 安装保障文档

> 本文是**操作手册 + 保障清单**。目标：让任何人在任何一台同版本 FreePBX 上，能在 10 分钟内
> 装好、验完、且**随时能退回去**。
>
> 全程不需要重装系统、不需要重启 Asterisk、不影响正在进行的通话（`app_voicemail.so` 走模块热重载）。

---

## 目录

1. [适用版本与前置条件](#1-适用版本与前置条件)
2. [动手前必读的 6 条硬约束](#2-动手前必读的-6-条硬约束)
3. [快速安装](#3-快速安装)
4. [分步详解（含每步验证与失败处置）](#4-分步详解)
5. [安装后完整验收清单](#5-安装后完整验收清单)
6. [回滚（三种粒度）](#6-回滚三种粒度)
7. [故障排查：按症状查表](#7-故障排查按症状查表)
8. [已知坑与长期注意事项](#8-已知坑与长期注意事项)
9. [本次未覆盖事项](#9-本次未覆盖事项)

---

## 1. 适用版本与前置条件

### 1.1 版本矩阵（★ 必须逐项对上）

| 组件 | 本包验证版本 | 检查命令 |
|---|---|---|
| Asterisk | **22.8.2** | `asterisk -rx 'core show version'` |
| FreePBX | 17.0.30 | `fwconsole --version` |
| 发行版 | Debian 12 (bookworm) | `cat /etc/os-release` |
| 架构 | x86_64 | `uname -m` |
| glibc | 2.36（`.so` 最高符号 `GLIBC_2.34`） | `ldd --version \| head -1` |
| PHP | 8.2 | `php -v` |

**不满足怎么办：**

- **Asterisk 版本不一致** → `.so` 与内核模块 ABI 强绑定，**绝对不要**直接替换。
  改用 `patches/app_voicemail-22.8.2-vm_instructions_zh.patch` + `build/build_app_voicemail_wsl.sh`
  在你的版本上重编（脚本里 `AST_VER` 改成你的版本）。
- **非 x86_64 / glibc 更低** → 同样须自己重编（见 [2.4](#24-app_voicemailso-必须在-glibc--目标机的环境里编译)）。
- **音频 / AGI / dialplan 三部分与版本无关**，任何 Asterisk 22.x 都能用。

### 1.2 权限与备份要求

- 需要 **root**（要写 `/var/lib/asterisk/`、`/etc/asterisk/`、模块目录、MySQL）。
- 需要 **MySQL/MariaDB `asterisk` 库的访问权**（脚本用 `mysql`/`mysqldump` 免密或 root 免密）。
- 需要 **≥ 200MB 空闲**（备份约占 25MB，语音 24MB）。
- 安装脚本会**自动全量备份**到 `/root/zhpack-backup-<YYYYmmdd-HHMMSS>/`，**不要手动删除**。

### 1.3 端口 / 服务依赖

- 无需开放任何新端口。
- `asterisk` 服务须在运行（脚本用 `asterisk -rx` 做热重载与自检）。
- 若装了 Hotel Wakeup 模块才有 `*68`，没装则 KVStore 那步会自动跳过。

---

## 2. 动手前必读的 6 条硬约束

> 这 6 条是踩过的坑，**违反任何一条都会出问题**。建议先读完再动手。

### 2.1 语言代码必须用 `zh_CN`，**绝不能用 `cn`**

Asterisk `app_voicemail` 的**中文语序引擎**（`vm_intro_zh`、`vm_instructions_zh` 等）只在通道
language **以 `zh` 开头**时才启用。用 `cn` 会落到英文语序引擎，拼出

> 「您有**三新的和一条旧留言**」 ← 病句

所以我们**同时维护两个名字**：文件放在 `cn/`（历史习惯），但**通道语言必须是 `zh_CN`**。
本包的 `install.sh` 会自动建 `zh_CN -> cn` 软链接，并把 Soundlang 默认语言设为 `zh_CN`。

### 2.2 语言有**两处**源头，改一处不够

| 源头 | 位置 | 作用范围 |
|---|---|---|
| ① Soundlang 默认语言 | GUI `Admin → Sound Languages`；DB `asterisk.soundlang_settings.language` | 全局默认 |
| ② **逐分机覆盖** | FreePBX **Languages 模块**，值存在 **AstDB** `AMPUSER/<ext>/language` | 只影响该分机，**盖住全局** |

排查时**必须两条都查**：

```bash
# ① 全局
mysql -N -B asterisk -e "select * from soundlang_settings;"
# ② 逐分机：pjsip 端点块里 language= 会以「后出现的为准」覆盖全局
awk '/^\[/{ep=$0} /^language=/{print ep" -> "$0}' /etc/asterisk/pjsip.endpoint.conf
# ③ AstDB
asterisk -rx 'database show' | grep -i language
```

> 症状：全局设了 zh_CN，但某个分机仍然报英文 → 十有八九是 ② 覆盖了。

### 2.3 `cn/custom` 必须是指向 `../custom` 的**软链接**

Asterisk 在语言目录下找 `custom/xxx` 时，会尝试 `<lang>/custom/xxx`。
少了这个软链接，`*60`、`*68` 这些播 `custom/xxx` 的功能会**整段变哑**。

```bash
ls -la /var/lib/asterisk/sounds/cn/custom      # 应为 -> /var/lib/asterisk/sounds/custom
# 若没有：
ln -sfn /var/lib/asterisk/sounds/custom /var/lib/asterisk/sounds/cn/custom
```

`install.sh` 每次都会重建它。

### 2.4 `app_voicemail.so` 必须在 **glibc ≤ 目标机** 的环境里编译

在 Ubuntu 24.04（glibc 2.39）上编出来的 `.so`，拷到 Debian 12（glibc 2.36）会因
`GLIBC_2.38 not found` / `dlopen 失败` 而**加载不了**。

正确做法（`build/build_app_voicemail_wsl.sh` 已自动化）：

```bash
# 在 WSL 里造一个与目标机 glibc 同版的 chroot
wsl.exe -d Ubuntu-24.04 -u root
debootstrap --variant=minbase --arch=amd64 bookworm /opt/deb12 https://deb.debian.org/debian
chroot /opt/deb12 bash     # 在这个 chroot 里编
```

编完**必须**做三道自检，再拷到目标机：

```bash
file app_voicemail.so                      # 期望 ELF 64-bit LSB shared object, x86-64
readelf -V app_voicemail.so | grep -oE 'GLIBC_[0-9.]+' | sort -uV   # 最高符号 ≤ 目标机 glibc
readelf -d app_voicemail.so | grep NEEDED  # 期望只有 libc.so.6
```

### 2.5 换模块用 `module unload` + `module load`，**`module reload` 无效**

`module reload app_voicemail.so` 不会重新 `dlopen` 新的 `.so`，改动不生效。

```bash
asterisk -rx 'module unload app_voicemail.so'
asterisk -rx 'module load app_voicemail.so'      # 会重新 dlopen，无需重启 Asterisk
```

> 卸载瞬间该模块的功能不可用（毫秒级），建议避开话务高峰。

### 2.6 判断 FreePBX 时区，**必须带引导**查 PHP

`PHPTIMEZONE` 决定 PHP（含 AGI）的时区，它决定叫醒电话的触发时刻。查法：

```bash
# ✅ 正确：带 FreePBX 引导
php -r 'require "/etc/freepbx.conf"; echo date_default_timezone_get(), PHP_EOL;'

# ❌ 错误：裸 php -r 看的是 php.ini（不含 FreePBX 覆盖）
# ❌ 错误：date 看的是系统时区（可能与 PHP 不一致）
```

本机原为 `UTC` 而系统是 `Asia/Hong_Kong(+08)` → **叫醒电话整体偏 8 小时**，
且 GUI/语音列表同用错误时区计算 → **界面上完全看不出来**。`install.sh` 会自动对齐。

---

## 3. 快速安装

```bash
git clone https://github.com/Mrcoolfuyu/asterisk-freepbx-chinese-pack.git
cd asterisk-freepbx-chinese-pack

sudo bash install.sh --dry-run     # ① 干跑：只打印将做什么
sudo bash install.sh               # ② 正式安装（自动备份）
sudo bash uninstall.sh             # ③ 不满意就回滚
```

### 3.1 参数一览

| 参数 | 默认 | 说明 |
|---|---|---|
| `--lang-dir NAME` | `cn` | 语音语言目录名（同时建 `zh_CN -> NAME` 软链接） |
| `--timezone TZ` | `Asia/Hong_Kong` | FreePBX `PHPTIMEZONE`；传 `""` 表示不改 |
| `--skip-sounds` | 关 | 跳过语音文件 |
| `--skip-so` | 关 | 跳过 `app_voicemail.so` 替换 |
| `--skip-agi` | 关 | 跳过叫醒电话 AGI 补丁 |
| `--skip-kvstore` | 关 | 跳过 KVStore 中文消息导入 |
| `--skip-dialplan` | 关 | 跳过 `extensions_custom.conf` 片段 |
| `--skip-settings` | 关 | 跳过 FreePBX 设置（时区/Soundlang） |
| `--no-reload` | 关 | 不做模块重载与 dialplan reload（不推荐） |
| `--dry-run` | 关 | 只打印，不落盘 |

### 3.2 推荐的分段安装（稳妥派）

```bash
# 第一段：只上语音（零风险，随时可回滚）
sudo bash install.sh --skip-so --skip-agi --skip-kvstore --skip-dialplan
  # → 先听 *98 语音信箱、*65 报分机号，确认音质与语序

# 第二段：上 dialplan 与叫醒电话
sudo bash install.sh --skip-sounds --skip-so

# 第三段：最后替换模块（会短暂卸载 app_voicemail）
sudo bash install.sh --skip-sounds --skip-agi --skip-kvstore --skip-dialplan
```

---

## 4. 分步详解

`install.sh` 共 9 步，每步都可独立失败、独立回退。

### 第 0 步 · 前置检查

**做什么**：校验 root、`asterisk` 命令、定位模块目录与语音目录、探测 FreePBX、校验包内文件齐备。

**怎么验证**：脚本会打印 OK/WARN。若出现
`定位不到 Asterisk 模块目录` → 手动指定：

```bash
AST_MOD_DIR=/usr/lib/x86_64-linux-gnu/asterisk/modules sudo -E bash install.sh
```

### 第 1 步 · 备份

**做什么**：把将被覆盖的东西全部复制到 `/root/zhpack-backup-<时间戳>/`：

```
sounds-cn/                原 cn 目录
sounds-custom/            原 custom 目录
app_voicemail.so.orig     原模块
agi-wakeup / agi-wakeglobal.php / hwagi-wakeup
extensions_custom.conf    原拨号方案
kvstore-message_zh_CN.sql 原 KVStore 中文消息
soundlang_settings.txt / soundlang_customlangs.txt / phptimezone.txt
ENV.txt                   环境快照（含原 .so 的 sha256）
```

**怎么验证**：`ls -la /root/zhpack-backup-*`；脚本同时把路径写入 `/tmp/zhpack-last-backup`，
供 `uninstall.sh` 自动定位。

### 第 2 步 · 语音文件

**做什么**：`sounds/cn/` → `/var/lib/asterisk/sounds/cn/`；`sounds/custom/` → `.../custom/`；
重建 `cn/custom` 软链接；建 `zh_CN -> cn`；`chown asterisk:asterisk`。

**怎么验证**：

```bash
find /var/lib/asterisk/sounds/cn -maxdepth 1 -name '*.wav' | wc -l     # ≈ 383
ls -la /var/lib/asterisk/sounds/cn/custom                              # 应为软链接
file /var/lib/asterisk/sounds/cn/vm-opts.wav                           # 16 bit, mono 8000 Hz
for k in vm-you vm-have vm-tong vm-haveno vm-listen press; do
  ls /var/lib/asterisk/sounds/cn/$k.wav >/dev/null 2>&1 || echo "缺 $k"
done
```

> `vm-you / vm-have / vm-tong / vm-haveno / vm-listen / press` 这 6 个是**中文语序引擎专用**音，
> 英文清单里没有。缺任何一个，`*97` 的整段 intro 会**变哑**。

### 第 3 步 · 替换 `app_voicemail.so`

**做什么**：校验包内 `.so` 的 `sha256`（应为 `206fc943…8dbd3`）→ 校验 ELF 架构 →
覆盖模块 → `module unload/load`。

**为什么**：上游 `vm_instructions_zh()` 在播完中文短菜单后**无条件** `return vm_instructions_en(...)`
（Asterisk 22.8.2 第 11151–11154 行）。结果：拨 `*97` **一个键都不按**，也会在中文菜单后
**无缝接一整套英文语序菜单**（`vm-advopts → vm-repeat → vm-next → vm-delete → vm-toforward →
vm-savemessage → vm-helpexit`，循环 ≤2 次后超时）。**这不是配置能关的**，只能改源码。

补丁把「无条件委派英文」改成「原地等按键 6 秒，重复超 2 次才超时退出」，见
`patches/app_voicemail-22.8.2-vm_instructions_zh.patch`。

**怎么验证**：

```bash
sha256sum /usr/lib/x86_64-linux-gnu/asterisk/modules/app_voicemail.so
  # 期望 206fc943c2473d241c9d0fed9333d2c58f641727a4d6063baa0d700f5483dbd3
asterisk -rx 'module show like app_voicemail'      # 应列出 app_voicemail.so
# 然后拨 *97 一个键都不按：应只播 1~12 段后静等，不再出现英文菜单
```

**失败了怎么办**（模块加载失败 = 业务中断，立刻回滚）：

```bash
cp -a /root/zhpack-backup-<ts>/app_voicemail.so.orig \
      /usr/lib/x86_64-linux-gnu/asterisk/modules/app_voicemail.so
asterisk -rx 'module unload app_voicemail.so'
asterisk -rx 'module load   app_voicemail.so'
asterisk -rx 'module show like app_voicemail'      # 确认恢复
```

### 第 4 步 · 叫醒电话 AGI 补丁

**做什么**：把补丁版 `wakeup`、`wakeglobal.php` 装到 `/var/lib/asterisk/agi-bin/`，
**同时**同步一份到模块目录 `/var/www/html/admin/modules/hotelwakeup/agi-bin/`。

**两处改动**：

| 文件 | 改动 | 解决什么 |
|---|---|---|
| `wakeup` | `wait_for_digit(1000)` → **`6000`** | 输 `2230` 时第 4 位常因按键间隔 >1s 被丢，导致掉进 12 小时制、再报「输入无效」 |
| `wakeglobal.php` | `init()` 里加 `set_variable('CHANNEL(language)','zh_CN')` | 让 AGI 侧也走中文（官方只有 `answer()`） |

**怎么验证**：

```bash
grep -n 'wait_for_digit' /var/lib/asterisk/agi-bin/wakeup        # 应为 6000
grep -n 'CHANNEL(language)' /var/lib/asterisk/agi-bin/wakeglobal.php
diff /var/lib/asterisk/agi-bin/wakeup /var/www/html/admin/modules/hotelwakeup/agi-bin/wakeup   # 应无差异
php -l /var/lib/asterisk/agi-bin/wakeup && php -l /var/lib/asterisk/agi-bin/wakeglobal.php
```

### 第 5 步 · KVStore 中文消息

**做什么**：导入 20 条 `message_zh_CN`（整句中文），覆盖 Hotel Wakeup 模块默认的**英文片段拼装**。

**为什么**：`*68` 的提示原本是 `please-enter-the` + `time` + `for` + `your` + `wakeup-call`
这类**英文单词片段**拼的，逐词直译成中文后语序崩坏。模块的 `getMessage($msg,$lang)`
会**优先读 KVStore 的 `message_<lang>`**，命中即整体替换 —— 于是**零代码**就能换成通顺整句。

**怎么验证**：

```bash
mysql -N -B asterisk -e "select count(*) from kvstore_FreePBX_modules_Hotelwakeup where id='message_zh_CN';"
  # 期望 >= 20
```

### 第 6 步 · 拨号方案片段

**做什么**：把 `config/extensions_custom.conf.snippet` 追加到 `/etc/asterisk/extensions_custom.conf`，
用 `# >>> asterisk-freepbx-chinese-pack BEGIN/END >>>` 标记包裹（**幂等**，重装会先替换旧块），
然后 `dialplan reload`。

**为什么**：FreePBX 自动生成的 `extensions_additional.conf` 里，`[sub-hr12format]` **只内置
en/fr/de/ja 四个分支，没有 zh**。`*60 → Gosub(sub-hr12format,s,1())` 在 zh_CN 下
`DIALPLAN_EXISTS` 判假 → 回退 en 分支 → 播出「听到提示音时…二点整 二十五分钟 和 十秒 秒 上午」。

而 `[sub-hr12format]` 顶部有 `include => sub-hr12format-custom`，且 `DIALPLAN_EXISTS()` **会遍历
include** → 所以只要补一个 `[sub-hr12format-custom]` + `exten => zh_CN,…` 就能接管 `*60`。

> ⚠ **只写 `extensions_custom.conf`**。`extensions_additional.conf` 会被 FreePBX Apply Config
> 重新生成覆盖，写那里会被冲掉。

片段里还包含一个自建的 `[custom-speakingclock-zh]`（循环报时上下文），可按需删掉。

**怎么验证**：

```bash
asterisk -rx 'dialplan show sub-hr12format-custom'   # 应看到 exten => zh_CN,1,...
grep -c 'asterisk-freepbx-chinese-pack' /etc/asterisk/extensions_custom.conf   # 应为 2（BEGIN + END）
```

### 第 7 步 · FreePBX 设置

**做什么**：

1. `fwconsole setting PHPTIMEZONE Asia/Hong_Kong`（若与 `date_default_timezone_get()` 不一致）
2. `soundlang_settings.language = zh_CN`
3. 注册 `soundlang_customlangs` 的 `zh_CN`

**怎么验证**：

```bash
php -r 'require "/etc/freepbx.conf"; echo date_default_timezone_get(), PHP_EOL;'   # Asia/Hong_Kong
mysql -N -B asterisk -e "select * from soundlang_settings; select * from soundlang_customlangs;"
```

### 第 8 步 · 安装后自检

脚本自动检查：cn 顶层 WAV 数量、`cn/custom` 软链接、WAV 格式、zh 专用 6 音、`.so` 的 sha256、
日志中 `does not exist` 条数。

### 第 9 步 · 输出验证指引

打印拨测清单与回滚命令。

---

## 5. 安装后完整验收清单

> 建议逐条打勾，全部通过才算安装成功。

### 5.1 文件层

| # | 检查 | 命令 | 期望 |
|---|---|---|---|
| 1 | cn 顶层 WAV 数 | `find /var/lib/asterisk/sounds/cn -maxdepth 1 -name '*.wav' \| wc -l` | ≈ 383 |
| 2 | cn 全量文件数 | `find /var/lib/asterisk/sounds/cn -type f \| wc -l` | ≈ 595 |
| 3 | custom WAV 数 | `ls /var/lib/asterisk/sounds/custom/*.wav \| wc -l` | ≥ 39 |
| 4 | `cn/custom` 软链接 | `readlink /var/lib/asterisk/sounds/cn/custom` | `/var/lib/asterisk/sounds/custom` |
| 5 | `zh_CN` 软链接 | `readlink /var/lib/asterisk/sounds/zh_CN` | `/var/lib/asterisk/sounds/cn` |
| 6 | WAV 格式 | `file .../cn/vm-opts.wav` | `16 bit, mono 8000 Hz` |
| 7 | zh 专用 6 音 | 见 [第 2 步](#第-2-步--语音文件) | 全在 |
| 8 | 属主 | `ls -la .../sounds/cn \| head -3` | `asterisk asterisk` |

### 5.2 模块层

| # | 检查 | 命令 | 期望 |
|---|---|---|---|
| 9 | `.so` 校验 | `sha256sum /usr/lib/.../modules/app_voicemail.so` | `206fc943…8dbd3` |
| 10 | 模块已加载 | `asterisk -rx 'module show like app_voicemail'` | 有输出且非 `Not Running` |
| 11 | glibc 兼容 | `readelf -V .../app_voicemail.so \| grep -oE 'GLIBC_[0-9.]+' \| sort -uV \| tail -1` | ≤ 目标机 glibc |

### 5.3 播报层（真实拨测，最重要）

| # | 操作 | 期望听感 |
|---|---|---|
| 12 | 拨 `*97`，**不按键** | 中文：`您有 N 条新留言…（1~12 段）` → 静等按键。**不应**再听到英文菜单 |
| 13 | 拨 `*97` → 按 `1` | `第一条留言`（不再说「第一留言」） |
| 14 | 拨 `*98` | 中文操作提示 |
| 15 | 拨 `*60` | 「北京时间 上午/下午 X 点 X 分 X 秒 / 整」 |
| 16 | 拨 `*68` → 按 `1` → 输 `2230` | 「已为您设置叫醒电话，时间是 下午十点三十分」，**不报输入无效** |
| 17 | 拨 `*68` → 按 `2` | 中文列表播报，含时间 |
| 18 | 拨 `*65` | 「您的分机号是 …」 |

### 5.4 日志层

```bash
# 全部播报均以 .slin 解析（= 我们的中文 WAV）；出现 .sln16/.ulaw/.g722 = 回退到英文音
grep -a "Playing '" /var/log/asterisk/full | tail -40

# 缺音检查
grep -a 'does not exist' /var/log/asterisk/full | tail -20
# 期望 0 条
```

> **★ 判读速查**：`Playing 'xxx.slin'` → **中文音**（我们的 WAV）；
> `Playing 'xxx.sln16' / '.ulaw' / '.alaw' / '.g722'` → **官方英文音（回退）**。不用听就能判中/英。

### 5.5 叫醒排程层（★ 极易漏）

```bash
# 设一个 22:30 的叫醒，然后看落点
stat -c '%y %n' /var/spool/asterisk/outgoing/wuc.*.call
# mtime 必须等于你设定的挂钟时间；若差 8 小时 → PHPTIMEZONE 没设对
```

---

## 6. 回滚（三种粒度）

### 6.1 一键全回滚

```bash
sudo bash uninstall.sh                 # 自动找最近一次备份
sudo bash uninstall.sh --from /root/zhpack-backup-20260924-140000   # 指定备份
sudo bash uninstall.sh --list          # 列出所有可用备份
sudo bash uninstall.sh --keep-sounds   # 只回滚代码/配置，保留语音文件
sudo bash uninstall.sh --dry-run
```

回滚覆盖：语音目录、`custom` 目录、`app_voicemail.so.orig`、三个 AGI 文件、KVStore、拨号方案。

> **不会**自动回滚 `PHPTIMEZONE` —— 因为保留 `Asia/Hong_Kong` 才是对的，回到 `UTC` 反而会让
> 叫醒电话偏 8 小时。脚本会在结尾提示安装前的值，需要时自己决定。

### 6.4 语音覆盖度（实测基线）

以 `en/core-sounds-en-g722.txt` 的索引条目为权威集合逐条比对：

| 项 | 数量 |
|---|---|
| `core-sounds` 索引条目 | **564** |
| `cn/` 已覆盖 | **563** |
| `cn/` 未覆盖 | 1（`astcc-followed-by-pound`） |
| `cn/` 总 WAV 文件数 | 593（含 383 顶层 + digits/letters/phonetic/dictate/silence/followme） |

> 那"1 条未覆盖"是**上游索引的陈旧键**：`en` 索引写的是 `astcc-followed-by-pound`，
> 而磁盘上真实文件是 `astcc-followed-by-the-pound-key`（我们**已译**）。
> 所以按磁盘真实文件算，**核心集 100% 覆盖**。
>
> `en/` 目录共 1910 个键 —— 多出来的 1300 余条属于 **`asterisk-extra-sounds`**
> （天气 `wx/*`、家居 `ha/*`、美国各州/城市、笑话音等），**本包未翻译**，
> 只按需补了叫醒电话用到的 28 条。见 [第 9 节](#9-本次未覆盖事项)。

### 6.2 只退模块（最快的急救）

```bash
cp -a /root/zhpack-backup-<ts>/app_voicemail.so.orig \
      /usr/lib/x86_64-linux-gnu/asterisk/modules/app_voicemail.so
asterisk -rx 'module unload app_voicemail.so'
asterisk -rx 'module load   app_voicemail.so'
```

### 6.3 只退某个单项

| 想退什么 | 怎么做 |
|---|---|
| 单个语音 | 从 `backup/sounds-cn/<key>.wav` 拷回，或重新用 `edge-tts` 生成 |
| 叫醒电话中文消息 | `mysql asterisk -e "delete from kvstore_FreePBX_modules_Hotelwakeup where id='message_zh_CN';"` |
| `*60` 中文报时 | 从 `extensions_custom.conf` 删掉托管块 → `asterisk -rx 'dialplan reload'` |
| 时区 | `fwconsole setting PHPTIMEZONE UTC`（⚠ 会让叫醒偏 8 小时） |

---

## 7. 故障排查：按症状查表

| 症状 | 最可能原因 | 处置 |
|---|---|---|
| 拨 `*97` 整段**没声音**（或只有部分） | 缺 zh 专用 6 音（`vm-you/vm-have/vm-tong/vm-haveno/vm-listen/press`） | 检查第 2 步的 6 音；`grep 'does not exist' /var/log/asterisk/full` |
| 说成「**您有三新的和一条旧留言**」 | 通道 language = `cn`（不是 `zh_CN`） | 见 [2.1](#21-语言代码必须用-zh_cn绝不能用-cn) / [2.2](#22-语言有**两处**源头改一处不够) |
| 全局设了 zh_CN，**某个分机**仍英文 | 分机级覆盖（Languages 模块 / AstDB） | `asterisk -rx 'database show' \| grep -i language`；GUI 里清掉该分机语言 |
| `*60` 读到「…二点整 二十五分钟 和 十秒」 | `sub-hr12format-custom` 未生效 | `asterisk -rx 'dialplan show sub-hr12format-custom'`；确认 `extensions_custom.conf` 有托管块 |
| `*60` / `*68` 播 `custom/xxx` **变哑** | `cn/custom` 软链接丢了 | `ln -sfn /var/lib/asterisk/sounds/custom /var/lib/asterisk/sounds/cn/custom` |
| `*68` 输入 `2230` 报「**输入无效**」 | AGI 第 4 位丢失 | 确认 `wait_for_digit(6000)`；`diff` live 与模块目录两份 |
| `*68` 提示是**英文单词拼装** | KVStore 没有 `message_zh_CN` | 见 [第 5 步](#第-5-步--kvstore-中文消息) |
| 叫醒**偏 8 小时 / 到点不响** | `PHPTIMEZONE` 与系统不一致 | 见 [2.6](#26-判断-freepbx-时区必须带引导查-php)；`stat -c '%y' /var/spool/asterisk/outgoing/wuc.*.call` 核对 |
| `app_voicemail.so` **加载失败** | glibc 不匹配 / Asterisk 版本不符 | 见 [2.4](#24-app_voicemailso-必须在-glibc--目标机的环境里编译)；立即用 [6.2](#62-只退模块最快的急救) 回退 |
| 换了模块**完全没变化** | 用了 `module reload` | 必须 `module unload` + `module load` |
| 播的都是英文音 | 文件没落到 `/var/lib/asterisk/sounds/cn/`，或语言目录名不符 | 看日志 `Playing 'xxx.sln16'` 后缀；检查 `soundlang_settings.language` |
| 重装后仍听旧音 | 播报链路走的是缓存/别名路径 | 确认改的是 `cn/`（`zh_CN` 是软链接，写哪都一样，但别只改 `zh_CN` 之外的副本） |

### 7.1 万能诊断三连

```bash
# ① 日志判中/英（.slin=中文音，.sln16=英文回退）
asterisk -rx 'core set verbose 5'; grep -a "Playing '" /var/log/asterisk/full | tail -30

# ② 缺音
grep -a 'does not exist' /var/log/asterisk/full | tail -20

# ③ 实际生效的语言（全局 + 逐分机）
mysql -N -B asterisk -e "select * from soundlang_settings;"
awk '/^\[/{ep=$0} /^language=/{print ep" -> "$0}' /etc/asterisk/pjsip.endpoint.conf
```

---

## 8. 已知坑与长期注意事项

| # | 坑 | 影响 | 对策 |
|---|---|---|---|
| 1 | `fwconsole ma upgrade hotelwakeup` 会**覆盖模块目录里的 AGI** | `wait_for_digit` 补丁与 language hack 被冲掉 | 升级后重跑 `install.sh --skip-sounds --skip-so --skip-kvstore --skip-dialplan --skip-settings`；**KVStore 的 `message_zh_CN` 在独立表，不受影响** |
| 2 | FreePBX **Apply Config** 会重新生成 `extensions_additional.conf` | 写在那里的内容会被冲掉 | 我们只写 `extensions_custom.conf`（安全）+ `[sub-hr12format-custom]` 机制 |
| 3 | Asterisk 升级会替换 `app_voicemail.so` | 补丁失效，英文菜单回归 | 升级后按 `build/` 脚本对新版本重编；或暂用 `--skip-so` 只保留其余部分 |
| 4 | `say.c` 里 `digits/oclock`、`minute(s)` 是**音名硬编码** | 报时里出现「点整」「分钟」很不自然 | 本包已替换 `cn/digits/oclock.wav` → 「点」、`cn/minute(s).wav` → 「分」 |
| 5 | `SayUnixTime` 的格式串 `IMpABd` 会把上下午放后 | 读成「…十点三十分 下午」 | 改为 **`pIM`**（上下午必须在最前） |
| 6 | 测试 `addWakeup` 会**真写** call 文件 | 产生幽灵叫醒 | `ls /var/spool/asterisk/outgoing/wuc.*.call` 清理自己造的；别误删用户真实叫醒 |
| 7 | 上游 `core-sounds-en` 索引里 6 个 `followme/*` 键**自带 `.wav` 后缀**（如 `followme/sorry.wav: sorry`） | 键名与实际文件名（`followme/sorry`）不一致 | 这是**官方索引的写法**，不是我们的错。`core-sounds-cn.txt` 沿用同样写法保持一致；实际文件按无后缀命名，不影响播放 |
| 8 | `soundlang_packages` 里**没有** zh_CN | Soundlang 的「安装语言包」列表里找不到中文 | 本包走 **Custom Language** 路线，不依赖官方包列表 |
| 9 | 本机 SSH 登录 banner 会污染 `scp` / `ssh 'cat x' > f` | 传输文件损坏（`Received message too long`、文件头被污染） | 用 `base64 -w0` + 起止标记，或 `tar over ssh`；传完校验 `md5sum`/`ffprobe` |
| 10 | `digits/day` 在**英文包里也不存在**（`en/` 只有 `digits/day-0`…`day-6` 星期名） | 日志偶现 `file.c: File digits/day does not exist in any format` | **上游版本漂移，非本包引入**。影响面极小（单条提示静音）；如要补，用 `edge-tts` 造 `cn/digits/day.wav` 即可 |
| 11 | 日志里大量 `db.c: AstDB key ... does not exist` | 看着像"缺一堆东西" | 那是 FreePBX 探测**可选** AstDB 键的正常告警，与语音无关。自检脚本已只统计 `file.c: File` 类 |
| 12 | 每跑一次 `install.sh` 都会新建一个 `/root/zhpack-backup-<时间戳>/`（约 23MB） | 反复调试会堆积备份 | 每次约 23MB；确认没问题后留最新一个即可：`ls -dt /root/zhpack-backup-* \| tail -n +2 \| xargs rm -rf` |

---

## 9. 本次未覆盖事项

> 这些**没做**或**没验证**，如实列出，便于下一位接手。

1. **`asterisk-extra-sounds` 未翻译**：`en/` 目录共 1910 个键，`core-sounds` 只有 564 个 ——
   其余 1300 余条属 extra-sounds（天气 `wx/*`、家居自动化 `ha/*`、美国各州/城市、
   笑话/彩蛋音、会议控制等）。**本包只按需补了叫醒电话用到的 28 条 + 报时 11 条**，
   也就是说凡是调用 extra-sounds 的功能（`app_weather`、`app_voicemail` 的部分提示、
   `app_conference` 等）在中文下会**回退英文或静音**。
   - 自测方法：`grep -a "Playing '" /var/log/asterisk/full | grep -v '\.slin'` —— 出现 `.sln16/.ulaw/.g722` 即回退。
   - 补齐方法：把缺的键名丢给 `asterisk-tts-zh` skill 批量生成（见该 skill 的 `batch` 子命令）。
2. **`zh_TW` / `zh_HK`**：目录名与语言码未做（本包只做 `zh_CN`）。Asterisk 的 `zh_TW` 语序引擎分支是否完备未验证。
3. **`.sln16` / `.ulaw` / `.alaw` / `.g722` 多编码**：本包只发 WAV（`slin`）。Soundlang 的
   `formats` 设为 `g722,ulaw`，若你的环境强制 g722/ulaw 更省带宽，需要另转一套（WAV 仍可用，
   Asterisk 会自行转码，仅占少量 CPU）。
4. **`digits/day`**：上游英文包也缺这个音（见 [第 8 节](#8-已知坑与长期注意事项) 第 10 条），未补。
5. **`sub-hr24format`**：24 小时制报时未接（本机无调用点）。机制相同，照 `sub-hr12format-custom` 抄即可。
6. **`*61` 自建报时**：片段里的 `[custom-speakingclock-zh]` 是自建循环报时，仍读「二点」而非「两点」
   （`zh-liang` 只用在 `*60` 路径上）。
7. **其他 FreePBX 模块的中文提示**：Conference、Queue、Directory、Blacklist、Follow Me 等模块
   的提示未逐一校对，可能有英文回退。
8. **非 x86_64 架构**：未提供 arm64 的 `app_voicemail.so`。
9. **回滚不覆盖 `PHPTIMEZONE`**：刻意如此（见 [6.1](#61-一键全回滚)）。
10. **未做自动化播测脚本**：验收清单（第 5 节）目前靠人工拨打。后续可加一个基于 AGI 桩的自动化拨测。
11. **`.so` 只验证了一台机器**：仅在本项目的 FreePBX 17.0.30 + Asterisk 22.8.2 上真机验证过；
    其他同版本环境属于"应当可用但未实测"。
12. **`hw-*` 语音的响铃路径未回归**：到点响铃后的贪睡菜单（`wakeConfirmMenu`）此前用 AGI 桩验证过，
    本版未重新回归。
