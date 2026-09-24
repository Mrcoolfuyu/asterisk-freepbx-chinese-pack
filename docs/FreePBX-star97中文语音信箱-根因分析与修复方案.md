# FreePBX *97 / *98 语音信箱「生硬直译」根因核实与修复方案（v2）

- 目标机：FreePBX **17.0.30** / Asterisk **22.8.2**（192.168.50.15，ssh root）
- 核实时间：2026-09-23
- 相较 v1 的变更：**① 修正 `sounds/zh_CN` 的性质（软链接）；② 定位语言设置的真正来源（Soundlang，一处生效）；③ 补全「听完留言后」的整条菜单链审计；④ 把「必须改写的提示音」从 5 个缩减为 2 个（有据）**

---

## 零、结论（TL;DR）

**根因不是翻译质量，是「语言代码不是中文」。**

Asterisk 内置**中文语序引擎**（`vm_intro_zh` / `vm_instructions_zh` / `vm_browse_messages_zh` / 信封中文日期格式），
只在 channel language **以 `zh` 开头**时才启用。而系统设的是 **`cn`** → `strncasecmp("cn","zh",2)` 不匹配
→ 走**英文语序**分支，把英文语序的片段直译后硬拼。

**修复 = ①语言改 `zh_CN`（改一处 Soundlang 设置即可）＋ ②补 6 个 zh 专有提示音 ＋ ③改 2 个提示音文案 ＋ ④修若干纯文案硬伤。**

---

## 一、核实项 ①：`sounds/zh_CN` 其实是指向 `sounds/cn` 的软链接

```
$ ls -la /var/lib/asterisk/sounds/ | grep -- '->'
lrwxrwxrwx 1 root root 27 Jul  2 00:51 zh_CN -> /var/lib/asterisk/sounds/cn      ← 软链接
lrwxrwxrwx 1 asterisk asterisk 59 ... silence-30.gsm -> .../broadcast/sounds/...
lrwxrwxrwx 1 asterisk asterisk 58 ... silence-5.gsm  -> .../broadcast/sounds/...
```

**由此推出的四条结论（很重要）：**

| # | 结论 | 说明 |
|---|---|---|
| 1 | 切到 `zh_CN` 后，提示音**依然从 `cn/` 读** | 不会因为「换了个目录」而丢文件 |
| 2 | 往 `zh_CN/` 写文件 = 往 `cn/` 写文件 | 两者**永远同一份**，不需要"保持镜像同步" |
| 3 | v1 报告里 `diff -rq cn zh_CN` 无输出的"字节级一致"是**假象** | 同一个目录跟自己比，当然无差异 —— 该结论作废 |
| 4 | 「语言切成 `zh_CN` 会变哑」这个**风险依然成立** | 因为 6 个 zh 专有提示音在 `en/` 里也没有，回退救不回来（详见第三节） |

---

## 二、核实项 ②：`language=cn` 的真正来源 = **Soundlang 设置**（不是逐个分机）

### 现象
```
/etc/asterisk/pjsip.endpoint.conf        : 6 处 language=cn  （8633 / 2201 / 2202×2 / 8514 / Chinatelecom_IMS）
/etc/asterisk/sip_general_additional.conf: 13: language=cn
/etc/asterisk/iax_general_additional.conf: 11: language=cn
```
三份文件 mtime 都等于上次 Apply Config 时间 → 都是**自动生成**的，说明来源在数据库里。

### 溯源链
```
freepbx.soundlang_settings:
    keyword | value
    --------+-------
    formats | g722,ulaw
    language| cn            ← ★ 就是这个
```

`core/functions.inc/drivers/PJSip.class.php:661`：

```php
$lang = !empty($trunk['language']) ? $trunk['language']
      : ($this->freepbx->Modules->moduleHasMethod('Soundlang','getLanguage')
           ? $this->freepbx->Soundlang->getLanguage() : "");     // ← 取 Soundlang 的默认语言
if (...) $conf['pjsip.endpoint.conf'][$tn]['language'] = $lang;
```

即：**端点/中继自己有 language 就用它，为空则回落到 Soundlang 的全局默认语言**。
实测端点自身语言是**空的**（`sip` 表里 4 个分机都没有 `language` 行；`pjsip` 表只有中继一行且值为空）
→ 所以那 6 处 `language=cn` 全部派生自**同一个 Soundlang 设置**。

### Soundlang 认识的正确代码是 `zh_CN`
`Soundlang.class.php` 里语言表是 **语言**、地区表是**地区**，两者拼起来才是完整代码：

