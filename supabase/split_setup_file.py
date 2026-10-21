"""Splits setup_new_environment.sql into parts small enough to paste into
the Supabase SQL Editor one at a time (supabase/setup_parts/).

Cuts only at a blank line between two complete statements, outside any
dollar-quoted body, so every part is whole statements.
Run after build_setup_file.py:
    python supabase/split_setup_file.py
"""
import os
import re

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, 'setup_new_environment.sql')
OUT = os.path.join(HERE, 'setup_parts')
TARGET = 90_000  # bytes per part, roughly

DOLLAR = re.compile(r'\$[A-Za-z_]*\$')
STARTS = re.compile(r'^(--|create|alter|drop|do|insert|select|grant|revoke|update|comment|delete)\b', re.I)


def main():
    lines = open(SRC, encoding='utf-8').read().split('\n')
    # Where a cut is safe: a header line, preceded by a blank line, with no
    # dollar-quoted body open and no statement half-written.
    safe = set()
    open_tag = None
    pending = ''  # text since the last ';' outside quotes
    for i, line in enumerate(lines):
        code = line if open_tag else line.split('--', 1)[0]
        # A blank line between two complete statements, where the next line
        # opens a new statement or a comment.
        if open_tag is None and line.strip() == '' and pending.strip() == '':
            nxt = next((l for l in lines[i + 1:] if l.strip()), '')
            if STARTS.match(nxt):
                safe.add(i + 1)
        for m in DOLLAR.finditer(code):
            tag = m.group(0)
            if open_tag is None:
                open_tag = tag
            elif tag == open_tag:
                open_tag = None
        if open_tag is None:
            pending += code + '\n'
            if ';' in code:
                pending = code.rsplit(';', 1)[1]
    assert open_tag is None, 'unbalanced dollar quote'

    parts, start, size = [], 0, 0
    for i, line in enumerate(lines):
        if i in safe and size >= TARGET and i > start:
            parts.append(lines[start:i])
            start, size = i, 0
        size += len(line.encode('utf-8')) + 1
    parts.append(lines[start:])

    os.makedirs(OUT, exist_ok=True)
    for f in os.listdir(OUT):
        os.remove(os.path.join(OUT, f))
    n = len(parts)
    for k, part in enumerate(parts, 1):
        name = f'part{k}_of_{n}.sql'
        head = (f'-- GENTRI WASA setup -- PART {k} of {n}. Run the parts in order,\n'
                f'-- each once, in the Supabase SQL Editor. (From setup_new_environment.sql.)\n\n')
        with open(os.path.join(OUT, name), 'w', encoding='utf-8', newline='\n') as fh:
            fh.write(head + '\n'.join(part).strip('\n') + '\n')
        print(name, sum(len(l) + 1 for l in part) // 1024, 'KB', len(part), 'lines,', part[0][:60] if part[0].strip() else part[1][:60])


if __name__ == '__main__':
    main()
