# FreePBX `*60` 报时「不通顺」——根因分析与修复

> 环境：FreePBX 17 / Asterisk 22.8.2（192.168.50.15，Debian 12）
> 日期：2026-09-24
> 相关：`extensions_custom.conf`、`extensions_additional.conf`、`custom/zh-*.wav`

---

## 一、现象

拨打 `*60`（内置 Speaking Clock）进行时间播报，中文听感不通顺。实测抓到的真实播放序列（端点语言 `zh_CN`，零按键）：

```
at-tone-time-exactly
digits/2   digits/oclock
digits/20  digits/5   minute
vm-and
digits/10  second   seconds
digits/a-m
beep
```

按 `core-sounds-cn.txt` 逐条折回中文，实际听到的是：

> 听到提示音时，时间将正好是… **二点整 二十五分钟 和 十秒 秒 上午**

问题点一目了然：

| # | 问题 | 说明 |
|---|---|---|
| 1 | **英文语法残留** | `digits/oclock`(点整)、`minute`(分钟)、`second`/`seconds`(秒)、`vm-and`(和)、`digits/a-m`(上午) 是**英文 `say.conf` 规则**拼出来的句式，直接把中文词填进英文骨架 |
| 2 | **「分钟」错用** | 报"分"应读"分"，`minute` 译成"分钟"是时长单位 |
| 3 | **「十秒 秒」重复** | `second` + `seconds` 连播，中文重复 |
| 4 | **「上午」在句尾** | AM/PM 被排到最后（英文语序），中文应前置做"上午/下午" |

> 注：`cn/`（= `zh_CN` 软链）里这些音**都存在**，所以不是"缺音回退"，而是**英文句式 + 中文词**的混搭。

---

## 二、根因

`*60` 由 `extensions_additional.conf` 的 `[app-speakingclock]` 提供，核心是：

```
*60 → Gosub(sub-hr12format,s,1())
```

而 `[sub-hr12format]`（FreePBX 自动生成）**只内置 en / fr / de / ja 四个语言分支，没有 zh / zh_CN**：

```
[sub-hr12format]
include => sub-hr12format-custom
exten => s,1,GotoIf($[${DIALPLAN_EXISTS(sub-hr12format,${CHANNEL(language)},1)}]?sub-hr12format,${CHANNEL(language)},1:sub-hr12format,en,1)

exten => en,1,Playback(at-tone-time-exactly)
exten => en,n,SayUnixTime(${FutureTime},,IM 'vm-and' S 'seconds' p)   ; ← 英文 say 规则
exten => en,n,Return()
exten => fr,...
exten => de,...
exten => ja,...
```

因为 `zh_CN` 在 `sub-hr12format` 里不存在，`DIALPLAN_EXISTS` 判假 → **回退到 `en` 分支**。`en` 分支用 `SayUnixTime(...,IM 'vm-and' S 'seconds' p)`，走的是 `say.conf` 的**英文** `[en]` 规则（Asterisk 用编译内置默认规则，本机无 `/etc/asterisk/say.conf` 自定义节），于是产出英式句式；具体**音文件**仍按通道语言 `zh_CN` 解析 → 就出现了"英文骨架 + 中文词"的怪句子。

**一句话：`*60` 从设计上就没有中文，中文端点等于在用英文报时模板。**

---

## 三、修复方案

### 3.1 思路

`[sub-hr12format]` 顶部自带 `include => sub-hr12format-custom`，这是 FreePBX 留给用户扩展语言分支的钩子。而 Asterisk 的 `DIALPLAN_EXISTS()` **会遍历 include**，所以在 `extensions_custom.conf` 里给 `[sub-hr12format-custom]` 补一个 `zh_CN` 扩展，即可被 `DIALPLAN_EXISTS(sub-hr12format,zh_CN,1)` 命中并接管 `*60`。

> 实测已验证：补 `zh_CN` 后 `*60` 直接进入自定义分支（`Noop` 命中），不再回退 `en`。

**为什么写 `extensions_custom.conf`**：`extensions_additional.conf` 由 FreePBX GUI 每次 Apply Config 时**重新生成**，手改会被覆盖；`extensions_custom.conf` 是官方指定的用户扩展文件，不会被覆盖，且 `[sub-hr12format-custom]` 与 additional 里的同名 include 天然衔接。

### 3.2 已实施的改动（`/etc/asterisk/extensions_custom.conf`）