```php
// getLanguageNames():  'zh' => _('Chinese')
// getLocationNames():  'CN' => _('China')
```
→ 中文（中国）的正规值就是 **`zh_CN`**。当初填的裸 `cn` 既不是 Soundlang 的语言代码，也不是 Asterisk 认识的中文代码。

### ★ 因此最干净的修法（一处生效、可回退、不怕 Apply Config）

> **FreePBX 管理页 → Admin → Sound Languages（声音语言）→ 把默认语言从 `cn` 改为「中文（中国）zh_CN」→ Apply Config**

改完后 `pjsip.endpoint.conf` 的 6 处 / `sip_general_additional.conf` / `iax_general_additional.conf` 会统一变成 `language=zh_CN`，
**所有**语音信箱入口（*97 / *98 / 分机「留言」键 / 转入语音信箱）一起生效。

> ⚠️ 同时要确认 Soundlang **没有**去下载/安装官方 `zh_CN` 声音包 —— 因为 `zh_CN` 是软链，
> 安装动作有可能覆盖到你自建的中文提示音。切换前先确认 `Soundlang` 里 zh_CN 包状态（无包/未安装最安全）。

---

## 三、把 `*97` 的整条播报链逐段过一遍（v2 新增）

先记住一个**关键机制**：`vm_instructions_zh`（中文语序菜单）**只在 `vms->starting` 为真时生效一次**；
而 `play_message()` 一开始就执行 `vms->starting = 0;`（`app_voicemail.c:9341`）。
所以 **`vm_instructions_zh` 只管「刚登录的第一次」；听完任一条留言之后的菜单全部回到 `vm_instructions_en`（英文语序）**。

| # | 段落 | 由谁播 | 调用的提示音（源码顺序） | 语序来源 |
|---|---|---|---|---|
| 1 | 登录后「您有 N 条留言」 | `vm_intro_zh`（10830） | `vm-you` `vm-have` N `vm-tong` `vm-INBOX` [`vm-and`\|`vm-messages`] … | **中文**（需 zh*） |
| 2 | 首次主菜单 | `vm_instructions_zh`（11153） | `vm-listen` + 文件夹名 + `press` + `digits/1` + `vm-opts` | **中文**（需 zh*） |
| 3 | **听完每条留言后的菜单** | `vm_instructions_en`（10967） | `vm-prev` `vm-advopts` `vm-repeat` `vm-next` `vm-delete`/`vm-undelete` `vm-toforward` `vm-savemessage` `vm-helpexit` | **英文**（zh 分支管不到） |
| 4 | 无留言时进文件夹 | `vm_browse_messages_zh`（11691） | `vm-you` `vm-haveno` `vm-messages` + 文件夹名 | **中文**（需 zh*） |
| 5 | 每条留言的信封 | `play_message`（9331）→ `play_message_datetime`/`callerid`/`duration` | 日期(`qR 'vm-received'`) + `vm-from*`/`vm-unknown-caller` + `vm-duration` | **中文**（需 zh*） |
| 6 | 按 2 换文件夹 / 按 9 存文件夹 | `get_folder2` → `get_folder`（8291） | `vm-changeto`/`vm-savefolder` + [ `vm-press` + N + **`vm-for`** + 文件夹名 + `vm-messages` ] ×5 + `vm-tocancel` | 英文结构（无 zh 分支） |
| 7 | 按 3 高级选项 | `advanced_options`（16571） | `vm-toreply` `vm-tocallback` `vm-tohearenv` `vm-tomakecall` `vm-leavemsg` `vm-starmain` … | 英文结构（无 zh 分支） |

### 逐段评估

**① intro（中文语序）—— 修文案后就对**
3 新 1 旧：`您` `有` `三` `条` `新的` [顿] `有` `一` `条` `旧` `留言` → **「您有三条新的，有一条旧留言」** ✅

**② 首次主菜单（中文语序）**
`vm-listen` + 文件夹(`vm-INBOX`=`新的` + `vm-messages`=`留言`) + `press` + `digits/1`
→ 改完文案：「请收听**新的留言**，请按一」✅
> 副作用（Asterisk 中文分支自身写法，无解）：播完 `vm-opts` 后它把 `vms->starting` 置 0 再**委派** `vm_instructions_en`，
> 于是**首屏会把整串菜单连播两遍**（"更改文件夹请按2…" 之后紧跟 "收听上一条留言请按4，高级选项请按3…"）。语速可接受，但不是理想体验。

**③ 听完留言后的菜单（英文语序）—— 基本可读，1 处必须修**
把中文包逐条串起来实际会播：

