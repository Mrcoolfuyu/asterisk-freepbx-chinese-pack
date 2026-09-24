# FreePBX *68 叫醒电话：hw-add 提示不清 & 输入 2230 报错——根因与修复

> 服务器：FreePBX 17 / Asterisk 22.8.2（192.168.50.15）
> 日期：2026-09-24　执行人：WorkBuddy

---

## 一、用户报告的两个现象

1. `hw-add` 的语音提示**没有说明要输入几位数字、什么格式**，用户不知道怎么输。
2. 想定一个 **22:30** 的叫醒，输入 `2230` 却**报错**（听到「输入无效」）。

---

## 二、现象 1：提示文案缺格式说明

旧提示（音频 `custom/hw-add.wav` 实听转写）：

> **「请输入叫醒时间，例如晚上10点30分，输完请按井号键结束。」**

问题：

- 完全没说「**几位数**」「**什么进制**」，也不知道 22:30 到底该按 `2230` 还是 `1030`；
- 「按井号键结束」把用户往 **3 位 + #** 的老路径引导，而 3 位只能表达 12 小时制的时间（还得再选上/下午），**根本没法直接表达 22:30**。

---

## 三、现象 2：输入 2230 报错——真正的根因（已用真实通话日志坐实）

### 3.1 真实通话日志（用户 03:56 的 *68 实测）

```
03:56:13  AGI agi://127.0.0.1/wakeup 启动
03:56:14  Playing 'custom/hw-welcome.slin'
03:56:16  Playing 'custom/hw-menu1.slin'
03:56:19  Playing 'custom/hw-menu2.slin'      ← 用户按 1（设置）
03:56:24  Playing 'custom/hw-add.slin'        ← 提示开始，开始收数字
03:56:37  Playing 'custom/hw-addtype1.slin'   ← 13s 后：竟然去了「按1上午/按2下午」
03:56:37  Playing 'custom/hw-invalid.slin'    ← 同一秒：判为「输入无效」
03:56:38  Playing 'custom/hw-add.slin'        ← 重试
03:56:47  Playing 'custom/hw-addok.slin'      ← 这次成功
```

关键点：用户输的是 `2230`（4 位），AGI 却走进了 **12 小时制**分支（`hw-addtype1`），紧接着报「输入无效」。

### 3.2 源码事实（`/var/lib/asterisk/agi-bin/wakeup` → `wakeupAdd()`）

```php
$time = $hotelwakeup->sim_background("wakeupAdd", "0123456789", 3);   // ← 只收 3 位！
if(strlen($time) > 1) {
    $last = '';
    if(strlen($time) < 4) {
        $ret = $hotelwakeup->wait_for_digit(1000);                     // ← 第 4 位只等 1000ms！
        if ($ret['result'] > 0) { $last = chr($ret['result']); $last = $last != '#' ? $last : ''; }
    }
    $times = (string)($time.$last);  $time = (int)($time.$last);
}
$type = (strlen($times) == 4) ? 24 : 12;                               // 3 位 → 走 12 小时制
```

`sim_background(..., 3)` 最多只收 **3 位**，之后用 `wait_for_digit(1000)` 再等 **1 秒**去捞第 4 位。
用户按 `2230` 时：

1. `223` 三位被收走；
2. 第 4 位 `0` 与第 3 位之间只要**超过 1 秒**（人按键间隔 + DTMF/网络时延，实测该用户约 2.3s/位），第 4 位就丢了；
3. `times = "223"`（3 位）⇒ `$type = 12` ⇒ **弹出「如需上午请按1，下午请按2」**；
4. 用户那记迟到的 `0` 正好落在这一步，被当成「上/下午选择」= `0`，既不是 1 也不是 2 ⇒ **`optionInvalid` = 「输入无效」**。

> 这也解释了日志里 `hw-addtype1` 与 `hw-invalid` 出现在**同一秒**、且 `hw-addtype2` 没播：用户的 `0` 一到就把 `hw-addtype1` 打断了。

### 3.3 AGI 桩复现（`agi_harness.py`）

| 注入按键 | 结果 |
|---|---|
| `1223`（模拟第 4 位丢失） | `hw-add → hw-addtype1 → hw-addtype2`（落入 12 小时制）**复现** |
| `12230`（4 位齐） | `hw-add → hw-addok + SayUnixTime(...,pIM)` **24 小时制正常** |

---

## 四、修复（已上线）

### 4.1 重录 `hw-add` 提示（说清格式）

新文案：

> **「请输入叫醒时间。请按四位数字输入，例如晚上十点三十分就输入二二三零。」**

- 生成：`asterisk-tts-zh` 流程（edge-tts `zh-CN-XiaoxiaoNeural` → 8000Hz/mono/16bit → 去头尾静音）
- 文件：`/var/lib/asterisk/sounds/custom/hw-add.wav`（120814 B，7.55s，md5 `d9f68d996ff4fb41b92a8243edb82091`）

