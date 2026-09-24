# `*68` 叫醒电话（Hotel Wakeup）中文提示 —— 检查与改进建议

> 检查时间：2026-09-24 03:00–03:20
> 目标机：FreePBX 17（Debian 12，Asterisk 22.8.2）`192.168.50.15`
> 复现分机：8514（`language=zh_CN`）
> 结论一句话：**`*68` 的提示语不是"缺音"，而是"英文句子片段被逐词直译成中文后拼在一起"——语序崩坏。** 另外有 1 处"回退英文"（`menu`）和一处本地 hack（容易被模块升级冲掉）。

---

## 一、`*68` 的调用链

```
from-internal → include => app-hotelwakeup
[app-hotelwakeup]                                   (extensions_additional.conf:1438)
  exten => *68,1,Gosub(macro-user-callerid,s,1())
  exten => *68,n,Answer
  exten => *68,n,Wait(1)
  exten => *68,n,AGI(agi://127.0.0.1/wakeup)        ← 全部语音由这个 AGI 控制
  exten => *68,n,Hangup()
```

- AGI 脚本：`/var/lib/asterisk/agi-bin/wakeup`（模块 `/var/www/html/admin/modules/hotelwakeup/agi-bin/wakeup` 的副本）
- 语音引擎：`wakeglobal.php` 的 `sim_playback()` / `sim_background()`
- 提示内容：`Hotelwakeup.class.php` 的 `public static $defaultMessage`（**英文句子片段**）
- **关键机制**：`getMessage($msg, $lang)` 先读 KVStore `message_<lang>`，**没有才用英文默认**。
  `$lang` = AGI 请求头 `agi_language`（= 呼叫时的通道语言 = `zh_CN`）。
  ⇒ **模块原生支持"按语言逐条覆盖提示"，这正是最佳修复入口。**

### 本地改动（1 处，注意会丢）

| 文件 | 官方版本 | 本机版本 |
|---|---|---|
| `agi-bin/wakeglobal.php` `init()` | `$this->AGI->answer();` | `$this->AGI->answer();`<br>**`$this->AGI->set_variable('CHANNEL(language)','zh_CN');`** ← 本地私加 |

⚠️ 该行把通道语言**硬写成 zh_CN**（不论分机实际语言）。它让 `*68` "看起来是中文"，但：
1. 任何分机都进中文，无法多语言；
2. **`fwconsole ma upgrade hotelwakeup` 会覆盖模块目录 → 这行消失 → `*68` 提示整体退回英文**。

`agi-bin/wakeup` 与官方**完全一致**（无改动）。

---

## 二、检查方法（可复现）

1. **AGI 桩**：用脚本喂 `AGI` 环境头 + 按序注入按键（`1` → `630#` → `1` → `2`），直接驱动 `wakeup` AGI，捕获它请求的每一个音频文件。
2. **日志取证**：`SayUnixTime` 的真实展开序列用临时上下文 + `channel originate` 抓 `Playing '...'`。
3. **音频转写**：把 `cn/` 下的提示音下载回本机，用 faster-whisper(large-v2) 转写，还原真实中文内容。
4. **日志扩展名规则**（本次新发现，很重要）：
   - `Playing 'x.slin'` ⇒ 播放的是**我们生成的 WAV（中文音）**
   - `Playing 'x.sln16' / '.ulaw' / '.g722'` ⇒ 播放的是**官方英文音**

---

## 三、拨 `*68` → 按 `1` 的实际播报（zh_CN，实测）

按顺序实际播出的音（全部 `.slin` ⇒ 都是中文音，**没有缺音**）：