```
收听上一条留言请按4，高级选项请按3，重听当前留言请按5，收听下一条留言请按6，
删除这条留言请按7，转交这条留言请按8，或按9保存这条留言，请求帮助请按星号键，退出请按井号键
```
→ **每条都是独立完整句、按键号全对**，中文可读（顺序 4→3→5→6 略跳，但 Asterisk 对英文用户也是这个顺序）。
> **唯一硬伤**：`vm-undelete` 与 `vm-delete` 文案一模一样（都叫"删除这条留言请按7"），
> 而源码语义是「该留言已删 → 播 undelete（恢复）」。**建议把 `vm-undelete` 改成「恢复这条留言请按7」。**

**④ 无留言（中文语序）—— 仍有一处源码级病句**
`vm-you` `vm-haveno` `vm-messages` + 文件夹名 → 「您没有留言**新的**」。
顺序由 `.so` 固定（先播 haveno/messages 再补文件夹名），**不改源码无解**。仅在「手动切进一个空文件夹」这一罕见路径出现。

**⑤ 信封 —— 日期链完整，但 2 处译文硬伤**
- 中文日期格式 `"qR 'vm-received'"`：`q`=今天/昨天/更早(年+月+日+星期)，`R`=`kM`（时+`digits/oclock`+分+`minute`）
  → 实测 `cn/digits` 具备 `mon-0..11` / `day-0..6` / `h-*` / `at` / `oclock` / `oh`，根目录也有 `minute` `second` → **日期播报可用** ✅
  （仅 `digits/year`、`digits/day` 在 cn/en 里**都不存在**，属上游 core-sounds 缺口，与本次无关。）
- 呼叫方播报：
  - `vm-from` = **「from来自」** ← 夹了一个英文单词 ❌ 应改「来自」
  - `vm-from-extension` = **「留言来自来分机」** ← "来"字重复 ❌ 应改「留言来自分机」
  - `vm-from-phonenumber` = 「留言来自电话号码」 ✅
  - `vm-unknown-caller` = 「来自一个未知的呼叫」 ✅
  - `vm-duration` = 「本条留言共」 ✅

**⑥ 换/存文件夹（英文结构）—— 1 处必须修**
`get_folder` 的结构是 `vm-press` + N + **`vm-for`** + 文件夹名 + `vm-messages`（英文 "Press 1 for new messages"）。
中文包现在 `vm-for = 为了` → 播出 **「按0 为了 新的留言」** ❌ 应改 **「收听」/「查看」** → 「按0 收听新的留言」✅

**⑦ 高级选项（英文结构）—— 1 处错字**
`vm-tomakecall` = **「拨打电话请铵4」**（"铵"是错字）→ 应改「拨打电话请按4」。
其余 `vm-toreply`/`vm-tocallback`/`vm-tohearenv`/`vm-leavemsg`/`vm-starmain`/`vm-star-cancel` 均正确 ✅

---

## 四、提示音改动清单（v2 修正版）

> 所有文件放 **`/var/lib/asterisk/sounds/cn/`**（= `zh_CN/`，软链接同一份），用 `asterisk-tts-zh` 流水线生成
> （edge-tts → 8000Hz / mono / 16-bit → 去静音 `-35dB / 0.05s / 0.2s`）。

### A. 必须新增 6 个（zh 引擎专有，en/cn 都没有 → 不补就变哑）

| 提示音 | 建议文案 | 出现在 |
|---|---|---|
| `vm-you` | 您 | 段落 ①④ |
| `vm-have` | 有 | 段落 ① |
| `vm-tong` | 条 | 段落 ① |
| `vm-haveno` | **没有**（不要带"留言"） | 段落 ①④ |
| `vm-listen` | **请收听** | 段落 ② |
| `press` | 请按 | 段落 ② |

### B. 必须改写 2 个（不改就会拼出病句）

| 提示音 | 现值 | 改为 | 原因 |
|---|---|---|---|
| `vm-Old` | 条旧 | **旧** | zh 引擎为「有 M **条** 旧 留言」，"条"已由 `vm-tong` 承担；现值会变「有1**条条旧**留言」 |
| `vm-for` | 为了 | **收听** | 段落 ⑥：`按 N + vm-for + 文件夹名` → 「按0收听新的留言」 |

### C. 强烈建议修正（纯文案，与语序无关）

| 提示音 | 现值 | 改为 |
|---|---|---|
| `vm-undelete` | 删除这条留言请按7 | **恢复这条留言请按7** |
| `vm-from` | from来自 | **来自** |
| `vm-from-extension` | 留言来自来分机 | **留言来自分机** |
| `vm-tomakecall` | 拨打电话请铵4 | **拨打电话请按4** |
| `vm-review-nonurgent` | 清除**当时**留言的紧急标记请按4 | 清除**当前**留言的紧急标记请按4 |
| `vm-review` | 接受当前**语言**信息请按1 | 接受当前**语音**信息请按1 |