```ini
[sub-hr12format-custom]
exten => zh_CN,1,Noop(zh-CN speaking clock, FutureTime=${FutureTime})
 same => n,Playback(custom/beijing-shijian)                 ; 北京时间
 same => n,Set(CH=${STRFTIME(${FutureTime},,%H)})
 same => n,Set(CM=${STRFTIME(${FutureTime},,%M)})
 same => n,Set(CS=${STRFTIME(${FutureTime},,%S)})
 same => n,Set(CH12=$[${CH} % 12])
 same => n,GotoIf($[${CH12} = 0]?zzero,1)
 same => n,Goto(zperiod,1)
exten => zzero,1,Set(CH12=12)
 same => n,Goto(zperiod,1)
exten => zperiod,1,GotoIf($[${CH} < 6]?zdawn,1)
 same => n,GotoIf($[${CH} < 12]?zam,1)
 same => n,GotoIf($[${CH} < 13]?znoon,1)
 same => n,GotoIf($[${CH} < 18]?zpm,1)
 same => n,Goto(zeve,1)
exten => zdawn,1,Playback(custom/zh-lingchen)              ; 凌晨
 same => n,Goto(zsaytime,1)
exten => zam,1,Playback(custom/zh-shangwu)                 ; 上午
 same => n,Goto(zsaytime,1)
exten => znoon,1,Playback(custom/zh-zhongwu)               ; 中午
 same => n,Goto(zsaytime,1)
exten => zpm,1,Playback(custom/zh-xiawu)                   ; 下午
 same => n,Goto(zsaytime,1)
exten => zeve,1,Playback(custom/zh-wanshang)               ; 晚上
 same => n,Goto(zsaytime,1)
exten => zsaytime,1,GotoIf($[${CH12} = 2]?zliang,1)        ; 2 点读"两点"
 same => n,SayNumber(${CH12})
 same => n,Goto(zhour,1)
exten => zliang,1,Playback(custom/zh-liang)                ; 两
 same => n,Goto(zhour,1)
exten => zhour,1,Playback(custom/zh-dian)                  ; 点
 same => n,GotoIf($["${CM}" = "00"]?zsec,1)
 same => n,SayNumber(${CM})
 same => n,Playback(custom/zh-fen)                          ; 分
 same => n,Goto(zsec,1)
exten => zsec,1,GotoIf($["${CS}" = "00"]?zzheng,1)
 same => n,SayNumber(${CS})
 same => n,Playback(custom/zh-miao)                         ; 秒
 same => n,Return()
exten => zzheng,1,Playback(custom/zh-zheng)                ; 整
 same => n,Return()
；语言别名保险
exten => cn,1,Goto(zh_CN,1)
exten => zh,1,Goto(zh_CN,1)
```

**新增音文件**：`/var/lib/asterisk/sounds/custom/zh-liang.wav`（"两"，8286 B，`pcm_s16le/8000/mono/16bit`，md5 `460c301890ab0e6301cb2d103dcc3619`），由 `asterisk-tts-zh` skill 生成。

### 3.3 为什么用 `FutureTime` 而不是 `EPOCH`

`*60` 的语义是"提示音响起时正好是 X 点"——它先播报、再等到 `FutureTime`（当前时间向上取整到下一个 10 秒）踩点响 beep。故分支里用 `FutureTime` 播报，与 beep 时刻严格对应。

### 3.4 时段划分

| 小时 (24h) | 前缀 |
|---|---|
| 0–5 | 凌晨 |
| 6–11 | 上午 |
| 12 | 中午 |
| 13–17 | 下午 |
| 18–23 | 晚上 |

---

## 四、验证

拨测方式：临时上下文 `Set(CHANNEL(language)=zh_CN)` → `Goto(app-speakingclock,*60,1)`，从 `/var/log/asterisk/full` 抓 `Playing '…'`。

**修复后实测序列（零按键，02:30 左右）**：

```
custom/beijing-shijian  ← 北京时间
custom/zh-lingchen      ← 凌晨
custom/zh-liang         ← 两
custom/zh-dian          ← 点
digits/30               ← 三十
custom/zh-fen           ← 分
digits/10               ← 十
custom/zh-miao          ← 秒
beep
（循环）custom/beijing-shijian  custom/zh-lingchen  custom/zh-liang  custom/zh-dian  digits/30  custom/zh-fen  digits/30  custom/zh-miao
```

听感：**「北京时间 凌晨 两点 三十分 十秒」→ 哔 → 「北京时间 凌晨 两点 三十分 三十秒」**，`does not exist` 计数 = 0，`Noop` 命中 2 次（循环正常）。

> `*60` 原生 cadence 保留：播报 → 等待到 10 秒整点 → beep → 等 5 秒 → 循环（最多 5 轮）→ `Playback(goodbye)`（`cn/goodbye.wav` 存在，为中文）。

---

## 五、维护与回滚

- **维护**：改文案只动 `extensions_custom.conf` 里的 `[sub-hr12format-custom]` 段，或替换 `custom/zh-*.wav`；FreePBX Apply Config **不会**影响本文件。
- **依赖音**（均在 `/var/lib/asterisk/sounds/custom/`）：`beijing-shijian`、`zh-lingchen`、`zh-shangwu`、`zh-zhongwu`、`zh-xiawu`、`zh-wanshang`、`zh-liang`、`zh-dian`、`zh-fen`、`zh-miao`、`zh-zheng`。
- **备份**：`/root/extensions_custom.conf.bak-20260924-022848`（改动前）。
- **回滚**：`cp` 回备份 → `asterisk -rx 'dialplan reload'`；如需彻底恢复英文报时可删该段与 `zh-liang.wav`。
- **生效**：`asterisk -rx 'dialplan reload'`（无需重启，零中断）。

---

## 六、遗留与可选

| 项 | 说明 | 建议 |
|---|---|---|
| `*61`（`custom-speakingclock-zh`） | 自建中文报时，逻辑独立、文本自然，但 **2 点仍读"二点"** | 如需统一为"两点"，把其 `saytime` 段加同样的 `CH12==2 → custom/zh-liang` 分支 |
| `sub-hr24format` | 同样缺中文分支；本机**无任何调用点** | 暂不处理 |
| 6–11 点读"上午" | 中文口语更常说"早上" | 可按需替换 `zh-shangwu` 音 |
| 0–5 点读"凌晨" | 可接受 | — |