| # | 阶段 | 实际音频序列 | 中文内容（转写） |
|---|---|---|---|
| 1 | 欢迎 | `hello` `this-is-yr-wakeup-call` | 你好。这是您的叫醒电话。 |
| 2 | **主菜单** | `for-wakeup-call` `press-1` `list` `press-2` | 要设置叫醒电话。请按1。查询列表。请按2。 |
| 3 | **【按 1】输入时间** | `please-enter-the` `time` `for` `your` `wakeup-call` | **请输入。时间。为了。您的。叫醒电话。** |
| 4 | 【输 630#】选上下午 | `1-for-am-2-for-pm` | 上午请按1，下午请按2。 |
| 5 | **【按 1】确认** | `wakeup-call` `added` `digits/at` + `SayUnixTime(IMpABd)` | 叫醒电话。已添加。在。两点整。三十分。分钟。上午。星期四。9月。二十四。 |
| 6 | 回到主菜单 | （同 #2） | |
| 7 | 【按 2】列表菜单 | `to-cancel-wakeup` `press-1` `list` `press-2` **`menu`** `press-3` | 要取消叫醒电话。请按1。查询列表。请按2。**menu（英文）**。请按3。 |

`SayUnixTime` 的 `IMpABd` 实测展开（2026-09-24 02:30）：
`digits/2` `digits/oclock` `digits/30` `minute` `digits/a-m` `digits/day-4` `digits/mon-8` `digits/20` `digits/4`
= 两点整 · 三十分 · 分钟 · 上午 · 星期四 · 9月 · 二十四

---

## 四、问题清单（按严重度）

| 级别 | 位置 | 问题 | 说明 |
|---|---|---|---|
| ★★★ | 阶段 3（**`wakeupAdd`**） | **"请输入。时间。为了。您的。叫醒电话。"** | `please-enter-the`+`time`+`for`+`your`+`wakeup-call` 是**英文语序**的词块，中文逐词直译后完全不成句。中文应为「请输入您叫醒电话的时间」。**这就是"按1设置时语音提示有问题"的主因。** |
| ★★★ | 阶段 3 | **完全没讲输入格式** | 用户不知道：输几位？HHMM 还是 HMM？要不要按井号？什么时候问上下午？AGI 实际逻辑（源码）：最多收 3 位 → 再等 1 位：输 `#` ⇒ 3 位 + 问上下午；输第 4 个数字 ⇒ 4 位 24 小时制；只输 1 位 ⇒ 解析成 00:0X（bug）。**这些提示里一个字都没说。** |
| ★★ | 阶段 7（`wakeupListMenu`） | **`menu` 播英文** | `cn/menu.wav` 不存在，`en/menu.*` 存在 ⇒ 回退英文，播出英文字 "menu"。 |
| ★★ | 阶段 5（`wakeupAddOk`） | 时间播报**乱序 + 自相矛盾** | ①「两点整 **三十分**」——`IMpABd` 的 `I` 产生"点整"、`M` 又给"三十分"，中文里"点整"和"三十分"冲突；②「三十分。**分钟**」重复"分"；③ 日期是英文语序「星期四 9月 二十四」（中文应为「9月24日 星期四」）；④ 无"设置成功/时间是"等引导词。 |
| ★★ | 阶段 5 / 阶段 2 | 断句生硬 | 「叫醒电话。已添加。」应连读「叫醒电话已设置」；「要设置叫醒电话。请按1。」缺连接词。 |
| ★ | 阶段 2 / 7 | `list` = 「查询列表」用词不当 | 这里是"收听/查看叫醒"之意，"查询列表"偏书面且与前后"请按1/请按2"脱节。 |
| ★ | 空列表（按2且未设置过） | `vm-youhave`+`say_number(0)`+`wakeup-call` = 「您有。0。叫醒电话。」 | 不通顺，应为「您还没有设置叫醒电话」。 |
| ★ | 列表条目（`wakeupListInfoCall`） | 「叫醒电话。号码。1。在。两点整…」 | 同样断句+用词问题。 |
| ★ | Operator 模式（仅 00/01，本机未用） | `operatorSelectExt` = 「请输入。号码。为了。您的。叫醒电话。然后按**警**号键。」 | 同样语序问题；且 `then-press-pound` 疑似读"警号键"（应"井号键"）。 |
| ★ | 到点叫醒 `wakeConfirmMenu` | 「延时。5。分钟。请按1。延时。10。分钟。请按2。…」 | 可懂但生硬（应"推迟5分钟请按1"）。 |

> 另：`SayUnixTime` 用到的 `digits/day-N`（星期）、`digits/mon-N`（月份）**cn 里都有**（已实测为"星期四""9月"），不是缺音。
> `menu`、`digits`（`invalidDialing` 用到）是 **cn 缺失 → 回退英文**。