### D. 可选（调音 / 清理）

| 提示音 | 建议 | 说明 |
|---|---|---|
| `vm-and` | 「和」→ 约 **0.3s 静音** | 让「您有三条新的⏸有两条旧留言」更像逗号；保留"和"也可用 |
| `vm-theperson` / `vm-Work` | 去掉前导空格 | 现值是「␣分机」「␣工作」 |

### E. **不需要**改的（v1 曾建议改，v2 经逐字核对后撤销）

| 提示音 | 现值 | v2 结论 |
|---|---|---|
| `vm-INBOX` | 新的 | **保持不动** ✅ —— zh 引擎里它时而被 `vm-messages` 跟随时而不跟随，保留"新的"可让 4 种场景全部通顺 |
| `vm-messages` | 留言 | **保持不动** ✅ —— 被 64 处引用，改静音会连带弄坏段落 ②⑥，风险远大于收益 |
| `vm-Urgent` | 紧急 | **保持不动** ✅ —— 文件夹名路径是 `紧急 + 留言` = 「紧急留言」，本来就对 |

### F. 改完后 4 种留言场景（由轻到重逐字验证）

| 场景 | 拼接（源码顺序） | 播出 |
|---|---|---|
| 3 新 1 旧 | 您·有·三·条·新的·[顿]·有·一·条·旧·留言 | **您有三条新的，有一条旧留言** ✅ |
| 仅 3 新 | 您·有·三·条·新的·留言 | **您有三条新的留言** ✅ |
| 仅 1 旧 | 您·有·一·条·旧·留言 | **您有一条旧留言** ✅ |
| 无留言 | 您·没有·留言 | **您没有留言** ✅ |

---

## 五、执行步骤

### Step 1 — 生成提示音（6 新增 + 2 必改 + 6 建议改）
用 `asterisk-tts-zh` 流水线，输出到 `/var/lib/asterisk/sounds/cn/`（软链即 `zh_CN/`）；
同步更新本地 `D:\workbuddy工作区\sound\core-sounds-cn.txt` 的对应条目。

### Step 2 — 切语言（推荐方式：改一处）

