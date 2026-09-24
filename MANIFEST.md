# MANIFEST.md —— 改动清单（改了什么 · 为什么 · 怎么核）

> 本清单对应 FreePBX 17.0.30 + Asterisk 22.8.2 + Debian 12 (x86_64) 这一套真实线上环境，
> 所有条目均为**实测验证过**，非理论推导。校验值可用 `SHA256SUMS` 一键核对。

---

## 总览

| # | 类别 | 改动对象 | 解决的现象 | 生效方式 |
|---|---|---|---|---|
| 1 | 音频 | `cn/` 593 个 WAV（全量中文音） | 官方无中文语音包 | 直接落盘 |
| 2 | 音频 | `cn/digits/oclock.wav`、`cn/minute.wav`、`cn/minutes.wav` | 报时读「点整」「分钟」不自然 | 直接落盘 |
| 3 | 音频 | `custom/` 39 个 WAV | `*60`、`*68` 依赖的整句中文音 | 直接落盘 |
| 4 | **源码** | `apps/app_voicemail.c` → 重编 `app_voicemail.so` | `*97` 播完中文又接一整套英文菜单 | 模块热重载 |
| 5 | **源码** | `agi-bin/wakeup` | `*68` 输 4 位 `HHMM` 丢失第 4 位报「输入无效」 | 立即生效 |
| 6 | **源码** | `agi-bin/wakeglobal.php` | AGI 侧语言未强制为 `zh_CN` | 立即生效 |
| 7 | 配置 | `extensions_custom.conf` → `[sub-hr12format-custom]` | `*60` 报时英文句式 | `dialplan reload` |
| 8 | 配置 | `soundlang_settings` / `soundlang_customlangs` | 全局语言 = `zh_CN`、注册自定义语言 | 立即生效 |
| 9 | 配置 | `PHPTIMEZONE` = `Asia/Hong_Kong` | **叫醒电话整体偏 8 小时** | 立即生效 |
| 10 | 数据库 | KVStore `message_zh_CN`（20 条） | `*68` 提示是英文单词片段拼装 | 立即生效 |

---

## 1. 音频：`cn/`（593 个 WAV）

**来源**：`asterisk-core-sounds-en` + `asterisk-extra-sounds-en` 的英文条目表逐条译为中文，
用 `edge-tts`（`zh-CN-XiaoxiaoNeural`）合成 → ffmpeg 转 `8000Hz / mono / 16bit PCM` → 去头尾静音
（`start_threshold=-35dB`，头缓冲 0.05s、尾缓冲 0.2s）。

**为什么**：官方音频库 `downloads.asterisk.org/pub/telephony/sounds/releases/` 只有
`en en_AU en_GB en_NZ es fr it ja ru sv`，**没有中文**；FreePBX `soundlang_packages` 也没有 `zh_CN`。
中文只能自建（Custom Language）。

**结构**：

| 路径 | 数量 | 说明 |
|---|---|---|
| `sounds/cn/`（顶层） | 383 | 主体提示音 |
| `sounds/cn/digits/` | 94 | 数字、序数 |
| `sounds/cn/letters/` | 61 | 字母拼读 |
| `sounds/cn/phonetic/` | 27 | 音标词 |
| `sounds/cn/dictate/` | 12 | 听写控制 |
| `sounds/cn/silence/` | 10 | 静音（**不要**对它们做去静音处理） |
| `sounds/cn/followme/` | 6 | 跟随转移 |
| `sounds/cn/core-sounds-cn.txt` / `core-sounds-en.txt` | 2 | 文本索引（Soundlang 用） |

**★ 中文语序引擎专用 6 个音**（英文清单里**没有**，缺则整段 intro 变哑）：

`vm-you`(您) · `vm-have`(有) · `vm-tong`(条) · `vm-haveno`(没有留言) · `vm-listen`(收听) · `press`(按)

**★ 语义被改写过的键**（中文语序下含义变了，不能直译）：

| 键 | 直译（错） | 本包（对） |
|---|---|---|
| `vm-INBOX` | 新的 | **新留言** |
| `vm-Old` | 条旧 | **旧留言** |
| `vm-Urgent` | 紧急的 | **紧急留言** |
| `vm-and` / `vm-messages` | 和 / 留言 | **短静音**（否则出现「新留言留言」） |
| `vm-first` | 第一 | **第一条** |
| `vm-last` | 最后 | **最后一条** |