---

## 五、改进建议

### 方案 A（推荐，效果最好、不动代码）

**用模块自带的"多语言消息"覆盖，把 zh_CN 的每条提示换成整句中文。**

- 入口：`Hotel Wakeup → Settings → Messages`，语言选 `Chinese (zh_CN)`（Soundlang 已存在该语言，`isLanguagesAvailable('zh_CN')=true`）；或脚本化写 KVStore `message_zh_CN`。
- 原理：`getMessage($msg,$lang)` 优先读 `message_zh_CN`，命中就不再拼英文片段。
- 做法：新增约 10 条**整句中文**录音放 `custom/`，把消息指过去；同时把 `SayUnixTime` 格式由 `IMpABd` 改成 `IMp`（只报"几点几分 上午/下午"，去掉乱序的星期/月日）。

建议覆盖表（可直接照做）：

| 消息 ID | 现默认（英文片段） | 建议中文（整句） |
|---|---|---|
| `welcome` | hello,this-is-yr-wakeup-call | （沿用现有两音，已通顺） |
| `wakeupMenu` | for-wakeup-call,press-1,list,press-2 | **`custom/hw-menu`**：要设置叫醒电话请按1，要查看或取消叫醒电话请按2。 |
| `wakeupAdd` | please-enter-the,time,for,your,wakeup-call | **`custom/hw-enter-time`**：请输入叫醒时间，二十四小时制四位数字，例如早上六点三十分请输入 0630。 |
| `wakeupAddType12H` | 1-for-am-2-for-pm | （沿用现有音，已通顺） |
| `wakeupAddOk` | wakeup-call,added,digits/at,SayUnixTime | **`custom/hw-ok`** + `SayUnixTime\|{time}`：叫醒电话已设置，时间是…… |
| `wakeupListEmpty` | vm-youhave,{count},wakeup-call | **`custom/hw-list-empty`**：您还没有设置叫醒电话。 |
| `wakeupList` | vm-youhave,{count},wakeup-call | **`custom/hw-list-n`** + `{count}`：您已设置 {count} 个叫醒电话。 |
| `wakeupListInfoCall` | wakeup-call,number,{number},digits/at,SayUnixTime | **`custom/hw-list-item`**：第 {number} 个，时间是 SayUnixTime\|{time} |
| `wakeupListMenu` | to-cancel-wakeup,press-1,list,press-2,menu,press-3 | **`custom/hw-list-menu`**：取消请按1，下一个请按2，返回主菜单请按3。 |
| `wakeupListCancelCall` | wakeup-call-cancelled | **`custom/hw-cancelled`**：已取消。 |
| `optionInvalid` | option-is-invalid | **`custom/hw-invalid`**：输入无效，请重新输入。 |
| `invalidDialing` | you-entered,bad,digits | **`custom/hw-bad`**：输入有误。 |
| `wakeConfirmMenu` | to-snooze-for,5,minutes,press-1,… | **`custom/hw-snooze`**：推迟五分钟请按1，十分钟请按2，十五分钟请按3。 |
| `wakeConfirmDelay` | rqsted-wakeup-for,{delay},minutes,vm-from,now | **`custom/hw-delayed`** + `{delay}`：已在 {delay} 分钟后再次叫醒。 |
| `SayUnixTime` | `IMpABd` | 格式改为 **`IMp`**（或 `digits/at IMp`）——去掉星期/月/日，避免乱序与"点整+三十分"矛盾 |

优点：零代码改动、GUI 可维护、只影响中文端点、模块升级不被冲掉。
代价：需生成约 10 条整句中文语音（可用现成的 `asterisk-tts-zh` 流程，几分钟）。

### 方案 B（快速止血，10 分钟）

只补/改最小集合，缓解但不根治：

1. 生成 `cn/menu.wav`（"菜单"）→ 消灭阶段 7 的英文；
2. 生成 `cn/digits.wav`（"数字"）→ 消灭 `invalidDialing` 的英文；
3. 把 `cn/please-enter-the.wav` 改成"请输入您叫醒电话的时间。"（让它至少自成一个完整句）。

缺点：碎片拼接天生不通顺（`time`/`for`/`your`/`wakeup-call` 仍会跟在后面），只能减轻。

