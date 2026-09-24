# patches/ —— 源码级改动证据

三个补丁都能**独立复现**本包的核心修复。它们不是"参考"，是我们实际用过的改动文本。

| 补丁 | 目标文件 | 命中位置 | 解决 |
|---|---|---|---|
| `app_voicemail-22.8.2-vm_instructions_zh.patch` | `apps/app_voicemail.c` | 第 11145 行起（hunk） | `*97` 登录后多播英文语序菜单 |
| `hotelwakeup-wakeup-digit-timeout.patch` | `agi-bin/wakeup` | 第 91 行 | `*68` 输 4 位 `HHMM` 报「输入无效」 |
| `wakeglobal-language-zh_CN.patch` | `agi-bin/wakeglobal.php` | `init()` 内 | AGI 侧强制 `zh_CN` |

---

## 用法

### 1) `app_voicemail.c`（改 Asterisk 源码）

```bash
# 前提：源码版本必须是 22.8.2
cd /usr/src/asterisk-22.8.2
md5sum apps/app_voicemail.c      # 应为 67a97b4d843fe8c4e0e51ba13ee31723

patch -p1 --dry-run < /path/to/patches/app_voicemail-22.8.2-vm_instructions_zh.patch
patch -p1           < /path/to/patches/app_voicemail-22.8.2-vm_instructions_zh.patch

# 然后重编（见 ../build/build_app_voicemail_wsl.sh）
```

若 `--dry-run` 报 hunk failed，说明你的 `app_voicemail.c` 不是 22.8.2 或已被改过 ——
用 `../modules/patch_avm.py` 替代（它会**先断言目标代码块唯一命中**，命中数 ≠ 1 直接报错退出，
比 `patch` 更安全），或手动对照补丁里的上下文改。

### 2) AGI 文件（直接替换即可，补丁仅作留痕）

```bash
# 实际部署请直接用 ../agi/ 下的补丁版文件，别手工 patch AGI
install -m 755 -o asterisk -g asterisk ../agi/wakeup          /var/lib/asterisk/agi-bin/wakeup
install -m 755 -o asterisk -g asterisk ../agi/wakeglobal.php  /var/lib/asterisk/agi-bin/wakeglobal.php
```

检查补丁内容：

```bash
cd /var/lib/asterisk/agi-bin
patch -p1 --dry-run < /path/to/patches/hotelwakeup-wakeup-digit-timeout.patch
patch -p1 --dry-run < /path/to/patches/wakeglobal-language-zh_CN.patch
```

---

## 补丁方向说明

`hotelwakeup-wakeup-digit-timeout.patch` 与 `wakeglobal-language-zh_CN.patch` 的
`---` 一侧是**上游原状**（无改动），`+++` 一侧是**本包**。所以：

- `patch -p1` = 打上我们的改动（部署）
- `patch -p1 -R` = 还原成上游原状（回滚）

`app_voicemail-22.8.2-vm_instructions_zh.patch` 同理：`---` 是 Asterisk 22.8.2 原始代码。

---

## 为什么把补丁也放进仓库

`INSTALL.md` 2.4 说过：`.so` 与 Asterisk 版本强绑定。如果你的环境不是
**Asterisk 22.8.2 + Debian 12 + x86_64**，就不要直接替换 `modules/app_voicemail.so` ——
用这里的补丁在你的版本上重编。补丁 + `build/` 脚本 = 完整的 self-hosted 复现路径。