---

## 2. 音频：被**重点替换**的核心音

| 文件 | 原中文 | 改为 | 为什么 |
|---|---|---|---|
| `cn/digits/oclock.wav` | 点整 | **点** | 音名在 `say.c` 里硬编码为 `digits/oclock`，只能改音文件；「下午两点整25分」很怪 |
| `cn/minute.wav` | 分钟 | **分** | 同上（`minute` 硬编码） |
| `cn/minutes.wav` | 分钟 | **分** | 同上（`minutes` 硬编码） |

> 效果：`14:30` → **下午二点三十分**；`04:00` → **上午四点零零分**。
> 这三个音是**全局**生效的，所有走中文报时的功能都受益。

---

## 3. 音频：`custom/`（39 个 WAV）

### 3.1 报时（`*60` / `*61` 路径）

| 键 | 文案 |
|---|---|
| `beijing-shijian` | 北京时间 |
| `zh-lingchen` | 凌晨 |
| `zh-shangwu` | 上午 |
| `zh-zhongwu` | 中午 |
| `zh-xiawu` | 下午 |
| `zh-wanshang` | 晚上 |
| `zh-liang` | 两 |
| `zh-dian` | 点 |
| `zh-fen` | 分 |
| `zh-miao` | 秒 |
| `zh-zheng` | 整 |

> `zh-liang`：`2` 点要读「**两点**」而不是「二点」，单独录一个音专门处理。

### 3.2 叫醒电话（`*68`，28 个 `hw-*`）

| 键 | 文案 |
|---|---|
| `hw-welcome` | 您好，这里是叫醒电话服务。 |
| `hw-menu1` | 设置叫醒电话请按1 |
| `hw-menu2` | 查询叫醒列表请按2 |
| `hw-add` | **请输入叫醒时间。请按四位数字输入，例如晚上十点三十分就输入二二三零。** |
| `hw-addtype1` | 如需上午请按1 |
| `hw-addtype2` | 下午请按2 |
| `hw-addok` | 已为您设置叫醒电话，时间是： |
| `hw-list-pre` | 您已设置 |
| `hw-list-post` | 个叫醒电话。 |
| `hw-listempty` | 您当前没有设置叫醒电话。 |
| `hw-info-pre` | 第 |
| `hw-info-mid` | 个，时间是： |
| `hw-lmenu1` | 取消此叫醒请按1 |
| `hw-lmenu2` | 继续查询请按2 |
| `hw-lmenu3` | 返回主菜单请按3 |
| `hw-cancelled` | 叫醒电话已取消。 |
| `hw-goodbye` | 再见。 |
| `hw-error` | 系统错误，请稍后再试。 |
| `hw-invalid` | 输入无效。 |
| `hw-retry` | 请重新输入。 |
| `hw-invaliddial` | 您输入的数字有误。 |
| `hw-opselect` | 请输入要设置叫醒电话的分机号，然后按井号键结束。 |
| `hw-opentered` | 您输入的分机号是： |
| `hw-cmenu1` | 延后5分钟请按1 |
| `hw-cmenu2` | 延后10分钟请按2 |
| `hw-cmenu3` | 延后15分钟请按3 |
| `hw-conf-pre` | 已延后 |
| `hw-conf-post` | 分钟，从现在开始。 |

> `hw-add` 是**重录版**：原音只说「例如晚上10点30分，输完请按井号键结束」，
> 既没说位数/进制，还用「按井号键」把用户引向 **3 位 12 小时制**那条根本表达不了 22:30 的岔路。
> 新音明确「**四位数字**」并给出「2230」的读法。
>
> 菜单类消息（`hw-menu*`/`hw-lmenu*`/`hw-cmenu*`）**刻意拆成多段**：`sim_background` 遇按键即停，
> 整句会被截断。

### 3.3 未收录

| 文件 | 原因 |
|---|---|
| `custom/cool-welcome1.wav` | **本机自用的私人 IVR 欢迎音**（内容含个人称谓），**刻意不公开**。若你要用于自己的 IVR，从自己的备份取回即可。 |

---

## 4. 源码：`app_voicemail.so`

**改动文件**：`apps/app_voicemail.c` 的 `vm_instructions_zh()`
**补丁**：`patches/app_voicemail-22.8.2-vm_instructions_zh.patch`（hunk 位于第 11145 行起）

