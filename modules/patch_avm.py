#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
补丁：Asterisk app_voicemail.c 的 vm_instructions_zh
把「播完中文短菜单后无条件委派 vm_instructions_en」改成「原地等按键」，
从而消除 *97 登录后多播的英文语序菜单（vm-advopts/vm-repeat/.../vm-helpexit）。

用法：
    cd /usr/src/asterisk-22.8.2 && python3 patch_avm.py
（会先断言目标代码块唯一命中，命中数 != 1 直接报错退出，避免误改）

★ 不要额外添加 `vms->starting = 0;`：保留 starting=1 才能让 vm_instructions() 的
  `starting && zh*` 判据持续命中 _zh；清 0 后登录时按 `*` 会掉回 _en 的英文语序菜单。
  vm_instructions_ja() 同样从不清理该标志，照抄它最稳。

已验证版本：Asterisk 22.8.2（apps/app_voicemail.c md5 = 67a97b4d843fe8c4e0e51ba13ee31723）
"""
import sys

P = "apps/app_voicemail.c"

OLD = (
    "\t\tif (!res) {\n"
    "\t\t\tvms->starting = 0;\n"
    "\t\t\treturn vm_instructions_en(chan, vmu, vms, skipadvanced, in_urgent, nodelete);\n"
    "\t\t}\n"
)

NEW = (
    "\t\tif (!res)\n"
    "\t\t\tres = ast_waitfordigit(chan, 6000);\n"
    "\t\tif (!res) {\n"
    "\t\t\tvms->repeats++;\n"
    "\t\t\tif (vms->repeats > 2) {\n"
    "\t\t\t\tres = 't';\n"
    "\t\t\t}\n"
    "\t\t}\n"
)


def main():
    with open(P, encoding="utf-8", errors="surrogateescape") as f:
        s = f.read()

    n = s.count(OLD)
    print("MATCH_COUNT =", n)
    if n != 1:
        print("ERROR: 目标代码块命中数 != 1，拒绝修改（可能版本不符或已被打过补丁）", file=sys.stderr)
        return 1

    with open(P, "w", encoding="utf-8", errors="surrogateescape") as f:
        f.write(s.replace(OLD, NEW, 1))

    print("PATCH_APPLIED_OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
