#!/usr/bin/env python3
"""
inject_app.py -- 往已解包的 .app 里注入 dylib 并加加载指令。

与 inject.py 的区别：这个直接操作解包后的目录，方便 CI 里分步执行。
"""
import argparse
import os
import plistlib
import shutil
import sys
from pathlib import Path

try:
    import lief
except ImportError:
    lief = None

DYLIB_NAME = "Player.dylib"
INSTALL_NAME = "@executable_path/Player.dylib"


def log(m):
    print(f"[inject_app] {m}", flush=True)


def parse_macho(path: Path):
    """LIEF 在 Windows 上打不开含非 ASCII 的路径，统一用 chdir + 文件名。"""
    if lief is None:
        raise SystemExit("请先 pip install lief")
    cwd = os.getcwd()
    os.chdir(path.parent)
    try:
        b = lief.MachO.parse(path.name)
    finally:
        os.chdir(cwd)
    if b is None:
        raise SystemExit(f"不是 Mach-O: {path}")
    return b


def write_macho(binary, path: Path):
    cwd = os.getcwd()
    os.chdir(path.parent)
    try:
        tmp = path.name + ".patched"
        binary.write(tmp)
        os.replace(tmp, path.name)
    finally:
        os.chdir(cwd)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--app", required=True, help="解包后的 .app 目录")
    ap.add_argument("--dylib", required=True, help="要注入的 dylib")
    args = ap.parse_args()

    app = Path(args.app).resolve()
    dylib = Path(args.dylib).resolve()
    if not app.is_dir():
        raise SystemExit(f"不是目录: {app}")
    if not dylib.exists():
        raise SystemExit(f"dylib 不存在: {dylib}")

    info = plistlib.loads((app / "Info.plist").read_bytes())
    exe_name = info.get("CFBundleExecutable")
    if not exe_name:
        raise SystemExit("Info.plist 缺少 CFBundleExecutable")
    exe = app / exe_name
    if not exe.exists():
        raise SystemExit(f"可执行文件不存在: {exe}")

    # 1) 拷 dylib
    shutil.copy2(dylib, app / DYLIB_NAME)
    log(f"已拷入 {DYLIB_NAME}")

    # 2) 加 LC_LOAD_DYLIB
    binary = parse_macho(exe)
    added = 0
    for i in range(binary.size):
        fat = binary.at(i)
        if fat is None:
            continue
        if INSTALL_NAME in [c.name for c in fat.libraries]:
            log(f"slice#{i} 已存在，跳过")
            continue
        fat.add(lief.MachO.DylibCommand.load_dylib(INSTALL_NAME))
        added += 1
        log(f"slice#{i} 已加入 {INSTALL_NAME}")

    if added:
        write_macho(binary, exe)

    # 3) 校验
    chk = parse_macho(exe)
    for i in range(chk.size):
        fat = chk.at(i)
        if fat is None:
            continue
        names = [c.name for c in fat.libraries]
        ok = INSTALL_NAME in names
        log(f"verify slice#{i}: {'OK' if ok else 'MISSING'} (共 {len(names)} 条依赖)")
        if not ok:
            raise SystemExit("注入校验失败")

    return 0


if __name__ == "__main__":
    sys.exit(main())