**原状（Asterisk 22.8.2 第 11151–11154 行）**：播完 `vm-opts` 后**无条件**委派英文：

```c
if (!res) {
    vms->starting = 0;
    return vm_instructions_en(chan, vmu, vms, skipadvanced, in_urgent, nodelete);
}
```

**改后**：原地等按键，重复超 2 次才超时退出：

```c
if (!res)
    res = ast_waitfordigit(chan, 6000);
if (!res) {
    vms->repeats++;
    if (vms->repeats > 2) {
        res = 't';
    }
}
```

**为什么**：这是导致「拨 `*97` 一个键都不按，却在中文菜单后无缝接一整套英文语序菜单
（`vm-advopts → vm-repeat → vm-next → vm-delete → vm-toforward → vm-savemessage → vm-helpexit`，
循环 ≤2 次后超时）」的**唯一**根因。上游 master 至今未修，**没有任何配置项能关掉**，只能改源码。

> ★ **不要**额外加 `vms->starting = 0;` —— 保留 `starting=1` 才能让 `vm_instructions()` 的
> `starting && zh*` 判据持续命中 `_zh`；清 0 后登录时按 `*` 会掉回 `_en` 的英文语序菜单。
> 官方 `vm_instructions_ja()` 同样从不清理该标志，照抄最稳。

**构建**：`build/build_app_voicemail_wsl.sh`
在 WSL 里用 `debootstrap` 造 **Debian 12 chroot**（glibc 2.36，与目标机一致）编译，
避免在 Ubuntu 24.04（glibc 2.39）上编出带 `GLIBC_2.38` 符号、目标机 `dlopen` 失败的 `.so`。

**产物校验**：

```
大小    306,576 字节
md5     2592d691859105685ed22f563d7dcb17
sha256  206fc943c2473d241c9d0fed9333d2c58f641727a4d6063baa0d700f5483dbd3
来源源码  Asterisk 22.8.2  apps/app_voicemail.c  md5=67a97b4d843fe8c4e0e51ba13ee31723
最高 GLIBC 符号  GLIBC_2.34      NEEDED  libc.so.6（与官方一致）
```

**生效**：`module unload app_voicemail.so` → `module load app_voicemail.so`
（会重新 `dlopen`；`module reload` **不重读 .so，无效**）。

**实测**：8514 分机零按键 → 只播 1–12 段后进入等待，`vm-advopts…vm-helpexit` 全部消失，
`does not exist` = 0。

---

## 5. 源码：叫醒电话 AGI

### 5.1 `agi-bin/wakeup`

**补丁**：`patches/hotelwakeup-wakeup-digit-timeout.patch`

```diff
-			$ret = $hotelwakeup->wait_for_digit(1000);
+			$ret = $hotelwakeup->wait_for_digit(6000);
```

**为什么**：`wakeupAdd()` 用 `sim_background(..., "0123456789", 3)` **最多只收 3 位**，
再用 `wait_for_digit(1000)` **只等 1 秒**去捞第 4 位。而人按键间隔 + DTMF/网络时延常 **> 1 秒**，
于是第 4 位丢失 → `times="223"` → 掉进 **12 小时制**分支 → 弹「上午按1/下午按2」→
那记迟到的 `0` 被当成上下午答案（既非 1 非 2）→ **`optionInvalid`（输入无效）**。

**日志铁证**（用户真实通话）：`hw-add` 之后 `hw-addtype1` 与 `hw-invalid` 出现在**同一秒**，
且 `hw-addtype2` **缺席** —— 正是第 4 位打断播放的特征。

**修法取舍**：只把超时从 1s 放宽到 6s，**保持 `length=3` 与 12 小时制分支不变** —— 最小改动、零回归。

### 5.2 `agi-bin/wakeglobal.php`

**补丁**：`patches/wakeglobal-language-zh_CN.patch`

```diff
 	private function init()
 	{
 		$this->AGI->answer();
+		$this->AGI->set_variable('CHANNEL(language)', 'zh_CN');
 	}
```

**为什么**：官方 `init()` 只有 `answer()`，AGI 侧通道语言不保证是 `zh_CN`；
而中文语序引擎**只在 language 以 `zh` 开头**时启用（见 `INSTALL.md` 2.1）。

