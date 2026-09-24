# FreePBX *97 真实播报文案核对（分机 8514）

> 测试时间：2026-09-24 01:22–01:32  
> 服务器：FreePBX 192.168.50.15（Asterisk 22.8.2）  
> 分机 8514「傅宇手机」，语序语言 = `zh_CN`；留言状态：INBOX 0 条 / Old 2 条 / Urgent 0 条

---

## 一、测试方式与证据

| 方式 | 说明 | 结果 |
|---|---|---|
| ① 真实通话 | 日志中抓到用户本人 **01:22:21** 从 `PJSIP/8514-000000a3` 拨入 `*97`（`VoiceMailMain("8514@default")`），`language 'zh_CN'` | 完整序列见下 |
| ② 受控复现 | 临时上下文 `Set(CHANNEL(language)=zh_CN)` 模拟端点语言 → `Gosub(macro-user-callerid,s,1())` → `VoiceMailMain(8514@default,s)` | `LANGBEFORE=zh_CN`、`LANGAFTER=zh_CN`，序列与①完全一致；`does not exist` = 0 |

> 结论：`macro-user-callerid` 第 27 行是 `ExecIf($["${DB(AMPUSER/${AMPUSER}/language)}" != ""]?Set(CHANNEL(language)=...))` —— **带条件**，
> 8514 的 AstDB 值为空 → **不会覆盖**端点语言，真实拨入稳定走 zh_CN。
> （注：用 Local 通道测试时若不显式设语言，会因"无端点语言"而回落到 `en`，这是测试方法的假象，不是线上问题。）

---

## 二、真实序列 × core-sounds-cn.txt 文案对照

### 阶段 A：登录后自动播报（一个键都不按）

| # | 提示音 | core-sounds-cn.txt 文案 | 连读结果 |
|---|---|---|---|
| 1 | `vm-you` | 您 | |
| 2 | `vm-have` | 有 | |
| 3 | `digits/2` | 二 | |
| 4 | `vm-tong` | 条 | |
| 5 | `vm-Old` | 旧 | |
| 6 | `vm-messages` | 留言 | **您有二条旧留言** |
| 7 | `vm-listen` | 收听 | |
| 8 | `vm-Old` | 旧 | |
| 9 | `vm-messages` | 留言 | |
| 10 | `press` | 请按 | |
| 11 | `digits/1` | 一 | **收听旧留言请按一** |
| 12 | `vm-opts` | 更改文件夹请按2，高级选项请按3，其它语音信箱选项请按0. | |
| 13 | `vm-advopts` | 高级选项请按3 | ← 与 #12 **重复** |
| 14 | `vm-repeat` | 重新听该留言请按5 | |
| 15 | `vm-next` | 收听下一条留言请按6 | |
| 16 | `vm-delete` | 删除该留言请按7 | |
| 17 | `vm-toforward` | 转交这条留言请按8 | |
| 18 | `vm-savemessage` | 保存该留言请按9 | |
| 19 | `vm-helpexit` | 请求帮助请按星号键，退出请按井号键 | |

**整段连读（实际听感）**

> 您有二条旧留言。收听旧留言请按一。更改文件夹请按2，高级选项请按3，其它语音信箱选项请按0。**高级选项请按3**。重新听该留言请按5。收听下一条留言请按6。删除该留言请按7。转交这条留言请按8。保存该留言请按9。请求帮助请按星号键，退出请按井号键。

（#1–#12 = `vm_intro_zh` + `vm_instructions_zh`；#13–#19 = `vm_instructions_en`，即"多出来的那一段"）

### 阶段 B：按 `2` 换文件夹（真实通话中确实按了）

| 提示音 | 文案 | 连读 |
|---|---|---|
| `vm-changeto` | 请选择您需要的文件夹 | |
| `vm-press` + `digits/0` + `vm-for` + `vm-INBOX` + `vm-messages` | 按 / 零 / 收听 / 新的 / 留言 | 按零收听新的留言 |
| `vm-press` + `digits/1` + `vm-for` + `vm-Old` + `vm-messages` | 按 / 一 / 收听 / 旧 / 留言 | 按一收听旧留言 |
| `vm-press` + `digits/2` + `vm-for` + `vm-Work` + `vm-messages` | 按 / 二 / 收听 / 工作 / 留言 | 按二收听工作留言 |
| `vm-press` + `digits/3` + `vm-for` + `vm-Family` + `vm-messages` | 按 / 三 / 收听 / 家庭 / 留言 | 按三收听家庭留言 |
| `vm-press` + `digits/4` + `vm-for` + `vm-Friends` + `vm-messages` | 按 / 四 / 收听 / 朋友 / 留言 | 按四收听朋友留言 |
| `vm-tocancel` | 或按井号键退出 | |

