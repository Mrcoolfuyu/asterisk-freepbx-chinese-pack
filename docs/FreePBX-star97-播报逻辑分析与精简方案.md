# FreePBX `*97` 播报逻辑分析 与「去掉冗余英文菜单」方案

> 服务器：FreePBX 17 / Asterisk **22.8.2**（Debian 12，模块 `/lib/x86_64-linux-gnu/asterisk/modules/app_voicemail.so`）
> 分机语言：`zh_CN`（端点 + AstDB 均为 zh_CN）
> 结论时间：2026-09-24

---

## 一、结论速览

| 问题 | 结论 |
|---|---|
| `*97` 登录后为何多播 13–19 段？ | `vm_instructions_zh()` 播完 `vm-opts` 后**无条件** `return vm_instructions_en(...)`，把 `vms->starting` 清零，随后 6 条逐条菜单由**英文语序引擎** `vm_instructions_en()` 播出 |
| 是提示音缺失 / 语言配错吗？ | **不是**。`zh_CN` 已生效（`vm-you`/`vm-haveno`/`vm-listen` 等 zh 专有音全部播出即铁证） |
| 是配置能关掉吗？ | **不能**。`voicemail.conf` / FreePBX GUI 无任何开关（`skipms`、`skip instructions` 只作用于**录制留言**，不作用于信箱菜单） |
| 上游会修吗？ | **不会**。Asterisk `master` 分支 2026-09 仍是同一段代码（已实测下载比对） |
| 怎么办？ | 打一个 **5 行补丁**重编 `app_voicemail.so`（方案 A，推荐）；或退而改写 7 条文案（方案 B，零风险但不满足"不播"） |

**一句话**：这不是"配错了"，是 Asterisk 中文（台湾）本地化**只做了半套** —— 只本地化了 `intro` + 一级菜单摘要，逐条菜单直接`复用英文语序引擎`。

---

## 二、完整播报链路（源码级，Asterisk 22.8.2）

### 2.1 主流程（`apps/app_voicemail.c`）

```
VoiceMailMain()
 └─ vm_authenticate()                       // 验证分机+密码
     └─ cmd = vm_intro(chan, vmu, &vms)     // 12693  ← 播 1~6
         └─ vm_intro()(10881) 按语言分发
             └─ vm_intro_zh()(10812)        // lang="zh*" → 中文 intro
     vms.starting = 1;                       // 12699  ★关键状态位
     while (cmd > -1 && cmd != 't' && cmd != '#') {   // 主菜单循环
         switch (cmd) {
         ...
         default:                            // 13171  ← 首轮 cmd=0 落这里
             cmd = vm_instructions(chan, vmu, &vms, 0, in_urgent, nodelete);
         }
     }
```

### 2.2 `vm_instructions()` 的语言分发（11159）

```c
static int vm_instructions(chan, vmu, vms, skipadvanced, in_urgent, nodelete)
{
    if   (!strncasecmp(ast_channel_language(chan), "ja", 2))  return vm_instructions_ja(...);  // 日语：完整分支
    else if (vms->starting && !strncasecmp(..., "zh", 2))     return vm_instructions_zh(...);  // ★ 仅"首次"
    else                                                      return vm_instructions_en(...);  // 其余全部 → 英文引擎
}
```

### 2.3 `vm_instructions_zh()`（11135）—— 问题就在最后 3 行

```c
static int vm_instructions_zh(...)
{
    int res = 0;
    while (!res) {
        if (vms->lastmsg > -1) {                    // 有留言时
            res = ast_play_and_wait(chan, "vm-listen");
            if (!res) res = vm_play_folder_name(chan, vms->vmbox);
            if (!res) res = ast_play_and_wait(chan, "press");
            if (!res) res = ast_play_and_wait(chan, "digits/1");
        }
        if (!res) res = ast_play_and_wait(chan, "vm-opts");
        if (!res) {
            vms->starting = 0;                      // ★ 把"首次"标志清掉
            return vm_instructions_en(chan, vmu, vms, skipadvanced, in_urgent, nodelete);
        }                                           // ★ 无条件委派给英文引擎，不等按键
    }
    return res;
}
```

### 2.4 `vm_instructions_en()`（10949）—— 委派进来后走的是 `else`（非首次）分支