### 4.2 修 AGI 的第 4 位等待窗口

`/var/lib/asterisk/agi-bin/wakeup`（**同时**改了模块源 `/var/www/html/admin/modules/hotelwakeup/agi-bin/wakeup`）：

```diff
-			$ret = $hotelwakeup->wait_for_digit(1000);
+			$ret = $hotelwakeup->wait_for_digit(6000);
```

- 保持 `sim_background(..., 3)` 与 12 小时制分支不变（改动最小、无回归）；
- 3 位用户按 `#` 立即结束、无需等待；4 位用户有 6 秒窗口从容输入。

---

## 五、★ 顺带发现并修复的**致命问题**：叫醒时间整体偏 8 小时

### 5.1 现象

修完输入问题后验证，输入 `2230` 生成的排程文件竟然是这样：

```
wuc.1790202600.ext.8514.call   mtime = 2026-09-24 06:30:00 +0800   ← 设的是 22:30，排到了 06:30！
```

### 5.2 根因

- 系统/`/etc/localtime` = **Asia/Hong_Kong (+08)**，Asterisk 也用 +08；
- 但 **FreePBX 的时区设置 `PHPTIMEZONE` = `UTC`**，导致所有 FreePBX PHP 进程（含 AGI）都在 UTC 下跑；
- `wakeupAdd()` 里 `convert_time()` 用 `mktime()` 按 **UTC** 把「22:30」换算成时间戳；
- 模块 `generateCallFile()` 用 `touch($file, $time)` 把该时间戳写成 `.call` 文件的 **mtime**，Asterisk 按 mtime 触发 ⇒ **实际在 +08 的 06:30 才响**。
- 更隐蔽的是：**GUI / 语音列表的显示时间同样用 UTC 计算**，显示出来仍是「22:30」，所以**从界面完全看不出差 8 小时**，只会「到点不响/响错时间」。

### 5.3 修复

```bash
fwconsole setting PHPTIMEZONE Asia/Hong_Kong     # 原来 = UTC
```

- 选 `Asia/Hong_Kong` 是为了**与 `/etc/localtime` 完全一致**（同为 +08，无夏令时）；
- 改后 `php -r 'require "/etc/freepbx.conf"; echo date_default_timezone_get();'` 返回 `Asia/Hong_Kong`，AGI 与 GUI 时区一致。

### 5.4 验证

```
输入 2230 → 生成 wuc.1790260200.ext.8514.call
          → mtime = 2026-09-24 22:30:00 +0800   ✅（终于对上了）
模块视图：time=22:30  date=Sep 24 2026   ✅
```

> 注：期间曾试过在 `php.ini` 加 `date.timezone`，**无效**——FreePBX 引导流程会用 `PHPTIMEZONE` 覆盖它。已把那两个临时 ini 文件删除，改由 `PHPTIMEZONE` 统一管控。
> **排查启示**：FreePBX 自托管环境下要判断时区，**必须用带引导的 PHP 去看**（`php -r 'require "/etc/freepbx.conf"; ...'`），光看 `date`（系统）或裸 `php -r` 都会误判。

---

## 六、变更清单与回滚

| # | 变更 | 路径/命令 | 备份/回滚 |
|---|---|---|---|
| 1 | 重录 hw-add 提示 | `/var/lib/asterisk/sounds/custom/hw-add.wav` | 旧文件：`/root/hwadd-old.wav.bak-20260924` |
| 2 | AGI 第4位窗口 1000→6000ms | `/var/lib/asterisk/agi-bin/wakeup` + 模块源同名文件 | 旧文件：`/root/agibak-20260924-041037/{wakeup.live,wakeup.module}` |
| 3 | FreePBX 时区 | `fwconsole setting PHPTIMEZONE Asia/Hong_Kong` | 原值 `UTC`：`fwconsole setting PHPTIMEZONE UTC` |

⚠️ `fwconsole ma upgrade hotelwakeup` 会用模块源覆盖 `agi-bin/wakeup`——升级后需重新打第 2 项补丁（模块源已同步改，可减小概率，但官方包仍会覆盖）。

---

## 七、现在的使用方式（拨 *68）

```
拨 *68
 ├─ 听「您好，这里是叫醒电话服务。」
 ├─ 按 1（设置叫醒）
 ├─ 听到「请输入叫醒时间。请按四位数字输入，例如晚上十点三十分就输入二二三零。」
 ├─ 输入 2 2 3 0        ← 直接 4 位 24 小时制，不用按 #
 └─ 听到「已为您设置叫醒电话，时间是：下午十点三十分。」
```

要点：**4 位数字、HHMM、24 小时制**。
- 22:30 → `2230`　·　06:30 → `0630`　·　00:05 → `0005`
- 老式的「3 位 + #」（12 小时制，再选上/下午）仍然兼容，但**表达不了 22:30**，不再推荐。