**整段连读**

> 请选择您需要的文件夹。按零收听新的留言。按一收听旧留言。按二收听工作留言。按三收听家庭留言。按四收听朋友留言。或按井号键退出。

### 阶段 C：进留言后的提示音

| 提示音 | 文案 | 连读 |
|---|---|---|
| `vm-advopts` | 高级选项请按3 | |
| `vm-first` + `vm-message` | 第一个 / 留言 | 第一个留言 |
| `vm-repeat` / `vm-next` / `vm-delete` / `vm-toforward` / `vm-savemessage` / `vm-helpexit` | 见上表 | |
| `vm-last` + `vm-message` | 最后 / 留言 | 最后留言 |
| `vm-prev` | 收听上一条留言请按4 | |

---

## 三、通顺度评估

**总体：语义正确、无病句，可以听懂；但有 1 处量词错误、1 处重复播报、若干用词不统一。**

| 级别 | 问题 | 现状 | 建议 |
|---|---|---|---|
| ★ 高 | **「二条」量词搭配错** | `vm-tong`(条) 前的数字由 `say_and_wait` → `digits/2`="二"，得到「您有**二条**旧留言」 | 应为「两**条**」。需在 `say.conf` 为 `zh_CN` 加计数读法规则（影响面大，需谨慎）；若不改，至少知悉这是唯一硬伤 |
| ★ 中 | **「高级选项请按3」连播两遍** | `vm-opts` 内含一次 + `vm_instructions_en` 的 `vm-advopts` 又一次 | 可只改 `vm-opts` 音频，去掉"高级选项请按3"一句（本环境恒为 zh_CN，`vm-opts` 只会在 zh 路径出现，删掉不会丢信息） |
| 中 | 用词不统一 | `vm-repeat`/`vm-delete`/`vm-savemessage` 用"**该**留言"，`vm-toforward` 用"**这条**留言" | 统一为"该留言"或"这条留言" |
| 中 | 缺量词 | `vm-first`+`vm-message`=「第一个留言」；`vm-last`+`vm-message`=「最后留言」 | 宜为「第一条留言」「最后一条留言」 |
| 低 | 「请按一」略显生硬 | 登录菜单 `press`(请按)+`digits/1`="一"；文件夹菜单用 `vm-press`(按)+digits | 口语里 "请按1" 更常见；但"按一/按二"可接受，非错误 |
| 低 | 「收听新的留言」 | `vm-INBOX`="新的" + `vm-messages`="留言" | 宜「收听新留言」。但 `vm-INBOX` 若改成"新"，混合场景会变成「三条**新**和有一条旧留言」（不通），**故建议保留"新的"**，这是权衡后的可接受代价 |
| 低 | `vm-opts` 句尾半角 `.` | "…选项请按0." | 与其它条目风格不一致，重生成时去掉即可 |

### 已确认没问题的部分

- `vm-for`="收听"（曾为"为了"）→ 换文件夹菜单全部通顺
- `vm-repeat`="重新听该留言请按5"、`vm-delete`="删除该留言请按7"、`vm-savemessage`="保存该留言请按9"、`vm-listen`="收听"（本次新改的 4 个）→ 与上下文拼接自然
- `vm-tocancel`="或按井号键退出" → 通顺
- 文件夹名 `vm-Work`/`vm-Family`/`vm-Friends` + `vm-messages` → 「工作留言/家庭留言/朋友留言」✓
- 全流程 `does not exist` = 0，无缺文件

---

## 四、附：本次测试用到的排查命令

```bash
# 1) 真实通话序列（按通道过滤日志）
grep "PJSIP/8514-000000a3" /var/log/asterisk/full | grep "Playing '" \
  | sed -E "s/.*Playing '([^']+)'.*/\1/"

# 2) 确认真实拨入的语言
grep "PJSIP/8514-" /var/log/asterisk/full | grep -E "VoiceMailMain|language" | head

# 3) 受控复现（临时上下文，测完回滚）
# [tts-test-8514b]
# exten => 1,1,Answer()
#  same => n,Wait(1)
#  same => n,Set(CHANNEL(language)=zh_CN)      ; 模拟 PJSIP 端点语言
#  same => n,Set(CALLERID(num)=8514)
#  same => n,Set(AMPUSER=8514)
#  same => n,Gosub(macro-user-callerid,s,1())
#  same => n,NoOp(LANGAFTER=${CHANNEL(language)})
#  same => n,VoiceMailMain(8514@default,s)
#  same => n,Hangup()
```

回滚备份：`/root/extensions_custom.conf.bak-20260924-013054`