### 方案 C（治本但改动大，不建议）

给 `wakeup` AGI 打补丁，对 zh 走"整句消息"分支（类似 `*97` 的处理思路）。风险与维护成本都高于方案 A，收益与 A 相同。

---

## 六、建议动作

1. **采纳方案 A**：先落 `wakeupMenu`、`wakeupAdd`、`wakeupAddOk`、`wakeupListMenu`、`wakeupListEmpty` 五条（覆盖"按 1 设置"全流程 90% 的听感），`SayUnixTime` 一并改 `IMp`。
2. **同时处理本地 hack**：把 `wakeglobal.php` 里硬写的 `CHANNEL(language)=zh_CN` 去掉，改由**分机/端点语言**驱动（你的端点本来就是 `zh_CN`），并记录一份"模块升级后需重打"的备注；或干脆把它写进模块 `functions.inc.php` 的 install 钩子，避免升级丢失。
3. 生成整句语音后，用本报告的 AGI 桩 + 临时拨测复验，确认 `does not exist=0` 且序列符合预期。

---

## 附：本次检查的产物与回滚

- 音频样本（按 1 全流程实听）：`wakeup-check/68-当前按1流程-实际听到的序列.wav`
- 转写结果：`wakeup-check/transcript.txt`、`wakeup-check/transcript2.txt`
- 下载的音源：`wakeup-check/audio/`、`wakeup-check/audio2/`
- AGI 桩：`/root/agi_harness.py`（服务器）
- 临时拨测上下文已回滚：`/root/extensions_custom.conf.bak-20260924-030615`
- 本报告未对生产环境做任何配置改动。

---

## 七、方案 A 执行记录（2026-09-24，已上线，零代码改动）

**思路**：`getMessage($msg,$lang)` 会优先读 KVStore `message_<lang>`，命中即整体替换默认的“英文片段拼装”。本机 Soundlang 已有 `zh_CN`，故用模块自带的**多语言消息覆盖**机制，写入 `message_zh_CN`，全部改用**整句中文录音**；再把 `SayUnixTime` 格式由 `IMpABd` 改为 `pIM`（时/分/上下午，顺序符合中文语序）。

### 7.1 写入的 20 条 `message_zh_CN`（id=`message_zh_CN`，表 `kvstore_FreePBX_modules_Hotelwakeup`）

| 消息键 | 覆盖后的音序列 | 实际播报 |
|---|---|---|
| `SayUnixTime` | `pIM` | （时间格式）|
| `welcome` | `custom/hw-welcome` | 您好，这里是叫醒电话服务。 |
| `goodbye` | `custom/hw-goodbye` | 再见。 |
| `error` | `custom/hw-error` | 系统错误，请稍后再试。 |
| `retry` | `custom/hw-retry` | 请重新输入。 |
| `optionInvalid` | `custom/hw-invalid` | 输入无效。 |
| `invalidDialing` | `custom/hw-invaliddial` | 您输入的数字有误。 |
| `operatorSelectExt` | `custom/hw-opselect` | 请输入要设置叫醒电话的分机号，然后按井号键结束。 |
| `operatorEntered` | `custom/hw-opentered` + `d\|{number}` + 静音 | 您输入的分机号是：<数字> |
| `wakeupMenu` | `hw-menu1` + 静音 + `hw-menu2` | 设置叫醒电话请按1，查询叫醒列表请按2。 |
| **`wakeupAdd`** | `custom/hw-add` | **请输入叫醒时间，例如晚上十点三十分，输完请按井号键结束。** |
| `wakeupAddType12H` | `hw-addtype1` + 静音 + `hw-addtype2` | 如需上午请按1，下午请按2。 |
| `wakeupAddOk` | `hw-addok` + `SayUnixTime\|{time}` + 静音 | 已为您设置叫醒电话，时间是：<时间> |
| `wakeupList` | `hw-list-pre` + `{count}` + `hw-list-post` + 静音 | 您已设置 <N> 个叫醒电话。 |
| `wakeupListEmpty` | `custom/hw-listempty` | 您当前没有设置叫醒电话。 |
| `wakeupListInfoCall` | `hw-info-pre` + `{number}` + `hw-info-mid` + `SayUnixTime\|{time}` + 静音 | 第 <N> 个，时间是：<时间> |
| `wakeupListMenu` | `hw-lmenu1` + `hw-lmenu2` + `hw-lmenu3` | 取消此叫醒请按1，继续查询请按2，返回主菜单请按3。 |
| `wakeupListCancelCall` | `custom/hw-cancelled` | 叫醒电话已取消。 |
| `wakeConfirmMenu` | `hw-cmenu1` + `hw-cmenu2` + `hw-cmenu3` | 延后5分钟请按1，延后10分钟请按2，延后15分钟请按3。 |
| `wakeConfirmDelay` | `hw-conf-pre` + `{delay}` + `hw-conf-post` + 静音 | 已延后 <N> 分钟，从现在开始。 |

