#!/usr/bin/env python3
"""Patch ONLY the reviewed recovery gzip recipe; fail closed on source drift."""
import argparse
from pathlib import Path
import re
import sys

RULE = ('$(recovery_ramdisk): $(recovery_uncompressed_ramdisk) $(COMPRESSION_COMMAND_DEPS)\n'
        '\t@echo ----- Making compressed recovery ramdisk ------\n'
        '\t$(COMPRESSION_COMMAND) < $(recovery_uncompressed_ramdisk) > $@\n')
MARKER = '# TB300FU verified gzip compression\n'


def patch_text(source, python, compressor):
    # A restricted absolute Linux path avoids make expansion and shell quoting ambiguity.
    for path in (python, compressor):
        if not re.fullmatch(r'/[A-Za-z0-9_./-]+', path):
            raise ValueError('compression tools need simple absolute Linux paths')
    command = f'/usr/bin/timeout 20m {python} {compressor}'
    patched = MARKER + RULE.replace('\t$(COMPRESSION_COMMAND) <', '\t' + command + ' <')
    if source.count(patched) == 1 and MARKER in source and RULE not in source:
        return source
    if MARKER in source or source.count(RULE) != 1:
        raise ValueError('unreviewed or partially patched recovery compression recipe')
    return source.replace(RULE, patched, 1)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('makefile', type=Path)
    parser.add_argument('python')
    parser.add_argument('compressor')
    args = parser.parse_args()
    try:
        original = args.makefile.read_text()
        patched = patch_text(original, args.python, args.compressor)
        if patched != original:
            args.makefile.write_text(patched)
        print('Verified gzip recipe installed; kernel and partition limit unchanged.')
        return 0
    except (OSError, ValueError) as error:
        print(str(error), file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