```c
while (!res) {
    if (vms->starting) { ... }                      // zh 已把它清 0 → 跳过
    else {
        if (vms->curmsg || (!in_urgent && vms->urgentmessages > 0) || (VM_MESSAGEWRAP && vms->lastmsg > 0))
            res = ast_play_and_wait(chan, "vm-prev");          // 登录时不播（curmsg=0,无紧急留言）
        if (!res && !skipadvanced) res = ast_play_and_wait(chan, "vm-advopts");
        if (!res) res = ast_play_and_wait(chan, "vm-repeat");
        if (!res && (vms->curmsg != vms->lastmsg || ...)) res = ast_play_and_wait(chan, "vm-next");
        if (!res) { ... vm-delete / vm-undelete ... }
        if (!res) res = ast_play_and_wait(chan, "vm-toforward");
        if (!res) res = ast_play_and_wait(chan, "vm-savemessage");
    }
    if (!res) res = ast_play_and_wait(chan, "vm-helpexit");
    if (!res) res = ast_waitfordigit(chan, 6000);
    if (!res) { vms->repeats++; if (vms->repeats > 2) res = 't'; }   // 超时→菜单最多重播 2 次→挂断
}
```

### 2.5 落到你的编号上

| 段 | 来源函数 | 提示音 |
|---|---|---|
| 1–6 | `vm_intro_zh` | `vm-you` `vm-have` `digits/N` `vm-tong` `vm-Old` `vm-messages` → 「您有N条旧留言」 |
| 7–11 | `vm_instructions_zh` 上半段 | `vm-listen` + 文件夹名 + `press` + `digits/1` → 「收听旧留言请按一」 |
| 12 | `vm_instructions_zh` 末句 | `vm-opts` → 「更改文件夹请按2，高级选项请按3，其它语音信箱选项请按0。」 |
| **13** | **`vm_instructions_en`** | **`vm-advopts`** |
| **14** | **`vm_instructions_en`** | **`vm-repeat`** |
| **15** | **`vm_instructions_en`** | **`vm-next`** |
| **16** | **`vm_instructions_en`** | **`vm-delete`** |
| **17** | **`vm_instructions_en`** | **`vm-toforward`** |
| **18** | **`vm_instructions_en`** | **`vm-savemessage`** |
| **19** | **`vm_instructions_en`** | **`vm-helpexit`** |

→ **你的判断完全正确**：逻辑上 1–12 播完就该等按键，13–19 是被上游代码硬塞进来的。

### 2.6 对照：同样被"半套本地化"的还有

`vm_browse_messages()`（11728）读留言时同理 —— zh 只有 `vm_browse_messages_zh`（11540 附近），**播放留言后**主循环回 `default`，此时 `vms->starting` 已被 `play_message()`（9323 行）清 0 → 又落到 `vm_instructions_en`。所以**听完一条留言后的「5 重听 / 6 下一条 / 7 删除 …」菜单也是英文语序**（内容虽是中文）。

对比 `vm_instructions_ja()`（11039）：日语**自己实现了 `starting` 与 `else` 两个分支**、不委派，所以日语没这个毛病。这正是"中文该打补丁"的参照物。

---

## 三、方案 A（推荐，根治）：打补丁重编 `app_voicemail.so`

### 3.1 补丁内容（`apps/app_voicemail.c`，`vm_instructions_zh` 函数尾部）

把"无条件委派给英文引擎"改成"原地等按键"：

```diff
--- a/apps/app_voicemail.c
+++ b/apps/app_voicemail.c
@@ static int vm_instructions_zh(...)
         if (!res)
             res = ast_play_and_wait(chan, "vm-opts");
-        if (!res) {
-            vms->starting = 0;
-            return vm_instructions_en(chan, vmu, vms, skipadvanced, in_urgent, nodelete);
-        }
+        if (!res)
+            res = ast_waitfordigit(chan, 6000);
+        if (!res) {
+            vms->repeats++;
+            if (vms->repeats > 2) {
+                res = 't';
+            }
+        }
     }
+    vms->starting = 0;
     return res;
 }
```

**效果**：`*97` 登录后只播 1–12，然后静默等待按键（60 秒 ×3 次超时后挂断，与英文行为一致）；听完留言后的逐条菜单仍走 `vm_instructions_en`（不受影响）。

### 3.2 可选进阶（同一次编译一起做）：`vm_instructions_zh` 全中文语序

若想让"听完留言"的菜单也是中文语序，把上面补丁换成 A2 版：

1. `vm_instructions()` 里去掉落 `vms->starting &&` 条件，让 **zh 一律走中文分支**；
2. 把 `vm_instructions_zh()` 补齐 `if (vms->starting) {…一级菜单…} else {…逐条菜单，中文顺序：vm-prev→vm-advopts→vm-repeat→vm-next→vm-delete→vm-toforward→vm-savemessage→vm-helpexit…}`，结构与 `vm_instructions_ja()` 相同。

所需中文提示音**已全部就绪**（`vm-prev`=收听上一条留言请按4、`vm-advopts`=高级选项请按3、`vm-repeat`/`vm-next`/`vm-delete`/`vm-toforward`/`vm-savemessage`/`vm-helpexit` 均已生成），无需补音。

### 3.3 构建步骤（在本机取源码 → 中转 → 服务器编译）