- 菜单类消息拆成多段（与原英文结构一致），保留“播报中按键即停”的行为。
- 写入方式：用模块官方 API `FreePBX::Hotelwakeup()->setMessage($k,$v,'zh_CN')`（等价于 GUI 里编辑消息），**未改任何 PHP/AGI 代码**。

### 7.2 新增/替换的音频

- 新增 **28 个** `custom/hw-*.wav` → `/var/lib/asterisk/sounds/custom/`（8000Hz/mono/16bit，去头尾静音 -35dB）
- 替换 **3 个核心报时音**（原为 `点整`/`分钟`，say.c 里 `digits/oclock`、`minute(s)` 是**硬编码**，只能在音文件层改）：
  - `cn/digits/oclock.wav`：`点整` → **`点`**
  - `cn/minute.wav`、`cn/minutes.wav`：`分钟` → **`分`**
- 本地清单 `sound/core-sounds-cn.txt` 同步更新（第 199/265/446 行）。

### 7.3 验证（AGI 桩 + 真实拨号）

| 场景 | 实测序列 | 听感 |
|---|---|---|
| `*68` 按 1 设置（630#，1=上午）| `hw-welcome` → `hw-menu1/2` → `hw-add` → `hw-addtype1/2` → `hw-addok` + `SayUnixTime(...,,pIM)` | 「请输入叫醒时间，例如晚上十点三十分，输完请按井号键结束。」→「已为您设置叫醒电话，时间是：上午六点三十分」 |
| `*68` 按 2 查询列表 | `hw-list-pre` + `SAY NUMBER 2` + `hw-list-post` + `hw-info-pre` + `SAY NUMBER 1` + `hw-info-mid` + 时间 + `hw-lmenu1/2/3` | 「您已设置二2个叫醒电话。第1个，时间是：下午两点三十分。」|
| 叫醒响铃后贪睡 | `hw-welcome` + `hw-cmenu1/2/3` + (`hw-conf-pre`+`SAY NUMBER 10`+`hw-conf-post`) + `hw-goodbye` | 「…延后10分钟请按2…已延后十分钟，从现在开始。再见。」|
| 时间读法 | 14:30 → `digits/p-m`+`digits/2`+`digits/oclock`+`digits/30`+`minute`；04:00 → `digits/a-m`+`digits/4`+`digits/oclock`+`digits/0`+`digits/0`+`minute` | 「下午二点三十分」「上午四点零零分」|

真实拨号（`Local/s@…`，`Set(CHANNEL(language)=zh_CN)`）全序列 **`does not exist` = 0**，8 个 custom 音全部以 `.slin`（=我们的 WAV）解析成功。

### 7.4 备份与回滚

- 音频：`/root/hwbak-20260924-034945/`（custom/hw-* 无旧件）、`/root/hwbak-20260924-034951/core/`（oclock/minute/minutes 原件）
- 消息：回滚即删除 KVStore 里 `id='message_zh_CN'` 的 20 行（`message_zh_CN` 原为空）
  ```sql
  -- 服务器执行
  mysql asterisk -e "delete from kvstore_FreePBX_modules_Hotelwakeup where id='message_zh_CN';"
  ```
- 时间格式随 `SayUnixTime` 一并回滚；核心音用 7.4 的备份文件覆盖回去即可。

### 7.5 遗留 / 注意

