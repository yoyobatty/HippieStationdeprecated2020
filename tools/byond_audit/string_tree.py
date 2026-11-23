"""Measure byondcore's string-intern tree in a live dd.exe (516.1688 layout).

Globals (rva): 0x430BF0 = string table (node* per string id), 0x430BF4 = count.
Root = table[0]. Node: +0 char*, +8 left, +12 right (from fn 0x213580).

usage: python -I string_tree.py <pid>
"""
import collections, ctypes, ctypes.wintypes as wt, sys

k32 = ctypes.WinDLL("kernel32", use_last_error=True)
psapi = ctypes.WinDLL("psapi", use_last_error=True)


def core_base(h):
    arr = (ctypes.c_void_p * 1024)(); need = wt.DWORD()
    psapi.EnumProcessModulesEx(h, arr, ctypes.sizeof(arr), ctypes.byref(need), 1)
    for i in range(need.value // ctypes.sizeof(ctypes.c_void_p)):
        name = ctypes.create_unicode_buffer(260)
        psapi.GetModuleBaseNameW(h, ctypes.c_void_p(arr[i]), name, 260)
        if name.value.lower() == "byondcore.dll":
            return arr[i]


def main():
    pid = int(sys.argv[1])
    h = k32.OpenProcess(0x0410, False, pid)
    base = core_base(h)
    buf = (wt.DWORD * 4)()

    def rd(addr, n=1):
        if not k32.ReadProcessMemory(h, ctypes.c_void_p(addr), buf, 4 * n, None):
            raise OSError(f"read {addr:#x}")
        return list(buf[:n])

    table, count = rd(base + 0x430BF0, 2)
    root = rd(table)[0]
    depths = collections.Counter()
    stack = [(root, 1)]
    nodes = 0
    while stack:
        node, depth = stack.pop()
        if not node:
            continue
        nodes += 1
        _, _, left, right = rd(node, 4)
        depths[depth] += 1
        stack.append((left, depth + 1))
        stack.append((right, depth + 1))
    total = sum(d * c for d, c in depths.items())
    print(f"string ids {count}, tree nodes {nodes}, max depth {max(depths)}, "
          f"mean depth {total / nodes:.1f}, balanced ideal {nodes.bit_length()}")
    for d in sorted(depths)[::max(1, len(depths) // 20)]:
        print(f"  depth {d:4d}: {depths[d]}")


if __name__ == "__main__":
    main()
