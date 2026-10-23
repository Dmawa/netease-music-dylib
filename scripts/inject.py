#!/usr/bin/env python3
"""
inject.py -- 把 Player.dylib 注入宿主 IPA。

只做三件事，全部是「加一条加载指令」，不改宿主原有逻辑：
  1. 解包 IPA，定位 Payload/*.app 的主可执行文件
  2. 往主可执行文件的 LC_LOAD_DYLIB 里加 @executable_path/Player.dylib
  3. 把 dylib 拷进 .app，重打包；尽量 ad-hoc 重签

用法:
  python3 inject.py --ipa host.ipa --dylib Player.dylib --out dist
"""
import argparse
import os
import plistlib
import shutil
import subprocess
import sys
import zipfile
from pathlib import Path

try:
    import lief
except ImportError:  # 只有在真正注入时才需要
    lief = None

DYLIB_INSTALL_NAME = "@executable_path/Player.dylib"
DYLIB_FILENAME = "Player.dylib"


def log(msg: str) -> None:
    print(f"[inject] {msg}", flush=True)


def safe_extract(ipa: Path, work: Path) -> None:
    """防 zip-slip 的解包，并容忍目录条目重复。"""
    root = work.resolve()
    with zipfile.ZipFile(ipa) as zf:
        for info in zf.infolist():
            target = (work / info.filename).resolve()
            if not str(target).startswith(str(root)):
                raise SystemExit(f"非法条目（路径逃逸）: {info.filename}")
            if info.is_dir():
                target.mkdir(parents=True, exist_ok=True)
                continue
            target.parent.mkdir(parents=True, exist_ok=True)
            with zf.open(info) as src, open(target, "wb") as dst:
                shutil.copyfileobj(src, dst)


def find_app(payload: Path) -> Path:
    apps = [p for p in payload.iterdir() if p.suffix == ".app" and p.is_dir()]
    if not apps:
        raise SystemExit("Payload 里没有找到 .app")
    if len(apps) > 1:
        log(f"存在多个 .app，取第一个: {[a.name for a in apps]}")
    return apps[0]


def find_executable(app: Path) -> Path:
    info_path = app / "Info.plist"
    if not info_path.exists():
        raise SystemExit(f"缺少 Info.plist: {info_path}")
    with info_path.open("rb") as fh:
        info = plistlib.load(fh)
    name = info.get("CFBundleExecutable")
    if not name:
        raise SystemExit("Info.plist 缺少 CFBundleExecutable")
    exe = app / name
    if not exe.exists():
        raise SystemExit(f"可执行文件不存在: {exe}")
    return exe


def _parse_macho(exe: Path):
    """LIEF on Windows cannot open paths containing non-ASCII characters.
    Change into the file's directory and pass a bare filename."""
    if lief is None:
        raise SystemExit("pip install lief 后再注入")

    cwd = os.getcwd()
    os.chdir(exe.parent)
    try:
        binary = lief.MachO.parse(exe.name)
    finally:
        os.chdir(cwd)
    if binary is None:
        raise SystemExit("not a Mach-O")
    return binary


def add_load_command(exe: Path) -> None:
    binary = _parse_macho(exe)
    if binary is None:
        raise SystemExit("不是有效的 Mach-O")

    changed = 0
    for i in range(binary.size):
        fat = binary.at(i)
        if fat is None:
            continue
        if DYLIB_INSTALL_NAME in [c.name for c in fat.libraries]:
            log(f"slice#{i} 已存在加载指令，跳过")
            continue
        # LIEF 1.x 用工厂方法；旧版 create() 已移除
        fat.add(lief.MachO.DylibCommand.load_dylib(DYLIB_INSTALL_NAME))
        changed += 1
        log(f"slice#{i} 已加入 {DYLIB_INSTALL_NAME}")

    if changed == 0:
        log("所有 slice 均已注入，未改动")
        return

    tmp = exe.with_name(exe.name + ".patched")
    cwd = os.getcwd()
    os.chdir(exe.parent)
    try:
        binary.write(tmp.name)
    finally:
        os.chdir(cwd)
    os.replace(tmp, exe)


def verify(exe: Path) -> None:
    binary = _parse_macho(exe)
    for i in range(binary.size):
        fat = binary.at(i)
        if fat is None:
            continue
        names = [c.name for c in fat.libraries]
        ok = DYLIB_INSTALL_NAME in names
        log(f"verify slice#{i}: {'OK' if ok else 'MISSING'} (共 {len(names)} 条依赖)")
        if not ok:
            raise SystemExit("注入校验失败")


def resign(app: Path) -> None:
    if shutil.which("codesign") is None:
        log("未找到 codesign（非 macOS），跳过签名。"
            "iOS 会拒绝未签名包，请在 macOS / CI 上执行此步。")
        return

    # 先签嵌套库，再签主包
    for root, _dirs, files in os.walk(app):
        for name in files:
            if name.endswith((".dylib", ".so")):
                subprocess.run(["codesign", "-f", "-s", "-", os.path.join(root, name)],
                               check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run(["codesign", "-f", "-s", "-", str(app)], check=False)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--ipa", required=True)
    ap.add_argument("--dylib", required=True)
    ap.add_argument("--out", default="dist")
    ap.add_argument("--keep", action="store_true", help="保留解包目录")
    args = ap.parse_args()

    ipa = Path(args.ipa).resolve()
    dylib = Path(args.dylib).resolve()
    if not ipa.exists():
        raise SystemExit(f"IPA 不存在: {ipa}")
    if not dylib.exists():
        raise SystemExit(f"dylib 不存在: {dylib}")

    outdir = Path(args.out).resolve()
    outdir.mkdir(parents=True, exist_ok=True)

    work = outdir.parent / (outdir.name + "-work")
    if work.exists():
        shutil.rmtree(work, ignore_errors=True)
    work.mkdir(parents=True, exist_ok=True)
    log(f"工作目录 {work}")

    safe_extract(ipa, work)

    payload = work / "Payload"
    if not payload.exists():
        raise SystemExit("不是标准 IPA：缺少 Payload/")

    app = find_app(payload)
    exe = find_executable(app)
    log(f"宿主 App: {app.name} / 可执行文件: {exe.name}")

    shutil.copy2(dylib, app / DYLIB_FILENAME)
    log(f"{DYLIB_FILENAME} 已拷入 .app")

    add_load_command(exe)
    verify(exe)
    resign(app)

    out_ipa = outdir / f"{app.stem}-nemusic.ipa"
    with zipfile.ZipFile(out_ipa, "w", zipfile.ZIP_DEFLATED) as zf:
        for root, _dirs, files in os.walk(work):
            for name in files:
                full = Path(root) / name
                zf.write(full, full.relative_to(work))

    log(f"完成 -> {out_ipa} ({out_ipa.stat().st_size / 1024 / 1024:.1f} MB)")

    if not args.keep:
        shutil.rmtree(work, ignore_errors=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())