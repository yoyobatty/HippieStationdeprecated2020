# BYOND engine audit, 2026-11-16

BYOND 516.1688 (installed), checked against 516.1689 where noted. Server profile: Hippie Station, 25 bot crew, headless testkit
round, 30 s of main-thread sampling (776,000 samples, main thread busy 52.2% of the time). Addresses are RVAs in
`byondcore.dll` 516.1688 (image base 0x10000000). Percentages are of the main thread's busy time unless stated.

Tools (all in `tools/byond_audit/`, none need admin):
- `eip_sample.py <pid> <s> <out> [interval_ms] [tid]`: suspends threads, reads EIP + EBP chain, buckets by module/offset.
- `attribute.py`, `stacks.py`, `fninfo.py`: function totals, caller chains, a function's size/callees/strings/disassembly.
  Function starts are call targets from `dumpbin /disasm` (`data/byond_audit/byondcore_<build>.asm`).
- `string_tree.py <pid>`: walks the live string-intern tree (size, depth).
- `spike_watch.py`: 50 ms windows, reports runs of >= 100 ms busy and what ran.
- `profile_cmd.py <out> <exe> ...`: samples a command (dm.exe) until it exits.
- `op_scaling/op_scaling.dm`, `op_scaling/assoc_split.dm`: stand-alone DM probes of op cost against N.

## Where server time goes (top of byondcore, self time)

| rva | self | what |
|---|---|---|
| 13E750 | 13.1% | bytecode interpreter (0x16CA0 bytes, 29 jump tables) |
| 224810 | 5.9-6.9% | DecRefCount |
| 2030D0 | 5.1-5.7% | var lookup on an object ("undefined variable %s/var/%s"), binary search over (id, value) pairs |
| 131070 | 5.0% | var read ("reading from non-readable variable") |
| 213470 | 4.2-4.5% | binary search in a per-type table (stride 0x98 type records, sorted id array) |
| 24C110 | 4.1-6.9% | plain byte-by-byte strcmp |
| 20C360 | 3.9-4.6% | binary search over 12-byte entries (proc/var table) |
| 2250C0 | 2.8-3.4% | IncRefCount |
| 164860 | 2.6-2.8% | proc call argument setup (named args) |
| 202500 | 2.4% | lookup helper under 2030D0 |
| small helpers | ~8% | 208B40, 10E190, 16EC20, 248D60, 24CA00, 2120C0, 205D40, 226D20, 202E80: 0x20-0x90 byte functions, not inlined |

Malloc/free (ucrtbase) is ~1.2% of the thread. The rest is the tick wait in win32u.

## Findings and proposed changes

### 1. Runtime string interning is an unbalanced binary tree keyed by strcmp (~5.8%)
- `213580` walks a plain BST: node `+0 char*`, `+8 left`, `+12 right`, child picked by the sign of `strcmp` (`24C110`),
  with a "Broken string" guard every 1000 steps. Callers: new runtime strings (`1EE960` from the interpreter) and the
  release path (`221DE0` under DecRefCount): a string whose count reaches 0 is found again **by content** to unlink it.
- Live tree at 25 bots: 282,686 strings, mean depth 22.8 (balanced: 19), **max depth 660**. The deep chains are
  strings made in ascending order: `\ref` text (`[0x2102c5e3]`, 1573 nodes past depth 100), `camera_console_[0x...]_map`,
  and timestamped log lines (`22:31:00 ...`). Every compare on those chains first matches 8+ identical prefix bytes.
- Cost: strcmp 4.1% + walk 1.7% of the busy main thread. Still present in 516.1689 (`102138F5`).
- **Proposal:** hash table for interning (FNV-1a/xxHash over the bytes, open addressing, hash stored per entry so most
  misses never touch the string). Release by string id (the id is already in hand on DecRef) instead of a lookup by
  content. If a tree must stay (sorted iteration somewhere), make it balanced (red-black/AVL) and compare a stored
  hash before strcmp.
- **Hippie side, now:** fewer ascending throwaway strings: bot log lines with leading timestamps, `REF()`/`"\ref"`
  keys built per call, `camera_console_[REF]_map`-style ids.
