#!/usr/bin/env python3
"""Uploads your extracted game (default.xex and media/) to /data/MGR/game_root on the console over FTP.

From the SMW port's uploader: one connection for every file; folders are created as needed; a file already on the
console with the same size is skipped, so an interrupted upload resumes where it stopped. The disc's dashboard
extras ($SystemUpdate, AvatarAssetPack, nxeart) are not needed by the game and are left out. Run it from Windows
(uploads sent from inside WSL were undone on the console, see ps4-kit's scripts/upload.sh):

    py scripts/upload-data.py [source] --host <your PS4's IP> [--port 2121] [--dest /data/MGR/game_root]

source defaults to \\\\wsl.localhost\\Ubuntu\\home\\<user>\\mgr-build\\game (the WSL user from %USERNAME% lowercased, or
MGR_WSL_USER); --host defaults to PS4_HOST. The data is your game: never upload it anywhere else.
"""
import argparse
import ftplib
import os
import posixpath
import sys
import time

GAME_ENTRIES = ("default.xex", "media")


def remote_sizes(ftp, path):
    """name -> size of the files in a remote folder ({} if it does not exist)."""
    lines = []
    try:
        ftp.retrlines("LIST " + path, lines.append)
    except ftplib.error_perm:
        return {}
    sizes = {}
    for line in lines:
        parts = line.split(None, 8)
        if len(parts) == 9 and not line.startswith("d"):
            try:
                sizes[parts[8]] = int(parts[4])
            except ValueError:
                pass
    return sizes


def connect(host, port):
    ftp = ftplib.FTP()
    ftp.connect(host, port, timeout=60)
    ftp.login()
    ftp.voidcmd("TYPE I")
    return ftp


def main():
    user = os.environ.get("MGR_WSL_USER", os.environ.get("USERNAME", "user").lower())
    ap = argparse.ArgumentParser()
    ap.add_argument("source", nargs="?", default=rf"\\wsl.localhost\Ubuntu\home\{user}\mgr-build\game")
    ap.add_argument("--host", default=os.environ.get("PS4_HOST"), help="the PS4's IP address (default: PS4_HOST)")
    ap.add_argument("--port", type=int, default=int(os.environ.get("PS4_FTP_PORT", "2121")))
    ap.add_argument("--dest", default="/data/MGR/game_root")
    a = ap.parse_args()
    if not a.host:
        ap.error("give your PS4's address: --host <IP> (or set PS4_HOST)")
    if not os.path.isfile(os.path.join(a.source, "default.xex")):
        sys.exit(f"no default.xex in {a.source} (extract your disc there: upstream's tools/extract_iso.py)")

    plan = []  # (local path, remote folder, name, size)
    for entry in GAME_ENTRIES:
        top = os.path.join(a.source, entry)
        if os.path.isfile(top):
            plan.append((top, a.dest, entry, os.path.getsize(top)))
            continue
        for d, dirs, files in os.walk(top):
            dirs.sort()
            rel = os.path.relpath(d, a.source).replace(os.sep, "/")
            rdir = posixpath.join(a.dest, rel)
            for f in sorted(files):
                p = os.path.join(d, f)
                plan.append((p, rdir, f, os.path.getsize(p)))
    total = sum(s for *_, s in plan)
    print(f"{len(plan)} files, {total / 2**30:.2f} GB -> ftp://{a.host}:{a.port}{a.dest}", flush=True)

    ftp = connect(a.host, a.port)
    known_dirs, listing = set(), {}
    sent = skipped = done_bytes = 0
    t0 = last = time.time()
    for k, (p, rdir, name, size) in enumerate(plan):
        if rdir not in known_dirs:
            parts = rdir.strip("/").split("/")
            for i in range(1, len(parts) + 1):
                sub = "/" + "/".join(parts[:i])
                if sub in known_dirs:
                    continue
                try:
                    ftp.mkd(sub)
                except ftplib.error_perm:
                    pass  # already there
                known_dirs.add(sub)
            listing[rdir] = remote_sizes(ftp, rdir)
        if listing.get(rdir, {}).get(name) == size:
            skipped += 1
        else:
            for attempt in range(3):
                try:
                    with open(p, "rb") as fh:
                        ftp.storbinary("STOR " + posixpath.join(rdir, name), fh, blocksize=1 << 20)
                    break
                except ftplib.all_errors as e:
                    print(f"  retry {name}: {e}", flush=True)
                    try:
                        ftp.close()
                    except Exception:
                        pass
                    time.sleep(3)
                    ftp = connect(a.host, a.port)
            else:
                sys.exit(f"could not upload {p}")
            sent += 1
        done_bytes += size
        now = time.time()
        if now - last > 30 or k == len(plan) - 1:
            last = now
            rate = done_bytes / max(now - t0, 1e-6) / 2**20
            print(f"  {k + 1}/{len(plan)} files ({sent} sent, {skipped} already there), "
                  f"{done_bytes / 2**30:.2f}/{total / 2**30:.2f} GB, {rate:.1f} MiB/s", flush=True)
    ftp.quit()
    print(f"done in {(time.time() - t0) / 60:.1f} min: {sent} sent, {skipped} already there", flush=True)


if __name__ == "__main__":
    main()