> ⚠️ 这是**本地 hack**，`fwconsole ma upgrade hotelwakeup` 覆盖模块目录后会消失
> （但 `message_zh_CN` 在独立 KVStore 表，**不受影响**）。

---

## 6. 配置：`extensions_custom.conf`

**片段**：`config/extensions_custom.conf.snippet`（含两个上下文）

### 6.1 `[sub-hr12format-custom]` —— `*60` 中文报时

**机制**：FreePBX 生成的 `[sub-hr12format]` 只内置 **en/fr/de/ja** 四个分支，`zh_CN` 会回退 en。
而 `[sub-hr12format]` 顶部有 `include => sub-hr12format-custom`，且 **`DIALPLAN_EXISTS()` 会遍历 include**
→ 因此在本文件补 `exten => zh_CN,1,…` 即可**接管** `*60`（连同 `cn`/`zh` 两个别名保险）。

**关键实现点**：

- 用 **`FutureTime`** 取时间（不是 `EPOCH`）—— 与踩点 beep 对应；
- 用 **`Return()`** 结束 —— 保留 `*60` 原生 cadence；
- 扩展名**别用连字符**（用 `zzero`/`zperiod`/`zsaytime`…）；
- 2 点走 `zh-liang`（两点），其余走 `SayNumber`。

> ⚠️ **只写 `extensions_custom.conf`**。`extensions_additional.conf` 会被 FreePBX Apply Config 重新生成覆盖。

### 6.2 `[custom-speakingclock-zh]` —— 自建循环报时上下文

不限次数的循环报时（`北京时间 + 时段 + H点M分S秒 + beep + Wait 5 → 循环`）。
可按需删除，不影响 `*60`。

---

## 7. 配置：FreePBX 设置

| 设置 | 值 | 为什么 |
|---|---|---|
| `soundlang_settings.language` | `zh_CN` | ★ 必须是 `zh_CN`，**不能是 `cn`**（`cn` 会落到英文语序引擎） |
| `soundlang_customlangs` | `zh_CN / Chinese` | 中文不在官方包列表里，必须以「自定义语言」注册 |
| `PHPTIMEZONE` | `Asia/Hong_Kong` | ★ 决定叫醒电话触发时刻，见下 |

### ★ 时区：最隐蔽的一个坑

- `generateCallFile()` 用 `touch()` 把 `convert_time()`（`mktime()`）算出的时间戳写成
  `.call` 文件的 **mtime**，Asterisk 按 mtime 触发。
- 本机原 `PHPTIMEZONE = UTC` 而系统 `/etc/localtime = Asia/Hong_Kong(+08)`
  → **叫醒电话整体偏 8 小时**（设 22:30 实际 06:30 响）。
- **最坑的是**：GUI 与语音列表**同用这个错误时区**计算 → **显示完全正常，界面上看不出**。
- 改 `php.ini` 的 `date.timezone` **无效**（FreePBX 引导会用 `PHPTIMEZONE` 覆盖）。

**排查铁律**：

```bash
php -r 'require "/etc/freepbx.conf"; echo date_default_timezone_get(), PHP_EOL;'   # 带引导
stat -c '%y %n' /var/spool/asterisk/outgoing/wuc.*.call                          # mtime 应等于目标挂钟时间
```

---

## 8. 数据库：KVStore `message_zh_CN`

**文件**：`config/message_zh_CN.sql`（20 条）
**表**：`kvstore_FreePBX_modules_Hotelwakeup`，`id='message_zh_CN'`

**机制**：Hotel Wakeup 的 `getMessage($msg, $lang)` **优先读 KVStore 的 `message_<lang>`**，
命中即**整体替换**默认的英文片段拼装 —— 于是**零代码**就能换成通顺整句。

