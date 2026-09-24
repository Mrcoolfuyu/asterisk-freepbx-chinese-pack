# asterisk-freepbx-chinese-pack

**FreePBX 17 / Asterisk 22.x 中文语音全套包** —— 不只是"换音文件"，而是把中文播报里**语法不通、中英混播、时间偏移**这些坑一并修掉。

> 面向场景：`*97`（语音信箱）、`*60`（时间播报）、`*68`（叫醒电话）等一堆功能，官方**根本没有中文语音包**，社区包又只给音文件、修不了逻辑。这个包把两边都补齐了。

---

## 为什么需要它

| 问题 | 官方/社区包 | 本包 |
|---|---|---|
| Asterisk 官方音频库有中文吗 | ❌ 只有 `en en_AU en_GB en_NZ es fr it ja ru sv` | ✅ 提供 `cn/` 593 个 WAV |
| FreePBX Sound Languages 有中文吗 | ❌ 只有 14 种语言，无 zh_CN | ✅ 注册为 Custom Language |
| `*97` 播完中文又接一整套英文菜单 | ❌ 需改 `app_voicemail` 源码 | ✅ **提供已编译 `app_voicemail.so`** |
| `*60` 报时读成「…二点整 二十五分钟 和 十秒」 | ❌ 需补 dialplan 的 zh_CN 分支 | ✅ 提供 `sub-hr12format-custom` |
| `*68` 提示是英文片段拼装、输入 4 位报错 | ❌ 需 AGI + KVStore 双改 | ✅ 提供 AGI 补丁 + 20 条中文消息 |
| 叫醒电话整体偏 8 小时 | ❌ 界面看不出，需查 `PHPTIMEZONE` | ✅ 安装脚本自动对齐 |
| 报时里「点整 / 分钟」别扭 | ❌ `say.c` 硬编码音名 | ✅ 替换音文件为「点」「分」 |

---

## 包内容

```
sounds/cn/            593 个 WAV（含 digits/ letters/ followme/ phonetic/ silence/ dictate/）
sounds/custom/         39 个 WAV（28 个叫醒电话 hw-*、10 个报时 zh-*、北京时间播报）
modules/app_voicemail.so   已打补丁（Asterisk 22.8.2 / Debian 12 / x86_64）
agi/                   wakeup、wakeglobal.php（叫醒电话补丁版）
config/                extensions_custom.conf 片段、KVStore message_zh_CN 的 SQL
patches/               三个可复现的 .patch（源码级证据，便于自己重编）
build/                 在 WSL 里 glibc 对齐重编 app_voicemail.so 的脚本
docs/                  六份根因分析报告 + 语音文本索引
install.sh / uninstall.sh   一键安装 / 一键回滚
```

**覆盖度（实测）**：`asterisk-core-sounds` 索引 564 条 → **中文 563 条，按磁盘真实文件算 100%**
（唯一"缺"的是上游索引陈旧键 `astcc-followed-by-pound`，真实文件我们已译）。
`asterisk-extra-sounds`（天气 / 家居 / 州名城市 / 笑话音等 1300 余条）**未翻译**，
只按需补了叫醒电话与报时所需的 39 条 —— 详见 [INSTALL.md 第 9 节](INSTALL.md#9-本次未覆盖事项)。

---

## 快速开始

```bash
# 1. 下载
git clone https://github.com/Mrcoolfuyu/asterisk-freepbx-chinese-pack.git
cd asterisk-freepbx-chinese-pack

# 2. 先干跑一遍，看看它会改什么（不落盘）
sudo bash install.sh --dry-run

# 3. 正式安装（自动全量备份到 /root/zhpack-backup-<时间戳>）
sudo bash install.sh

# 4. 不满意，一键回滚
sudo bash uninstall.sh
```

详细步骤、前置条件、逐项验证与排错见 **[INSTALL.md](INSTALL.md)**；
改了哪些文件、为什么改、怎么核对，见 **[MANIFEST.md](MANIFEST.md)**。

---

## 安装后自测

| 拨测 | 期望 |
|---|---|
| `*97` 不按任何键 | 只播 1~12 段中文后进入等待，**不再接一整套英文菜单** |
| `*98` | 语音信箱中文提示 |
| `*60` | 「北京时间 上午/下午 X 点 X 分 X 秒」或「…X 点整」 |
| `*68` → 按 `1` → 输 `2230` | 直接播「已为您设置叫醒电话」，**不再报输入无效** |

```bash
# 叫醒排程落点核验：mtime 应等于你设定的挂钟时间
stat -c '%y %n' /var/spool/asterisk/outgoing/wuc.*.call
```

---

## 兼容性

| 项 | 要求 |
|---|---|
| Asterisk | **22.8.2**（`app_voicemail.so` 二进制与内核模块 ABI 绑定，版本必须一致） |
| FreePBX | 17.x |
| 系统 | Debian 12 (bookworm)，x86_64 |
| glibc | ≥ 2.36（本 .so 编译于 2.36 环境，最高符号 `GLIBC_2.34`） |

> 版本不一致时**不要**直接替换 `.so`：用 `patches/` + `build/build_app_voicemail_wsl.sh` 在
> 与目标机 glibc 同版的 chroot 里自己重编。音频、AGI、dialplan 三部分与版本无关，可放心使用。

---

## 许可与致谢

- 本包整体以 **GPL-2.0** 发布（见 `LICENSE`）。`app_voicemail.so` 是 Asterisk 的衍生物，必须随 GPL-2.0 分发。
- 语音由 `edge-tts`（微软在线合成，`zh-CN-XiaoxiaoNeural`）生成，再用 ffmpeg 转成 Asterisk 标准的 `8000Hz / mono / 16bit` 并去头尾静音。
- 全部改动源自真实线上环境（FreePBX 17 + Asterisk 22.8.2 + 中国电信 IMS 中继）的实测排查，非理论推导。

**免责**：请先在测试环境验证。生产环境务必保留备份目录；`app_voicemail.so` 替换后如模块加载失败，按 `INSTALL.md` 的「紧急回滚」处理。