| 方式 | 操作 | 优点 | 缺点 |
|---|---|---|---|
| **A（推荐）** | FreePBX → **Admin → Sound Languages** → 默认语言 `cn` → `zh_CN` → Apply Config | 一处生效；*97/*98/分机留言键/转入语音信箱**全部一致**；不怕后续 Apply Config | 影响面是全系统语言（但提示音同一份，风险≈0） |
| B（保底/局部） | `/etc/asterisk/extensions_custom.conf` 追加下段，只盖 *97/*98 | 零风险、可回退、只影响这两条路径 | 其它入口仍是英文语序，体验不一致 |

```ini
; 追加到 /etc/asterisk/extensions_custom.conf（该文件不受 Apply Config 覆盖）
[from-internal-custom]
exten => *97,1,Set(CHANNEL(language)=zh_CN)
 same => n,Goto(from-internal-additional,*97,1)
exten => *98,1,Set(CHANNEL(language)=zh_CN)
 same => n,Goto(from-internal-additional,*98,1)
```
> 注：`from-internal-custom` 的 include 顺序在 `from-internal-additional` 之前，可覆盖 FreePBX 生成的 `*97`/`*98`（`extensions_additional.conf:2204` / `2432`）。

### Step 3 — 验证

```bash
# 语言是否生效
grep -n 'language=' /etc/asterisk/pjsip.endpoint.conf /etc/asterisk/sip_general_additional.conf
# 6 个 zh 专有提示音是否到位（应全为 1）
cd /var/lib/asterisk/sounds/cn
for p in vm-you vm-have vm-tong vm-haveno vm-listen press; do echo "$p=$(ls $p.* 2>/dev/null|wc -l)"; done
asterisk -rx 'core reload'    # 或 Apply Config
```
拨测顺序：`*97` → 听 intro → 进留言 → 听信封 → 按 4/6 翻页 → 按 2 换文件夹 → 按 3 高级选项。

### 回退
- 方式 A：Sound Languages 改回 `cn` + Apply Config。
- 方式 B：删掉 `extensions_custom.conf` 里那几行。
- 提示音：建议先把改动的 wav 备份成 `*.wav.bak`。

---

## 六、已知遗留（不改源码无法避免）

| # | 现象 | 位置 |
|---|---|---|
| 1 | 切进**空文件夹**会播「您没有留言**新的**」 | `vm_browse_messages_zh`（11698-11706），顺序由 .so 固定 |
| 2 | **中文菜单播完会「无缝接」一整套英文语序菜单**（中文短菜单 + 英文长菜单连播，**空信箱也照播、无需任何按键**） | `vm_instructions_zh` 末尾 `vms->starting=0; return vm_instructions_en(...)`（22.8.2: 11151-11154 / branch22: 11168-11171） |
| 3 | **听完留言后的菜单永远是英文语序** | `vm_instructions()`（11181）只在 `vms->starting` 时走中文分支 |
| 4 | `digits/year`、`digits/day` 在 cn/en 都不存在（信封"更早日期"缺词） | 上游 core-sounds 缺口 |

以上均需打补丁重编 `app_voicemail.so` / 补 sounds 才能根治，**不建议为本次需求动**。

---

## 七、核对清单

- [x] `sounds/zh_CN` 是指向 `sounds/cn` 的软链接（`ls -la` 已确认）
- [x] `language=cn` 来源 = `soundlang_settings.language`（一处派生 6 端点 + 3 全局）
- [x] Soundlang 的正确中文代码 = `zh_CN`（其语言表 `zh` + 地区表 `CN`）
- [x] `app_voicemail.so` 含 zh 语序引擎（`strings` 命中 `vm-you/vm-have/vm-tong/vm-haveno/vm-listen/press`）
- [x] 6 个 zh 专有提示音在服务器上**完全缺失**，且 `en/` 也没有（缺则变哑）
- [x] 已枚举 `*97` 全部 7 个播报段落及各自提示音序列
- [x] 已确认「听完留言后的菜单」= `vm_instructions_en`（英文语序），逐条可读
- [x] 已确认必须改的只有 `vm-Old` / `vm-for` 两个（其余为文案建议）
- [x] **已执行**：生成提示音 → 切语言 → Apply Config → 端到端拨测（详见第九节）

---

## 八、补充核实：自定义语言代码该取什么（回应「在 Custom Languages 建 cn 是否标准」）

**结论：机制标准，代码不规范。**

| 层次 | 判定 | 依据 |
|---|---|---|
| 用 Custom Languages 机制 | ✅ 标准 | 官方 *Sound Languages User Guide* 的 *How to Define a Custom Language* 就是为「无官方语音包的语言」准备的入口；代码会成为下拉可选项并创建同名目录 |
| 把 Global Language 设为中文 | ✅ 标准 | 同上；且 Soundlang 的 `doDialplanHook` 会把它下发到 `SIPLANG` + `sip_general` + `iax_general`，并经 core 派生到各 pjsip 端点（单点生效） |
| 语言代码取名 `cn` | ❌ 不规范 | ① Soundlang 命名惯例是 `lang` / `lang_region`（`getLanguageNames()` 内置 `'zh'=>Chinese`、`getLocationNames()` 内置 `'CN'=>China`）→ 正规代码是 **`zh_CN`**；② `cn` 是国家代码而非语言代码；③ **`cn` 不满足 `app_voicemail` 的 `strncasecmp(lang,"zh",2)` 判据 → 中文语序引擎不激活**（正是本次病句根因） |

补充事实：

- **官方语音包确实没有中文**（`soundlang_packages` 去重清单）：`cs de_DE en en_AU en_GB en_NZ es es_419 fa fr he it ja nl no pl ru sv tr`。
  → **排除**了「安装官方 `zh_CN` 包覆盖自建提示音」的风险。
- **模块不做代码格式校验**：`doConfigPageInit` 的 add/update 直接 INSERT/UPDATE（零校验），仅 ajax `convert`（上传转换）才 `preg_match('/[^A-Za-z0-9_-]/', $lang)`。所以 `cn` 能存进去，模块不会纠正你。
- **改名零风险**：`updateCustomLanguage` 只 `UPDATE` DB + `@mkdir`（不动已有文件）；`delCustomLanguage` 只 `@rmdir`（非空目录删不掉）+ 全局语言退回默认。`sounds/zh_CN` 本就是 `-> cn` 的软链 → 把代码从 `cn` 改成 `zh_CN` 后目录自动对齐，**零搬迁**。用行内铅笔（Edit）编辑即可。
- **回退链实证**（`main/file.c` 的 `fileexists_core`）：`preflang` → 去 `_` 主语言 → 无语言前缀 → `en`（`DEFAULT_LANGUAGE`；asterisk.conf 的 `defaultlanguage` 被注释）。
- **变哑实证**（`apps/app_voicemail.c:vm_intro_zh` @10830）：`res=ast_play_and_wait(chan,"vm-you"); if(!res && …)` 链式判断 → `vm-you` 缺则整段 intro 跳过。故**顺序必须「先补提示音、再切语言」**。

> 一句话：**同一步操作里把代码填成 `zh_CN` 而不是 `cn`，既符合官方惯例，又正好激活中文语序引擎。**

---

## 九、执行记录（2026-09-23 23:18–23:37 已完成）

> 状态：**✅ 已上线并拨测通过**。备份保留在服务器 `/root/vmfix-backup-20260923-231854/`。

### 9.1 执行内容

| 步骤 | 动作 | 结果 |
|---|---|---|
| 1 | 用 `asterisk-tts-zh`（edge-tts `zh-CN-XiaoxiaoNeural` → 8000Hz/mono/16bit → -35dB/0.05s/0.2s 去静音）生成 12 个 WAV | 12/12 成功，格式 `pcm_s16le/8000/1ch/16bit` |
| 2 | 推送到 `/var/lib/asterisk/sounds/cn/`（`zh_CN` 软链同体），`chown asterisk:asterisk && chmod 644` | 12 个文件 MD5 本地=远端，逐一致 |
| 3 | 修正 **逐分机语言覆盖**（见 9.2，新发现） | `AMPUSER/2202/language` `cn`→`zh_CN`；删除残留键 `AMPUSER//language` |
| 4 | `fwconsole reload`（Apply Config） | Reload Complete |
| 5 | 端到端拨测 | 见 9.3，**0 missing** |

### 9.2 ★ 新发现：`language` 有**第二个**源头（逐分机覆盖）

v2 报告原本断言「改 Soundlang 一处即全局生效」。执行时实测发现**例外**：

```
pjsip.endpoint.conf:
  [8633] language=zh_CN   [2201] language=zh_CN
  [2202] language=zh_CN
  [2202] language=cn      ← ★ 第 151 行，后写覆盖前写
  [8514] language=zh_CN   [Chinatelecom_IMS] language=zh_CN
```

溯源：
- 生成者 = **Languages 模块**（`modules/languages/Languages.class.php:276` → `$pjsip->addEndpoint($device['id'], 'language', $users[$device['user']])`），它把逐分机语言**追加在端点块尾部**（所以盖住了 core 驱动写的全局值）。
- 数据源 = **AstDB**（不是 DB 表！）：`/AMPUSER/<ext>/language`。`languages` / `language_incoming` 两个 DB 表都是空的。
- 当时 AstDB：`AMPUSER/2202/language = cn`（只此一台）+ `AMPUSER//language = cn`（空分机号残留，会被 `macro-user-callerid` 的 `Set(CHANNEL(language)=${DB(AMPUSER/${AMPUSER}/language)})` 命中）。

处置：

```bash
asterisk -rx 'database put AMPUSER 2202/language zh_CN'   # 改为 zh_CN
asterisk -rx 'database del AMPUSER /language'             # 清除空分机号残留
fwconsole reload
```

→ 修正后 6 处 `language=` 全部为 `zh_CN`。

> **教训**：`grep language pjsip.endpoint.conf` 必须**逐端点核对**，同一端点出现两行 `language=` 时**后一行为准**。改完 Soundlang 不等于改完所有入口 —— 还要查 `database show | grep language`。

### 9.3 端到端拨测证据

测试方法（临时上下文，验证后已删除并回滚 `extensions_custom.conf`）：把 channel language 置 `zh_CN` 后真实调用 `VoiceMailMain(2202@default,s)` 与逐条 `Playback` 全部 vm 提示音，再从 `/var/log/asterisk/full` 抓 `Playing '...'` 与 `does not exist`。

**拨测 1 — 真实 `*97` 路径（`VoiceMailMain`，邮箱为空）**：

```
Playing 'vm-you.slin'      (language 'zh_CN')   ← zh 引擎起始标记
Playing 'vm-haveno.slin'   (language 'zh_CN')
Playing 'vm-messages.slin' (language 'zh_CN')   → 实际播出「您没有留言」
Playing 'vm-opts.slin'     (language 'zh_CN')
Playing 'vm-advopts.slin'  (language 'zh_CN')
```

> **`vm-you` / `vm-haveno` 是 zh 引擎专有提示音，英文语序分支永远不会播它们** —— 它们出现 = 中文语序引擎已激活，这就是本次修复生效的铁证。

**拨测 2 — 全部 vm 提示音**：17 个 `Playing '...' (language 'zh_CN')`，**`does not exist` 计数 = 0**。

**拨测 3 — 中文数字播报（zh 引擎拼接 `N 条` 依赖）**：`say.conf` 无生效规则 → 走内置 say 逻辑，实测：

| 调用 | 实际播放 | 中文读法 |
|---|---|---|
| `SayNumber(3)` | `digits/3` | 三 |
| `SayNumber(21)` | `digits/20` + `digits/1` | 二十一 |
| `SayNumber(105)` | `digits/1` + `digits/hundred` + `digits/0` + `digits/5` | 一百零五 |

### 9.4 修复后 4 种留言场景的实际播出

| 场景 | 拼接序列 | 播出 |
|---|---|---|
| 3 新 + 1 旧 | you+have+3+tong+INBOX+and+have+1+tong+Old+messages | **您有三条新的和有一条旧留言** |
| 仅 3 新 | you+have+3+tong+INBOX+messages | **您有三条新的留言** |
| 仅 1 旧 | you+have+1+tong+Old+messages | **您有一条旧留言** |
| 无留言 | you+haveno+messages | **您没有留言**（已实测） |

> 第 1 行「和**有**一条…」的重复"有"是 Asterisk zh 引擎源码自身结构（`vm-have` 在两个分支各播一次），**非提示音问题**，与上游设计一致，不改 `.so` 无法消除。

### 9.5 本次改动的 12 个提示音

| key | 内容 | 类别 |
|---|---|---|
| `vm-you` | 您 | 新增 |
| `vm-have` | 有 | 新增 |
| `vm-tong` | 条 | 新增 |
| `vm-haveno` | 没有 | 新增 |
| `vm-listen` | 请收听 | 新增 |
| `press` | 请按 | 新增 |
| `vm-Old` | 旧（原「条旧」） | 修改 |
| `vm-for` | 收听（原「为了」） | 修改 |
| `vm-undelete` | 恢复这条留言请按7（原误译「删除这条留言请按7」，与 `vm-delete` 撞车） | 文案修复 |
| `vm-from` | 来自（原「from来自」，夹英文） | 文案修复 |
| `vm-from-extension` | 留言来自分机（原「留言来自来分机」，"来"重复） | 文案修复 |
| `vm-tomakecall` | 拨打电话请按4（原错字「铵」） | 文案修复 |

### 9.6 回退

```bash
# 提示音回退（服务器备份目录）
BK=/root/vmfix-backup-20260923-231854
cp -a $BK/vm-Old.wav $BK/vm-for.wav $BK/vm-undelete.wav \
      $BK/vm-from.wav $BK/vm-from-extension.wav $BK/vm-tomakecall.wav \
      /var/lib/asterisk/sounds/cn/
# 删除本次新增的 6 个
rm -f /var/lib/asterisk/sounds/cn/{vm-you,vm-have,vm-tong,vm-haveno,vm-listen,press}.wav
# 分机语言回退
asterisk -rx 'database put AMPUSER 2202/language cn'
# 全局语言回退（GUI：Sound Languages → Global Language 改回，或 DB）
mysql -ufreepbxuser -p*** -hlocalhost asterisk -e "UPDATE soundlang_settings SET value='cn' WHERE keyword='language';"
fwconsole reload
```

> 本地源文件 `sound/core-sounds-cn.txt` 与 `sound/*.wav` 已同步为改后版本（MD5 与服务器一致），以后可直接用 `asterisk-tts-zh` 重新生成。

---

## 十、补充核实：`*97` 不按键时为何会多播一段（2026-09-24 实测）

**问题**：拨打 `*97`、一个键都不按，按理只应播 `vm_intro_zh` + `vm_instructions_zh`，但实际还多出一段。

**结论：多出来的是 `vm_instructions_en`（英文语序菜单），由上游源码无条件链式触发，与提示音、语言配置均无关。**

### 10.1 源码依据（Asterisk 22.8.2，`apps/app_voicemail.c`）

```c
/* 11159 */
static int vm_instructions(...) {
    ...
    } else if (vms->starting && !strncasecmp(lang, "zh", 2)) {
        return vm_instructions_zh(...);        /* 首次：中文短菜单 */
    } else {
        return vm_instructions_en(...);        /* 其余：一律英文语序 */
    }
}