| 键 | 内容 | 备注 |
|---|---|---|
| `SayUnixTime` | `["pIM"]` | ★ 格式从 `IMpABd` 改为 **`pIM`**：上下午必须在最前，否则读成「…十点三十分 下午」 |
| `welcome` | `custom/hw-welcome` | |
| `goodbye` | `custom/hw-goodbye` | |
| `error` | `custom/hw-error` | |
| `retry` | `custom/hw-retry` | |
| `optionInvalid` | `custom/hw-invalid` | |
| `invalidDialing` | `custom/hw-invaliddial` | |
| `operatorSelectExt` | `custom/hw-opselect` | |
| `operatorEntered` | `hw-opentered` + `d|{number}` + `silence|500` | |
| `wakeupMenu` | `hw-menu1` + `silence|400` + `hw-menu2` + `silence|500` | 拆段防截断 |
| `wakeupAdd` | `custom/hw-add` | ★ 4 位数字说明版 |
| `wakeupAddType12H` | `hw-addtype1` + `silence|300` + `hw-addtype2` | |
| `wakeupAddOk` | `hw-addok` + `SayUnixTime|{time}` + `silence|500` | |
| `wakeupList` | `hw-list-pre` + `{count}` + `hw-list-post` + `silence|500` | |
| `wakeupListEmpty` | `custom/hw-listempty` | |
| `wakeupListInfoCall` | `hw-info-pre` + `{number}` + `hw-info-mid` + `SayUnixTime|{time}` + `silence|500` | |
| `wakeupListMenu` | `hw-lmenu1/2/3` 三段 | |
| `wakeupListCancelCall` | `custom/hw-cancelled` | |
| `wakeConfirmMenu` | `hw-cmenu1/2/3` 三段 | |
| `wakeConfirmDelay` | `hw-conf-pre` + `{delay}` + `hw-conf-post` + `silence|500` | |

**回滚**：

```bash
mysql asterisk -e "delete from kvstore_FreePBX_modules_Hotelwakeup where id='message_zh_CN';"
```

---

## 9. 明确**未改动**的项

| 项 | 说明 |
|---|---|
| `vm-INBOX` / `vm-Urgent` / `vm-messages` 的音文件内容 | 未动音频，只改了语义映射说明 |
| `soundlang_packages` 表 | 未伪造 zh_CN 条目（走 Custom Language 正规路线） |
| `silence/*`、`phonetic/*` 的音文件内容 | 保持原样（本就该是静音/音标词，**不可**做去静音处理） |
| `extensions_additional.conf` | **绝不**手动修改（会被 Apply Config 覆盖） |
| 拨号规则/中继/分机 | 未触碰 |
| 用户真实叫醒记录 | 未删除（测试产生的 call 文件已清理） |

---

## 10. 校验汇总

```bash
# 全仓校验（排除 .git）
sha256sum -c SHA256SUMS

# 关键三件套
sha256sum modules/app_voicemail.so        # 206fc943…8dbd3
md5sum    modules/app_voicemail.so        # 2592d691859105685ed22f563d7dcb17
find sounds/cn -type f | wc -l            # 595
ls sounds/custom/*.wav | wc -l            # 39
```

### 10.1 覆盖度对账（以英文磁盘文件为权威集合）

| 项 | 数量 |
|---|---|
| `core-sounds` 索引条目 | 564 |
| `cn/` 已覆盖 | **563** |
| `cn/` 未覆盖 | 1 → `astcc-followed-by-pound`（**上游索引陈旧键**；磁盘真实文件是 `astcc-followed-by-the-pound-key`，我们已译） |
| `cn/` WAV 总数 | 593 |
| `en/` 全部键（core + extra） | 1910 |

**结论：按磁盘真实文件算，`core-sounds` 100% 覆盖。**
多出的 1300 余条属 `asterisk-extra-sounds`（天气 / 家居 / 州名城市 / 笑话音等），**未翻译**，
只按需补了叫醒电话 28 条与报时 11 条（见 `INSTALL.md` 第 9 节）。

### 10.2 文本索引

`docs/reference/` 里另存了三份，便于比对：

| 文件 | 说明 |
|---|---|
| `core-sounds-cn.source.txt` | 我们维护的**源**索引（488 行，含 zh 专用 6 键） |
| `core-sounds-cn.server-deployed-20260924.txt` | 部署机上的**实际**索引（482 行） |
| `core-sounds-en.txt` | 英文原表，翻译依据 |

> 源索引比部署索引多出 `press / vm-have / vm-haveno / vm-listen / vm-tong / vm-you` 六个
> zh 专用键 —— 本包安装时会用**源索引**覆盖部署索引，把这 6 键补齐。
>
> `followme/*` 的 6 个键在**上游 en 索引里就自带 `.wav` 后缀**（如 `followme/sorry.wav: sorry`），
> 我们的索引沿用同一写法；磁盘文件按无后缀命名，不影响播放。这不是缺陷。