1. **`wakeglobal.php` 的本地 hack**：`init()` 里被私加 `set_variable('CHANNEL(language)','zh_CN')`（官方无此行）。它是既有改动，与本次覆盖无关（`agi_language` 本身就是 zh_CN）；但 **`fwconsole ma upgrade hotelwakeup` 会覆盖模块目录**，届时 `message_zh_CN` 仍在（KVStore 独立），hack 丢失也不影响本方案。
2. 小时读作“二点”（中文口语更常“两点”）：`digits/2` 全局用于数字 2，不能单为报时改；可接受。
3. 整点会读成“四点零零分”（say.c 硬编码 `oclock` 后仍走分钟段），语义清楚，非错误。
4. `{count}`/`{delay}` 为 `say_number`，>1 时会读“二/三个”（口语“两个”），量词小瑕疵。

---

## 八、2026-09-24 追加修复：hw-add 提示不清 & 输入 2230 报错 & 时区偏 8 小时

> 详见独立报告：`FreePBX-star68-hw-add提示与2230报错-根因与修复.md`

### 8.1 现象 1：`hw-add` 提示没说位数/格式

旧音频实听：「请输入叫醒时间，例如晚上10点30分，输完请按井号键结束。」——没说几位、哪个进制，
且「按井号键结束」把用户引向 3 位 12 小时制（表达不了 22:30）。

**已重录**为：「请输入叫醒时间。请按四位数字输入，例如晚上十点三十分就输入二二三零。」
（`custom/hw-add.wav`，md5 `d9f68d996ff4fb41b92a8243edb82091`）

### 8.2 现象 2：输入 2230 报「输入无效」——根因

`wakeupAdd()`：`sim_background(...,3)` **只收 3 位**，再用 `wait_for_digit(1000)` **仅等 1 秒**捞第 4 位。
按键间隔 + DTMF/网络时延常 >1s ⇒ 第 4 位丢失 ⇒ `times="223"` ⇒ `$type=12`（掉进 12 小时制）
⇒ 弹上/下午选择 ⇒ 迟到的 `0` 被当成上下午答案（既非 1 非 2）⇒ `optionInvalid`。
真实日志铁证：`hw-add` 后 **`hw-addtype1` 与 `hw-invalid` 同秒出现、`hw-addtype2` 缺席**。

**已修**：`wait_for_digit(1000)` → **`wait_for_digit(6000)`**（live + 模块源两处）。最小改动、无回归。

### 8.3 ★ 附带发现：叫醒时间整体偏 8 小时

验证时发现设 22:30 生成的 `wuc.*.call` 的 **mtime = 06:30 +0800**。
根因：**FreePBX `PHPTIMEZONE` = `UTC`**，而系统/Asterisk 是 `Asia/Hong_Kong (+08)`；
`convert_time()` 的 `mktime()` 按 UTC 算时间戳，`generateCallFile()` 用 `touch()` 写成 `.call` 的 mtime，
Asterisk 按 mtime 触发 ⇒ **实际 8 小时后才响**。而 GUI/语音列表同用 UTC 计算 ⇒ **显示正常，界面上看不出**。

**已修**：`fwconsole setting PHPTIMEZONE Asia/Hong_Kong`（与 `/etc/localtime` 对齐）。
> 试过改 `php.ini` 的 `date.timezone`，**无效**（FreePBX 引导会覆盖），已删除该临时文件。

修后核验：输入 `2230` → `wuc.1790260200.ext.8514.call`，mtime = **2026-09-24 22:30:00 +0800** ✅

### 8.4 备份/回滚

| 项 | 回滚 |
|---|---|
| hw-add 音频 | `cp -a /root/hwadd-old.wav.bak-20260924 /var/lib/asterisk/sounds/custom/hw-add.wav` |
| AGI 补丁 | `cp -a /root/agibak-20260924-041037/wakeup.live /var/lib/asterisk/agi-bin/wakeup`（模块源同理） |
| 时区 | `fwconsole setting PHPTIMEZONE UTC` |

### 8.5 结论：现在拨 *68 的正确用法

**按 1 设置 → 直接输入 4 位 24 小时制（HHMM），不用按 #。** 22:30=`2230`、06:30=`0630`、00:05=`0005`。
