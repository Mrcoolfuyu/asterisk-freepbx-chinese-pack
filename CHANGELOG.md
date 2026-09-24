# Changelog

本包的所有改动，按时间倒序。对应 FreePBX 17.0.30 + Asterisk 22.8.2 + Debian 12 (x86_64)。

---

## [1.0.0] — 2026-09-24

首个版本。源自一套线上 FreePBX 的中文语音本地化工程，全部改动均在真实话务环境验证。

### 新增 · 中文语音

- `sounds/cn/` —— **593 个 WAV**（16bit / mono / 8000Hz），覆盖 core-sounds 与 extra-sounds 的英文条目。
  含 `digits/`(94) `letters/`(61) `phonetic/`(27) `dictate/`(12) `silence/`(10) `followme/`(6)。
  - 补入中文语序引擎**专用 6 音**：`vm-you` `vm-have` `vm-tong` `vm-haveno` `vm-listen` `press`
    （英文清单里没有，缺则 `*97` 整段 intro 变哑）。
  - 改写语义：「新留言 / 旧留言 / 紧急留言」、`vm-and`/`vm-messages` 改短静音、`vm-first`「第一条」、`vm-last`「最后一条」。
- `sounds/custom/` —— **39 个 WAV**：报时 11 个（`zh-*` + `beijing-shijian`）、叫醒电话 28 个（`hw-*`）。

### 新增 · 模块补丁

- **`modules/app_voicemail.so`**（306,576 B，sha256 `206fc943…8dbd3`）
  修 `vm_instructions_zh()` 无条件委派英文的问题 → 消除 `*97` 登录后多播的 6 段英文语序菜单。
  配套 `patches/app_voicemail-22.8.2-vm_instructions_zh.patch` 与 `build/build_app_voicemail_wsl.sh`
  （WSL + `debootstrap` 造 Debian 12 chroot，保证 glibc 与目标机一致）。

### 修复 · 报时（`*60`）

- 补 `[sub-hr12format-custom]` 的 **`zh_CN` 分支**（FreePBX 只内置 en/fr/de/ja，zh 会回退 en，
  播出「听到提示音时…二点整 二十五分钟 和 十秒 秒 上午」）。
- 替换三个 `say.c` 硬编码音：`digits/oclock`「点整」→「点」、`minute`/`minutes`「分钟」→「分」。
- 新增 `zh-liang`（两），使 2 点读「两点」而非「二点」。

### 修复 · 叫醒电话（`*68`）

- `agi-bin/wakeup`：`wait_for_digit(1000)` → **`6000`**。
  修「输入 2230 报『输入无效』」——原逻辑只收 3 位 + 1 秒捞第 4 位，按键稍慢即丢位、掉进 12 小时制分支。
- `agi-bin/wakeglobal.php`：`init()` 增加 `set_variable('CHANNEL(language)','zh_CN')`。
- 新增 20 条 KVStore `message_zh_CN` 整句中文，替换模块默认的英文单词片段拼装；
  `SayUnixTime` 格式 `IMpABd` → **`pIM`**（上下午须在前）。
- `hw-add` 重录：明确「**四位数字**，例如 2230」，不再误导用户走 3 位 12 小时制。

### 修复 · 时区（★ 影响最大）

- FreePBX `PHPTIMEZONE` 由 `UTC` 改为 `Asia/Hong_Kong`。
  原状态下**叫醒电话整体偏 8 小时**（设 22:30 实际 06:30 响），
  且 GUI 与语音列表同用错误时区计算 —— **界面上完全看不出**。

### 新增 · 工具

- `install.sh` —— 9 步幂等安装：前置检查 → 全量备份 → 语音 → 模块 → AGI → KVStore → dialplan →
  FreePBX 设置 → 自检。支持 `--dry-run` 与逐段 `--skip-*`。
- `uninstall.sh` —— 一键回滚（自动定位最近备份，或 `--from` 指定）。
- `INSTALL.md` —— 安装保障文档：版本矩阵、6 条硬约束、逐项验证清单、故障排查表、9 条已知坑。
- `MANIFEST.md` —— 逐项改动清单（改了什么 / 为什么 / 怎么核）。

### 已知限制

见 `INSTALL.md` 第 9 节「本次未覆盖事项」。要点：
仅提供 x86_64 模块；`zh_TW`/`zh_HK` 未做；`sub-hr24format` 未接；其他 FreePBX 模块的中文提示未逐一校对；
验收目前靠人工拨测。
