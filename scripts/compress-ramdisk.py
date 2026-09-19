#!/usr/bin/env python3
"""Deterministic gzip stream; verify every CPIO byte before emitting output.

Build-host dependency: zopfli==0.2.3.post1. No device access or CPIO filtering.
"""
import gzip
import hashlib
import sys

import zopfli.gzip


def compress_stream(source, destination, report, limit=128 * 1024 * 1024):
    raw = source.read(limit + 1)
    if len(raw) > limit:
        raise ValueError("ramdisk exceeds input limit")
    regular = gzip.compress(raw, compresslevel=9, mtime=0)
    optimized = zopfli.gzip.compress(raw, numiterations=15)
    if gzip.decompress(optimized) != raw:
        raise ValueError("Zopfli round-trip verification failed")
    selected, result = min((('gzip9', regular), ('zopfli', optimized)), key=lambda item: len(item[1]))
    if gzip.decompress(result) != raw:
        raise ValueError("gzip round-trip verification failed")
    print(f"input_bytes={len(raw)} gzip9_bytes={len(regular)} "
          f"zopfli_bytes={len(optimized)} selected={selected} "
          f"cpio_sha256={hashlib.sha256(raw).hexdigest()}", file=report)
    destination.write(result)


def main():
    try:
        compress_stream(sys.stdin.buffer, sys.stdout.buffer, sys.stderr)
        return 0
    except (OSError, ValueError, EOFError) as error:
        print("RAMDISK COMPRESSION FAILED: " + str(error), file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