/* 11135 */
static int vm_instructions_zh(...) {
        res = ast_play_and_wait(chan, "vm-opts");
        if (!res) {
            vms->starting = 0;
            return vm_instructions_en(...);    /* ★ 无条件委派，不放等按键 */
        }
}
```

主流程：`vm_intro()`（12693）返回后 `vms.starting=1`，主菜单 `while` 的 `default:` 分支（13173）
调 `vm_instructions(..., skipadvanced=0, ...)` → 进入 `vm_instructions_zh` → 播完 `vm-opts` 直接转 `vm_instructions_en`。

### 10.2 实测序列（2202 空信箱，`language=zh_CN`，日志 `Playing '…'` 实捕）

| # | 提示音 | 来源段落 |
|---|---|---|
| 1-3 | `vm-you` → `vm-haveno` → `vm-messages` | `vm_intro_zh`（您没有留言）|
| 4 | `vm-opts` | `vm_instructions_zh` 末句（更改文件夹请按2，高级选项请按3…）|
| 5 | `vm-advopts` | **`vm_instructions_en`** |
| 6 | `vm-repeat` | `vm_instructions_en` |
| 7 | `vm-next` | `vm_instructions_en` |
| 8 | `vm-delete` | `vm_instructions_en` |
| 9 | `vm-toforward` | `vm_instructions_en` |
| 10 | `vm-savemessage` | `vm_instructions_en` |
| 11 | `vm-helpexit` | `vm_instructions_en` |

`does not exist` 计数 = 0；5–11 会再循环最多 2 次后超时挂断。空信箱下 `vm-prev` 不播（`vms->curmsg=0`、`lastmsg=-1` 使条件为假），与源码一致。

### 10.3 影响与对策

- 影响：`vm-repeat` / `vm-delete` / `vm-savemessage` / `vm-toforward` / `vm-next` / `vm-advopts` / `vm-helpexit` **每次普通 `*97` 登录都会听到**，其文案必须逐个打磨（本次已更新其中 4 条）。
- 想彻底去掉这段英文菜单，只能打补丁重编 `app_voicemail.so`（把 `return vm_instructions_en(...)` 改为在 zh 分支内自行 `ast_waitfordigit`）。不建议为现需求动。

### 10.4 本次同步的 4 个提示音

| 提示音 | 新文案 | 服务器 MD5 |
|---|---|---|
| `vm-savemessage` | 保存该留言请按9 | `742e778889268c8a0e9d1bf0dad903e2` |
| `vm-delete` | 删除该留言请按7 | `e552b68f3574ffd90c60ece72d9d0b01` |
| `vm-repeat` | 重新听该留言请按5 | `918e16b195bc04e2b0bb2870906a7c5d` |
| `vm-listen` | 收听 | `057a18bf6150db26dad1fbf6ad1ff819` |

（旧文件已备份至 `/root/wavbak-20260924-002303/`；`sound/core-sounds-cn.txt` 中 `vm-repeat` / `vm-savemessage` 文案已同步更新。）

---

## 十一、分机 8514 真实播报文案核对（2026-09-24）

对真实通话（`PJSIP/8514-000000a3`，01:22:21）与受控复现逐条比对 `core-sounds-cn.txt`，结果见独立文档：
**`FreePBX-star97-8514-真实播报文案核对.md`**

要点：
- 真实拨入语言确认 `zh_CN`；`macro-user-callerid` 对 language 是**带条件**赋值（3649 行），AstDB 为空时不覆盖 → 8514 稳定走中文语序。
- 序列与 2202 空信箱一致（`vm_instructions_zh` 后必跟 `vm_instructions_en`）。
- 文案问题：**①「二条」应为「两条」（量词）**、**②「高级选项请按3」连播两遍**；另有"该留言/这条留言"用词不统一、「第一个留言/最后留言」缺量词等次要问题。

---

## 十二、`*97` 登录后多播（13–19 段）的源码根因与精简方案（2026-09-24）

完整分析、源码逐行依据、补丁与构建步骤另立文档：
**`FreePBX-star97-播报逻辑分析与精简方案.md`**

要点：
- 13–19 段（`vm-advopts`→`vm-repeat`→`vm-next`→`vm-delete`→`vm-toforward`→`vm-savemessage`→`vm-helpexit`）**全部来自 `vm_instructions_en()`**。
- 触发点：`vm_instructions_zh()`（11135）播完 `vm-opts` 后**无条件** `vms->starting = 0; return vm_instructions_en(...)`（11151–11153），且**不放等按键**。
- 语言分发 `vm_instructions()`（11159）判据是 `vms->starting && lang==zh*` → `starting` 刚被清 0，后续永远落英文语序分支。
- 上游 `master` 分支 2026-09 仍是同一段代码，**未修复**；日语（`vm_instructions_ja`）自己实现双分支、不委派，故无此问题。
- **没有任何配置项可关闭**（`skipms`/`skip instructions` 只作用于录制留言）。
- 方案 A（推荐）：给 `vm_instructions_zh` 打 5 行补丁后重编 `app_voicemail.so`；方案 B（零风险折中）：改写 7 条文案为连贯中文；方案 C（静音化）不可接受（会连带静音"听完留言"的逐条菜单）。