- **Prototype, measured (`proto/string_hash.c`, injected by `proto/inject.py`):** hooks `213580` and `213890`; the
  tree is relinked as a chain (sentinel.right, then each node's left), so the engine's own link-in and splice-out keep
  working, and a FNV-1a table finds nodes. Repro: new kept ascending string 4.1-6.7 us -> 0.47-0.56 us, existing
  string 0.63-0.76 -> 0.44 us, 0 failures (`proto/string_test.dm`). Live round, 30 bots, `ab_share.py ... strings`:
  3.45% -> 1.23% of busy time. 5 min soak: 2.33M lookups, 743k removals, 0 runtimes, 0 hard deletes.

### 2. Var access is a binary search per access (~15%)
- `2030D0` + `202500`: per-object var override list, binary search on var id (3.7% on the compare loop alone).
- `213470`, `20C360`: binary searches in type / proc tables on the same path.
- **Proposal:** inline caches at each var-access bytecode site (cache type id -> slot index; one compare on a hit),
  or a fixed per-type slot layout so a var read is `obj->vars[slot]` with the override list consulted only for vars
  that were never written. A per-object "last looked up" one-entry cache is the smallest version.
- **Prototype, measured: a search cache does not help (`proto/var_cache.c`).** Hooks `2030D0`, `2031F0`, `213470`
  with a direct-mapped cache of the last index found per (list, var id), checked against the entry's id so it is never
  wrong. Stand-alone test 0 failures. Live round, 30 bots: 90% of reads hit the cache, yet the var-read cluster stayed
  at 11.9% of busy time (off 11.86%, on 11.88%). The samples sit on the first load of the object's override list
  header and entries (and of the cache table itself): the cost is cache misses on scattered objects, not the compares.
  So the fix has to change memory layout (values inline in the object at fixed per-type slots, one load), which needs
  the engine source. The hash-chain walk in `202500` (`202590`, datum id -> record, 1.6-1.8%) is the same kind of cost.

### 3. IncRefCount / DecRefCount pay an exception frame on every call (~11% self)
- The hottest instructions are the prologue/epilogue: SEH registration (`fs:[0]`), the `/GS` cookie (`xor eax,ebp`),
  and a destructor call (`280500`) on a by-value argument (`lea ecx,[ebp+0Ch]`), before the per-type jump table.
  Number and null values (no refcount) take the same path.
- **Proposal:** inline fast path at call sites: `if (type is not refcounted) return;`. Pass the value by const
  reference / plain struct so no destructor runs, mark the functions `noexcept` so MSVC drops the EH frame, and
  `#pragma strict_gs_check(off)` / `__declspec(safebuffers)` on these two.
- **Prototype, measured (`hotpatch.py ... refcount2`/`refcount3`):** entry stub with a per-type dword table (0 =
  original code, 1 = no-op, else call the simple handler directly); refcount3 also retargets all 690 call sites past
  the jmp (no measurable gain). Live round, 30 bots, `ab_share.py`: 8.1% -> 6.4% of busy time; `patch_bench.dm` mixed
  work about -10%. The stub keeps ~5.9%, which is call overhead only an inline check at the caller removes.

### 4. Small helpers aren't inlined (~8%)
- e.g. `248D60` builds a float Value (13 instructions with a frame), `24CA00` builds an id Value, `10E190`, `2120C0`.
  Every function keeps a frame pointer.
- **Proposal:** build with `/GL` + `/LTCG` (whole-program inlining across .cpp files), then PGO (`/GENPROFILE`, run a
  real server, `/USEPROFILE`). PGO usually gives 10-20% on interpreters like this with no source changes.

### 5. Assoc list: inserting a new key scans the whole list (cliff, 0.07% in this round)
- `12F2F0` ("bad list"): before the index tree insert (`10D300`), a backward linear scan over the 8-byte element array
  (`12F330: cmp bl,[ecx+eax*8]`) checks whether the key is already a plain element.
- Measured (stand-alone): new key insert 345 ns at N=10, 533 ns at 1,000, **21.5 us at 100,000, 63 us at 300,000**.
  Existing-key writes stay flat (166 ns). `k in A` is also linear: 110 ns -> **304 us at 300,000**, while
  `!isnull(A[k])` stays 75-214 ns. Unchanged in 516.1689 (`1012F551`).
- **Proposal:** a per-list flag "every element has an index entry", set at creation, cleared when `+=`/`Add`/`Insert`
  adds an element that isn't indexed. While set, skip the scan and answer `in` from the index. Lists built only
  with `A[k] = v`, most of tg's, become O(log n) for both.
- **Hippie side, now:** `!isnull(L[k])` or `L[k]` instead of `k in L` on large keyed lists.

- **Prototype, measured (proto/in_index.c):** hooks `17F8B0` (`in`). For a list, it walks the list's index tree
  (the same order as `24CC60`) and answers a bitwise-equal hit at once; anything else goes to the engine's scan, so a
  key that was only `+=`ed is still found. proto/in_test.dm: 239 answers after dup/cut/remove/insert/swap/len/
  -=/|=/&=/^=/+/Copy/Splice, deleted and reused datum keys, 0/-0 and list keys: **0 differ**. 100,000 keys: hit
  **104.3 us -> 0.94 us**; a miss is unchanged (~106 us), and so is the new-key insert. Both need the per-list flag
  above, kept by every mutation inside the engine; it can't be done from outside.

### 6. Moving onto a turf costs O(things on the turf)
- `new /obj(T)` then `loc = null` with 1,000 plain objs on the tile: 7.9 us; with 20,000: ~300 us.
- **Cause (found while prototyping; the Cross/Uncross guess here before was wrong):** the objs in a loc are a singly
  linked chain of obj ids (head slot from `1FEE80`, next id at obj record +48h, 0xFFFF ends it). Entering
  (`1EF940`) walks the whole chain to append at the tail (loop `1EF986`); leaving (`2149F0`) walks from the head to
  find the predecessor (loop `214A42`).
- **Prototype, measured (proto/turf_chain.c):** both loops jump to a stub that takes the slot from a tail cache and a
  predecessor cache, each checked before use (the cached obj's loc is this loc, its next is END / this obj); a
  failed check walks as before. proto/turf_test.dm: seeded moves, Move(), contents +=/-=, del, objs in boxes and
  mobs, loc = null; 720 contents lists compared in order, **0 differ**. Onto a turf and off again: 1,000 objs
  **6,475 -> 227 ns**, 20,000 objs **241,727 -> 347 ns**.
- **Proposal:** a tail id in the loc record and a prev id in the obj record (a doubly linked chain). Contents order
  stays the same.

### 7. Sleep/spawn queue insert grows with sleepers
- `spawn(rand)` with 10 sleepers 0.67 us, 1,000 -> 2.8 us, 20,000 -> 9-13 us.
- The queue is a sorted array of procs (wake time at +8Ch) with room at both ends (`42E410`, head `42D918`, end
  `42D91C`, cap `42D920`). Insert `16D7B0` binary-searches, then always shifts the front part when there's room in
  front (however long), otherwise shifts the back part one element per loop pass.
- **Prototype, measured (proto/sleep_queue.c):** same array, same order. It moves whichever side is shorter with
  memmove; once, when there's no front room and a long back, it recentres the entries in the free space. Queues under
  256 and a full array go to the engine. proto/sleep_test.dm: 6,857 wake-ups of a seeded run (some re-sleep while
  waking) in the same order, **0 differ**. One spawn with ~27,000 queued: **5,223 -> 557-799 ns** (the engine at
  ~50,000 queued: 13 us).
- **Proposal:** the shorter-side move is a few lines in `16D7B0`. A heap or timer wheel would change the wake order of
  equal times unless it keeps insertion order.

### 8. Number formatting is slow everywhere
- `num2text(x)` ~650-730 ns, and any `"[number]"` string ~1 us. A list read is ~30 ns.
- **Proposal:** integer fast path (values that are whole and below 2^24 printed with a digit loop, no `sprintf("%g")`),
  and Ryu/`std::to_chars` for the rest.
- Sites: `108A40` (number to text, `sprintf("%.6g")` at `108A87`), the `"[x]"` builder's integer `"%d"` append
  (`1B2A57`) and `"%.6g"` append (`1B2A79`), and `num2text(x, digits)` (`"%.*g"` at `1826DE`).
- **Prototype, measured (proto/numfmt.c, proto/numfmt_core.h):** the four calls are retargeted to an exact `%.6g`
  for 1e-4 <= |x| < 999999.5 and a digit loop for integers; ties and other ranges go to the engine's sprintf.
  proto/numfmt_check.c compared every float in that range (630,766,762) and every integer below 2^24 with the CRT:
  **0 differ** (11.9% of floats left to sprintf). proto/num_test.dm: 160,130 texts, 0 differ. `"[i/7]"` **~830 ->
  ~525 ns**, `num2text(i/7)` **790-1,070 -> 488 ns**. `"[i]"` is unchanged at ~520 ns; its cost is interning the
  string, not formatting. In the bot round, formatting is 0.15% of busy time.

### Items 5-8 in the bot round
- Live A/B on the Hippie Station bot round (35 bots, ab_share.py, 2 rounds of 20 s): share of main-thread busy time,
  patch off/on: `in` 0.12/0.13%, turf enter/leave 0.14/0.12%, sleep queue insert 0.09/0.10% (sd 0.01). No gain or
  loss to measure: these are cliffs that only matter on big piles, big keyed lists and many sleepers. Over ~8.5 min
  with each patch going in and out: 0 runtimes, 0 hard deletes, 0 MC alerts.

### Which DM code hits each path (proc_paths.py)
- proc_paths.py pairs each game-thread sample's byondcore path with the DM proc on top of hippie_prof's shadow stack
  (read while the thread is suspended). 300 s of a 30-bot Hippie Station round (data/byond_audit/proc_paths_2.json):
  vars 9.6%, refcount 8.3%, strings 2.6%, datum hash walk 1.7%, assoc new key 0.11%, number text 0.05%, turf 0.03%,
  sleep queue 0.01%, `in` 0.00% of busy samples.
- Vars and refcount are spread over hundreds of procs; no DM proc is more than ~0.6% of busy. Strings: SSgarbage.Queue's
  `"ef"` 13.5% of the string share, bot verbose log lines 5%, timedevent/New 4.4%, progressbar/update 4.3%.
- Ruling 2026-11-16: no DM-side workarounds (under 1% of busy for the lot); the engine reports are the route.

### Compiler (dm.exe)
- **Fixed in 516.1689:** `0FCED0` (compiler string intern) scanned the string table from slot 0 for the first free
  slot on every new string (`100FCF36`, 77% of that function). That loop is gone in 1689 (25 s -> 18 s compile).
- Fresh `.rsc` build is **quadratic in byte-identical files**: 50 copies 1.1 s, 100 3.5 s, 200 13 s, 400 51 s (main
  thread 71% `ZwReadFile`, 22% seeks: each new file is compared against every earlier same-size entry by reading it
  back from disk). Distinct files: 400 in 1.1 s. Hippie has only 13 duplicate copies, so this doesn't affect us.
  Proposal: keep a content hash per `.rsc` entry and compare hashes first.
- Full Hippie compile under load: 47% of the compile thread was in `ZwCreateFile`. Not followed up (machine was busy
  with the server and probes). Next step: count opens per file with a clean machine.

## Not done
- **Item 5 (map sending against client count):** needs several real clients, each logged in with its own key. The
  testkit has one client lane. Not measured.
- **Spikes:** 138 runs of >= 100 ms busy in 5 minutes, all with the same function mix as the average tick, so they are
  heavy ticks of DM work rather than engine stalls. One (t=51 s) had `1876A0` at 18.7%, unnamed. Strings grew
  288k -> 306k in 5 minutes (~60/s), private memory flat (912 -> 913 MB).
- **Inclusive costs:** the EBP walk breaks inside the interpreter (it doesn't keep a frame in all paths), so caller
  chains are partial. Self times above are solid.