> 服务器国际出口受限（`downloads.asterisk.org` 可能超时），源码在**本机**下载再传过去。

```bash
# ── 服务器 A：装编译依赖（走 USTC 镜像，已确认可达）
apt-get update && apt-get install -y build-essential pkg-config \
  libedit-dev libssl-dev libxml2-dev libsqlite3-dev uuid-dev \
  libjansson-dev libcurl4-openssl-dev libncurses-dev libxslt1-dev

# ── 本机 B：下载与运行版本严格一致的源码（22.8.2）
curl -LO https://downloads.asterisk.org/pub/telephony/asterisk/asterisk-22.8.2.tar.gz
scp asterisk-22.8.2.tar.gz root@192.168.50.15:/usr/src/

# ── 服务器 C：解包、打补丁、编译
cd /usr/src && tar xzf asterisk-22.8.2.tar.gz && cd asterisk-22.8.2
# 应用 3.1 的补丁（vim apps/app_voicemail.c）
./configure
make menuselect.makeopts
grep -c "app_voicemail" menuselect.makeopts     # 确认 >=1（默认已选中）
make -j2                                        # 2 核，约 20–40 分钟

# ── 服务器 D：备份 → 替换 → 重启
cp -a /lib/x86_64-linux-gnu/asterisk/modules/app_voicemail.so \
      /root/app_voicemail.so.bak-$(date +%Y%m%d-%H%M%S)
install -m 644 apps/app_voicemail.so \
      /lib/x86_64-linux-gnu/asterisk/modules/app_voicemail.so
fwconsole restart                               # 或 systemctl restart asterisk
```

### 3.4 风险评估

| 项 | 评估 |
|---|---|
| ABI 兼容 | **低风险**。源码版本与运行版本完全一致；已核实官方 `app_voicemail.so` 内 **无 IMAP / ODBC 字符串**（`strings \| grep -ci imap/odbc` 均为 0）→ 官方就是"裸构建"，我们用默认 `./configure` 即可对齐 |
| 磁盘 | 19G 总 / **6.6G 可用**，源码 + 编译产物约 1–2G，够用但建议先清理 `apt-get clean` |
| CPU/耗时 | 2 核，`make -j2` 约 20–40 分钟 |
| 业务影响 | 需重启 Asterisk（**中断当前通话，约 10–20 秒**），建议低峰执行 |
| 回滚 | 保留 `.so` 备份 + `/var/spool/asterisk/voicemail` 快照，重启即回到现状 |

---

## 四、方案 B（零风险折中，不用编译）：把 7 条改写成连贯中文

接受 13–19 会播出，但把文案写成**连读自然**的中文补充菜单（按 `core-sounds-cn.txt` 改后重生成即可）。示意：

| 提示音 | 建议文案 | 连读效果 |
|---|---|---|
| `vm-advopts` | 收听留言时， | 作连接词 |
| `vm-repeat` | 按5重新听该留言， | |
| `vm-next` | 按6收听下一条， | |
| `vm-delete` | 按7删除该留言， | |
| `vm-toforward` | 按8转交该留言， | |
| `vm-savemessage` | 按9保存该留言， | |
| `vm-helpexit` | 按星号键请求帮助，按井号键退出。 | |

**代价**：仍是"多一段"，只是内容对了、语序顺了；且 `vm-next` 是**条件播放**（只有 1 条留言时不播），连读会有断裂。**不满足你"13–19 不播"的诉求**。

---

## 五、方案 C（不推荐）：把这 7 个音频"静音化"

把 `vm-advopts/vm-repeat/vm-next/vm-delete/vm-toforward/vm-savemessage/vm-helpexit` 换成极短静音文件。
- 登录后：静默约 18 秒（3×6s 超时）后挂断；
- **副作用致命**：这 7 个文件**同样被"听完留言"的逐条菜单使用**（同一套文件），会一起变哑 → 用户听完留言后完全失去按键指引。

**结论：可判定为不可接受。**

---

## 六、环境事实（本次核实）

| 项 | 值 |
|---|---|
| Asterisk | 22.8.2（`asterisk22-voicemail 22.8.2-1.sng12`） |
| 模块路径 | `/lib/x86_64-linux-gnu/asterisk/modules/app_voicemail.so` |
| 官方模块构建特征 | 无 IMAP、无 ODBC（默认构建） |
| 编译工具 | gcc / make 已具备；无 asterisk 头文件、无源码树 |
| 包源 | USTC Debian 12 镜像可达；Sangoma 源已移除（**无法 `apt-get source`**） |
| 上游状态 | `master` 分支 2026-09 仍是同一段委派代码，**未修复** |

---

## 七、本次同步的提示音（vm-first / vm-last）

