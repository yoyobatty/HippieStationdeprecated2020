"""Find byondcore.dll addresses for a BYOND build from a build whose addresses are known (byond-tracy's table, 516.1666).

Usage: python find_offsets.py <known build's byondcore.dll (516.1666)> <new build's byondcore.dll>
Prints a row for known_builds[] in hippie_prof.c. Check each function by more than its first bytes: exec_proc in 1688 matched 10
places on its prologue and was told apart by its unusually large stack frame (sub esp, 0x918; 0x968 in 1666).

Functions: the known build's first bytes, with call/jump targets and relocated addresses wildcarded, searched for in the new
build. Globals: every place the known build's code names the global's address (from its relocation table), the same code
found in the new build, and the address it names there read off.
"""
import re
import struct
import sys
from collections import Counter

OLD_DLL, NEW_DLL = sys.argv[1], sys.argv[2]
# byond-tracy's offsets for 516.1666: strings, strings_len, miscs, miscs_len, procdefs, procdefs_len, procdef, exec_proc,
# server_tick, send_maps, prologue
OLD = dict(strings=0x0042CA18, strings_len=0x0042CA1C, miscs=0x0042CA2C, miscs_len=0x0042CA30, procdefs=0x0042CA3C,
           procdefs_len=0x0042CA40, exec_proc=0x0013D6D0, server_tick=0x002287E0, send_maps=0x001DA860)
FUNCS = ['exec_proc', 'server_tick', 'send_maps']
GLOBALS = ['strings', 'strings_len', 'miscs', 'miscs_len', 'procdefs', 'procdefs_len']


class PE:
    def __init__(self, path):
        self.b = open(path, 'rb').read()
        e = struct.unpack_from('<I', self.b, 0x3C)[0]
        nsec = struct.unpack_from('<H', self.b, e + 6)[0]
        opt = e + 24
        self.base = struct.unpack_from('<I', self.b, opt + 28)[0]
        optsize = struct.unpack_from('<H', self.b, e + 20)[0]
        self.secs = []
        for i in range(nsec):
            o = opt + optsize + i * 40
            name = self.b[o:o + 8].rstrip(b'\0').decode()
            vsize, va, rsize, rptr = struct.unpack_from('<IIII', self.b, o + 8)
            self.secs.append((name, va, vsize, rptr, rsize))
        # base relocation directory (data directory 5)
        reloc_rva, reloc_size = struct.unpack_from('<II', self.b, opt + 96 + 5 * 8)
        self.relocs = set()
        p = self.rva2off(reloc_rva)
        end = p + reloc_size
        while p < end:
            page, size = struct.unpack_from('<II', self.b, p)
            if size == 0:
                break
            for k in range((size - 8) // 2):
                ent = struct.unpack_from('<H', self.b, p + 8 + 2 * k)[0]
                if ent >> 12 == 3:
                    self.relocs.add(page + (ent & 0xFFF))
            p += size

    def rva2off(self, rva):
        for name, va, vsize, rptr, rsize in self.secs:
            if va <= rva < va + max(vsize, rsize):
                return rptr + rva - va
        raise ValueError(hex(rva))

    def off2rva(self, off):
        for name, va, vsize, rptr, rsize in self.secs:
            if rptr <= off < rptr + rsize:
                return va + off - rptr
        return None

    def text(self):
        for name, va, vsize, rptr, rsize in self.secs:
            if name == '.text':
                return rptr, rptr + rsize
        raise ValueError('no .text')


def masked_pattern(pe, rva, length):
    """Regex for `length` bytes at rva, with relocated words and call/jump targets wildcarded."""
    off = pe.rva2off(rva)
    data = pe.b[off:off + length]
    wild = [False] * length
    for i in range(length):
        if rva + i in pe.relocs:
            for j in range(i, min(i + 4, length)):
                wild[j] = True
        op = data[i]
        if op in (0xE8, 0xE9) and i + 5 <= length and not wild[i]:
            for j in range(i + 1, i + 5):
                wild[j] = True
        if op == 0x0F and i + 1 < length and 0x80 <= data[i + 1] <= 0x8F and i + 6 <= length:
            for j in range(i + 2, i + 6):
                wild[j] = True
    return b''.join(b'.' if w else re.escape(bytes([c])) for c, w in zip(data, wild)), sum(wild)


def find_func(old, new, rva):
    lo, hi = new.text()
    for length in (64, 48, 32, 24):
        pat, nwild = masked_pattern(old, rva, length)
        hits = [m.start() for m in re.finditer(pat, new.b[lo:hi], re.DOTALL)]
        if len(hits) == 1:
            return new.off2rva(lo + hits[0]), length, nwild
    return None, None, None


def find_global(old, new, rva):
    target = old.base + rva
    lo, hi = old.text()
    sites = [r for r in old.relocs if lo <= old.rva2off(r) < hi and struct.unpack_from('<I', old.b, old.rva2off(r))[0] == target]
    votes = Counter()
    nlo, nhi = new.text()
    for site in sites[:60]:
        before, after = 10, 10
        pat, _ = masked_pattern(old, site - before, before + 4 + after)
        # the global's own address becomes a capture group
        parts = pat.split(b'....', 1)
        hits = [m.start() for m in re.finditer(pat, new.b[nlo:nhi], re.DOTALL)]
        if len(hits) != 1:
            continue
        value = struct.unpack_from('<I', new.b, nlo + hits[0] + before)[0]
        votes[value - new.base] += 1
    return votes, len(sites)


old, new = PE(OLD_DLL), PE(NEW_DLL)
print(f'old base {old.base:#x}, {len(old.relocs)} relocs; new base {new.base:#x}, {len(new.relocs)} relocs')
found = {}
for f in FUNCS:
    rva, length, nwild = find_func(old, new, OLD[f])
    found[f] = rva
    print(f'{f:13} old {OLD[f]:#010x} -> new {rva and hex(rva)} (matched {length} bytes, {nwild} wildcard)')
    if rva:
        print('   old start', old.b[old.rva2off(OLD[f]):old.rva2off(OLD[f]) + 12].hex(' '))
        print('   new start', new.b[new.rva2off(rva):new.rva2off(rva) + 12].hex(' '))
for g in GLOBALS:
    votes, nsites = find_global(old, new, OLD[g])
    best = votes.most_common(3)
    found[g] = best[0][0] if best else None
    print(f'{g:13} old {OLD[g]:#010x} -> votes {[(hex(v), n) for v, n in best]} from {nsites} code sites')
print('table: {' + ', '.join(f'0x{found[k]:08X}' if found.get(k) is not None else 'None' for k in GLOBALS) + ', 0x001C002C, ' +
      ', '.join(f'0x{found[k]:08X}' if found.get(k) else 'None' for k in FUNCS) + ', 0x00050606}')