| 提示音 | 新文案 | 服务器 MD5 | 备份 |
|---|---|---|---|
| `vm-first` | 第一条 | `4d93d6742b91df21c6c08c6754073996` | `/root/wavbak-20260924-014307/` |
| `vm-last` | 最后一条 | `1503741011453c307c64aa8bcd4b46cc` | 同上 |

`core-sounds-cn.txt` 第 315/334 行已同步（`vm-first:第一条`、`vm-last:最后一条`）。

---

## 十三、方案 A 执行记录：WSL 内 Debian 12 chroot 交叉编译 + 热替换上线（2026-09-24）

**用户约束**：不要在生产 FreePBX 上编译，改用本机 WSL 编好再上传。

### 13.1 为什么要先造 chroot（关键决策）

| | 本机 WSL | 目标机 |
|---|---|---|
| 系统 | Ubuntu 24.04.3 | Debian 12 (bookworm) |
| glibc | **2.39** | **2.36-9+deb12u14** |

直接用 Ubuntu 24.04 编译会把 `GLIBC_2.38+` 符号（典型 `strlcpy`）带进模块，拷过去 dlopen 直接失败。
故在 WSL 内用 `debootstrap` 造了一个 **Debian 12 chroot**（`/opt/deb12`），glibc 与目标机完全同版。

### 13.2 编译

- 源码取自官方 **releases 子目录**（★ 顶层目录只放最新版，写死版本号会 404）：
  `https://downloads.asterisk.org/pub/telephony/asterisk/releases/asterisk-22.8.2.tar.gz`
  解包后 `apps/app_voicemail.c` 的 md5 = `67a97b4d843fe8c4e0e51ba13ee31723`，与先前反编译分析的版本**完全一致**。
- 补丁：`vm_instructions_zh` 尾部「无条件委派」→「原地等按键」（python 精确串替换，命中数断言 = 1）。
  ★ **不补** `vms->starting = 0;`（否则登录后按 `*` 会掉回英文语序菜单；`vm_instructions_ja` 同样从不清理该标志）。
- `./configure --without-pjproject-bundled --without-imap --without-unixodbc --without-iodbc`
  `&& make menuselect.makeopts && make -j12` → 约 **1 分 20 秒**。
  关掉 bundled pjproject 是必须的，否则 make 会去下载并编译一份 pjproject（与本模块无关，纯浪费时间）。

### 13.3 产物自检（三道，缺一都可能"拷过去加载失败"）

| 项 | 结果 |
|---|---|
| `file` | ELF 64-bit LSB shared object, x86-64 ✅ |
| `readelf -V` 最高符号版本 | **GLIBC_2.34**（≤ 目标机 2.36）✅ |
| `readelf -d` NEEDED | **仅 `libc.so.6`**，与官方模块完全一致 ✅ |
| 补丁验证 | `objdump -d --disassemble=vm_instructions_zh` 内 `vm_instructions_en` 引用数 = **0** ✅ |
| 体积 | `strip --strip-debug` 后 306,576 B（官方 335,144 B）|
| sha256 | `206fc943c2473d241c9d0fed9333d2c58f641727a4d6063baa0d700f5483dbd3` |

> 新版 `strings` 比官方多 2/1 条 imap/odbc 字样，经核为**内嵌 XML 帮助文档**（`VM_ODBC_AUDIO_ON_DISK`、`LIBCURL_PROTOCOL_IMAP`）；
> 官方包应是用 `--disable-xmldoc` 编的才没有这些串，与运行逻辑无关。

### 13.4 上线

- 备份：`/root/sobak/app_voicemail.so.orig-20260924-021255`（335,144 B，sha256 `f72f7d07…1dd65b`）
- 替换：`install -m 644 -o root -g root`，两端 sha256 双向核对一致
- 生效：`module unload app_voicemail.so` → `module load app_voicemail.so`（**未重启 Asterisk，零中断**）

### 13.5 拨测（8514，零按键）

```
vm-you vm-have digits/2 vm-tong vm-Old vm-messages            ← 1–6「您有二条旧留言」
vm-listen vm-Old vm-messages press digits/1 vm-opts            ← 7–12「收听旧留言请按一 / 更改文件夹请按2，高级选项请按3…」
（6 秒无按键 → 重播 7–12，最多 3 轮后超时挂断）
```

**13–19 段全部消失**（`vm-advopts` / `vm-repeat` / `vm-next` / `vm-delete` / `vm-toforward` / `vm-savemessage` / `vm-helpexit`），
`does not exist` 计数 = 0。**方案 A 目标达成。**

测试用临时拨测上下文已回滚（`/root/extensions_custom.conf.bak-20260924-021326`）。

> 行为细节：6 秒无按键会**重播中文短菜单**（与上游 en/ja 行为一致），属预期；若希望"只播一遍就静默等待"，
> 可把 `ast_waitfordigit(6000)` 加长或把 repeats 上限调小，需再编一次。
