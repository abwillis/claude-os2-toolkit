# DOSCALL1.DLL's data objects (5-11)

What is in each data object of IBM's `DOSCALL1.DLL` (OS/2 Warp 4.5, SMP and uniprocessor builds): every
named cell, what it holds, its initial value in the shipped image, which routines read and write it,
which exports bind it, and what lock covers it.

## What these objects are

`DOSCALL1.DLL` carries the parts of the system IBM implemented outside `os2krnl` but which every
process depends on - the session manager, the base video subsystem (BVS) and the keyboard/mouse
routers, the 16-bit IPC queues, NLS and message caches, and per-process runtime state - and their
data lives in the module's data objects 5 to 11 `[OBS-RE]`. `DOSCALL1.DLL` is one of the system DLLs
the kernel loads during its own initialisation, initialised before every other module, so these
objects exist, with their initial contents and their init code's results, before any application
runs `[OBS-RE]`.

| object | segment group (`.SYM`) | SMP size | sharing | data exports bound into it |
|---|---|---|---|---|
| 5 | `SHRDATA_GROUP` | 0x1170 | shared - one copy for the system | 855 `DosSMSysInit`, 856 `QhKeybdHandle`, 857 `QhMouseHandle` |
| 6 | `DGROUP` | 0x1DC0 | instance - one per process | 414 `_QUEINST_DATA` (+0x126A) |
| 7 | `OS2CHAR_GROUP` (`BVSGLOBAL`) | 0x0F24 | shared | 858-863 (`CHRQueueRamSem`, `CHRArray`, `CHRPIDArray`, `CHRInitialized`, `CHRArraySize`, `CHRBVSGLOBAL`) |
| 8 | `OS2CHAR_I_GROUP` (`SMGINSTANCE` + `BVHINSTANCE`) | 0x05D0 | instance | 864 `CHRSMGINSTANCE` (+0x000), 865 `CHRBVHINSTANCE` (+0x1B0; UNI +0x160) |
| 9 | (no symbols) - `_QSEG1` | 0x1000 | shared | none |
| 10 | (no symbols) - `_QSEG2` | 0x1000 | shared | none |
| 11 | `FAR_BSS` - `_SpawnData` | 0x0030 | instance | none |

Sizes and sharing are the SMP LX object table's; objects 5-8 grow at run time (each object's section
says how). Every data object carries the 16-bit alias flag, so each is reachable by a selector as well
as flat `[OBS-RE]`. Objects 9, 10 and 11 have no image bytes (map size 0): the loader hands them out
zero-filled `[OBS-RE]`.

**How other modules reach them** `[OBS-RE]`. Only through `DOSCALL1.DLL`'s own linkage: an importer's
fixup to one of the data exports above is resolved through `DOSCALL1`'s entry table, whose entry names
an object and an offset (for example `PMMERGE` binds 855 by a selector and a 16-bit offset fixup, and
856 by those and a 32-bit offset fixup - both its 16:16 and flat forms); a run-time
`DosGetProcAddr` by ordinal resolves the same entries (`SYSINIT` does so for 855); and some
`DOSCALL1` routines hand out addresses or selectors of cells to their callers (`DosSMHDeInit`, #711,
returns 16:16 addresses of object-5 cells to `HARDERR.EXE`). The objects have no name in the
`\SHAREMEM\` namespace and no other lookup `[INF]`. A shared object is one copy at one address in
every process; an instance object has one address in every process with private contents.
`DOSCALL1`'s own 16-bit code reaches objects 5 and 6 through its data selectors (every 16-bit entry
runs with `DS` = object 6), and its 32-bit code through their flat addresses `[OBS-RE]`.

**Conventions.**

- Binaries: the SMP build of `DOSCALL1.DLL` with its `DOSCALL1.SYM`, and the uniprocessor
  (UNI) build with its `doscall1.sym`. **Offsets are SMP** unless marked UNI. Where the UNI offset
  differs it is given; across most of object 5 the UNI offset is the SMP offset - 0x30.
- `objN+0xNNNN` / `objN:0xNNNN` is an offset inside LX object N of `DOSCALL1.DLL`. Code objects:
  obj1 (UNI fast-safe primitive), obj2 (32-bit code), obj3 and obj4 (16-bit code). Data objects:
  obj5 (selector `0x9807`, flat base `0x13000000` in SMP), obj6 (`DGROUP`, selector `0x980F`,
  flat base `0x13010000`), obj7 (`BVSGLOBAL`), obj8 (`BVHINSTANCE`, selector `0x981F`), obj9
  (`_QSEG1`, selector `0x9827`), obj10 (`_QSEG2`, selector `0x982F`), obj11 (`_SpawnData`).
  A 32-bit reference to an obj5 cell appears in obj2 as a flat address `0x1300xxxx` (obj6:
  `0x1301xxxx`).
- Code addresses written as a bare 8-digit hex number (`1C03F473`, `1C0400C6`) are linear addresses in
  a disassembly that bases code object N at `0x1C0N0000`: `1C03F473` = obj3+0xF473, `1C0400C6` =
  obj4+0x00C6, `0x1c0270ec` = obj2+0x70EC. In quoted 16-bit instructions the far-call selectors
  `0xe01e:` and `0xe026:` name obj3 and obj4 (`call 0xe01e:0x2788` = `_FuncInit` at obj3+0x2788)
  `[OBS-RE]`.
- `#N` is a `DOSCALLS` ordinal (the `DOSCALLS.#N` namespace: the kernel's own entries and
  `DOSCALL1`'s exports). Routine names in capitals or with leading underscores are `.SYM` names.
- "Image" is the value the shipped LX image holds for a cell before any code runs. It records
  what the cell's meaning requires at start; it is not a statement about any other system.
- A cell, a routine name or an offset given here was read from the binary and its `.SYM` unless
  tagged otherwise. Tags follow the corpus `README.md`.

---

## Object 5 - shared session-manager, queue, message and screen-save data (selector 0x9807)

Object 5 is a single **shared** data segment (one copy system-wide, the same selector `0x9807` in
every process) `[OBS-RE]`. Its size, as the screen-save pool code tracks it in `segsize`, is
**0x1161** in the image, and it **grows at run time** by `DosReallocSeg` (see group 8) `[OBS-RE]`.
It splits into eight groups by owning code:

| group | span (SMP) | owning code |
|---|---|---|
| 2 init / InfoSeg / DBCS / spinlock | +0x000..+0x084 | `InitDOSCALL1` (LIBINIT, every process) |
| 3 16-bit IPC queues | +0x085..+0x21F | queue ordinals #674-#681 and their exit lists |
| 4 message selectors, selector slots, message DBCS, error table | +0x220..+0x33F | message ordinals, NLS ordinals, queue code via slots |
| 1 session manager core | +0x340..+0xA13 | session-manager ordinals |
| 5 SM daemons, popups, VDM start, handles | +0xA14..+0xB15 | `DosSMInitialize` #707 and the SM daemon threads |
| 6 DD notification, `SMG_Flags`, PM callbacks | +0xB16..+0xC1F | #707, #711, #713-#716 |
| 7 screen save / screen lock | +0xC20..+0xDE8 | #689, #691, #695-#697, #700, #701, #704, switch path |
| 8 `memory_pool` | +0xDE9..+0x1160 | as group 7 |

### The concurrency primitives object 5 sits on (SMP vs UNI)

1. **`DOSFSRAMSEMREQUEST` (#161) / `DOSFSRAMSEMCLEAR` (#162) - fast-safe RAM semaphore.** The
   object is the 16-bit `DOSFSRSEM`: `cb, pid, tid, cUsage, client, ULONG sem` = **14 bytes**
   `[DOC-IBM]` (Open Watcom 1.9 `h/os21x/bsedos.h:449-456`; the DDK `sem.inc`
   `FastSafeRamSemStruc` is the 20-byte padded 32-bit form and is **not** this layout). The image
   confirms it: `PopUpBlockSem` and `SMRoutSem` both hold `0e 00` (cb = 14) `[OBS-RE]`.
   - **UNI** (obj1:0x0C): owner test-and-set of `pid:tid` at `+2`, `cUsage` at `+6`, bracketed by
     `cli` ... `sti` `[OBS-RE]`.
   - **SMP** (obj3:0x60): the same test-and-set, bracketed by
     `push [DC1hSpinLock+2]; push [DC1hSpinLock]; call DOSCALLS.#450` (`DOS32ACQUIRESPINLOCK`) ...
     `call DOSCALLS.#451` (`DOS32RELEASESPINLOCK`), with `DS=0x9807` loaded to read the handle at
     obj5+0x57/+0x59, plus RAS trace points. Fixups obj3+0xCE -> #450, obj3+0x104 -> #451; clear
     path obj3+0x231 #450, +0x282/+0x2F1 #451, +0x2FE #125 `[OBS-RE]`.
   - So the SMP-only lock is **`DC1hSpinLock`, one system-wide spinlock taken around every
     fast-safe-semaphore ownership transition in DOSCALL1** `[OBS-RE]`.
   - The call inventory is the same in both builds: 56 requests / 70 clears (SMP counted by
     resolved name, UNI by obj1 fixup). For `DOSSMSWITCH` the per-routine semaphore choice was
     compared in full: UNI obj3:0xADD2 requests `PopUpBlockSem` then `SMRoutSem`, each with timeout
     -1, exactly as SMP obj3:0xCC92 `[OBS-RE]`.
2. **`DOSSEMREQUEST` / `DOSSEMCLEAR` - plain 4-byte RAM semaphore.** Both builds do
   `xchg al,[sem]` (atomic byte exchange, no `cli`, no spinlock), then block in the kernel if the
   semaphore was taken. SMP adds RAS trace points. UNI additionally does `test byte [sem+1],3`
   right after the `xchg`; whether SMP moved or dropped that test is **not established** (only
   0x59 bytes of SMP were read, to obj3+0x667) `[OBS-RE]`.
3. **The access set is the same in both builds.** Mapping both builds' DS-relative accesses to
   (variable, routine, access kind) through their own symbol maps gives no difference in object 5
   except collisions in obj4 BVS code. The SMP concurrency difference for the whole object is
   primitive 1 (`cli`/`sti` -> `DC1hSpinLock`), plus the SMP-only spinlock creation and `_globptr`
   store in `InitDOSCALL1` `[OBS-RE]`.
4. **RAS trace macro.** About 40 routines open with
   `push es; push 0x9807; pop es; cmp [es:GlobalSelector],0; push [es:GlobalSelector]; pop es;
   test [es:0x36],0x40; test [es:0x26],0x40; push [es:0x4a]; pop es; mov word [es:4],<code>`
   `[OBS-RE]`. Global InfoSeg +0x26 is `SIS_mec_table[32]` ("Table of RAS Major Event Codes")
   `[DOC-IBM]` (DDK `base/h/infoseg.h:91`), so this is a trace point gated on the MEC table `[INF]`.
   What GIS+0x4A and the store target are is not established.
5. **The RAS trace halves are labels inside the ordinal body, not separate routines** `[OBS-RE]`:
   the message ordinals' `PRE*`/`POST*` labels (group 4) and the 32-bit `_Pre`/`_PostDOS32Sub*`
   hooks around #344-#347 (group 2) are two instances of the same convention.

---

### Group 2 - module init, InfoSeg, NLS/DBCS, SMP spinlock (+0x00..+0x84)

The strings in this range carry **no `.SYM` names**; they are cells because code uses them.
Image bytes (identical in SMP and UNI at every string offset read): `+0x16 "NOJIT"`,
`+0x1c "DOSCALL2"`, `+0x27 "NPXEMLTR"`, `+0x34 "NPXNPHandler"`, `+0x41 "NPXFPDataSize"`,
`+0x60 "COUNTRY.SYS"`, `+0x70 "\SHAREMEM\DOS\CDIB"`. Everything else in +0x00..+0x84 is zero in
the image `[OBS-RE]`.

Low offsets collide with other segments: `DOSFSRAMSEMREQUEST`'s `[0x0]/[0x6]/[0xa]` run with DS =
the LIS (a fixup to DOSCALLS #216 `DOS16LOCALINFO`); `DOSSCRLOCK`'s `[0x0]/[0x8]` run after
`mov ds,[0xc28]`; `DOSSMSGENDPOPUP`'s `[0x8]` after `mov ds,[LocalSelector]`; `DOSSMINITIALIZE`'s
`[0x1b]` after `GETINFOSEGS` set DS = GIS (`SIS_ProtMdOnly`); `MSGTRACE`'s `[0x26]/[0x36]/[0x4a]`
after `mov ds,[0x220]`; `ULOADWINTHORNVDH`/`DOSLOADVIDEOHANDLER`'s `mov es,[0x14]` are obj4 BVS code
on obj7; the RAS macro's `[es:0x0]`..`[es:0xc]` are inside the traced segment. None of these is an
object-5 access `[OBS-RE]`.

#### What runs here: `InitDOSCALL1` (obj4+0x2C), per process, SMP order `[OBS-RE]`

1. `DosGetInfoSeg(&globalIS, &localIS)` (#8) - every process.
2. obj6+0x11A0 (per-process DGROUP, `pTLMA0`) = `((localIS >> 3) << 16) + 0x2C`. **SMP adds 0x2C,
   UNI adds 0x24** (UNI obj4+0x50 `add eax,+0x24`; SMP obj4+0x50 `add eax,+0x2c`).
3. If `smsw & 4` (MSW.EM, FPU emulated): `DosLoadModule(0,0,"NPXEMLTR",&hmod@+0x25)` (#44); failure
   aborts init.
4. **SMP only:** if `fSpinLockAlloc` == 0: `DOS32CREATESPINLOCK(&DC1hSpinLock)` (#449, obj4+0x7D:
   `cmp byte [fSpinLockAlloc],0 / jnz; push ds; push 0x57; call DOSCALLS.#449;
   mov byte [fSpinLockAlloc],1`); failure aborts.
5. If `+0x15` == 0: `DosLoadModule(0,0,"DOSCALL2",&hmod@+0x25)`; rc 2 -> `inc +0x15`; any other error
   aborts.
6. **Once-per-system block**, guarded by `+0x14`: `NLS_Init`, `MSGINIT`, `_DYNAINIT`,
   `SMGGLOBALINIT` (each failure aborts); `DosScanEnv("NOJIT")` (#152), and the JIT start via
   `call 0x5b:obj2+0x70EC` if `NOJIT` is not found; **SMP only:** `obj5+0x1F4 = globalIS;
   obj5+0x1F2 = 0`; `+0x14 = 1`; then `DosGetDBCSEv(12, 9807:0010, 9807:0004)` (#394) runs
   **after** the latch is set. Both builds push `cb=0x0c`, `pctryc=9807:0010`, `pbuf=9807:0004`
   (SMP obj4+0x135..0x140, UNI obj4+0xFF..0x10A).
7. Per process: copies LIS+0x1E/+0x20/+0x22 (`LIS_PackSel`/`PackShrSel`/`PackPckSel` `[DOC-IBM]`,
   DDK `base/h/infoseg.h:212-214`) into obj6 with their flat bases; `OS2BASEINIT`.

The UNI order is the same except that step 4 and the `_globptr` store in step 6 are absent.

| off / name | size / type | meaning | accessed by -> ordinal | image / init | concurrency (SMP) | prov |
|---|---|---|---|---|---|---|
| 0x00 `globalIS` (`_globalIS`) | WORD SEL | Selector of the Global InfoSeg, DOSCALL1's most-used copy. | Written by `InitDOSCALL1` via #8 (every process, same value). Read by `InitDOSCALL1` (step 6 store); by the RAS macro variant `cmp [es:0],0 / push [es:0]` with ES=0x9807 in 23 16-bit routines (e.g. `DOSFSRAMSEMREQUEST` #161, `DOSFSRAMSEMCLEAR` #162); and flat (`[es:0x13000000]`) at 20 sites in 10 obj2 routines: the eight RAS hooks `_PreDOS32SubAlloc`/`_PostDOS32SubAlloc`, `...SubFree`, `...SubSet`, `...SubUnSet` (obj2+0x7A9B..0x7D78), which bracket **#344 `DOS32SUBSETMEM`, #345 `DOS32SUBALLOCMEM`, #346 `DOS32SUBFREEMEM`, #347 `DOS32SUBUNSETMEM`**, plus **#356 `DOS32RAISEEXCEPTION`** (obj2+0xA60C/0xA61E) and **#357 `DOS32UNWINDEXCEPTION`** (obj2+0xA6CE/0xA6E0). | 0; each process's LIBINIT | Written without a lock by every process's init; the value is system-constant, so the race is benign `[INF]`. | [OBS-RE] |
| 0x02 `localIS` | WORD SEL | Selector of the Local InfoSeg (per-process contents at one selector number). | Written by `InitDOSCALL1` via #8; read by `InitDOSCALL1` (TLMA base, step 2; LIS pack selectors, step 7) and by 32-bit `UT_AllocTLM` only (`mov es,[0x13000002]; mov ax,[es:0x1c]`), which belongs to `DOS32ALLOCTHREADLOCALMEMORY` #454 by name (call chain not traced). | 0; every process | Shared cell rewritten by each process's init, no lock; correct only if the LIS selector number is the same in every process `[INF]`. | [OBS-RE] |
| 0x04 `dbcs_data` (buffer, +0x04..+0x0F) | BYTE[12] | The system's DBCS lead-byte range vector for the boot country/code page, cached once; first byte 0 => no DBCS. | Filled by `DosGetDBCSEv(cb=12, &+0x10, &+0x04)` in the once-per-system tail of `InitDOSCALL1`. Read by 32-bit `w_Dos32ExecPgm` (#283) only, flat: `cmp byte [0x13000004],0` chooses the path-separator scan. | 0; once per system | Written once, after the latch is set (so not retried); readers take no lock. | [OBS-RE]; "lead-byte vector" [DOC-IBM] by the #394 contract |
| 0x10 (inside `dbcs_data`) | 4 bytes, `COUNTRYCODE` (country, codepage) | Input to that `DosGetDBCSEv`: zero = current country/code page. | Pushed as `pctryc` by `InitDOSCALL1`; no DOSCALL1 code writes it. | 0 | read-only | [OBS-RE]; layout [DOC-IBM] 16-bit `COUNTRYCODE` |
| 0x14 (unnamed) | BYTE | **Once-per-system init latch** for the NLS / message / queue / SMG / JIT block. | `InitDOSCALL1` tests it and sets it to 1 mid-block (after JIT, before `DosGetDBCSEv`); reached by every process that loads DOSCALL1. | 0 | **No DOSCALL1 lock** in either build; the test-then-set spans four sub-inits. Whether the loader serialises LIBINIT is not established `[unverified]`. | [OBS-RE] |
| 0x15 (unnamed) | BYTE | "DOSCALL2 not found" flag: once set, no process retries the load. | `InitDOSCALL1` (`cmp [0x15],al` with AL=0; `inc` on rc 2). | 0 | No lock; a benign double increment is possible `[INF]`. | [OBS-RE] |
| 0x16 (unnamed) | ASCIIZ `"NOJIT"` | Environment variable name whose presence disables the JIT start. | Pushed to `DOSSCANENV` (#152) by `InitDOSCALL1`. | image string | read-only | [OBS-RE] |
| 0x1C (unnamed) | ASCIIZ `"DOSCALL2"` | Name of an optional companion module loaded by every process. | Pushed to `DosLoadModule` (#44) by `InitDOSCALL1`. | image string | read-only | [OBS-RE] |
| 0x25 (unnamed) | WORD HMODULE | Output handle of both init-time `DosLoadModule` calls (NPXEMLTR, then DOSCALL2) - one shared cell, overwritten. | `InitDOSCALL1`; no reader found. | 0 | Shared cell written per process, no lock. | [OBS-RE]; "no reader" by scan only |
| 0x27 (unnamed) | ASCIIZ `"NPXEMLTR"` | Name of the FPU emulator module, loaded when MSW.EM is set. | `InitDOSCALL1` -> #44. | image string | read-only | [OBS-RE] |
| 0x34 (unnamed) | ASCIIZ `"NPXNPHandler"` | A procedure name, presumably for the emulator. **No user found** (no 16-bit push/lea/mov-immediate of +0x34 and no obj2 fixup to it). | - | image string | read-only | [OBS-RE] bytes; use [unverified] |
| 0x41 (unnamed) | ASCIIZ `"NPXFPDataSize"` | As above. **No user found.** | - | image string | read-only | [OBS-RE] bytes; use [unverified] |
| 0x57 `DC1hSpinLock` (SMP only) | DWORD spinlock handle (read as two words `[0x57]`,`[0x59]`, pushed as one 32-bit argument) | The one DOSCALL1 spinlock: serialises the owner/usage update of every fast-safe RAM semaphore in the module. | Created by `InitDOSCALL1` via `DOS32CREATESPINLOCK` (#449). Acquired/released by `DOSFSRAMSEMREQUEST` (#161) and `DOSFSRAMSEMCLEAR` (#162) and their `post*` trace halves, via #450/#451 - and so by every internal caller of those two: the session manager, VIO popup/register/save-redraw, the message file code, `REALLOCSEG`, `DOSSCRLOCK` #695, and others. | 0; once per system | It IS the lock; held only across the few instructions of the owner test-and-set, never across a block and never across a call out of #161/#162, so it cannot take part in a lock-order cycle. | [OBS-RE] |
| 0x5B `fSpinLockAlloc` (SMP only) | BYTE | "`DC1hSpinLock` has been created" latch. | `InitDOSCALL1` only (test; set after #449 succeeds). | 0 | **No lock** around test / create / set; two processes initialising at once could each create a spinlock and one handle would be lost `[INF]`. | [OBS-RE] |
| 0x60 (unnamed) | ASCIIZ `"COUNTRY.SYS"` | Default country-file name for NLS lookups. | Pushed as the file name to `DosOpen` (#70) by `_getctry` (<- `_findinfo` <- `_cache_table`, `_w_nls_apis`). The exported ordinal that reaches `_getctry` is not established. | image string | read-only | [OBS-RE] |
| 0x70 (unnamed) | ASCIIZ `"\SHAREMEM\DOS\CDIB"` | Name of the kernel-built shared Country Data Information Block segment. | `NLS_Init` (once-per-system block): `DosGetShrSeg(&+0x83, "\SHAREMEM\DOS\CDIB")` (#36). (`_CopyFile`'s `mov di,0x70` is a return-code constant, obj4+0xDDBB, not a use.) | image string | read-only | [OBS-RE] |
| 0x83 `_gGDT_sel` | WORD SEL | Selector of the CDIB shared segment, obtained once. `NLS_Init` then copies the ASCIIZ at `CDIB:[CDIB:4]+4` into `_gFile` (+0x85). | Written by `NLS_Init` via #36. Read by `_w_cdib` and `_get_CDIB` as `[es:0x83]` with ES loaded from selector slot +0x240 (= 0x9807, group 4) - so it is this cell. | 0; once per system | Inside the unlocked once-per-system block. | [OBS-RE] |

**Locking, group 2.** Once-per-system work has no DOSCALL1 lock in either build: `+0x14` and SMP
`fSpinLockAlloc` are plain test-then-set, and `+0x14` is set mid-block. The only SMP lock object here
is `DC1hSpinLock`, created once and acquired only inside #161/#162, so it sits beneath every fast-safe
semaphore in the object `[OBS-RE]`.

**Not established (group 2):** any user of `NPXNPHandler` (+0x34) and `NPXFPDataSize` (+0x41)
(possibly strings for NPXEMLTR to resolve - not read); which exported ordinal reaches `_getctry`;
whether the OS/2 loader serialises LIBINIT, which is what makes `+0x14`/`fSpinLockAlloc` safe.

---

### Group 3 - 16-bit IPC queues (+0x85..+0x21F)

**How ES reaches object 5 in this group.** Queue routines load DS=0x9807 and then take ES from a
routine-private selector slot (`mov es,[0x2a2]`, `mov es,[0x2f2]`, ...; group 4). Every queue slot
holds 0x9807, so an `[es:0x1e3]` in `_FuncInit`, `_FuncFree`, `W_DOSWRITEQUEUE` or `_L_Tbl` is obj5
+0x1E3 `[OBS-RE]`.

**The queue data is not in object 5.** The queue, link and element records live in a heap
sub-allocated from objects 9 and 10 (`_QSEG1`/`_QSEG2`). Object 5 holds only the anchors, the lock
owner and a one-operation recovery journal `[OBS-RE]`. Record layouts are under objects 9 and 10.

#### The lock the whole group lives under - identical in SMP and UNI `[OBS-RE]`

`_FuncInit` (obj3+0x2788) is called first by every queue entry: `W_DOSCREATEQUEUE`,
`W_DOSOPENQUEUE`, `W_DOSREADQUEUE`, `W_DOSWRITEQUEUE`, `W_DOSPEEKQUEUE`, `DOSCLOSEQUEUE`,
`DOSPURGEQUEUE`, `DOSQUERYQUEUE`, `_Q_Sleep` - i.e. **ordinals #674-#681**. The 32-bit `DOS32*QUEUE`
entries reach the same `W_DOS*QUEUE` bodies through the CONFORM16 trampoline.

1. Per process, the first time (`_ISEG` record +2/+4 = 0): `DosGetInfoSeg` (#8); store the pid in
   `_ISEG`+0; `DosCreateSem(0, &hsem, "\SEM\IPCQUEUE.SEM")` (#24); on 183 (already exists) or 100,
   `DosOpenSem` (#25). The handle goes to `_ISEG`+2 inside `DosEnterCritSec` (#3) /
   `DosExitCritSec` (#6). Then `DosExitList` (#7) registers `_EXITLISTQUEUE1` (order code 0xD081)
   and `_EXITLISTQUEUE2` (0xD001), obj4+0xE350/+0xE355; `_ISEG`+6 = 0xFF.
2. Every call: `DosHoldSignal(1)` (#13), then `DosSemRequest(hsem, -1)`. On rc 0 **or 105
   (`ERROR_SEM_OWNER_DIED`)** the owner pid goes into `_statseg`+5; **on 95 the request is issued
   again** (UNI obj3:0x212C `cmp [bp-0x12],0x5f / jnz`, then `jmp 0x1c7b`, the push of the request's
   arguments); any other rc returns 328.
3. `_FuncFree` (obj3+0x2734): owner pid = 0, `DosSemClear(hsem)`, `DosHoldSignal(0)`.

So the queue subsystem's global lock is a **named system semaphore - one kernel object, one handle
per process - taken with signals held**. SMP adds no spinlock here. UNI `_DYNAINIT` is byte-for-byte
the same store sequence, and UNI `_FuncInit` makes the same #8/#24/#25/#3 calls on `+0x1ca`.

| off / name | size / type | meaning | accessed by -> ordinal | image / init | concurrency (SMP) | prov |
|---|---|---|---|---|---|---|
| 0x85 `_gFile` | char[0x10B] | The country-file path, copied out of the kernel's CDIB (`CDIB:[CDIB:4]+4`). Belongs to NLS, not queues. | Written by `NLS_Init` (once-per-system block). Read by `_getctry` (obj3+0x8195), which passes it as a far pointer (`push word 0x9807 / push word 0x85` at obj3+0x81A2). | 0; once per system | Inside the unlocked once-per-system block. | [OBS-RE] |
| 0x190 `_list1` | ASCIIZ `"\QUEUES\"` (10) | Required name prefix for queue names. | Pushed three times by `_F_Syntax` (<- `W_DOSCREATEQUEUE`, #681). | image string | read-only | [OBS-RE] |
| 0x19A `_action` | BYTE (step code) | **Recovery-journal step**: which stage of the current queue mutation has been reached, so an exit list can finish or undo it. | Set to 3/4/5/6/0 as `W_DOSREADQUEUE` progresses; 4 by `_El_Delete`; set by `W_DOSWRITEQUEUE`, `_Q_Delete`, `_L_Remove`, `_L_Tbl`, `_Q_Tbl`. `C_EXITLISTQUEUE1` does `dec ax; cmp 0xc` and jumps through a 13-entry table on it (obj3+0x591A; the per-value meanings are not decoded). | 0 | Written only while holding IPCQUEUE.SEM; read by the exit list after it re-takes the semaphore (rc 0 or 105). | [OBS-RE] use; "journal" [INF] from the exit-list switch |
| 0x19C `_count` | WORD | **The queue's element count** (queue record +0x0A), saved here before every element-list mutation. | `W_DOSREADQUEUE`, `W_DOSWRITEQUEUE`, `_El_Delete`, `_FuncInit`, `C_EXITLISTQUEUE1`. | 0 | under IPCQUEUE.SEM | [OBS-RE] |
| 0x19E `_prev_fst_q` | DWORD far ptr | Journal: the previous first-queue pointer, for restoring the queue-list head. | `_Q_Delete`, `_FuncInit`, `C_EXITLISTQUEUE1`. | 0 | under IPCQUEUE.SEM | [OBS-RE] access; meaning from name [INF] |
| 0x1A2 `_prev_fst_link` | DWORD far ptr | Journal: the previous first-link pointer. | `_L_Remove`, `_FuncInit`, `C_EXITLISTQUEUE1`. | 0 | same | [OBS-RE] access; meaning from name [INF] |
| 0x1A6 / 0x1AA / 0x1AE `_que1/_que2/_que3` | 3 x DWORD far ptr | Journal: queue records involved in the operation. The exit list writes through `_que1` (e.g. `or byte [_que1],2`, clears fields +0xC..+0x12). | `W_DOSREADQUEUE`, `W_DOSWRITEQUEUE`, `_El_Delete`, `_Q_Delete`, `_Q_Tbl`, `_L_Tbl`, `_FuncInit`, `C_EXITLISTQUEUE1`. | 0 | same | [OBS-RE] |
| 0x1B2 / 0x1B6 / 0x1BA `_lnk1/_lnk2/_lnk3` | 3 x DWORD far ptr | Journal: link (opener) records involved. The exit list restores the `_statseg` link head from `_lnk1`. | `_L_Remove`, `_L_Tbl`, `_FuncInit`, `C_EXITLISTQUEUE1`. | 0 | same | [OBS-RE] |
| 0x1BE / 0x1C2 / 0x1C6 `_emt1/_emt2/_emt3` | 3 x DWORD far ptr | Journal: element records involved (read / write / delete). | `W_DOSREADQUEUE`, `W_DOSWRITEQUEUE`, `_El_Delete`, `_FuncInit`, `C_EXITLISTQUEUE1`. | 0 | same | [OBS-RE] |
| 0x1CA `_name_sem` | ASCIIZ `"\SEM\IPCQUEUE.SEM"` (18) | Name of the queue subsystem's system semaphore. | Pushed to `DosCreateSem` #24 / `DosOpenSem` #25 by `_FuncInit`. | image string | the lock's name | [OBS-RE] |
| 0x1DC (unnamed) | WORD | **"`_QSEG2`'s pool has not been created yet" flag** - tested at `1C032F09` and cleared at `1C032F2E`, right after the `DosSubSet(_QSEG2,1,0x1000)` that creates object 10's pool. | `_FindMem`: `cmp word [0x1dc],0` on its segment-switch path. | **image 1** | Under IPCQUEUE.SEM (`_FindMem` is called from `_Q_Tbl`/`_L_Tbl`/`W_DOSWRITEQUEUE`). | [OBS-RE] |
| 0x1DE `_statseg` (+0) | BYTE | "Queue subsystem initialised" byte at the head of the status block. | Set 1 by `_DYNAINIT`. | 0; once per system | once-per-system block | [OBS-RE] |
| 0x1DF..0x1E2 (`_statseg`+1..+4) | 4 bytes | **No access found.** | - | 0 | - | [unverified] |
| 0x1E3 (`_statseg`+5) | WORD PID | PID currently owning IPCQUEUE.SEM. | Set by `_FuncInit` after acquiring (0 on an unexpected rc) and by `C_EXITLISTQUEUE1` after acquiring; cleared by `_FuncFree`; read by `_L_Tbl`/`_L_Find` (match the opener pid) and `W_DOSWRITEQUEUE` (stored as the element's writer pid, element +0x12). | 0 | Written only right after acquiring IPCQUEUE.SEM. | [OBS-RE] |
| 0x1E5 (`_statseg`+7) | WORD | Next queue id: pre-incremented, skipping 0, retried until `_Q_Scan` finds it unused. | `_DYNAINIT` (=0), `_Q_Tbl` (<- `W_DOSCREATEQUEUE` #681). | 0 | under IPCQUEUE.SEM | [OBS-RE] |
| 0x1E7 (`_statseg`+9) | DWORD far ptr | Head of the queue-record list (walked via record +0x14). | `_DYNAINIT` (=0); `W_DOSWRITEQUEUE`, `W_DOSREADQUEUE`, `_Q_Delete`, `_Q_Scan`, `_Q_Tbl`, `_ScanQname`, `_L_Remove`, `_FuncInit`, `C_EXITLISTQUEUE1/2`. | 0 | under IPCQUEUE.SEM | [OBS-RE] |
| 0x1EB (`_statseg`+0xD) | DWORD far ptr | Head of the link (opener) list (walked via record +6). | `_DYNAINIT` (=0); `_L_Tbl`, `_L_Find`, `_L_Remove`, `_Q_Delete`, `W_DOSWRITEQUEUE`, `C_EXITLISTQUEUE1/2`. | 0 | same | [OBS-RE] |
| 0x1EF (`_statseg`+0x11) | WORD | Current size of the queue heap segment; grows by 0x1000 via `DosReallocSeg` (#38) + `DosSubSet`. | `_DYNAINIT` (=0x1000), `_FindMem`. | 0x1000 at init | under IPCQUEUE.SEM | [OBS-RE] |
| 0x1F1 `_initq` | BYTE | "Queues initialised" flag. | Set 1 by `_DYNAINIT`; no reader found. | 0; once per system | once-per-system block | [OBS-RE] |
| 0x1F2 `_globptr` | DWORD far ptr | Far pointer to the Global InfoSeg (selector at +0x1F4, offset 0 at +0x1F2), used to gate queue RAS tracing on MEC byte GIS+0x37 bit 0x80. | Written by `_DYNAINIT` (selector) and, **SMP only**, again by `InitDOSCALL1` (selector + offset 0); read `les bx,[es:0x1f2]` by `W_DOS*QUEUE`, `DOSCLOSE/PURGE/QUERYQUEUE`, `_queues_sys_trace`, `_Nls_Sys_Trace`. | 0 | read-only after init | [OBS-RE]; GIS+0x37 is `SIS_mec_table[17]` [DOC-IBM] DDK `base/h/infoseg.h:91` |
| 0x1F6 `_e_offset` | DWORD far ptr (4 of a 10-byte gap) | The element being built by `DosWriteQueue`: `_FindMem(&_e_offset, 0x18)`, then the fields are filled through it. | `W_DOSWRITEQUEUE` (#679; also <- `C_EXITLISTQUEUE2`). | 0 | under IPCQUEUE.SEM | [OBS-RE] |
| 0x1FA..0x1FF | 6 bytes | **No access found.** | - | 0 | - | [unverified] |
| 0x200 `_QSEG` | WORD SEL | Selector of the queue heap segment currently being sub-allocated - a cursor that alternates between the two fixed heaps and starts on `_QSEG1`. | `_FindMem` (`DosSubAlloc`, `DosReallocSeg`; switches `_QSEG` between `_QSEG1`/`_QSEG2`). | **image 0x9827 + fixup -> obj9** | under IPCQUEUE.SEM | [OBS-RE] |
| 0x202 `_QSEG1` | WORD SEL | First queue heap segment (object 9). | `_DYNAINIT` (`DosSubSet(sel,1,0x1000)`), `_FindMem`. | **image 0x9827 + fixup -> obj9** | read-only | [OBS-RE] |
| 0x204 `_QSEG2` | WORD SEL | Second queue heap segment (object 10), switched to by `_FindMem`. Its pool is created lazily (see +0x1DC). | `_FindMem`. | **image 0x982F + fixup -> obj10** | read-only | [OBS-RE] |
| 0x206 `_ISEG` | DWORD far ptr -> obj6+0x126A | Pointer to this process's queue instance record in DGROUP (object 6, per process; export 414 `_QUEINST_DATA`): +0 pid, +2 the process's IPCQUEUE.SEM handle, +6 exit-list-registered byte. A shared cell holding a pointer valid in every process because object 6 has the same selector everywhere. | `_FuncInit`, `_FuncFree`, `C_EXITLISTQUEUE1/2`. | **image `6a 12` + fixup at +0x208 -> obj6** (= `980F:126A`) | read-only | [OBS-RE] |
| 0x208..0x21F | - | Selector half of `_ISEG`, then zeros up to `msgGlobalSeg` (+0x220). | - | - | - | [OBS-RE] bytes |

**Locking, group 3.**
- **One lock: `\SEM\IPCQUEUE.SEM`**, acquired in `_FuncInit` and released in `_FuncFree`, with
  `DosHoldSignal` bracketing the hold. Taken by #674-#681, the 32-bit queue entries (same bodies), and
  both exit lists (`C_EXITLISTQUEUE1/2`) on process exit. Every mutable cell in the group is written
  only under it; the owner pid is in `_statseg`+5 `[OBS-RE]`.
- **Owner death is designed in.** Acquire accepts rc 105 (`ERROR_SEM_OWNER_DIED`); `_action` plus the
  `_que`/`_lnk`/`_emt`/`_prev_fst_*` journal lets `C_EXITLISTQUEUE1` complete or undo the interrupted
  operation. So the journal cells are shared and persistent, not per-call scratch `[OBS-RE]`.
- **Nesting:** `_FuncInit` does not call into session-manager locks. The session manager calls
  `DosCreateQueue`/`OpenQueue`/`ReadQueue`/`WriteQueue`/`CloseQueue` (`DOSSMGETAPPREQ`,
  `APPSENDREQUEST`, `DOSSMSGSTART`, `APPSTARTSESSION`, `WRITETERMQUEUE`) while holding
  `PopUpBlockSem`/`SMRoutSem` on some paths, giving `PopUpBlockSem` -> `SMRoutSem` -> IPCQUEUE.SEM
  `[INF]` (per call site, not traced path by path).
- **SMP vs UNI:** no difference in the lock; the only SMP-only store is `InitDOSCALL1` rewriting
  `_globptr` (written twice in SMP, once in UNI; harmless as read).
- **Init writes** (`_DYNAINIT`) run inside `InitDOSCALL1`'s once-per-system block, without
  IPCQUEUE.SEM.
- The queue subsystem depends on objects 9 and 10 (`_QSEG1`/`_QSEG2` are image-initialised selectors
  to them) and on object 6 (`_ISEG`) being present at their selectors `[OBS-RE]`.

**Not established (group 3):** `_statseg`+1..+4; the six bytes after `_e_offset`; a reader of
`_initq`; what each `_action` value 1..13 means (the jump table at obj3+0x591A is not decoded).

---

### Group 4 - message InfoSeg selectors, selector-slot table, message DBCS cells, error-code table (+0x220..+0x33F)

**The selector slots.** The slots are three at **+0x240/+0x242/+0x244**, then zeros at
+0x246..+0x25F (which hold real variables at +0x250 and +0x25A), then **80 slots at +0x260..+0x2FF** -
**83 slots** in all: 82 with an LX fixup to `internal obj5+0` (image `07 98` = 0x9807) and one,
+0x244, with a fixup to obj6 (0x980F) `[OBS-RE]`.

- **Each slot is a load-time selector constant**: a 2-byte data cell filled by an LX fixup with the
  selector of a data object. A 16-bit routine with DS=obj5 loads ES from it (`mov es,[slot]`) before
  touching a far variable, so the fixup lives in object 5's data rather than in the routine's code
  `[OBS-RE]`.
- **Slots belong to routines, not variables.** Each routine owns its own consecutive slots, one per
  distinct far-reference site group; no two routines share a slot. That is what a compiler emits
  when every far-data segment reference goes through its own memory cell; why the build did this is
  not established from the binary `[INF]`.
- **+0x244 is obj6** because its only user, `_cache_table`, reads `[es:0x1220]`/`[es:0x1222]`, the
  per-process NLS cache cells in object 6. Every other slot user reads object-5 variables.
- A slot must hold exactly the selector the process sees for that object. No writer was found;
  slots are read-only after load and need no lock `[OBS-RE]`.
- The `.SYM` map puts `msgLocalSeg` at +0x222 with the next symbol at +0x340, but +0x240..+0x33F
  holds slots, message DBCS cells and the error table. A symbol gap is not a size `[OBS-RE]`.

| off / name | size / type | meaning | accessed by -> ordinal | image / init | concurrency (SMP) | prov |
|---|---|---|---|---|---|---|
| 0x220 `msgGlobalSeg` | WORD SEL | The message subsystem's copy of the Global InfoSeg selector. | Written by `MSGINIT` via `DosGetInfoSeg(&msgGlobalSeg,&msgLocalSeg)` (#8), from `InitDOSCALL1`'s once-per-system block. Read by `MSGTRACE` (DS=GIS; RAS gate GIS+0x36 bit 0x10, +0x26 bit 0x40, pushes GIS+0x4A; <- `DOSPUTMESSAGE` #383, `DOSTRUEGETMESSAGE` #384, `DOSINSMESSAGE` #385, `PREPUTMSG`/`PREINSMSG`/`PREQMSGCP`, `CLEAN_UP`) and by `FILENAME_OUT` (DS=GIS; GIS+0x24 = `SIS_BootDrv` + 0x3A40 -> the ASCII `"X:"` of the boot drive). | 0; once per system | read-only after init | [OBS-RE]; +0x24 = `SIS_BootDrv` [DOC-IBM] DDK `base/h/infoseg.h:87` |
| 0x222 `msgLocalSeg` | WORD SEL | The message subsystem's copy of the Local InfoSeg selector, captured once, by whichever process ran the once-per-system block first. | Written by `MSGINIT` (#8); **no reader found**. | 0; once per system | read-only after init | [OBS-RE] write; readers [unverified] |
| 0x224..0x23F | 28 bytes | No access found; zero. | - | 0 | - | [OBS-RE] bytes |
| 0x240 (slot) | WORD SEL = 0x9807 (fixup -> obj5) | ES = obj5 for NLS routines reading `_gGDT_sel` (+0x83). | `_w_cdib`, `_get_CDIB` (`mov es,[0x240]; mov ax,[es:0x83]`) <- `DOSCASEMAP` #391, `DOSGETCOLLATE` #392, `DOSGETCTRYINFO` #393, `DOSGETDBCSEV` #394. | image + fixup | read-only | [OBS-RE] |
| 0x242 (slot) | WORD SEL = 0x9807 (fixup -> obj5) | ES = obj5 for the NLS RAS trace reading `_globptr`. | `_Nls_Sys_Trace` (`les bx,[es:0x1f2]; test [es:bx+0x26],0x40`) <- #391-#394. | image + fixup | read-only | [OBS-RE] |
| 0x244 (slot) | WORD SEL = 0x980F (fixup -> obj6) | ES = obj6 (per-process DGROUP) for the NLS cache fields at obj6+0x1220/+0x1222. | `_cache_table` (<- `_w_nls_apis` <- `_w_cdib` <- #391-#394). | image + fixup | read-only | [OBS-RE] |
| 0x246..0x24F | 10 bytes | No access found; zero. | - | 0 | - | [OBS-RE] bytes |
| 0x250 (unnamed, inside `msgLocalSeg`'s `.SYM` span) | BYTE[10] | DBCS lead-byte vector for the code page a message is being output in; "no DBCS" is tested by `cmp word [0x250],0`. | Filled by `CHECK_DBCS`: `DosGetDBCSEv(cb=10, &+0x25A, &+0x250)` (#394). `CHECK_DBCS` is called at exactly five sites (`call 0x9bd1` at obj3+0x385F2/0x388B6/0x39586/0x397FF/0x39C68), from the labels `PREPUTMSG`, `PREGETMSG`, `PREINSMSG`, `PREQMSGCP` and `handle_found`. Those labels are not routines: each is a fall-through label inside its ordinal's body, with no calls or jumps to it anywhere in obj3 or obj4 - `PREPUTMSG` is +0x34 into `DOSPUTMESSAGE`@0x97A0 (followed by `POSTPUTMSG`@0x987D), `PREGETMSG` +0x1E into `DOSTRUEGETMESSAGE`@0x8580, `PREINSMSG` +0x21 into `DOSINSMESSAGE`@0x9540, `PREQMSGCP` +0x0F into `DOSIQUERYMESSAGECP`@0x9C30, and `handle_found` inside `DOSTRUEGETMESSAGE` (its four `jmp`s all come from 0x8580..0x88D8). So the owners are **four ordinals: #383 `DOSPUTMESSAGE`, #384 `DOSTRUEGETMESSAGE` (two of the five sites), #385 `DOSINSMESSAGE`, #389 `DOSIQUERYMESSAGECP`**. | 0 | **Shared cell written under a per-process lock**: `PREPUTMSG` holds a fast-safe semaphore released as `DosFSRamSemClear(980F:1692)`, i.e. one in object 6, per process (the request's pointer argument was not read). | [OBS-RE] |
| 0x25A (unnamed) | 4 bytes, `COUNTRYCODE` | Country / code page for that `DosGetDBCSEv`. Zeroed by `PREPUTMSG`; copied from obj6+0x14D2/+0x14D4 by `CHECK_DBCS` when obj6+0x14D6 != 0 (a per-process message code-page setting). | `PREPUTMSG`, `CHECK_DBCS`. | 0 | as 0x250 | [OBS-RE] |
| 0x25E..0x25F | 2 bytes | No access found; zero. | - | 0 | - | [OBS-RE] bytes |
| 0x260..0x2FF (80 slots) | 80 x WORD SEL = 0x9807 (fixups -> obj5) | ES = obj5 for the 16-bit queue implementation. Every slot is used, each by exactly one routine: **0x260-262** `DOSCLOSEQUEUE`; **264-26A** `_Q_Tbl`; **26C-26E** `W_DOSCREATEQUEUE`; **270-272** `C_EXITLISTQUEUE1`; **274-276** `C_EXITLISTQUEUE2`; **278-27E** `_L_Tbl`; **280** `W_DOSOPENQUEUE`; **282-284** `W_DOSPEEKQUEUE`; **286-288** `DOSPURGEQUEUE`; **28A-28C** `DOSQUERYQUEUE`; **28E-29C** `W_DOSREADQUEUE`; **29E-2A0** `_FuncFree`; **2A2-2BE** `_FuncInit`; **2C0** `_Q_Scan`; **2C2-2C8** `_FindMem`; **2CA** `_ScanQname`; **2CC-2D6** `_Q_Delete`; **2D8** `_L_Find`; **2DA-2E2** `_L_Remove`; **2E4** `_DYNAINIT`; **2E6-2EE** `_El_Delete`; **2F0-2FE** `W_DOSWRITEQUEUE`. | All feed group 3's variables -> queue ordinals #674-#681, the exit lists and `_DYNAINIT`. | image + fixups | read-only | [OBS-RE] (one `mov es,[slot]` per listed routine) |
| 0x300 (unnamed) | WORD[27] | A fixed set of error codes: 110, 3, 2, 206, 123, 203, 12, 54, 56, 57, 58, 59, 60, 64, 66, 69, 71, 86, 240, 51, 53, 55, 67, 71, 65, 5, 26 - **the error set that lets the message-file DPATH search continue**. | `end_dpath` (obj3+0x93AE: `mov es,0x9807; mov di,0x300; mov cx,0x1b; repne scasw` -> CF clear if found). `end_dpath` is not a routine but the error tail of `OPEN_DPATH` (obj3+0x932D, the message-file DPATH open), reached only by the `jmp short 0x9388` at obj3+0x934F; the `.SYM` neighbours are `DO_OPEN`@0x92FD, `OPEN_DPATH`@0x932D, `end_dpath`@0x9388, `test_1`@0x93C8. | image table | read-only | [OBS-RE] |
| 0x336..0x33F | 10 bytes | No access found; zero. | - | 0 | - | [OBS-RE] bytes |

**Locking, group 4.** Selector slots and the error table are read-only image data, no lock.
`msgGlobalSeg`/`msgLocalSeg` are written once inside the unlocked once-per-system block. +0x250/+0x25A
are written on every message output by `CHECK_DBCS` under a **per-process** fast-safe semaphore in
object 6 (released at `980F:1692`) - which in SMP still goes through `DC1hSpinLock` for its ownership
update but excludes only threads of the same process. So two processes outputting messages in
different code pages can interleave the `DosGetDBCSEv` fill and the test `[INF]` (the lock placement is
`[OBS-RE]`). No SMP-only lock in this group.

**Not established (group 4):** a reader of `msgLocalSeg`; the request half of `PREPUTMSG`'s fast-safe
semaphore (the pointer pushed before obj3+0x97CC); the build reason for per-routine slots.

---

### Group 1 - session-manager core (+0x340..+0xA13; UNI +0x310..+0x9E3)

| off / name | size / type | meaning | accessed by -> ordinal | image / init | concurrency (SMP) | prov |
|---|---|---|---|---|---|---|
| 0x340 `AppReqQueueName` | ASCIIZ, 23 bytes used of the 0x17 gap | Name of the session manager's application-request queue, `\QUEUES\SESMGR\APPREQQ`. | Pushed by `DOSSMGETAPPREQ` -> `DosCreateQueue` (#706, reached from #688); by `APPSENDREQUEST` -> `DosOpenQueue` (internal; called from `DOSSTARTSESSION` #702, `DOSSETSESSION` #699, `DOSSELECTSESSION` #694, `DOSSTOPSESSION` #693). | image string | read-only | [OBS-RE] |
| 0x357 `DefPgmName` | char[0x104] (260) | A default program name/path string, filled at session-manager init. | Written by `DOSSMINITIALIZE` (#707) at obj3:0xBE97 (`mov di,0x357; lodsb/stosb` to NUL, ES=0x9807); the source pointer is not traced. **No reader found** by DS-relative scan (a reader through another segment is not excluded). | 0; #707 | Written once at init; #707 holds no lock there (none requested before obj3:0xBF1D). | [OBS-RE] write; readers unestablished |
| 0x45B `We_Own_Sem` | BYTE | Flag: this start path currently owns `PopUpBlockSem` and must release it. | `APPSTARTSESSION` (internal, from `DOSSMDOAPPREQ` #692): sets 1 after a successful `DosFSRamSemRequest(PopUpBlockSem, 0)` (retried while rc = 0x5F); later tests 1 -> clears to 0 and `DosFSRamSemClear(PopUpBlockSem)` (obj3:0x4C01, 0x4D98-0x4DAA). | 0 | written only while holding `PopUpBlockSem` | [OBS-RE] |
| 0x45C `AppReqQueue` | WORD (HQUEUE) | Handle of the app-request queue. | `DOSSMGETAPPREQ` (#706): if 0, `DosCreateQueue(&AppReqQueue, 0, AppReqQueueName)`; then `DosReadQueue(AppReqQueue, ...)`. | 0; created lazily by #706 | #706 is gated by `ShellPID` (caller must be the shell) and by `ServiceAppThd`; no semaphore. | [OBS-RE] |
| 0x45E `DetSession` | WORD | **Not established.** No access in SMP obj3/obj4 by DS-relative, address-taken or override scan; none in UNI at 0x42E. | - | 0 | - | [unverified] |
| 0x460 `GlobalSelector` | WORD SEL | Selector of the Global InfoSeg. | Written by `DosGetInfoSeg` (#8) called from `DOSSMSGINIT` (internal, from #707) and `GETINFOSEGS` (from #707). Read by `DOSSMSGINIT` (`sgMax` at GIS+0x19), `DOSSMGSWITCH` (`sgCurrent` at GIS+0x18, under `SwitchRamSem`), `GETINFOSEGS`, and the RAS trace macro in ~40 SM routines. | 0; #707 | read-only after init | [OBS-RE] |
| 0x462 `LocalSelector` | WORD SEL | Selector of the caller's Local InfoSeg - a per-process value kept in a shared cell, last `DosGetInfoSeg` caller wins. All readers use it only as "the current process's LIS", which is correct only because the LIS selector is the same number in every process `[INF]`, not verified. | Written with `GlobalSelector`. Read by every shell-identity gate: `DOSSMBASESHELL` (LIS+0 pid vs `ShellPID`), `DOSSMGETAPPREQ` #706, `DOSSMSERVEAPPREQ` #688, `DOSSMDOAPPREQ` #692, `APPSENDREQUEST`, `DOSSETSESSION` #699, `DOSSELECTSESSION` #694, `DOSSTOPSESSION` #693, `DOSSMSGSETTITLE` (#690), `DOSSMINITALLOC`, `FOREGROUNDFAMILY`, `PARENTEXITLIST`. | 0; #707 | none | [OBS-RE] |
| 0x464 `NewSession` | 4 bytes | Out-parameter slot handed to `DOSSMSGSTART` by `DosSMStart`; what lands there is not traced. | `DOSSMSTART` (#708) pushes `ds:0x464` into `DOSSMSGSTART` (obj3:0xCC61). | 0 | #708 holds `PopUpBlockSem` + `SMRoutSem` at that call (linear). | [OBS-RE] use; meaning [unverified] |
| 0x468 `PopUpBlockSem` | `DOSFSRSEM`, 14 bytes | System-wide fast-safe semaphore serialising session-manager operations that may bring up or switch away from a popup (start, switch, parent switch, terminate, popup title change, child exit). **Outer lock.** | Requested/cleared by `DOSSMSWITCH` #687, `DOSSMSTART` #708, `DOSSMPARENTSWITCH` #709, `DOSSMTERMINATE` #705, `DOSSMPOPUPTLECHG` (internal), `APPSTARTSESSION` and `APPSELECTSESSION` (from #692; timeout 0 + retry on 0x5F in APPSTART), and `DOSSMCHILDEXIT` (obj3+0xA602, +0xA71B). Its far address is also returned by #711 to HARDERR.EXE (group 6). | image `cb=0x000E`, rest 0 | It is a lock (fast-safe -> `DC1hSpinLock` inside on SMP); taken **before** `SMRoutSem` everywhere both are held. | [DOC-IBM] layout, [OBS-RE] use |
| 0x476 `ReqBlock` | DWORD far ptr | Far pointer to the most recently dequeued app-request packet. | `DOSSMSERVEAPPREQ` #688 passes `&ReqBlock` to `DOSSMGETAPPREQ` #706 (which stores `DosReadQueue`'s data address there through its `[bp+6]` out pointer), then pushes `[ReqBlock]` to `DOSSMDOAPPREQ` #692. | 0 | serving thread only (`ServiceAppThd` latch) | [OBS-RE] |
| 0x47A `RequestLen` | WORD | Length of the dequeued request (`DosReadQueue` `PUSHORT`). | `DOSSMGETAPPREQ` #706 (address pushed as 3rd argument). | 0 | serving thread only | [DOC-IBM] prototype Open Watcom 1.9 `h/os21x/bsedos.h:436`, [OBS-RE] push order |
| 0x47C `Requestor` | 4 bytes (`PULONG` request word) | `DosReadQueue`'s request/pid word for the dequeued element. | #706 (2nd argument). | 0 | serving thread only | same |
| 0x480 `RequestPty` | BYTE (`PBYTE`; gap 2) | Element priority of the dequeued request. | #706 (7th argument). | 0 | serving thread only | same |
| 0x482 `ServiceAppThd` | WORD (TID) | TID of the thread currently inside `DosSMServeAppReq`; non-zero means the serve loop is running. | `DOSSMSERVEAPPREQ` #688: must be 0, stores LIS+6 (tid), loops GetAppReq/DoAppReq, zeroes on exit (else 418). `DOSSMGETAPPREQ` #706: must be 0 or equal to the caller's tid (else 418). | 0 | A check-then-store **with no lock** (obj3:0xB8C6..0xB8D1). | [OBS-RE] |
| 0x484 `ShellPID` (UNI 0x454) | WORD (PID) | PID of the registered base shell (the session manager). Every shell-only API compares it with LIS+0. | Writers: `DOSSMINITIALIZE` #707 (obj3:0xBF0A, from the LIS via `GETINFOSEGS`) and `DOSSMINITALLOC` (obj3:0xBFFC, from LIS+0; reached #707 -> `DOSSMSGINIT` ->). Readers: `DOSSMBASESHELL`, #706, #688, #692, `APPSENDREQUEST`. | 0 | Written at init only; #707's second write is followed by `NotDD_RamSem` (a `DOSSEMREQUEST`) - the write itself is outside it. | [OBS-RE] |
| 0x486 `ShellRedrawSem` | DWORD (system-semaphore HSEM) | Handle of the shell's "redraw" event semaphore, supplied by the shell in its `DosSMInitialize` block; pulsed to tell the shell to redraw. | Stored by #707 from init block `+2`, then `DosSemSet`; pulsed (`DosSemClear` then `DosSemSet`) by `DOSSMDOAPPREQ` #692 when `TopMost == BaseShell`, and by `DOSSMAPPNOTIFY` (from `DOSSMCHILDEXIT`, `DOSSMPOPUPTLECHG`) when TopMost's SGID is 1. | 0; #707 | Pulse in #692 is under `SMRoutSem`; in `DOSSMAPPNOTIFY` via `DOSSMPOPUPTLECHG` under `SMRoutSem` (linear); via `DOSSMCHILDEXIT` not established. | [OBS-RE] |
| 0x48A `ShellTermSem` | DWORD (HSEM) | Handle of the shell's "termination" event semaphore (init block `+6`). | Stored + `DosSemSet` by #707; pulsed by `DOSSMAPPNOTIFY` when TopMost's SGID equals the notified group. | 0; #707 | as above | [OBS-RE] |
| 0x48E `SMRoutSem` | `DOSFSRSEM`, 14 bytes | System-wide fast-safe semaphore serialising session-manager request routing (app-request dispatch, switch, start, parent switch, popup title change, child exit, terminate). **Inner lock.** | #692, #687, #708, #709, `DOSSMPOPUPTLECHG`, `DOSSMCHILDEXIT` (obj3+0xA619, +0xA726), `DOSSMTERMINATE` #705 (obj3+0xCD85, +0xCDA6). | image `cb=0x000E` | Lock; always acquired **after** `PopUpBlockSem` when both are held (#687 obj3:0xCCAA->0xCCBE, #708, #709, `DOSSMPOPUPTLECHG`, and `DOSSMCHILDEXIT` at +0xA602 < +0xA619 and +0xA71B < +0xA726), released first. | [DOC-IBM] layout, [OBS-RE] |
| 0x49C `PM_Data_Ptr` | DWORD far ptr | A PM-side datum returned by the registered `WinInitSession` callback for the session being started, then handed on. | `APPSTARTSESSION` (from #692): `push ds,0x49c; call far [WinInitSession]` (obj3:0x4C23/0x4C26, only when `PM_Present` = 1), then `push dword [0x49c]` to a later call at obj3:0x4CBC (callee not read). | 0 | under `PopUpBlockSem` (APPSTART holds it from 0x4BE4) | [OBS-RE]; meaning [INF] |
| 0x4A0 `StartRamSem` | RAM sem, DWORD | Plain RAM semaphore set at init and cleared when a session start completes; waited on by child-wait. | `DosSemSet` by `DOSSMINITALLOC`; `DosSemClear` by `DOSSMSGSTART` (obj3:0x3CF5); `DosSemRequest`/`Clear` by `DOSSMCHILDWAIT` (internal). | 0; set at #707 time | It is a lock (`xchg` primitive). | [OBS-RE]; purpose [INF] |
| 0x4A4 `SwitchRamSem` | RAM sem, DWORD | Plain RAM semaphore guarding the foreground chain (`TopMost`/`BottomMost`) during a switch and a topmost query. | `DOSSMGSWITCH` (internal; from `DOSSMSGSWITCH`, `DOSSMSGSTART`, `DOSSMSTARTSWITCH`, `DOSSMHDEPOPUP`, `DOSSMPOPUPTLECHG`) holds it obj3:0x6530..0x66F6 around `DOSSGSWITCHPOPUP`/`BACKGROUND`/`FOREGROUND`; `DOSSGQUERYTOPMOST` #878; `DOSSMHDEPOPUP`. | 0 | lock | [OBS-RE] |
| 0x4A8 `TopMost` | DWORD far ptr -> SGCB | The foreground session's SGCB (head of the Z-order chain); SGCB `+0x0A` is the foreground SGID. | Writers: `DOSSMINITALLOC` (= base-shell SGCB), `DOSSGSWITCHFOREGROUND` (obj3:0x6813/0x6817), `DOSSMDELSGCB` (obj3:0xA807/0xA80B, when the deleted SGCB was TopMost). Readers: #878, #692, #687, `DOSSMSGSTART`, `DOSSMSGSWITCH`, `DOSSMPOPUPTLECHG`, `DOSSMHDEPOPUP`, `DOSSGSWITCHPOPUP`, `DOSSMAPPNOTIFY`, `DOSSMCHILDEXIT`, `DOSSMSTARTSWITCH`, `FOREGROUNDFAMILY`, `PARENTSWITCH`, `DOSSMGETSTATUS` #703. | 0; init at #707 | Switch writes under `SwitchRamSem` (`DOSSGSWITCHFOREGROUND` is reached only from `DOSSMGSWITCH`, inside its hold). **Delete writes under `SGCB_QueueRamSem`, not `SwitchRamSem`** (`DOSSMDELSGCB` obj3:0xA7C5..0xA944). #703 reads under `SGCB_QueueRamSem`; #878 under `SwitchRamSem`. | [OBS-RE] |
| 0x4AC `BottomMost` | DWORD far ptr -> SGCB | Tail of the Z-order chain. | Writers `DOSSMINITALLOC`, `DOSSGSWITCHFOREGROUND` (0x681B/0x681F), `DOSSMDELSGCB`; readers `DOSSMHDEPOPUP`, `DOSSMPOPUPTLECHG`. | 0 | as `TopMost` | [OBS-RE] |
| 0x4B0 `LastElement` | DWORD far ptr -> SGCB | The most recently added SGCB: `DOSSMADDSGCB` allocates the new 0xDA-byte SGCB **into** this cell (`DOSSMGETMEM(&LastElement, 0xda)`) and links it from the previous one. | Writers `DOSSMINITALLOC`, `DOSSMADDSGCB` (via `DOSSMGETMEM`), `DOSSMDELSGCB`. | 0 | `DOSSMADDSGCB` takes no lock itself; its callers are `DOSSMINITALLOC` (init), `DOSSMSGSTART` from #708 (under `PopUpBlockSem` + `SMRoutSem`, linear) and from `APPSTARTSESSION` (under `PopUpBlockSem`). `DOSSMDELSGCB` runs under `SGCB_QueueRamSem`. | [OBS-RE] |
| 0x4B4 `BaseShell` (UNI 0x484; its selector half is UNI 0x486) | DWORD far ptr -> SGCB | The base shell's SGCB (screen group 1). | Written only by `DOSSMINITALLOC`; read by #692 (compare with TopMost), `DOSSMSGSTART`, #703. | 0; #707 | write-once | [OBS-RE] |
| 0x4B8 `UsedScrnGrps` | WORD count | Number of screen-group ids currently allocated. | `inc` in `DOSSMGETSGID`, `dec` in `DOSSMFREESGID`; read by #703. | 0 | `DOSSMGETSGID` via `DOSSMADDSGCB` (see `LastElement`); `DOSSMFREESGID` from `DOSSMDELSGCB` (under `SGCB_QueueRamSem`) and from `DOSSMADDSGCB` (retry path) - **not one lock for both**. | [OBS-RE] |
| 0x4BA `MaxFullScrnGrps` | WORD | Size of the full-screen partition of the SGID bitmap, = the Global InfoSeg's `sgMax` passed in BX. | Written by `DOSSMINITALLOC`; read by `DOSSMGETSGID` (partition width), `PARENTSWITCH` (`cmp al`). | 0; #707 | read-only after init | [OBS-RE] |
| 0x4BC `PopUpScrnGrp2` | WORD (SGID, bit 15 = flag) | The screen group that was foreground when a popup was brought up, restored when the popup ends; 0xFFFF = none. | Initialised 0xFFFF by `DOSSMINITALLOC` (a dword store together with `QueueFlags`); `DOSSGSWITCHPOPUP` (masks 0xFF, sets/clears 0x8000, restores 0xFFFF), `DOSSMHDEPOPUP`, `DOSSMGSWITCH` (sets), `DOSSGSWITCHBACKGROUND`, `DOSSMCHILDEXIT`, `DOSSMPOPUPTLECHG`. | 0; 0xFFFF at #707 | Switch-path writes under `SwitchRamSem`; `DOSSMHDEPOPUP` under `SwitchRamSem` (0xC57C..0xC605). | [OBS-RE]; "saved foreground" [INF] |
| 0x4BE `QueueFlags` | WORD | **Meaning not established.** Only written, as the high word of `mov dword [PopUpScrnGrp2],0xffff` in `DOSSMINITALLOC`; no other access found. | - | 0 | - | [OBS-RE] write; meaning [unverified] |
| 0x4C0 `TitleSelector` | WORD (SEL) | Selector of the shared title segment `\SHAREMEM\SMG\SGTITLE` (size 10 if PM is present, else 64 x `TotalScrnGrps`). | `DOSSMINITALLOC` (`DosAllocShrSeg` #35 out parameter; name at +0xAA2) and, after the MOUSE$ open, stores a word at `sel:0`; `DOSSMADDSGCB` writes a length-prefixed <=30-character title at `sel:dx`; `DOSSMSGSTART` zeroes a title byte. | 0; #707 | `DOSSMADDSGCB` callers as for `LastElement`. | [OBS-RE] |
| 0x4C2 `CurrentDebugger` | WORD | By its name, the debugger session currently foreground; value domain not established. | Initialised from AX of `DOSSMADDSGCB` (0) in `DOSSMINITALLOC`; `DOSSGSWITCHFOREGROUND` writes it (from BX) and compares; read by `DOSSGSWITCHPOPUP`, `DOSSMHDEPOPUP`, `DOSSMPOPUPTLECHG`. | 0 | switch writes under `SwitchRamSem` | [OBS-RE]; meaning [unverified] |
| 0x4C4 `IncomingDebugger` | WORD | By its name, the debugger session being switched to; value domain not established. | Initialised as above; written by `DOSSMHDEPOPUP`, `DOSSMPOPUPTLECHG` (three sites); `pop word` by `DOSSMSGSTART`, `DOSSMSGSWITCH`; read by `DOSSGSWITCHFOREGROUND`. | 0 | `DOSSMPOPUPTLECHG` writes under `PopUpBlockSem` + `SMRoutSem` (0xC6F9/0xC723 linear); `DOSSMHDEPOPUP` under `SwitchRamSem`. | [OBS-RE]; meaning [unverified] |
| 0x4C6 `FreeGroups` | BYTE[32] = 256-bit map, scanned as DWORDs | SGID allocation bitmap, bit set = allocated. The low bits of dword 0 are the full-screen partition. | `DOSSMGETSGID` (`lodsd` / `bts`), `DOSSMFREESGID` (`btr [si+0x4c6]`); `DOSSMINITALLOC` stores dword 0x0000000D (ids 0, 2, 3 marked allocated). | 0; #707 | as `UsedScrnGrps` | [OBS-RE] |
| 0x4E6 `Last_Dword` | WORD (DS offset) | Loop bound: DS offset of the last DWORD of `FreeGroups` (0x04E2 = `FreeGroups` + 32 - 4). | Read by `DOSSMGETSGID` (`cmp si,[Last_Dword]`). | **image 0x04E2** | read-only | [OBS-RE] |
| 0x4E8 `LastSGFreed` | WORD (SGID) | A **deferred** free: the SGID of the last deleted session is kept here and only returned to `FreeGroups` on the next delete, or when allocation runs out. | `DOSSMDELSGCB`: if non-zero, `DOSSMFREESGID`, then stores the new SGID; `DOSSMFREESGID` frees `LastSGFreed & 0xFF` and zeroes it; `DOSSMADDSGCB`: on 0x172 (no ids) with `LastSGFreed != 0`, frees it and retries. | 0 | `DOSSMDELSGCB` under `SGCB_QueueRamSem`; the `DOSSMADDSGCB` path is not under it. | [OBS-RE] |
| 0x4EA `SGCB_QueueRamSem` | DWORD far ptr -> `DOSFSRSEM` at obj7+0x00C0 | Pointer to the fast-safe semaphore that guards the SGCB table. | `push dword [0x4ea]` into the fast-safe request/clear: `DOSSMDELSGCB`, `DOSSMGETSTATUS` #703, `DOSSMSGSET` (from `APPSETSESSION`, `PARENTNOTIFY`); `DOSSMGETSGCB` #684 uses the same semaphore through DS = obj7 `0xc0`. | **image `c0 00` + fixup at +0x4EC -> obj7** | It is a lock (fast-safe -> `DC1hSpinLock` in SMP). | [OBS-RE] |
| 0x4EE `SGCB_Array` | DWORD far ptr -> obj7+0x00CE | Pointer to the cell holding the far pointer of the SGCB table. | `DOSSMADDSGCB`, `DOSSMDELSGCB`, `DOSSMCHILDWAIT`. | image `ce 00` + fixup -> obj7 | ADD/DEL as above | [OBS-RE] |
| 0x4F2 `SGCB_PIDArray` | DWORD far ptr -> obj7+0x00D2 | Pointer to the cell holding the parallel per-slot PID table. | `DOSSMADDSGCB` (grow), `DOSSMDELSGCB`, `DOSSMSGSTART` (stores the pid at `+2+sgid*2`). | image `d2 00` + fixup -> obj7 | as above | [OBS-RE] |
| 0x4F6 `SGCB_ArraySize` | DWORD far ptr -> obj7+0x00D6 (a BYTE) | Pointer to the table-capacity byte (seeded 0x19 by `DOSSMINITSGCB`, +8 per growth in `DOSSMADDSGCB`). | `DOSSMADDSGCB`, `DOSSMDOAPPREQ` #692, `REQUESTBLOCKALOC` (via ES). | image `d6 00` + fixup -> obj7 | as above | [OBS-RE] |
| 0x4FA `SGCB_Initialized` | DWORD far ptr -> obj7+0x00D7 (a BYTE) | Pointer to the "SGCB table built" flag; `DOSSMADDSGCB` calls `DOSSMINITSGCB` (#685) when it reads 0, and `DOSSMGETSGCB` #684's first statement does the same. | `DOSSMADDSGCB`. | image `d7 00` + fixup -> obj7 | none around the lazy init in `DOSSMADDSGCB` (as read) | [OBS-RE] |
| 0x4FE `CharData` | 10 bytes | Keystroke buffer for the one `KbdCharIn` issued during screen-group init. | `DOSSMSGINIT` pushes `ds:0x4fe` to `KBDCHARIN` with a `0x00010000` dword. | 0 | init only | [OBS-RE] call; size = `KBDKEYINFO` [INF] |
| 0x508 `CmdInputLen` | WORD | Copy budget for the program-name strings copied into `CmdInputs`: the buffer's size minus 4. | `DOSSMCOPYNAMES` (obj3+0x3EA8, from `DOSSMSGSTART`) loads `cx = [0x508]` once and spends it as one budget across both string copies, with at most three terminator `stosb` beyond it, which keeps `cx` plus the terminators inside `CmdInputs` with one byte spare. `CmdName` is the next symbol in both builds (UNI 0x9E4 after 0x4DA, SMP 0xA14 after 0x50A), so the buffer is 0x50A bytes and 0x50A - 4 = 0x506. | **image 0x0506** | callers of `DOSSMSGSTART` | [OBS-RE] |
| 0x50A `CmdInputs` | char[0x50A] (to 0xA14) | Buffer receiving the program name (and following strings) of the session being started, from the start-data block. | Written by `DOSSMCOPYNAMES` (ES:DI = 9807:050A). | 0 | under whatever `DOSSMSGSTART`'s caller holds (#708: `PopUpBlockSem` + `SMRoutSem`) | [OBS-RE] |

**The obj7 SGCB registry.** The five `SGCB_*` cells are image-initialised far pointers into object 7
(+0xC0, +0xCE, +0xD2, +0xD6, +0xD7): five `stype=2` fixups at obj5+0x4EC/+0x4F0/+0x4F4/+0x4F8/+0x4FC,
every one targeting object 7. Object 5 and object 7 therefore hold **one** SGCB registry, not two
`[OBS-RE]`. `DOSSMGETSGCB` (#684) geometry `[OBS-RE]`:

- Both tables (SGCB pointers and PIDs) start with a 2-byte word; entry N of the SGCB table is at
  table + 2 + Nx8 with the SGCB far pointer at entry +0..+3 (`shl bx,3 / add bx,2 /
  mov ax,[es:bx+di+2] / mov eax,[es:bx+di]`); the PID table is stride 2 after the same 2-byte word;
  **the PID scan starts at index 1, never 0**; the by-SGID arm applies **no bound** (`xor bh,bh`), so
  the zero-selector test is the whole liveness gate.
- **The 2-byte word is the allocator's length word.** `DOSSMGETMEM` (obj3+0x537D) pads the request
  (`add bx,byte +0x6 / and bx,byte -0x4`), allocates and zeroes that many bytes, and
  `mov [es:di],bx` writes the padded length into the block's first word; `DOSSMFREEMEM`
  (obj3+0x53F2) reads it back (`push word [si]`). So the SGCB table requested as 0xC8 is 204 bytes and
  the PID table requested as 0x32 is 56 bytes; entries 0..24 occupy +2..+201 and +2..+51 and both
  fit. Every `DOSSMGETMEM` block has this word, each 218-byte SGCB included ((0xDA+6) & ~3 = 224).

**Locking, group 1.**

| lock | kind | protects (as read) | acquired by -> ordinal |
|---|---|---|---|
| `PopUpBlockSem` (0x468) | `DOSFSRSEM` (SMP: `DC1hSpinLock` inside) | start / switch / parent switch / terminate / popup-title change / child exit as whole operations; `We_Own_Sem` records ownership on the async start path | #687, #708, #709, #705, `DOSSMPOPUPTLECHG`, `DOSSMCHILDEXIT`, `APPSTARTSESSION`/`APPSELECTSESSION` (#692) |
| `SMRoutSem` (0x48E) | `DOSFSRSEM` | request routing: `DOSSMDOAPPREQ` dispatch, `ShellRedrawSem` pulses, `IncomingDebugger` writes in `DOSSMPOPUPTLECHG` | #692, #687, #708, #709, #705, `DOSSMPOPUPTLECHG`, `DOSSMCHILDEXIT` |
| `SwitchRamSem` (0x4A4) | plain RAM sem (`xchg`) | `TopMost`/`BottomMost`/`CurrentDebugger`/`PopUpScrnGrp2` on the switch path | `DOSSMGSWITCH` (reached from #687/#708/#709/popup paths), #878, `DOSSMHDEPOPUP` |
| `SGCB_QueueRamSem` (-> obj7+0xC0) | `DOSFSRSEM` | SGCB table + chain unlink on delete (including the `TopMost`/`BottomMost`/`LastElement` fix-up and the deferred SGID free) | `DOSSMDELSGCB`, #703, `DOSSMSGSET`, #684 |
| `DC1hSpinLock` (obj5+0x57) | kernel spinlock, SMP only | the owner/usage fields of every `DOSFSRSEM` in DOSCALL1 during request/clear | `DOSFSRAMSEMREQUEST`/`CLEAR` via #450/#451 |

Order observed: **`PopUpBlockSem` -> `SMRoutSem`** (always this order, released in reverse).
`SwitchRamSem` is taken inside `DOSSMGSWITCH`, which `DOSSMSGSWITCH`/`DOSSMSGSTART` call while their
callers hold the two above, giving **`PopUpBlockSem` -> `SMRoutSem` -> `SwitchRamSem`** on the #687/#708
paths `[OBS-RE, linear, per call site]`. `NotDD_RamSem` (+0xB34) is taken inside
`DOSSGSWITCHFOREGROUND`/`BACKGROUND`/`POPUP` while `SwitchRamSem` is held. `SGCB_QueueRamSem`'s position
relative to these is **not established**.

**IBM races, as read** `[OBS-RE]` for the accesses, `[INF]` for the race:
- `TopMost`/`BottomMost` are written by `DOSSGSWITCHFOREGROUND` under `SwitchRamSem` and by
  `DOSSMDELSGCB` under `SGCB_QueueRamSem`. `FreeGroups`/`UsedScrnGrps` are touched by `DOSSMFREESGID`
  under `SGCB_QueueRamSem` (delete path) and by `DOSSMGETSGID`/`DOSSMFREESGID` in `DOSSMADDSGCB`
  without it. Whether callers make these mutually exclusive by holding the outer locks is not traced.
- `DOSSMSERVEAPPREQ` tests `ServiceAppThd == 0` and stores the TID with no lock.

**Not established (group 1):** `DetSession`; `QueueFlags`; what lands in `NewSession`; the value domain
of `CurrentDebugger`/`IncomingDebugger` (SGID? PID?); the callee at obj3:0x4CBC that receives
`PM_Data_Ptr`; any reader of `DefPgmName`; whether SMP `DOSSEMREQUEST` keeps UNI's
`test byte [sem+1],3`; the lock `DOSSMCHILDEXIT` holds around its `DOSSMDELSGCB`/`DOSSMAPPNOTIFY` calls
(its other fast-safe requests push 0x14DE, not an obj5 offset; that routine's DS is not traced).

---

### Group 5 - session-manager init names, hard-error / popup / pause daemons, VDM start, title, handles (+0xA14..+0xB15)

#### The machinery `[OBS-RE]`

`DOSSMSGINIT` (internal; <- `DOSSMINITIALIZE` #707), in order:
1. `DosSemSet(PopVioRamSem)`; DOSCALLS #55 (name not established; argument `0x00010000`);
   `KBDSHELLINIT`.
2. `DosGetDBCSEv(..., &CountryCode, &DBCSVector)` (#394).
3. `DosGetInfoSeg` (#8) -> `GlobalSelector`/`LocalSelector`.
4. `DOSSMINITALLOC`, `VIOSHELLINIT`, `DOSSMOPENDD` (#716).
5. `DosExecPgm(..., &HardErrPID, "HARDERR.EXE")`; DOSCALLS #105 (name not established) on `HardErrPID`.
6. `DOSSSINIT`, `DOSSGDDNOTIFY`, `KbdCharIn(&CharData)`.
7. `DosGetEnv` (#91) -> `CmdName`/`CmdArgs`, scanned for `OS2_SHELL`.
8. **`DOSSMNEWTHREADS` over the `NewThreads` table.**
9. If `HardErrPID`: `DosSemSet(HdeSMGRamSem)`; `StartActionPacket` = {1, 1, HardErrPID};
   `DosSystemService(StartActionPacket)` (#88); `DosSemWait(HdeSMGRamSem)`; return `HdeRC` if
   non-zero.

`NewThreads` (image; 6-byte records: entry offset in obj3, stack size, 2 bytes) starts **four
session-manager daemon threads** through `DosCreateThread` (#145), TID into `ThreadID`:

| thread (obj3 offset -> `.SYM`) | stack | loop, as read |
|---|---|---|
| 0xC3F8 `DOSSMCHILDWAIT` | 0x1000 | not read |
| 0xC538 `DOSSMHDEPOPUP` | 0x800 | `DosMuxSemWait(&HdeIndex, &HdeSemNum, -1)` -> hard-error popup: `DosSemSet(HdeVioRamSem)`, `SwitchRamSem` held around `DOSSMGSWITCH`, stores `HdeOldFgnd`/`HdePopRetCode`, `DosSemClear(HdeSMGRamSem)` |
| 0xC68C `DOSSMPOPUPTLECHG` | 0x800 | `DosMuxSemWait(&IndexNumber, &ListSemNum, -1)` -> either a VIO popup (reads `PopUpSGID`/`PID`/`Flags`, `PopUpBlockSem` -> `SMRoutSem`, `DOSSMGSWITCH`, `PopUpReturnCode`, `NotDD_RamSem` + `DOSSMNOTIFYDD`, `DosSemClear(PopSMGRamSem)`) or a title change (`TitleCount`, `STitleRamSem`, `SMRoutSem`, `DOSSMAPPNOTIFY`) |
| 0xC61E `DOSSMPAUDAEMON` | 0x400 | `DosSystemService(&PauseActionPacket, &PauseResponsePacket)` (#88), then `DOSSMPAUSE` (#710), loop |

So the session manager is four daemon threads plus a `HARDERR.EXE` child process, all created in
`DOSSMSGINIT`; popups and hard errors are request/reply handshakes to those threads.

**The popup handshake.** `DOSSMSGDOPOPUP` (#686, <- `VIOPOPUP`) and `DOSSMSGENDPOPUP` (#698,
<- `VIOENDPOPUP`) fill the request and pick a semaphore pair - ordinary popup: SI = `PopSMGRamSem`,
DI = `PopVioRamSem`; hard-error popup: SI = `HdeSMGRamSem`, DI = `HdeVioRamSem`. `_POSTDT` then does
`DosSemSet(SI); DosSemClear(DI); DosSemWait(SI)` and returns `PopUpReturnCode` or `HdePopRetCode`. Each
`*VioRamSem` wakes a daemon and each `*SMGRamSem` is the daemon's reply: these 4-byte RAM semaphores
are **events**, not mutexes.

| off / name | size / type | meaning | accessed by -> ordinal | image / init | concurrency (SMP) | prov |
|---|---|---|---|---|---|---|
| 0xA14 `CmdName` | DWORD far ptr | Pointer into the shell's environment segment: the protected-mode shell's program name, found by scanning for `OS2_SHELL`. | `DOSSMSGINIT` (`DosGetEnv` #91 out, rewritten after `DOSSMREPE`); `DOSSMGETNAMES` (<- `DOSSMSGSTART`). | 0; #707 time | Written once at SM init; read by start paths under group-1 locks. | [OBS-RE] |
| 0xA18 `CmdArgs` | DWORD far ptr | Pointer to the shell's argument string in the same environment. | `DOSSMSGINIT`, `DOSSMGETNAMES`. | 0 | same | [OBS-RE] |
| 0xA1C `VDMName` | ASCIIZ `"DOS Session"` (12) | Default program title for a DOS session. | `DOSSMGETNAMES`: `mov di,0xa1c` when the session type is 4 or 7 (VDM). | image string | read-only | [OBS-RE] |
| 0xA28 `CountryCode` | 4 bytes `COUNTRYCODE` | Country/code-page input to the session manager's own `DosGetDBCSEv`. | `DOSSMSGINIT`. | 0 | init only | [OBS-RE] |
| 0xA2C `DBCSVector` | BYTE[16] | The session manager's DBCS lead-byte vector - a live input to its path parsing, not init-only state. | Filled by `DOSSMSGINIT` (#394). Read by the session manager's DBCS-aware string scanners: `DOSSMREPNE` (obj3+0xC906) and `DOSSMREPE` (obj3+0xC955), each `mov bx,0x9807 / mov ds,bx / mov si,0xa2c` at +0xC912/+0xC961; and `DOSSMPARSEPATH` (obj3+0xC8B4) `mov si,0xa2c` at +0xC8BA on an inherited DS `[INF]`, immediately before a scan for `\`/`:` (`mov ax,0x3a5c`). These are the routines of the shell-name parse chain behind `CmdName`. | 0 | Written at init; read without a lock. | [OBS-RE] |
| 0xA3C `HardErrPID` | WORD (RESULTCODES `codeTerminate` slot) | PID of `HARDERR.EXE`, started by the session manager at init. | `DOSSMSGINIT` (`DosExecPgm` out; #105 on it; test; copied to `StartActionPacket`+4). | 0 | init only | [OBS-RE] |
| 0xA40 `HdeIndex` | WORD | `DosMuxSemWait` index output for the hard-error daemon. | `DOSSMHDEPOPUP`. | 0 | daemon-thread private use of a shared cell | [OBS-RE] |
| 0xA42 `HdeOldFgnd` | WORD | The foreground value saved by the hard-error switch (from CX after `DOSSMGSWITCH`). | `DOSSMHDEPOPUP`. | 0 | written after releasing `SwitchRamSem` | [OBS-RE]; value domain [unverified] |
| 0xA44 `HdePopFlags` | BYTE | Popup (0) vs end-popup (1) request for the hard-error daemon; added into its dispatch. | Set 0 by #686, 1 by #698; read by `DOSSMHDEPOPUP`. | 0 | set by the API thread before signalling `HdeVioRamSem` | [OBS-RE] |
| 0xA46 `HdePopRetCode` | WORD | Result of the hard-error popup, returned by #686/#698 on the hard-error path. | Written by `DOSSMHDEPOPUP`; read by `DOSSMSGENDPOPUP_POSTDT`. | 0 | handshake-ordered (written before the `HdeSMGRamSem` clear) | [OBS-RE] |
| 0xA48 `HdeProc` | ASCIIZ `"HARDERR.EXE"` (12) | Program the session manager starts as the hard-error handler. | `DOSSMSGINIT` -> `DosExecPgm`. | image string | read-only | [OBS-RE] |
| 0xA54 `HdeSMGRamSem` | RAM sem DWORD | Reply event: hard-error daemon -> caller; also waited on by `DOSSMSGINIT` for HARDERR's start. Its far address is returned by #711 to HARDERR.EXE (group 6). | `DOSSMSGINIT` (set, wait), `DOSSMHDEPOPUP` (clear), #686/#698 `_POSTDT` (set/wait); HARDERR.EXE clears it through the pointer #711 returns, which is what ends `DOSSMSGINIT`'s wait. | 0 | event (`xchg` primitive) | [OBS-RE] |
| 0xA58 `HdeRC` (UNI 0xA28) | WORD | Return code of the hard-error start handshake; non-zero is returned from `DOSSMSGINIT`. | Read by `DOSSMSGINIT`. No writer in DOSCALL1's code; **HARDERR.EXE writes it** through the far pointer #711 returns (`HdeSMGRamSem` + 4): HARDERR obj2:0x336 `mov word es:[di+4],ax` zeroes it before HARDERR's obj2:0x350 `DosSemClear(ES:DI)` (UNI build). | **image 481 (0x01E1)** | - | [OBS-RE] |
| 0xA5A `HdeVioRamSem` (UNI 0xA2A) | RAM sem DWORD | Request event: caller -> hard-error daemon. | `DOSSMINITALLOC` (set), `DOSSMHDEPOPUP` (set), #686/#698 (clear); listed in `HdeSem`. | 0 | event | [OBS-RE] |
| 0xA5E `IndexNumber` | WORD | `DosMuxSemWait` index output for the popup/title daemon. | `DOSSMPOPUPTLECHG`. | 0 | daemon-private | [OBS-RE] |
| 0xA60 `EnvName` | char[9] `"OS2_SHELL"` (not NUL-terminated) | Environment keyword whose value names the protected-mode shell. | `DOSSMSGINIT` (`mov si,0xa60`, count from `EnvNameLen`). | image string | read-only | [OBS-RE] |
| 0xA69 `EnvNameLen` | BYTE = 9 | Its length (length-byte form). | `DOSSMSGINIT`. | image 9 | read-only | [OBS-RE] |
| 0xA6A `KeyFileName` (UNI 0xA3A) | ASCIIZ `"KBD$"` | Keyboard device name. | `DOSSMINITALLOC` (`DosOpen` -> `QHKEYBDHANDLE`); `DOSSMOPENDD` (#716) compares registered DD names to it (`repe cmpsb`) and stores `QHKEYBDHANDLE` into `DD_Handles`. | image string | read-only | [OBS-RE] |
| 0xA6F `KeyNameLen` | BYTE = 5 | Compare length. | `DOSSMOPENDD`. | image 5 | read-only | [OBS-RE] |
| 0xA70 `MseFileName` | ASCIIZ `"MOUSE$"` | Mouse device name, same two uses. | `DOSSMINITALLOC`, `DOSSMOPENDD`. | image string | read-only | [OBS-RE] |
| 0xA77 `MseNameLen` | BYTE = 7 | Compare length. | `DOSSMOPENDD`. | image 7 | read-only | [OBS-RE] |
| 0xA78 `VVideo_Name` | ASCIIZ `"VVIDEO1$"` | Virtual-video device name, used on the VDM freeze path. | `DOSSMFREEZEVDM` pushes it as a far pointer (`push word 0x9807 / push word 0xa78` at obj3+0xC1BD) into `call 0xe01e:0x64bb`, with a second far pointer from `[bp+4]`. What the callee (obj3+0x64BB) does with the name is not read. | image string | read-only | [OBS-RE] bytes and push; callee's use [unverified] |
| 0xA81 `PM_Present` (UNI 0xA51) | BYTE | 1 if the registered shell is PM. Also the gate every IBM caller tests before `call far` through a PM callback cell (group 6). | Set by `DOSSMINITIALIZE` (#707) when the init block is type 0x10 with +0xE = 1; read by #712 (returns it), `APPSENDREQUEST`, `APPSTARTSESSION`, `APPSELECTSESSION`, `APPSETSESSION`, `DOSSMADDSGCB`, `DOSSMCHILDEXIT`, `DOSSMGSWITCH`, `DOSSMINITALLOC`, `DOSSMSETTITLE`, #703, #713. | 0 | write-once at #707 | [OBS-RE] |
| 0xA82 `StartVDMSGID` | BYTE | A pending "next start is this VDM's screen group" value, consumed once by a start request from the VDM server thread. | Written by 32-bit `VDMSTARTSESSION` (obj2+0x489D, flat `mov [0x13000a82],al`). Read by `REQUESTBLOCKALOC`: if non-zero, request SGID == 1 and caller TID (LIS+6) == `VDMServerTID`, marks the request 0x80, takes the SGID and zeroes the cell. | 0 | Read-and-clear with `DosHoldSignal(1)` held (#13 at obj3+0x5166..0x520A), **no lock**. | [OBS-RE] |
| 0xA84 `VDMServerTID` | WORD TID | The thread allowed to consume `StartVDMSGID`. | Written by 32-bit `CREATEVDMSERVER` (obj2+0x47E1, `mov [0x13000a84],ax`, the TID `DOS32CREATETHREAD` just returned); read by `REQUESTBLOCKALOC`. | 0 | as above | [OBS-RE] |
| 0xA86 `VDMCurDir` | DWORD far ptr | Current-directory string for a VDM start, pushed into the request when flag 0x80 is set. | Written by `VDMSTARTSESSION` (obj2+0x48A7, `mov [0x13000a86],eax`, four bytes after it writes +0xA82); read by `APPSENDREQUEST` (<- #702/#699/#694/#693) and `DOSSMSGSTART` (override). | 0 | - | [OBS-RE] |
| 0xA8A `PauseActionPacket` | WORD | Action code the pause daemon passes to `DosSystemService`. | `DOSSMPAUDAEMON` (#88). | **image 2** | read-only | [OBS-RE] |
| 0xA8C `PauseResponsePacket` | WORD | Response buffer for that call, then used by `DOSSMPAUSE` (#710). | `DOSSMPAUDAEMON`. | 0 | daemon-private | [OBS-RE] |
| 0xA8E `PopSMGRamSem` | RAM sem DWORD | Reply event: popup daemon -> #686/#698 caller. | #686/#698 `_POSTDT`, `DOSSMPOPUPTLECHG` (clear). | 0 | event | [OBS-RE] |
| 0xA92 `PopUpFlags` | WORD | Popup request flags: 0x8000 set by #686 variants, bit 0 set by #698. | #686, #698, `DOSSMPOPUPTLECHG`. | 0 | set by the API thread before the request event | [OBS-RE]; bit meanings [unverified] |
| 0xA94 `PopUpReturnCode` | WORD | Result of the popup switch. | Written by `DOSSMPOPUPTLECHG` (from `DOSSMGSWITCH`); read by #698 `_POSTDT`. | 0 | handshake-ordered | [OBS-RE] |
| 0xA96 `PopUpPID` | WORD PID | Process requesting the popup. | #686; `DOSSMPOPUPTLECHG`; `DOSSGSWITCHFOREGROUND` (pushed to #105); `DOSSGSWITCHPOPUP`. | 0 | - | [OBS-RE] |
| 0xA98 `PopUpSGID` | WORD SGID | Screen group of the popup requester. | #686; `DOSSMPOPUPTLECHG`; `DOSSMGSWITCH` (compare); `DOSSGSWITCHPOPUP`. | 0 | switch reads under `SwitchRamSem` | [OBS-RE] |
| 0xA9A `PopUpPrType` | WORD | Requester's process/session type for the popup. | #686, `DOSSGSWITCHPOPUP`. | 0 | - | [OBS-RE]; meaning from name [INF] |
| 0xA9C `PopVioRamSem` | RAM sem DWORD | Request event: caller -> popup daemon. Set at SM init; first entry of `ListSem`. | `DOSSMSGINIT` (set), `DOSSMPOPUPTLECHG` (set), #686/#698 (clear). | 0 | event | [OBS-RE] |
| 0xAA0 `PrsOpenAction` | WORD | `DosOpen` action output for the KBD$/MOUSE$ opens. | `DOSSMINITALLOC`. | 0 | init | [OBS-RE] |
| 0xAA2 `SGTitleName` | ASCIIZ `"\SHAREMEM\SMG\SGTITLE"` (22) | Name of the shared title segment. | `DOSSMINITALLOC` (`DosAllocShrSeg`), `DOSSMSGSETTITLE` (pushed; the call it feeds is not read). | image string | read-only | [OBS-RE] |
| 0xAB8 `STitleRamSem` | RAM sem DWORD | Request event: title changed -> popup/title daemon; second entry of `ListSem`. | `DOSSMINITALLOC` (set), `DOSSMPOPUPTLECHG` (clear then set), `DOSSMSGSETTITLE` (`push word 0x9807 / push word 0xab8` at obj3+0xC88A). | 0 | event | [OBS-RE] |
| 0xABC `StartActionPacket` | 6 bytes {1, ?, pid} | `DosSystemService` packet announcing the hard-error process: +2 set to 1, +4 = `HardErrPID`. | `DOSSMSGINIT` (#88). | **image {1,0,2}**; +2/+4 rewritten | init only | [OBS-RE] |
| 0xAC2 `SwitchActionPacket` | 6 bytes | A named switch action packet. **No access found** on any instrument. | - | image {1,0,2} | - | [OBS-RE] bytes; use [unverified] |
| 0xAC8 / 0xACA `SwtMseParm1/2` | 2 x WORD | Named mouse parameters for switch. **No access found.** | - | image 1, 0 | - | [unverified] |
| 0xACC / 0xACE `XitMseParm1/2` | 2 x WORD | Named mouse parameters for exit. **No access found.** | - | image 1, 0 | - | [unverified] |
| 0xAD0 `ListSemNum` + 0xAD2 `ListSem` | WORD count = 2, then 2 x {WORD 0, DWORD HSEM} | A `DosMuxSemWait` list: `PopVioRamSem` (9807:0A9C) and `STitleRamSem` (9807:0AB8). The popup/title daemon waits on both. | `DOSSMPOPUPTLECHG` (#22 `DosMuxSemWait`). | **image-initialised; obj5 fixups at +0xAD6/+0xADC**; the 12-byte gap holds exactly two entries | read-only | [OBS-RE]; layout = `MUXSEMLIST` [DOC-IBM] Open Watcom 1.9 `h/os21x/bsedos.h:458-466` |
| 0xADE `HdeSemNum` + 0xAE0 `HdeSem` | WORD count = 1 + {0, 9807:0A5A} | `DosMuxSemWait` list for the hard-error daemon: `HdeVioRamSem`. | `DOSSMHDEPOPUP` (#22). | image + fixup at +0xAE4 | read-only | [OBS-RE] |
| 0xAE6 `NewThreads` | 4 x 6-byte {WORD obj3 entry, WORD stack, WORD 0} | Table of the session manager's daemon threads (table above). | `DOSSMNEWTHREADS` (<- `DOSSMSGINIT`, `DOSSMCHILDWAIT`), via #145. | image table | read-only | [OBS-RE] |
| 0xB06 `ThreadID` | WORD (+2) | TID output of `DosCreateThread`. | `DOSSMNEWTHREADS`. | 0 | - | [OBS-RE] |
| 0xB0A `TitleCount` | WORD | Pending title-change counter: `inc` on a change that could not be delivered, zeroed when delivered. | `DOSSMPOPUPTLECHG`. | 0 | inc/zero under `SMRoutSem` (linear) | [OBS-RE] |
| 0xB0C `TotalScrnGrps` (UNI 0xADC) | WORD | `GINFOSEG.sgMax`; also SM init's once-guard (`cmp word [0xb0c],0` -> 418). | `DOSSMSGINIT` (guard, write), `DOSSMSGSETTITLE` (count). | 0 | - | [OBS-RE] |
| 0xB0E `QHMOUSEHANDLE` | WORD HFILE | MOUSE$ handle; **DOSCALLS data export #857**. | `DOSSMINITALLOC` (`DosOpen` out), `DOSSMOPENDD` (into `DD_Handles`). | 0 | init | [OBS-RE] |
| 0xB10 `QHKEYBDHANDLE` | WORD HFILE | KBD$ handle; **data export #856**. | same | 0 | init | [OBS-RE] |
| 0xB12 `SMG_INSTANCE` | DWORD far ptr -> obj8+0 | Pointer to the per-process `BVHINSTANCE` object (object 8), valid in every process because object 8 has the same selector everywhere. | `DOSSCRLOCK` #695, `DOSSCRUNLOCK` #691, `DOSMODEWAIT` #704, `DOSMODEUNDO` #701, `DOSSAVREDRAWWAIT` #696, `DOSSAVREDRAWUNDO` #697, `DOSCLEANUP`, `PARENTEXITLIST`, `SSTHAWPIDS`, `APPSENDREQUEST`, `REQUESTBLOCKALOC`, `DOSSTARTSESSION` #702. | **image: selector 0x981F + obj5 fixup -> obj8** | read-only | [OBS-RE] |

**Locking, group 5** `[OBS-RE]` unless marked.
- **Event semaphores, not mutexes:** `PopVioRamSem`/`PopSMGRamSem` and `HdeVioRamSem`/`HdeSMGRamSem`
  (request/reply pairs), plus `STitleRamSem`. They order a request between an API thread (#686/#698)
  and a daemon thread; they do not serialise two API callers.
- **Serialising two popup callers is not done in this code.** #686/#698 write
  `PopUpPID`/`SGID`/`Flags`/`PrType` and `HdePopFlags` without taking a lock. Their callers
  `VIOPOPUP`/`VIOENDPOPUP` take fast-safe semaphores; which, and whether that covers these cells, is
  not established.
- **The daemons take the group-1 locks inside:** the popup daemon takes `PopUpBlockSem` -> `SMRoutSem`
  (-> `SwitchRamSem` via `DOSSMGSWITCH`) and `NotDD_RamSem`; the hard-error daemon takes `SwitchRamSem`
  only.
- **The VDM start hand-off** (`StartVDMSGID` read-and-clear) runs with signals held and no lock.
- **Init-time cells** (`CmdName`, `CmdArgs`, `HardErrPID`, `TotalScrnGrps`, the handles, `PM_Present`)
  are written during #707 by the shell process only and are read-only afterwards.
- No SMP-only lock in this group.

**Not established (group 5):** any use of `SwitchActionPacket` and the four `Swt/XitMseParm*` (no
access on any instrument); the names of DOSCALLS #55 and #105; `DOSSMCHILDWAIT`'s loop; the lock
`VIOPOPUP`/`VIOENDPOPUP` hold around #686/#698.

---

### Group 6 - device-driver notification and registration, `SMG_Flags`, PM callback table (+0xB16..+0xC1F; UNI = SMP - 0x30)

Kernel ordinals used here: #34 `DosAllocSeg`, #44/#45/#46 `DosLoadModule`/`DosGetProcAddr`/
`DosFreeModule`, #59 `DosClose`, #70 `DosOpen`, #77 `DosQHandType`, #85 `DosSetMaxFH`, #99 (an IOCtl
entry; its name not confirmed), #121 `DosGetSeg`, #166 `DosQSysInfo`.

`SMGGLOBALINIT` (SMP obj3+0xDD3A): #166 into `Max_Path_Length` with the 0x104 default,
`imul cx,ax,0x10`, #34 into `DD_Names_Selector`, `rep stosw`, returns 1 or 0 `[OBS-RE]`.
`DOSSMOPENDD` (#716, SMP obj3+0xB948): the `HardError_Do_NotifyDD` == 1 -> `DosSetMaxFH(0x1E)` arm, #121
on `DD_Names_Selector`, the KBD$/MOUSE$ `repe cmpsb` storing `QHKEYBDHANDLE`/`QHMOUSEHANDLE` into
`DD_Bit_Maps`/`DD_Handles`, the generic #70/#77/#59 arm, the #44/#45/#46 DLL arm, `inc Registered_DLLs`
`[OBS-RE]`. `DOSSMREGISTERDD` (#713, SMP obj3+0xA2D5): `cmp Registered_DDs,0xF / jc` +
`mov ax,cs / cmp [bp+4],ax` (the cap of 15 applies to external callers), `test SMG_Flags,2` -> 418
(0x1A2), the record offset `Max_Path_Length * Registered_DDs`, the name cap `sub cx,6`,
`inc Registered_DDs`, `retf 4` `[OBS-RE]`.

| off / name | size / type | meaning | accessed by -> ordinal | image / init | concurrency (SMP) | prov |
|---|---|---|---|---|---|---|
| 0xB16 `NotDD_IOCtl_Error` | WORD (+2) | First error returned by a driver/DLL during a notification pass; returned from `DosSMNotifyDD`, then cleared. | Written by `DOSSMNOTIFYDD_LOOP`; read and zeroed by `DOSSMNOTIFYDD` (#714). | 0 | Written in the notifying thread while `NotDD_RamSem` is held by the requester. | [OBS-RE] |
| 0xB1A `NotDD_Data_Address` | DWORD far ptr | The notification packet being delivered. | Stored by #714; read (`les bx`, pushed) by `DOSSMNOTIFYDD_LOOP`. | 0 | as above | [OBS-RE] |
| 0xB1E `NotDD_DosDev_Data_Len` | WORD | First word (`Length`) of the **built-in notification packet** filled by the session manager itself. | Written by `DOSSGSWITCHFOREGROUND`, `DOSSGSWITCHBACKGROUND`, `DOSSGSWITCHPOPUP`, `DOSSMGSWITCH`, `DOSSMCHILDEXIT`, `DOSSMINITIALIZE` #707, `DOSSMPOPUPTLECHG`, `DOSSMSGSTART`, then `push ds,0xb1e` -> #714. | 0 | **under `NotDD_RamSem`** (request at e.g. obj3+0x67DB, clear +0x6809) | [OBS-RE] |
| 0xB20 `NotDD_Notification_Type` | WORD | Kind of event in that packet. Bit 0 (1) pre-session-save, bit 1 (2) post-session-save, bit 2 (4) post-session-restore, bit 3 (8) session termination. #707 writes 2 (post-save); `DOSSGSWITCHFOREGROUND` writes 2 then 4 at its two sites (post-save then post-restore); the switch routines write 2 or 4. The meanings of 0x10, 0x20, 0x40, 0x80 and 0x100 are **not established**: the documentation calls bits 15-4 reserved, yet #713's shipped mask `0xFE00` accepts bits 8..4 and #714 accepts 0x80/0x100 from an external caller. | same writers | 0 | under `NotDD_RamSem` | [OBS-RE] the writes; 1/2/4/8 [DOC] EDM2 `DosSMRegisterDD`, Parameters, `Notification` (bit 0 "Pre-Session save notification. Action = 1", bit 1 "Post-Session save ... Action = 2", bit 2 "Post-Session restore ... Action = 4", bit 3 "Session termination ... Action = 8"); 0x10-0x100 [unverified] |
| 0xB22 `NotDD_InSG_or_OutType` | WORD | Packet field 3: a screen group or a type, depending on the notification shape. | same writers | 0 | same | [OBS-RE]; name-derived meaning [INF] |
| 0xB24 `NotDD_InType_or_OutSG` | WORD | Packet field 4. | same writers | 0 | same | same |
| 0xB26 `NotDD_OutSG` | WORD | Packet field 5 (outgoing screen group). | `DOSSMGSWITCH` only (two sites). | 0 | same | same |
| 0xB28 `NotDD_OutType` | WORD | Packet field 6. | `DOSSMGSWITCH` only. | 0 | same | same |
| 0xB2A `SMG_DoNotifyDD` | RAM sem DWORD | Request event: "a notification is ready" -> the waiting `DosSMNotifyDD2` thread. | #714 clears it; #715 sets and waits on it. | 0 | event | [OBS-RE] |
| 0xB2E `SMG_DidNotifyDD` | RAM sem DWORD | Reply event: `DosSMNotifyDD2` -> the #714 caller. | #714 sets it and waits; #715 clears it. | 0 | event | [OBS-RE] |
| 0xB32 `HardError_Do_NotifyDD` (UNI 0xB02) | WORD | 1 = notifications are delivered by a separate thread (HARDERR's, via #715) rather than inline. **No writer exists; on a shipped system it is a constant 0** (see below). | Read by #714 (`cmp 1` -> handshake vs inline `DOSSMNOTIFYDD_LOOP`), #716 **twice** (`DosSetMaxFH(30)` when 1; and inside its record loop, see below), `DOSSMSGINIT` (0 -> sets `SMG_Flags` bit 1), and returned by #711 `DosSMHDeInit`. | **image 0** | - | [OBS-RE] |
| 0xB34 `NotDD_RamSem` | RAM sem DWORD, used as a mutex | **Mutex** serialising the built-in notification packet (`NotDD_*`) and each call into #714 by the session manager. | Requested/cleared by `DOSSGSWITCHFOREGROUND`/`BACKGROUND`/`POPUP`, `DOSSMGSWITCH`, `DOSSMCHILDEXIT`, #707, `DOSSMPOPUPTLECHG`, `DOSSMSGSTART`; set by `DOSSMCHILDWAIT`. | 0 | It is the lock (`xchg` primitive), the same in UNI. | [OBS-RE] |
| 0xB38 `DD_Bit_Maps` | WORD[16] | Per registered driver/DLL: which notification types it wants (tested per packet in `DOSSMNOTIFYDD_LOOP`). | Filled by #716; read by the loop. | 0 | Written once by #716 at SM init; read under the notification handshake. | [OBS-RE] |
| 0xB58 `DD_Handles` | DWORD[16], HFILE-or-PFN union | Per entry: a device HFILE (`push word [bx+si]` -> #99 IOCtl) or a DLL entry far pointer (`call far [bx+si]`). | Filled by #716; used by `DOSSMNOTIFYDD_LOOP`. | 0 | as above | [OBS-RE] |
| 0xB98 `Max_Path_Length` | WORD | Maximum path length + 4 = the registration-record stride. | `SMGGLOBALINIT` (#166, default 0x104), #713, #716. | 0; once per system | inside the unlocked once-per-system init | [OBS-RE] |
| 0xB9A `DD_Names_Selector` | WORD SEL | Selector of the zero-filled registration-record segment (16 records). | `SMGGLOBALINIT` (#34), #713 (#121), #716 (#121; frees it). | 0; once per system | same | [OBS-RE] |
| 0xB9C `Registered_DDs` | WORD count | Number of registration records. | #713 (cap 15 for external callers; `inc`), #716, `DOSSMNOTIFYDD_LOOP`. | 0 | #713 does check-then-append with **no lock**; its callers are driver INIT code, which the kernel runs serially `[INF]`. | [OBS-RE] |
| 0xB9E `Registered_DLLs` | WORD count | Entries #716 bound as DLLs; non-zero makes session start and start-switch take a notification path. | `inc` in #716; tested by `DOSSMSGSTART`, `DOSSMSTARTSWITCH`. | 0 | init-time write | [OBS-RE] |
| 0xBA0 `SMG_Flags` (UNI 0xB70) | BYTE bits | **Bit 0** "a session manager is registered" (set by #707). **Bit 1** "registration closed / notifications enabled" (set by `DOSSMSGINIT` when `HardError_Do_NotifyDD` == 0, and unconditionally by `DosSMNotifyDD2` #715; tested by #713 -> 418 and by #714). **Bit 2** set by #707 when GIS `SIS_ProtMdOnly` != 0; tested by #713 and `REQUESTBLOCKALOC`. **Bit 3** tested and then set by `APPSTARTSESSION` (UNI obj3:0x3B79 `test word [0xb70],0x8` / 0x3B98 `or word [0xb70],byte +0x8`) - a set-once latch whose meaning is not established. | Written by #707 (bits 0, 2), `DOSSMSGINIT` (bit 1), #715 (bit 1), `APPSTARTSESSION` (bit 3); read by `DOSSMSGINIT`, #713, #714, `REQUESTBLOCKALOC`. | 0 | Five write sites in four functions (UNI obj3: 0x341E #715, 0x3B98 `APPSTARTSESSION`, 0x9D5C `DOSSMSGINIT`, 0xA030 and 0xA04E #707); two are not the bare byte form (one `or word`, one `es:`-prefixed). **No lock around any of them**, and #715's runs on a different thread. | [OBS-RE]; bit-2 meaning [INF] |
| 0xBA2 `DOSSMSYSINIT` | DWORD | **DOSCALLS data export #855**: a RAM semaphore **born SET** in the image and cleared by `DosSMInitialize` (#707) once a non-PM shell has initialised (`PM_Present` == 0 -> `DosSemClear(9807:0BA2)`). An importer can wait on it for "session manager ready" `[INF]`. PMMERGE imports #855. | #707. | **image 0xFFFFFFFF** | an event, cleared once | [OBS-RE] |
| 0xBA6 `StartParmsMaxLen` | WORD | Accepted `STARTDATA` length for session starts: 0x3C by default; set to 0x20 if the PM callback DLLs fail to load, or 0x1E on a protect-mode-only non-PM system. | #707 writes; `DOSSTARTSESSION` #702 reads. | **image 0x3C** | init-time | [OBS-RE] |
| 0xBA8 `Winner_Handle` (+ ASCIIZ `"OS2SM"` at +0xBAA) | WORD HMODULE + name | Module handle of the PM session-callback DLL, loaded by name from the string stored just after it. | `DOSWINPROC` (#44 into `[si]` = 0xBA8, name at `si+2`), from #707; `DOSSMSETTITLE`. | 0; name in image | init-time | [OBS-RE] |
| 0xBB1 / 0xBB3 (inside `Winner_Handle`'s span) | WORD HMODULE + ASCIIZ `"PMVIOP"` | Handle and name of the PM VIO console DLL, same mechanism. | `DOSWINPROC` from #707 (`si` = 0xBB3). | image name | init-time | [OBS-RE] |
| 0xBBE `WinInitSession` ... 0xBD6 `WinSetTitle` | 7 x DWORD far ptr | PM callbacks resolved by ordinal from OS2SM: `WinInitSession`, `WinEndSession`, `WinInitSwEntry`, `WinSetSwEntry`, `WinQueryExtIDFocus`, `WinSetExtIDFocus`, `WinSetTitle`. Called `call far [cell]`: +0xBBE and +0xBC6 by `APPSTARTSESSION`; +0xBC2 by `DOSSMCHILDEXIT`; +0xBCA by `APPSETSESSION`; +0xBCE by `DOSSMGSWITCH`, `DOSSMSGSTART`, `FOREGROUNDFAMILY`, `PARENTSWITCH`; +0xBD2 by `APPSELECTSESSION`, `DOSSMSWITCH` #687, `PARENTSWITCH`; +0xBD6 by `DOSSMSETTITLE` #690 - the one called in the caller's own process. Every caller gates the call on `PM_Present` == 1 (`cmp byte [0xa51],1` in UNI, e.g. obj3:0x9B5B before `lcall [0xb8e]`, obj3:0x9C7C before `lcall [0xb96]`, the same shape at the other five), **not** on a null test of the cell; that works because one routine both sets the flag and fills the cells. | Filled by `DOSWINPROC` (#45 by ordinal; #46 unload on failure), from #707. | 0 | Called under whatever group-1 locks the caller holds. | [OBS-RE] |
| 0xBDA `WinInitSession_Name` ... 0xBE6 `WinSetTitle_Name` | 7 x WORD ordinal | The OS2SM export ordinals for those seven callbacks: 31, 32, 33, 34, 35, 36, 42. The `.SYM` names six of the seven cells; +0xBDC has no name. | `DOSWINPROC` (`bx` = 0xBDA). | **image 31, 32, 33, 34, 35, 36, 42** | read-only | [OBS-RE] |
| 0xBE8 `WinCreateConsole`, 0xBEC `WinDestroyConsole` | 2 x DWORD far ptr | PMVIOP console callbacks: +0xBE8 called by `DOSSMSTARTSWITCH`, +0xBEC by `DOSSMCHILDEXIT`. | `DOSWINPROC` from #707. | 0 | as above | [OBS-RE] |
| 0xBF0 (unnamed, inside `WinDestroyConsole`'s span) | 2 x WORD ordinal | PMVIOP export ordinals for those two. | `DOSWINPROC` (`bx` = 0xBF0). | **image 1, 2** | read-only | [OBS-RE] |
| 0xBF4 `SecQueueName` | ASCIIZ `"\QUEUES\SESMGR\SECURITY"` (24) | A named queue used at session start. | `DOSSMSGSTART` passes it as a far pointer (`push word 0x9807 / push word 0xbf4` at obj3+0x39C0) into `call 0xe01e:0x1b50`, with a `[bp-0x1a]` stack buffer as the second far argument and the result tested `or ax,ax` - the shape of a queue open/create returning an rc `[INF]`. The callee is not read. | image string | - | [OBS-RE] bytes and push; callee's use [unverified] |
| 0xC0C (unnamed) | ASCIIZ `"NOJIT"` | Environment variable name, a second copy (cf. +0x16), used by #707 (`push ds,0xc0c` -> `DosScanEnv`, obj3+0xBF52). | #707. | image string | read-only | [OBS-RE] |
| 0xC12..0xC1F | - | Zero (hits in `LoadWinthorn`/`OUTSKIP` run on other segments). | - | - | - | [OBS-RE] bytes |

#### The notification packet: three shapes on one set of six cells `[OBS-RE]`

IBM's own `_or_` symbol names (`NotDD_InSG_or_OutType`, `NotDD_InType_or_OutSG`) record that the
packet has three shapes, sized by its own first word, not by the number of cells:
- **Length 8**, four cells used, types 1/2/4/8 (and 0x10) - #707 and the switch routines.
- **Length 0x0C**, six cells used, types 0x20/0x40 - written only inside `DOSSMGSWITCH`, which is also
  the only writer of `NotDD_OutSG`/`NotDD_OutType` (UNI obj3:0x519A/0x51A1/0x5291/0x5298).
- **Length 0x18**, types 0x80/0x100 - the **external** shape, which has no internal writer and is the
  only shape #714 validates.

A short-shape writer leaves the last two cells holding the previous notification's values, which is
harmless because the `Length` word it wrote is what the IOCtl transfers.

**#714 validates only packets outside object 5.** UNI obj3:0x338C `mov cx,es / cmp cx,0x9807 /
je 0x33AF` takes the selector half of the far pointer just loaded from `NotDD_Data_Address` and, when
it is object 5's own selector, jumps past **both** the `cmp word [es:di],0x18` length check
(obj3:0x3394) and the type check (0x33A0/0x33A6) to the `or ax,ax` at 0x33AF. An object-5-resident
packet is an internal caller by construction and is never validated; 0x18 applies only to a packet
that lives elsewhere. That is why #707 can hand an 8-byte packet to a routine that otherwise demands
0x18 `[OBS-RE]`.

#### Delivery: inline or handed off `[OBS-RE]` (addresses UNI)

- **`NotDD_RamSem` is a mutex** (plain RAM sem, `xchg`). Every session-manager routine takes it
  around filling the shared `NotDD_*` packet and calling #714. It nests **inside** `SwitchRamSem` on
  the switch path (`DOSSMGSWITCH` holds `SwitchRamSem` and its callees take `NotDD_RamSem`) and inside
  `PopUpBlockSem` in `DOSSMPOPUPTLECHG`. So: `PopUpBlockSem` -> `SMRoutSem` -> `SwitchRamSem` ->
  `NotDD_RamSem`.
- **Delivery is chosen by `HardError_Do_NotifyDD`.** Inline: `DOSSMNOTIFYDD_LOOP` runs in the caller.
  Handed off: #714 does `DosSemSet(SMG_DidNotifyDD)`, `DosSemClear(SMG_DoNotifyDD)`,
  `DosSemWait(SMG_DidNotifyDD)`, while a thread parked in #715 wakes, runs the loop and clears
  `SMG_DidNotifyDD`. These two are events.
- **#715's loop-top order is load-bearing.** It re-arms the request event before releasing the
  requester: obj3:0x342A `DosSemSet(SMG_DoNotifyDD)` **then** 0x3433 `DosSemClear(SMG_DidNotifyDD)`,
  then 0x343C `DosSemWait(SMG_DoNotifyDD, -1)`, then the near call to the loop, then `jmp` back. In the
  other order a requester woken by the clear could post into an unarmed event and lose the request
  `[INF]`. The clear of `SMG_DidNotifyDD` happens at the top of the *next* iteration, after the work,
  which is what makes #714's `DosSemWait(SMG_DidNotifyDD, -1)` a completion wait.
- **#715 never returns**; the `.SYM` still names its unreachable `retf` `DOSSMNOTIFYDD2_POSTDT`
  (obj3:0x3451). It is the body of HARDERR.EXE's daemon thread, not a call that completes.
- **#715 takes a register argument, `ES:DI`, that is not an object-5 cell**: obj3:0x3423
  `push es / push di / call far DOSSEMCLEAR` clears the caller's own start-up semaphore, once, before
  the loop. HARDERR.EXE names it: its obj2:0x4FA `mov ax,0xF / mov es,ax / mov di,0x161B` immediately
  precedes its `call far #715`, and `DS:0x161B` is the cell its main thread `DosSemSet`s (obj2+0x314)
  and then waits on with -1 (obj2+0x349). The clear is the daemon saying "I am parked".
- **#715 also sets `SMG_Flags` bit 1 unconditionally** (obj3:0x341E `or byte [0xb70],0x2`). With
  `HardError_Do_NotifyDD` a constant 0, both paths exist and `DOSSMSGINIT`'s is the live one.
- **Registration (#713) takes no lock.** It relies on the `SMG_Flags` bit-1 close and on driver INIT
  being serial `[INF]`; the table was created in the unlocked once-per-system init.
- **PM callback pointers** are written once by #707 (`DOSWINPROC`) and are read-only afterwards. The
  PM session callbacks are a DLL IBM loads by name (OS2SM, PMVIOP) and binds by ordinal (31..36, 42;
  1, 2) at #707 time, with `StartParmsMaxLen` degrading to 0x20 if that fails.
- No SMP-only lock in this group; `NotDD_RamSem` is the same plain RAM semaphore in UNI.

#### `HardError_Do_NotifyDD` has no writer `[OBS-RE]` (UNI build)

All four code objects swept for `[0xb02]` (obj1/3/4 as USE16, obj2 as USE32) give five accesses, all
in obj3 and all reads: `cmp` at 0x33B3 (#714), 0x9AB2 and 0x9AD6 (#716), 0x9D55 (`DOSSMSGINIT`), and
`mov ax,[0xb02]` at 0x9EDA (#711). No internal fixup among the module's 2988 records targets
obj5+0xB02 (186 internal fixups target object 5 at other offsets). HARDERR.EXE imports #711/#715/#716,
is given only the two #711 return addresses (`HdeSMGRamSem`, `PopUpBlockSem`), and **reads** the value
from #711's AX and branches on it (its obj2:0x30B, 0x33A). The image value is 0. A reference whose
address is computed into a register rather than encoded as a displacement or a fixup would be
invisible to these sweeps.

Consequence: on a shipped system the cell is a constant 0, so #714 always takes its **inline** arm,
#716 always takes the KBD$/MOUSE$ shortcut, `DOSSMSGINIT` always sets `SMG_Flags` bit 1 itself, and the
#715 thread parks forever without work. The handed-off path is real code that is dead on IBM's own
system `[INF]` from the above.

**#716 reads the cell twice.** The second read, UNI obj3:0x9AD6 `cmp word [0xb02],0 / jne 0x9B69`, sits
inside its first record loop (the back edge at obj3:0x9BEE `jne 0x9ACD` lands three instructions above
it). When the cell is non-zero it skips the `KeyFileName`/`MseFileName` match for every record and
sends each down the generic `DosOpen`/`DosQHandType` arm. The reason is handle scope: a non-zero cell
means HARDERR.EXE is the caller, and `QHKEYBDHANDLE`/`QHMOUSEHANDLE` hold HFILEs the shell's process
opened, which name nothing in HARDERR's `[INF]`.

#### `DosSMHDeInit` (#711) - its external contract `[OBS-RE]` (UNI obj3:0x9EC1, 47 bytes; HARDERR.EXE call sites)

- Returns a far pointer **into object 5**: `9807:0A54` (`HdeSMGRamSem`) when AX is 0 on entry, else
  `9807:0468` (`PopUpBlockSem`). HARDERR.EXE therefore operates object 5's semaphores directly by
  address, which requires object 5 at its selector.
- **AX on return:** only the AX == 0 arm reaches `mov ax,[0xb02]` (`HardError_Do_NotifyDD`,
  obj3:0x9EDA). On the other arm AX's last write is the `mov ax,0x9807` that set DS, so that arm
  returns the **object-5 selector** in AX.
- **`arg_bytes` is 0 and there is still an argument**: obj3:0x9EEF is a bare `retf`, so the **caller
  pops** - not OS/2's usual 16-bit convention. HARDERR does `add sp,4` after both calls (its
  obj2+0x300, obj2+0x361).
- HARDERR writes through the first pointer as well as operating the semaphore: its obj2:0x336
  `mov word es:[di+4],ax` with ES:DI = `&HdeSMGRamSem` zeroes `HdeRC`, and its obj2:0x350
  `DosSemClear(ES:DI)` is the release that ends `DOSSMSGINIT`'s ten-second wait on that cell. So the
  external contract covers `HdeRC` too.

**Not established (group 6):** the meanings of notification types 0x10, 0x20, 0x40, 0x80 and 0x100;
the meaning of `SMG_Flags` bit 3; the name of #99; on SMP, #716's closing `DosFreeSeg` and
`xor ax,ax / retf`, and #713's bitmap store `mov [es:di+2],bx` (seen on UNI only); what the callee of
`SecQueueName` does.

---

### Group 7 - screen-save / screen-lock subsystem and the three `*_str` templates (+0xC20..+0xDE8)

Kernel ordinals here: #7 `DosExitList`, #8 `DosGetInfoSeg`, #23 `DosCloseSem`, #24 `DosCreateSem`,
#25 `DosOpenSem`, #38 `DosReallocSeg`, #88 `DosSystemService`; #101 (name not established).

**The three `*_str` cells are not names; they are initial-value templates** for control blocks that
live in `memory_pool` (+0xDE9). Each is paired with a length cell and block-copied with `rep movsb`
`[OBS-RE]`:

| template | length cell (image) | copied by | into |
|---|---|---|---|
| `memtbl_str` +0xCC7 | `memtbl_str_len` +0xD5B = **0x94** | `SSMEMTABLESU` (`mov di,[memtableptr]; mov si,0xcc7; mov cx,[0xd5b]; rep movsb`) <- `DOSSSINIT`, `SSMEMMAP` | `[memtableptr]` - image **0x0DE9 = `memory_pool`** (+ growth) |
| `pidcb_str` +0xD5F | `pidcb_str_len` +0xD89 = **0x2A** | no copy site found | - |
| `sgcb_str` +0xD8B (same address as `sgnumber`) | `sgcb_str_len` +0xDE7 = **0x5C** | `SSCBSETUP` (first `mov [0xd8b],bx` stamps the SGID into the template, then copies it to `[sgpointeroff]`) <- `DOSSGSAVE`, `SSGETSGCB`; `SSCBDEALLOCATE` (copies the template back over a freed block) <- `DOSSGFREE` | `[sgpointeroff]` = a block inside `memory_pool` |

The `memtbl_str` image is a header (`00 00 00 00 04 00 00 00`) followed by repeated 9-byte
`01 FF FF 00 00 00 00 00 00` entries. Their layouts are decoded under group 8.

#### The subsystem `[OBS-RE]`

- **`DOSSSINIT`** (<- `DOSSMSGINIT`, i.e. #707 time): `DosGetInfoSeg(&globalsg, &localsg)`; sets
  `ssmgr_pid`; builds the memory table (`SSMEMTABLESU`); gets the base SGCB; pre-allocates SGIDs 0..3
  (`cmp bx,3` loop calling `SSGETSGCB`).
- **`DosScrLock` #695 / `DosScrUnLock` #691** (<- `viorout`): #695 holds the fast-safe semaphore
  `savelocksem` (+0xC95) while it updates the lock state (`savelockflag`, `screenlocksgid`); registers
  an exit list (#7, obj3 handler 0xD094); opens the per-screen-group named system semaphore
  `\SEM\LKNED###.SEM` through `SSOPENSYSEM` (#25) and waits on it **outside** `savelocksem` (#23 closes
  it).
- **`SSSEMSETUP`** (<- `DOSSGSAVE`, `SSGETSGCB`): patches the three digits of `lockneededname`
  (`semsuffix`, +0xC84) with the screen group, then `DosCreateSem(noexclusive, &<in SGCB>, name)` (#24),
  and clears four RAM semaphores in the SGCB.
- **`SSLOCKCHECK`** (<- `DOSSGSAVE`, the switch-away path): `DosSemSet(locktimersem)`, then
  `DosSemWait(locktimersem, locktime)` (default **30 000 ms**, settable by #700). On expiry,
  `DosSystemService(actionpacket -> responsepacket)` (#88) with `procid` = the lock holder, then
  `lockfrozen = 1`. `VIOSSWSWITCH` brackets it. This is the "screen lock not released within the
  timeout" path; `SSTHAWPIDS` (<- `DOSSGRESTORE`) undoes it.

| off / name | size / type | meaning | accessed by -> ordinal | image / init | concurrency (SMP) | prov |
|---|---|---|---|---|---|---|
| 0xC20 `allocation_cnt` | WORD | Number of times the screen-save memory pool has been grown. | `inc` in `SSMEMMAP` after `DosReallocSeg` (#38) on `segsize`. | 0 | Switch path (under `SwitchRamSem` via `DOSSGSAVE` <- `DOSSGSWITCHBACKGROUND` <- `DOSSMGSWITCH`) `[INF]` per call chain. | [OBS-RE] |
| 0xC22 `blank` | WORD | The blank cell (space, attribute 7) used to clear the screen. | Pushed to `VIOSCROLLDN` by code next to `SSOPENSYSEM`; `DOSSGSAVE`. | **image 0x0720** | read-only | [OBS-RE] |
| 0xC24 `blockid` | WORD | Running id stamped into each new memory-table entry. | `SSMEMTABLESU` (`mov ax,[0xc24]; inc`). | 0 | as `allocation_cnt` | [OBS-RE] |
| 0xC26 `globalsg` | WORD SEL | The screen-save code's Global InfoSeg selector. | `DOSSSINIT` (#8). | 0; #707 time | read-only after | [OBS-RE] |
| 0xC28 `localsg` | WORD SEL | Its Local InfoSeg selector (per-process content: `mov ds,[0xc28]`, then `[0]` pid, `[8]` screen group) - a per-process selector kept in a shared cell. | `DOSSSINIT` (#8); read by #695, #696, #697, #701, #704, #700, `DOSSGSAVE`/`RESTORE`/`FREE`, `DOSSGDDNOTIFY`. | 0 | read-only after | [OBS-RE] |
| 0xC2A `locktime` | WORD | Milliseconds a switch waits for a screen lock to be released before acting. | Written by `DosSetMNLockTime` #700; used as the `DosSemWait` timeout by `SSLOCKCHECK`; read by `DosGetTimes` #689. | **image 30000 (0x7530)** | #700 writes without a lock | [OBS-RE] |
| 0xC2C `locktimepid` | WORD PID (-1 = none) | PID that set `locktime`; #700 accepts or refuses based on it (exact rule not read). | #700. | 0 | no lock | [OBS-RE] |
| 0xC2E `memmapptr` | WORD | **No access found.** | - | 0 | - | [unverified] |
| 0xC30 `noexclusive` | WORD | Non-exclusive flag passed to `DosCreateSem` for the per-group LKNED semaphores. | `SSSEMSETUP`. | **image 1** | read-only | [OBS-RE] |
| 0xC32 `lockfrozen` | WORD | 1 = the lock holder was acted on after the timeout; cleared by the thaw. | `SSLOCKCHECK` (set), `SSTHAWPIDS` (read/clear). | 0 | switch path | [OBS-RE] |
| 0xC34 `locktimerowner` | WORD | **No access found.** | - | 0 | - | [unverified] |
| 0xC36 `pidpointeroff` | WORD offset | Offset in `memory_pool` of the PID control-block area; set by `SSMEMTABLESU` to the same value as `sgpointeroff` (the first data block). | `SSMEMTABLESU`. | 0 | as `allocation_cnt` | [OBS-RE] |
| 0xC38 `priority` | WORD | Saved priority for the undo paths; its address is passed out. | `DOSMODEUNDO` #701, `DOSSAVREDRAWUNDO` #697 (address). | 0 | - | [OBS-RE]; meaning from name [INF] |
| 0xC3A `saveundoflag` | WORD | **No access found.** | - | 0 | - | [unverified] |
| 0xC3C `screenlocksgid` | WORD SGID | Screen group currently holding the screen lock. | #695 writes; read by `DOSCLEANUP`, `DOSSGSAVE`, `DOSSGDDNOTIFY`. | 0 | written while holding `savelocksem` | [OBS-RE] |
| 0xC3E `scrngroup` | 4 bytes | **No object-5 access** (the one hit is `FreeFocus` on another segment). | - | 0 | - | [unverified] |
| 0xC42 `sgpointeroff` | WORD offset | Offset in `memory_pool` of the current screen group's control block; target of `SSCBSETUP`'s copy and of `SSSEMSETUP`'s writes. | `SSMEMTABLESU`, `SSMEMMAP` (set), `SSCBSETUP`, `SSSEMSETUP`. | 0 | switch path | [OBS-RE] |
| 0xC44 `shsegsize` | WORD | **No access found.** | - | 0 | - | [unverified] |
| 0xC46 `ssmgr_pid` | WORD PID | PID of the process that initialised screen-save (the session manager). | `DOSSSINIT` (set/compare); read by `DOSSGSAVE`/`RESTORE`/`FREE`, `DOSSGDDNOTIFY`. | 0 | init | [OBS-RE] |
| 0xC48 `timedouterror` | WORD | Error recorded when the lock wait timed out. | `DOSSGSAVE`. | 0 | switch path | [OBS-RE] |
| 0xC4A `modeaction` | WORD | Pending mode-restore action flag. | `DOSMODEWAIT` #704, `DOSSGRESTORE`, code next to `SSOPENSYSEM`. | 0 | - | [OBS-RE]; values [unverified] |
| 0xC4C `scrnaction` | WORD | Pending redraw action flag (set 1 in code next to `SSOPENSYSEM`). | `DOSSAVREDRAWWAIT` #696, `DOSSGSAVE`. | 0 | - | [OBS-RE]; values [unverified] |
| 0xC4E `kbd_name` | char[9] `"KBD     "` | Space-padded keyboard device name. **No user found.** | - | image string | read-only | [OBS-RE] bytes |
| 0xC57..0xC61 `kbd_filehandle`, `kbd_actiontaken`, `kbd_filesize`, `kbd_fileattr`, `kbd_openflag`, `kbd_openmode` | 6 x WORD/DWORD | A pre-built `DosOpen` argument set for that name. **No access found.** | - | image (`kbd_openflag` +0xC5F = 1, `kbd_openmode` +0xC61 = 0x42) | - | [unverified] |
| 0xC63 `struc_length` | WORD | **No access found.** | - | image 3 | - | [unverified] |
| 0xC65 `shared_name` | ASCIIZ `"\SHAREMEM\SCRSWT.DAT"` | Name of a shared segment. **No access found.** | - | image string | - | [OBS-RE] bytes |
| 0xC7A `lockneededname` | ASCIIZ `"\SEM\LKNED000.SEM"` | Name template for the per-screen-group "lock needed" system semaphore. | `SSSEMSETUP` (#24, after patching), `DOSSCRLOCK` -> `SSOPENSYSEM` (#25). | image string; digits patched at run time | **The shared name buffer is patched in place**, with no lock of its own. | [OBS-RE] |
| 0xC84 `semsuffix` | 3 bytes (inside that string) | The `"000"` digits, overwritten with the screen-group number. | `SSSEMSETUP` (`mov bx,[0xc84]`, `mov dl,[0xc86]`). | image `"000"` | same | [OBS-RE] |
| 0xC8C `saveundosem` | RAM sem DWORD | Event for save / redraw / mode "undo". | Address pushed by `DOSCLEANUP`, #701, #697, `DOSSGSAVE`. | 0 | event | [OBS-RE] |
| 0xC90 `locktimersem` | RAM sem (5-byte gap) | The semaphore `SSLOCKCHECK` sets and waits on with `locktime`; cleared by `DosScrUnLock` #691. | `SSLOCKCHECK`, #691. | 0 | event with timeout | [OBS-RE] |
| 0xC95 `savelocksem` (+0xC97 `savelockowner`, +0xC9D `savelockflag` inside it) | `DOSFSRSEM` 14 bytes | **Mutex for the screen-lock state.** The `.SYM` names two fields inside it: owner (+2) and client (+8; set 0x0A while #695 works, 0 on exit). | #695, #691, #696, #697, #701, #704, `DOSCLEANUP`, `DOSSGSAVE`/`RESTORE`/`FREE`, `DOSSGDDNOTIFY` (address / fields). | **image cb = 0x0E** | fast-safe -> SMP `DC1hSpinLock` inside (UNI `cli`/`sti`) | [OBS-RE]; layout [DOC-IBM] `DOSFSRSEM` |
| 0xCA3 `actionpacket` (+0xCA5 `subfunction`, +0xCA7 `procid`) | 6 bytes | `DosSystemService` request in `SSLOCKCHECK`: `subfunction` = 0, `procid` = the lock-holder PID. What service 1 / subfunction 0 does to the holder is not established. | `SSLOCKCHECK`, `SSTHAWPIDS`. | image +0 = 1 | switch path | [OBS-RE]; the service's effect [unverified] |
| 0xCA9 `responsepacket` | 20 bytes | Its response buffer. | `SSLOCKCHECK`, `SSTHAWPIDS`. | 0 | same | [OBS-RE] |
| 0xCBD `memmapsize` | WORD | Size of one memory-table unit; `SSMEMTABLESU` adds it to get the PID/SGCB area offset. | `SSMEMTABLESU`. | **image 0x94** | read-only | [OBS-RE] |
| 0xCBF `scrngrpsize` | WORD | **No access found.** | - | 0 | - | [unverified] |
| 0xCC1 `ddnotify` = `kbd_parm_table` (two `.SYM` names, one cell) | 4 bytes | **No object-5 access** (hits at 0xD0C/0xD14 are `_MOUBASESUBSYS` on another segment). | - | 0 | - | [unverified] |
| 0xCC5 `ddnotifysize` | WORD | Its length. **No access found.** | - | image 4 | - | [unverified] |
| 0xCC7 `memtbl_str` | BYTE[0x94], template | Initial image of the screen-save **memory table** (header + 9-byte entries), copied into `memory_pool`; layout under group 8. | `SSMEMTABLESU`. | image | read-only (the copy target is what changes) | [OBS-RE] |
| 0xD5B `memtbl_str_len` | WORD | Its length. | `SSMEMTABLESU`. | **image 0x94** | read-only | [OBS-RE] |
| 0xD5D `memtableptr` | WORD offset | Where the next memory table goes: starts at `memory_pool`; `SSMEMMAP` advances it by the grown size. | `SSMEMTABLESU`, `SSMEMMAP`. | **image 0x0DE9** | switch path | [OBS-RE] |
| 0xD5F `pidcb_str` | BYTE[0x2A], template | Initial image of a **per-PID control block**. No copy site found; layout not established (group 8). | - | image | - | [OBS-RE] bytes; user [unverified] |
| 0xD89 `pidcb_str_len` | WORD | Its length. No access found. | - | **image 0x2A** | - | [OBS-RE] bytes |
| 0xD8B `sgcb_str` / `sgnumber` | BYTE[0x5C], template; +0 WORD = SGID stamp | Initial image of a **screen-group save/lock control block**. `SSCBSETUP` writes the SGID into the template's first word, then copies it to `[sgpointeroff]`; `SSCBDEALLOCATE` copies it back over a freed block. Layout under group 8. | `SSCBSETUP` (<- `DOSSGSAVE`, `SSGETSGCB`), `SSCBDEALLOCATE` (<- `DOSSGFREE`). | image | **The shared template is modified before each copy**, with no lock of its own. | [OBS-RE] |
| 0xDE7 `sgcb_str_len` | WORD | Its length. | `SSCBSETUP`, `SSCBDEALLOCATE`. | **image 0x5C** | read-only | [OBS-RE] |

**Locking, group 7.**
- **`savelocksem`** (`DOSFSRSEM`, SMP spinlock inside) is the screen-lock state mutex, taken by
  #695/#691 and the save/restore/redraw/mode wait-undo ordinals (#696/#697/#701/#704) `[OBS-RE]`.
- **Per-screen-group named system semaphores `\SEM\LKNED###.SEM`** (created in `SSSEMSETUP`, opened in
  #695) carry "lock needed" between processes. #695 waits on one **after releasing** `savelocksem`
  `[OBS-RE]`.
- **`locktimersem` + `locktime`** implement the bounded wait on the switch path. The switch path
  itself runs under group 1's `SwitchRamSem` (through `DOSSMGSWITCH` -> `DOSSGSWITCHBACKGROUND` ->
  `DOSSGSAVE`) `[INF]` (call chain, not path-traced).
- **Memory-table and SGCB building** (`SSMEMTABLESU`, `SSMEMMAP`, `SSCBSETUP`, `SSSEMSETUP`) takes no
  lock of its own; it is reached only from `DOSSGSAVE`/`SSGETSGCB`/`DOSSSINIT`. The two in-place
  patches of shared templates (`lockneededname`'s digits, `sgcb_str`+0) are safe only if the callers
  serialise them (the switch path's `SwitchRamSem`) `[INF]`, not path-traced.
- SMP vs UNI: only the fast-safe primitive differs.

**Not established (group 7):** any user of `memmapptr`, `locktimerowner`, `saveundoflag`,
`scrngroup`, `shsegsize`, `scrngrpsize`, `ddnotify`/`kbd_parm_table`, `ddnotifysize`, the `kbd_*`
`DosOpen` argument block, `struc_length`, `shared_name`, `pidcb_str` (16-bit code scanned; the 32-bit
object was not scanned for these); what `DosSystemService` action 1 / subfunction 0 does to the lock
holder; the name of #101.

---

### Group 8 - `memory_pool` and the three template layouts (+0xDE9..+0x1160)

Read in full: `SSMEMMAP`, `SSMEMTABLESU`, `SSFINDSG`, `SSGETSGCB`, `SSCBSETUP`, `SSCBDEALLOCATE`,
`SSSEMSETUP`; field accesses in `DOSSGSAVE`, `DOSSGRESTORE`, `DOSSGDDNOTIFY`, #695, #691,
`SSLOCKCHECK`, #704, #701, #696, #697, `DOSCLEANUP`. Image: `memory_pool` = 0x374 bytes of `0x4D`
(`'M'`), `mempoolsize` = 0x0374, `segsize` = 0x1161 `[OBS-RE]`.

#### A chained array of fixed-size blocks, allocated in pairs, that grows object 5 itself `[OBS-RE]`

- **One pool unit = 0x374 bytes = `mempoolsize`**: a 0x94-byte **memory table** (from `memtbl_str`)
  followed by **16 data blocks of 0x2E bytes** (0x94 + 16 x 0x2E = 0x374). `SSMEMTABLESU` builds a unit
  at `memtableptr`: copies the table template; stamps each of the 16 entries' +0 with a fresh
  `blockid`; sets `sgpointeroff` and `pidpointeroff` to the first data block; writes each entry's +7 =
  offset of its own 0x2E block.
- **Allocation (`SSMEMMAP`, only caller `SSGETSGCB`)** scans tables from +0xDE9 in steps of **0x12 =
  two entries**, looking for a free pair, following the terminator's `next` link. It marks both entries
  used with key (SGID, 0xFFFF) and returns the first entry's block in `sgpointeroff`. **One screen group
  owns 2 x 0x2E = 0x5C bytes = `sgcb_str_len`.**
- **Growth** when no pair is free: `segsize += mempoolsize`; **`DosReallocSeg(segsize, DS)` (#38) -
  object 5 itself is enlarged by 0x374**; `allocation_cnt++`; `memtableptr += 0x374`; `SSMEMTABLESU`
  builds the new unit there and the old terminator's link points at it. So the 17th concurrent
  screen-group pair grows the segment.
- **Lookup (`SSFINDSG`)** scans the same way for key (SGID, 0xFFFF) and returns the block or 419
  (0x1A3).
- **Release (`SSCBDEALLOCATE`, <- `DOSSGFREE`)** does **not** free the SG pair; the pair stays bound to
  its SGID. It re-copies the first 0x2F bytes of `sgcb_str` over the block, restoring the SGID and the
  LKNED digits (+0x28..+0x2A) and keeping the semaphores from +0x2F on. It then walks up to 0x20 entries
  and marks **free** (flag 1, keys 0xFFFF/0) every entry for that SGID whose second key != 0xFFFF.
  **Nothing allocates such entries** (`SSMEMMAP` always writes 0xFFFF), consistent with `pidcb_str`
  having no user: the PID-keyed half has a release but no allocation in this binary.
- `DOSSSINIT` pre-allocates SGIDs 0..3 at #707 time.

#### Template 1 - `memtbl_str` (+0xCC7, 0x94 bytes) = memory-table layout `[OBS-RE]`

| off | width | meaning | written by | read by |
|---|---|---|---|---|
| +0x00 + 9n (n = 0..15) | WORD | `blockid` of entry n; **0xFFFF marks the terminator** | `SSMEMTABLESU` | `SSMEMMAP`, `SSFINDSG`, `SSCBDEALLOCATE` |
| +0x02 + 9n | BYTE | free flag: **1 = free**, 0 = in use (template 1) | `SSMEMMAP` (0), `SSCBDEALLOCATE` (1) | `SSMEMMAP` |
| +0x03 + 9n | WORD | key 1 = owning SGID (template 0xFFFF) | `SSMEMMAP`, `SSCBDEALLOCATE` | `SSFINDSG`, `SSCBDEALLOCATE` |
| +0x05 + 9n | WORD | key 2 = 0xFFFF for a screen-group block; otherwise a second key never allocated in this binary (template 0) | same | same |
| +0x07 + 9n | WORD | offset (in object 5) of this entry's 0x2E data block | `SSMEMTABLESU` | `SSMEMMAP`, `SSFINDSG` |
| +0x90 | WORD | terminator marker 0xFFFF | template | walkers |
| +0x92 | WORD | offset of the next table (0xFFFF = none) | `SSMEMMAP` on growth | walkers |

#### Template 2 - `sgcb_str` (+0xD8B, 0x5C bytes) = per-screen-group save/lock control block

Accesses `[OBS-RE]`; meanings from the reading routine's API `[INF]` where so stated.

| off | width | meaning | written by | read by |
|---|---|---|---|---|
| +0x00 | WORD | SGID (template stamp) | `SSCBSETUP`, `SSCBDEALLOCATE` | - |
| +0x02 | WORD | template 0xFFFF; tested -1 by `SSCBDEALLOCATE` to skip its secondary-entry walk; meaning [unverified] | template | `SSCBDEALLOCATE` |
| +0x04 | WORD | **screen-lock owner** (the value `SSLOCKCHECK` passes as `procid` to `DosSystemService`) | #695 (set), #691 (zero) | #695, #691, `SSLOCKCHECK`, `DOSSGSAVE`, `DOSCLEANUP` |
| +0x06 | WORD | the owner that was acted on at lock timeout ("frozen") | `SSLOCKCHECK` (= +0x04) | `SSTHAWPIDS`, `DOSSGSAVE`, `DOSSGRESTORE` |
| +0x08 | WORD flags | **bit 15 = group is switched away** (set by `DOSSGSAVE`/`DOSSGDDNOTIFY`, cleared by `DOSSGRESTORE`); #695 grants the lock only while < 0x8000 | those | #695 |
| +0x0A | WORD | redraw-wait registrant thread (LIS+6) | #696 | #696, #697, `DOSCLEANUP` |
| +0x0C | WORD | redraw notify type (template 0xFFFF = none; 0/1 tested) | #696 | `DOSSGSAVE`, `DOSSGRESTORE`, #697 |
| +0x0E | DWORD far ptr | caller's output address for the redraw notification | #696 | #696 (`les si,[di+0xe]`) |
| +0x12 | WORD | redraw-wait registrant (second id, compared with BX) | #696 | #697, `DOSSGSAVE`, `DOSSGRESTORE`, `DOSCLEANUP` |
| +0x14 | WORD | template 0xFFFF; **no access found** | - | - |
| +0x16 | WORD flags | redraw state: bit 0 pending, 0x400/0x200 notify phases, 0x1000 | #696, #697, `DOSSGSAVE` | same, `DOSCLEANUP` |
| +0x18 | WORD | mode-wait registrant thread (LIS+6) | #704 | #704, #701, `DOSCLEANUP` |
| +0x1A | WORD | mode notify type (template 0xFFFF) | #704 | `DOSSGSAVE`, `DOSSGRESTORE`, #701 |
| +0x1C | DWORD far ptr | caller's output address for the mode notification | #704 | #704 |
| +0x20 | WORD | mode-wait registrant (second id) | #704 | #701, `DOSSGSAVE`, `DOSSGRESTORE`, `DOSCLEANUP` |
| +0x24 | WORD flags | mode state (0x600 phases, 0x1000) | #704, #701 | same, `DOSCLEANUP` |
| +0x26 | WORD | screen-lock recursion/holder flag (set with the owner, zeroed by #691) | #695, #691 | `DOSSGSAVE`, `DOSCLEANUP` |
| +0x28 | WORD + BYTE at +0x2A | the three ASCII digits of this group's `\SEM\LKNED###.SEM` | `SSSEMSETUP` | `SSCBDEALLOCATE` (preserved) |
| +0x2B | BYTE | redraw handshake state (1/0/0xFF; template 0xFF) | #696 | #696, #697, `DOSCLEANUP` |
| +0x2C | BYTE | mode handshake state (1/0/0xFF; template 0xFF) | #704 | #704, #701, `DOSCLEANUP` |
| +0x2F | DWORD HSYSSEM | handle of `\SEM\LKNED###.SEM` (`DosCreateSem` #24 out; `DosSemClear` on restore) | `SSSEMSETUP` | `DOSSGRESTORE`; `SSGETSGCB` tests it for 0 to create lazily |
| +0x33 / +0x37 | 2 x RAM sem | mode-wait / mode-undo events (cleared at setup) | `SSSEMSETUP` | #704, #701 |
| +0x3B / +0x3F | 2 x RAM sem | redraw-wait / redraw-undo events | `SSSEMSETUP` | #696, #697, `DOSSGSAVE` |
| +0x43..+0x5B | 25 bytes | **no access found** | - | - |

Where +0x0A/+0x12 and +0x18/+0x20 say "thread" and "second id", the stored values were read (LIS+6
into the first, BX into the second); what BX holds at those sites is not traced `[unverified]`.

#### Template 3 - `pidcb_str` (+0xD5F, 0x2A bytes)

Image: 0x26 zero bytes, then DWORD 0xFFFFFFFF at +0x26 `[OBS-RE]`. No routine copies it, and no
allocator creates the secondary (key 2 != 0xFFFF) entries it would belong to; only the release half
(`SSCBDEALLOCATE`'s walk) exists. Layout **not established** `[unverified]`.

| off / name | size / type | meaning | accessed by -> ordinal | image / init | concurrency (SMP) | prov |
|---|---|---|---|---|---|---|
| 0xDE9 `memory_pool` | BYTE[0x374] (+ growth) | First pool unit: memory table + 16 x 0x2E blocks (layouts above). | Built by `SSMEMTABLESU` (<- `DOSSSINIT`, `SSMEMMAP`); used by every screen-save/lock ordinal (#691, #695-#697, #701, #704) and the switch path. | image `0x4D` fill, overwritten at #707 time before any read | Allocation/growth and SGCB field updates run under `savelocksem` (those ordinals take it) `[INF]`; the SMP spinlock sits inside that fast-safe semaphore. | [OBS-RE] |
| 0x115D `mempoolsize` | WORD | Size of one pool unit; the growth step. | `SSMEMMAP`. | **image 0x0374** | read-only | [OBS-RE] |
| 0x115F `segsize` | WORD | Current total size of object 5 as the pool code believes it; grown and passed to `DosReallocSeg` on object 5. | `SSMEMMAP`. | **image 0x1161** | as `memory_pool` | [OBS-RE] |

**Not established (group 8):** `pidcb_str`'s layout and allocator; SGCB +0x02, +0x14, +0x43..+0x5B; the
BX values stored at SGCB +0x12/+0x20.

---

### Object 5 - summary

#### Groups, owners, locks

| group | span | owning ordinals | locking model |
|---|---|---|---|
| 2 init / InfoSeg / DBCS / spinlock | +0x000..+0x084 | LIBINIT `InitDOSCALL1` (every process); #8 #44 #152 #394; #449-#451 (SMP) | once-per-system block latched by +0x14, **no lock**; `DC1hSpinLock` created once (SMP only) |
| 3 queues | +0x085..+0x21F | #674-#681 (+ 32-bit queue entries), exit lists | system semaphore `\SEM\IPCQUEUE.SEM` + `DosHoldSignal`; owner pid at +0x1E3; owner-died recovery journal |
| 4 message selectors, slot table, message DBCS, error table | +0x220..+0x33F | #383-#385, #389, #391-#394, queues via slots | slots and table read-only; +0x250/+0x25A under a **per-process** object-6 fast-safe semaphore |
| 1 session-manager core | +0x340..+0xA13 | #684-#688, #690, #692-#694, #699, #702-#709, #878 | `PopUpBlockSem`, `SMRoutSem` (fast-safe), `SwitchRamSem`, `SGCB_QueueRamSem` (-> obj7); `ServiceAppThd` unlocked |
| 5 SM daemons, popups, VDM, handles | +0xA14..+0xB15 | #707, #686, #698, #710-#712, #716, #856/#857, #691/#695-#697/#701/#704 via `SMG_INSTANCE` | request/reply **event** semaphores (`Pop*`/`Hde*`/`STitle*`); daemons take group-1 locks inside; popup request fields written unlocked |
| 6 DD notification, `SMG_Flags`, PM callbacks | +0xB16..+0xC1F | #707, #711, #713-#716, #855, #702 | `NotDD_RamSem` mutex; `DoNotify`/`DidNotify` events; #713 unlocked (serial INIT assumed) |
| 7 screen save / lock | +0xC20..+0xDE8 | #689, #691, #695-#697, #700, #701, #704 + switch path | `savelocksem` (fast-safe); per-SG `\SEM\LKNED###.SEM`; `locktimersem` + `locktime` |
| 8 memory pool | +0xDE9..+0x1160 | as group 7 | under group 7's `savelocksem` `[INF]` |

#### Lock order observed across groups

- **`PopUpBlockSem` -> `SMRoutSem` -> `SwitchRamSem` -> `NotDD_RamSem`** - each link read at a call site
  (groups 1, 5, 6) `[OBS-RE]`.
- **Session-manager locks -> `\SEM\IPCQUEUE.SEM`** - `[INF]`, per call site, not path-traced.
- **Switch path (`SwitchRamSem`) -> `savelocksem` / LKNED semaphores** - `[INF]`, from call chains.
- **`DC1hSpinLock` is innermost and never held across a call**; it lives only inside #161/#162, so it
  cannot cycle `[OBS-RE]`.
- `SGCB_QueueRamSem`'s position relative to the others is **not established**.
- **SMP vs UNI:** the only difference in the whole object is the fast-safe primitive (`cli`/`sti` ->
  `DC1hSpinLock`), plus the SMP-only spinlock creation and `_globptr` store in init. The variables each
  routine touches, and the semaphores each takes, match UNI `[OBS-RE]`.

#### Per-process values kept in shared cells `[OBS-RE]`, correctness `[INF]`

`LocalSelector` (+0x462), `localIS` (+0x02), `msgLocalSeg` (+0x222) and `localsg` (+0xC28) each hold a
per-process Local InfoSeg selector in a shared cell; this is correct only because the LIS selector
number is the same in every process.

#### Cells with a non-zero value in the shipped image - every one is read as data `[OBS-RE]`

A zero-filled object 5 is not IBM's start state; each of these is read with its image value:

- **Strings:** +0x16 `NOJIT`, +0x1C `DOSCALL2`, +0x27 `NPXEMLTR`, +0x34 `NPXNPHandler`,
  +0x41 `NPXFPDataSize`, +0x60 `COUNTRY.SYS`, +0x70 `\SHAREMEM\DOS\CDIB`; +0x190 `\QUEUES\`,
  +0x1CA `\SEM\IPCQUEUE.SEM`; +0x340 `\QUEUES\SESMGR\APPREQQ`; +0xA1C `DOS Session`,
  +0xA48 `HARDERR.EXE`, +0xA60 `OS2_SHELL` / +0xA69 = 9, +0xA6A `KBD$` / +0xA6F = 5, +0xA70 `MOUSE$` /
  +0xA77 = 7, +0xA78 `VVIDEO1$`, +0xAA2 `\SHAREMEM\SMG\SGTITLE`; +0xBAA `OS2SM`, +0xBB3 `PMVIOP`,
  +0xBF4 `\QUEUES\SESMGR\SECURITY`, +0xC0C `NOJIT`; +0xC4E `KBD     `, +0xC65 `\SHAREMEM\SCRSWT.DAT`,
  +0xC7A `\SEM\LKNED000.SEM`.
- **Scalars:** +0x1DC = 1; +0x468 cb = 0x0E, +0x48E cb = 0x0E, +0x4E6 = 0x04E2, +0x508 = 0x0506;
  +0xA58 = 481, +0xA8A = 2, +0xABC/+0xAC2 = {1,0,2}, +0xAC8 = 1, +0xACC = 1, +0xAD0 = 2, +0xADE = 1;
  +0xBA2 = 0xFFFFFFFF (#855), +0xBA6 = 0x3C; +0xC22 = 0x0720, +0xC2A = 30000, +0xC30 = 1, +0xC5F = 1,
  +0xC61 = 0x42, +0xC63 = 3, +0xC95 cb = 0x0E, +0xCA3 = 1, +0xCBD = 0x94, +0xCC5 = 4, +0xD5B = 0x94,
  +0xD5D = 0x0DE9, +0xD89 = 0x2A, +0xDE7 = 0x5C; +0x115D = 0x374, +0x115F = 0x1161.
- **Selectors and far pointers carried by fixups:** +0x4EA..+0x4FD -> obj7; +0x200/+0x202 -> obj9,
  +0x204 -> obj10, +0x206 -> obj6:0x126A; slots +0x240, +0x242, +0x260..+0x2FF = 0x9807, +0x244 =
  0x980F; +0xAD2/+0xAD8 -> `PopVioRamSem`/`STitleRamSem`, +0xAE0 -> `HdeVioRamSem`, +0xB12 -> obj8.
- **Tables:** +0x300 error-code table (27 WORDs); +0xAE6 `NewThreads` (obj3 entry offsets, stack
  sizes); +0xBDA..+0xBE6 OS2SM ordinals 31-36/42, +0xBF0 PMVIOP ordinals 1/2; +0xCC7 `memtbl_str`,
  +0xD5F `pidcb_str`, +0xD8B `sgcb_str`.

#### Not established - object 5

- Group 1: `DetSession`; `QueueFlags`; what lands in `NewSession`; `CurrentDebugger`/`IncomingDebugger`
  value domain; `PM_Data_Ptr`'s later callee; `DefPgmName` readers; the lock around
  `DOSSMCHILDEXIT`'s calls; SMP `DOSSEMREQUEST`'s `test [sem+1],3`.
- Group 2: users of `NPXNPHandler`/`NPXFPDataSize`; the ordinal reaching `_getctry`; whether the loader
  serialises LIBINIT.
- Group 3: `_statseg`+1..+4; the bytes after `_e_offset`; an `_initq` reader; the `_action` 1..13 codes.
- Group 4: `msgLocalSeg` readers; `PREPUTMSG`'s request pointer; why the build uses per-routine slots.
- Group 5: `SwitchActionPacket` and `Swt/XitMseParm*` (no use on any instrument); DOSCALLS #55/#105;
  `DOSSMCHILDWAIT`'s loop; the lock `VIOPOPUP`/`VIOENDPOPUP` hold.
- Group 6: notification types 0x10-0x100; `SMG_Flags` bit 3; #99's name; #716's closing `DosFreeSeg`
  and #713's bitmap store on SMP.
- Group 7: users of `memmapptr`, `locktimerowner`, `saveundoflag`, `scrngroup`, `shsegsize`,
  `scrngrpsize`, `ddnotify`, `ddnotifysize`, the `kbd_*` block, `struc_length`, `shared_name`;
  `DosSystemService` action 1; #101.
- Group 8: `pidcb_str` layout and allocator; SGCB +0x02, +0x14, +0x43..+0x5B; the BX values stored at
  +0x12/+0x20.
- Lock order: `SGCB_QueueRamSem`'s position.

---

## Object 6 - `DGROUP`, the per-process data segment (selector 0x980F)

**Header** `[OBS-RE]` (LX object table, both builds): `.SYM` segment 6 is named **`DGROUP`** (obj4 is
`CODE02`, obj7 `OS2CHAR_GROUP`). SMP flat base `0x13010000`, size **0x1DC0** (UNI **0x1D90**),
`flags=0x1003` - the SHARED bit (0x20) is clear, so object 6 is **INSTANCE: one copy per process**, at
the same selector `0x980F` in every process. Objects 5, 7, 9 and 10 are `0x1023` (SHARED); objects 6, 8
and 11 are `0x1003` (INSTANCE). A base address in the shared arena is not an attribute: object 6 sits
there and is still per process.

**Symbols** `[OBS-RE]`: 47 rows / 45 distinct offsets in the SMP `.SYM` segment 6, the first at
**+0x116E** - so 0x116E of the 0x1DC0 bytes (58%) lie below the first named symbol. UNI segment 6 is
identical symbol for symbol through `_JITActionPacketPtr2` (+0x1904); from `_JITDaemonTid` on, SMP is
UNI + 0x30 (UNI +0x1D7C -> SMP +0x1DAC; `_ENDDATA16` UNI +0x1D90 -> SMP +0x1DC0). The +0x30 enlargement
lies in +0x1904..+0x1D7C and contains three written cells (+0x1D28, +0x1D50, +0x1D60), two of which
differ in meaning between the builds: in SMP the fixup at +0x1D50 targets object 5 and the one at
+0x1D60 object 11; in UNI the fixup at +0x1D50 targets object 11 and there is no fixup at +0x1D60.

**`.SYM` spans mislead in this object in six ways** `[OBS-RE]`: a span overruns into unrelated cells
(`"LOG$"` and a `0x20` inside `pThunkStacks`' span; `"\SEM32\VDMSTART\DONE"` and the two cached
selectors inside `_JITActionPacketPtr2`'s; +0x1280 inside `_QUEINST_DATA`'s; an 80-byte put-message
buffer inside `SAVED`'s; `_JITActionPacketPtr2`'s 0x4A8-byte span against a ~0x1C real extent, which
swallows `VDMSTARTSESSION`'s working set); the whole-object 16-bit listings lack 93 labels the `.SYM`
has; one address carries two names with unrelated meanings (`EndNetErrs`/`pTLMA0`); and the internal
labels of one assembly routine (`DOSTRUEGETMESSAGE`) are presented as peers. A symbol names a start,
never an extent.

**Fixups into object 6's own data** `[OBS-RE]` - only nine, each load-bearing: four `stype=2` selector
words at +0x115E/+0x1162/+0x1166/+0x116A -> **obj4** (the selector halves of four 16:16 far pointers at
+0x115C/+0x1160/+0x1164/+0x1168); one at +0x1222 -> **obj6 itself** (`_iNLS_Sem`, a far pointer to
`_iCache_sem`); one at +0x1D50 -> **obj5**; one at +0x1D60 -> **obj11**; and two **`stype=7`** (32-bit
flat offset) at +0x1152/+0x1156 -> **obj6+0x1052**.

**Image bytes (SMP)** `[OBS-RE]`: +0x0000..+0x1150 is zero except +0x101C/+0x101E (two WORDs, both
0x1020) and `"PATH"` at +0x103C. From +0x1150 up, non-zero: the four far pointers +0x115C..+0x116B
(`e026` placeholders); `2e 00` at +0x116C; the 25-word error list +0x116E..+0x119F; `"PATH"` +0x11B8;
the name strings +0x11D0..+0x1213; `_iNLS_Sem` = `24 12 0f 98`; `_FSRam_Sem`'s leading WORD 0x000E;
`_iSize` +0x1236 = 0x1DC0 (the object's own size); `ff "MKMSGF"` +0x1282; `"\SYSOSO001.MSG"` +0x14C2;
`"DPATH"` +0x14D8; `GetFSRamSem`'s leading 0x000E; +0x14EC = 0x14F0; `PutFSRamSem`'s leading 0x000E;
`"LOG$"` at +0x16B0 and +0x11F8; `0x20` at +0x16B8 and +0x191A; `"\SEM32\VDMSTART\DONE"` +0x1D28;
`0x9807` at +0x1D50; `0x9837` at +0x1D60.

### Mechanisms that set the whole object's shape `[OBS-RE]`

1. **`ENTER_DLL` is the DGROUP setter.** `ENTER_DLL` (obj4+0xCCC0) is three instructions:
   `mov dx,0x980f / mov ds,dx / jmp ax`. **Every 16-bit DOSCALL1 entry point runs with DS = object 6**
   and every routine it calls inherits that DS. `DOSWRITE` does the same inline
   (`mov ax,0x980f / mov ds,ax`). 59 routines also load the selector by literal (77 sites: obj3 x64,
   obj4 x13, obj2 x2). The reader set of object 6 is therefore the whole 16-bit half of DOSCALL1.
2. **Object 6 grows at run time; `REALLOCSEG` is the allocator.** Whole body at
   `1C0380E5..1C038151`: `DosFSRamSemRequest(980F:0x1228 /* _FSRam_Sem */, -1)` -> `es:si = 980F:0x1236`
   (`_iSize`) -> `dx = [_iSize] + [bp+0xa]` -> kernel `DosReallocSeg(dx, 0x980F)` -> **write the OLD
   `_iSize` through the caller's far pointer** (the offset of the block just allocated) -> store the new
   size -> `DosFSRamSemClear(980F:0x1228)`. A bump allocator on the segment itself, under a per-process
   fast-safe semaphore. The image's `_iSize` = 0x1DC0 makes the first allocation land at the end of the
   static data. `REALLOCSEG` has exactly two callers: `_cache_table` (group D3) and
   `check_room_to_save` (obj3+0x8D05, group D6). Returning the old size through a caller-supplied far
   pointer is what lets D6 allocate and link a cache entry in one call.
3. **+0x0000..+0x0FFF is `Init32Entry`'s private 16-bit init stack.** `Init32Entry` (obj2, `1C0209D8`)
   builds `ecx = 0x980F1000` (`mov ecx,0x1000 / ror ecx,16 / mov cx,0x980f / ror ecx,16`),
   `push ecx`, `lss sp,[esp]` (SS:SP = 0x980F:0x1000), pushes the saved flat SS/ESP on it,
   `jmp far 0xe026:0x1c` into the 16-bit half, and on return `lss esp,[esp]`. The 32-bit object has
   **41 `lss sp,[esp]` sites and exactly one builds `0x980f`**; the other 40 build a tiled alias of the
   caller's own ESP (`mov eax,esp / ror eax,16 / shl ax,3 / or al,dl / rol eax,16`), so every ordinary
   32->16 thunk (`DOS32QUERYCP`, `DOS32PSETPATHINFO`, `DOS32PQUERYPATHINFO`,
   `_xcptRemoveRegistrationHead`, ...) runs on the calling thread's stack and never touches object 6.
4. **`DosRead` on a console handle keeps its line buffer here** (group D1).
5. **`DosReadAsync`'s WORD ring** at +0x1020..+0x1031 with pointers at +0x101C/+0x101E, and a second
   SS switch to +0x1033 (group D0).

**The 32-bit half reads this INSTANCE 16-bit object.** Besides 16:32 segment access
(`dospath2$ChkValidErrs32` pushes `0x980f` as a segment), 32-bit code in obj2 addresses object 6 by
**flat address `0x1301xxxx`** - 87 (offset, routine) pairs over 39 distinct routines - which is neither
DS- nor ES-relative. A span can be entirely 32-bit-only state (group D8) `[OBS-RE]`.

---

### Group D0 - the init stack, a word ring, and `DosExecPgm`'s `"PATH"` (+0x0000..+0x1043)

No 32-bit flat access below +0x1044.

```
push:  si = [0x101e];  if (si >= 0x1030) si = 0x101e;  si += 2;  [si] = ax;  [0x101e] = si
pop:   si = [0x101c];  if (si == [0x101e]) <empty>;    if (si >= 0x1030) ...
```

`postDOSREADASYNC` (obj3+0x7176...0x71D6) does `mov ss,ax / mov sp,0x1033` - a second stack switch into
object 6 - and two short blocks beside it work that WORD ring: **+0x101E is the write pointer,
+0x101C the read pointer**, slots up to the `0x1030` wrap bound, storage +0x1020..+0x1031. The image
holds both pointers = 0x1020, the empty state `[OBS-RE]`.

| offset | size / type | meaning | routines -> ordinal | initial value | concurrency | prov |
|---|---|---|---|---|---|---|
| 0x0000..0x0FFF | 4096 bytes | **`Init32Entry`'s 16-bit init stack** (mechanism 3). The only `0x980F` stack in the module. | `Init32Entry` (obj2) - the module's 32-bit LIBINIT entry | none - it is stack | single-threaded init | [OBS-RE] |
| 0x1000..0x101B | 28 bytes | No access found (segment-relative, flat, offset-literal). | - | 0 | - | [unverified] |
| 0x101C / 0x101E | 2 x WORD | **Ring read pointer / write pointer.** | `postDOSREADASYNC`'s two helper blocks - `DosReadAsync` **#149** | **image 0x1020 each** (empty) | no lock found | [OBS-RE] |
| 0x1020..0x1031 | 18 bytes | The ring's WORD slots, bounded by the `cmp si,0x1030` wrap test. Only `ax` is stored; its producer is not traced. | same | 0 | as above | [OBS-RE] |
| 0x1032..0x103B | 10 bytes | Includes +0x1033, the SP `postDOSREADASYNC` loads. Whether this stack and the ring can be live at once is not established (the blocks are separated by `xchg bx,bx`/`nop` padding and may be separate subroutines entered with different SS; the whole of `postDOSREADASYNC` was not read). | `postDOSREADASYNC` | 0 | - | [unverified] |
| 0x103C | ASCIIZ `"PATH"`, 5 bytes | **`DosExecPgm`'s search-variable name.** After `IsPathAbsolute` rejects the name, `DOSEXECPGM` does `push 7 / push 980F / push 0x103C / push <caller's name> / push ss:&<260-byte stack buffer>` - `DosSearchPath(7, "PATH", ...)`, i.e. with `SEARCH_IGNORENETERRS`. A second `"PATH"` at +0x11B8 serves `preDOSQAPPTYPE`. | `DOSEXECPGM` -> **#144** (32-bit `DOS32EXECPGM` is #283) | image string | read-only | [OBS-RE]; flag values [DOC-IBM] Toolkit 4.5 `H/bsedos.h:728-731` |
| 0x1041..0x1043 | 3 bytes | Slack before D1. | - | 0 | - | [unverified] |

---

### Group D1 - console line input and the KBD/VIO entry vector (+0x1044..+0x116D)

`DosRead` on a **console handle** does not return the kernel's bytes: the kernel gate is called first,
and **only when it returns 0x74** does DOSCALL1 run its own cooked line discipline in object 6. What
0x74 names is not established. Every far call on that path resolves to an exact symbol start in obj4
`[OBS-RE]`:

| site | target | ordinal |
|---|---|---|
| `DOSREAD` `1C03559C` `call 0xe026:0x2308` | `KBDGETSTATUS` | #754 |
| `DOSREAD` `1C0355CD` `call 0xe026:0x26b8` | `KBDSTRINGIN` | #753 |
| `DOSREAD` `1C035613` `call 0xe026:0x3fd7` | `VIOWRTTTY` | #788 |
| `DOSQUERYFHSTATE` `1C037423` `call 0xe026:0x231c` | `KBDPEEK` | #766 |
| vector +0x115C / +0x1160 / +0x1164 / +0x1168 | `KBDCHARIN` / `KBDSTRINGIN` / `VIOWRTTTY` / `VIOSETANSI` | #748 / #753 / #788 / #774 |

**The refill** `[OBS-RE]` (`DOSREAD` whole body `1C035550..1C035645`). `si=[0x1152]; cmp si,[0x1156]` -
equal means the buffer is spent, unequal means unread data remains and the copy runs at once. Refill:
`KbdGetStatus` with a 10-byte `KBDINFO` on the caller's stack (`[bp-0xa]=0x000A` is its `cb`);
`[0x1044]=0xFE` (or the caller's byte count in binary mode, `test word [bp-0x8],0x4`) and `[0x1046]=0`;
`KbdStringIn(ds:0x1052, ds:0x1044, 0, 0)` - the second argument is a `STRINGINBUF`, `cb` at +0x1044 and
`cchIn` at +0x1046. Then `[0x1152]=0x1052`, `[0x1156]=0x1052+[0x1046]`. In cooked mode, if the first
byte is not **0x1A** (Ctrl-Z), `0x0A0D` is appended and `VioWrtTTY(ds:0x1151, 1, 0)` echoes the single
byte at +0x1151 (image 0x0A). The copy-out clamps `[0x1156]-[0x1152]` to the caller's count,
`rep movsb`, and stores the advanced cursor. A `DosRead` shorter than the line leaves the remainder for
the next call.

**`DosQueryFHState` reads the same state** `[OBS-RE]` (`1C0373D8..1C03743D`). After the kernel gate
returns, it masks the returned state byte with 0x18 and requires 0x18 (a character-device handle);
then, **only if the line buffer is empty**, it calls `KbdPeek(ds:0x1048, 0)` and tests
`byte [0x104a] & 0x40`. Bit 0x40 is the low bit of `fbStatus`'s bits 7-6 character-state field - set
for both "final character" encodings (01, 11), clear for "undefined" (00) and "interim" (10)
`[DOC-IBM]` (`cp2.txt`, "KBDKEYINFO Field - fbStatus"). So the test is "is a completed character
waiting", and when it is not, `DosQueryFHState` ORs **0x20** into the caller's state byte.

**Owning ordinals** `[OBS-RE]`. 16-bit `DOSREAD` is **#137**. `DOSQUERYFHSTATE`, `DOSPROTECTREAD` and
`DOSPROTECTQUERYFHSTATE` are 16-bit bodies in obj3; their 32-bit forms thunk down into them -
`DOS32QUERYFHSTATE` (**#276**) is `mov eax,0xe01e73d8 / mov edx,<descriptor> / sub ecx,ecx /
jmp THK32_UNITHUNK`, and `0xe01e73d8` is `DOSQUERYFHSTATE`'s obj3 address - so #276,
**#645** (`DOS32PROTECTQUERYFHSTATE`) and **#641** (`DOS32PROTECTREAD`) reach this state. The 16-bit
ordinals of the three `DOSPROTECT*`/`DOSQUERYFHSTATE` bodies are not established. In addition,
**`DOS32READ`** (obj2+0x24FC, a ~0x880-byte body running to `DOS32READQUEUE`@0x2D7C) and
**`DOS32PROTECTREAD`** (obj2+0x5F26..) drive all eight console-buffer cells directly in 32-bit code with
the same instruction sequence (obj2+0x253D..+0x25B4: reads +0x1152/+0x1156, re-points both at +0x1052,
pushes +0x1048, tests +0x104A, stores 0xFE into +0x1044).

**`KbdStringIn` #753 does not share this buffer.** Its body (obj4+0x26B8) loads DS = 0x9817 (obj7),
reads obj7's slot table and takes `_KbdGetSemaphore`/`_KbdClearSemaphore`; it touches no D1 offset. It
fills whatever buffer its caller supplies - `DosRead` supplies object 6's `[OBS-RE]`.

| offset | size / type | meaning | routines -> ordinal | initial value | concurrency | prov |
|---|---|---|---|---|---|---|
| 0x1044 | WORD | **`STRINGINBUF.cb`** - the maximum this read may take: 0xFE in cooked mode, the caller's byte count in binary mode. Written on every refill; never read back by DOSCALL1. | `DOSREAD` #137, `DOSPROTECTREAD` (<- #641), `DOS32READ`, `DOS32PROTECTREAD` | 0 | none | [OBS-RE]; `STRINGINBUF` [DOC-IBM] Toolkit `bsesub.h` |
| 0x1046 | WORD | **`STRINGINBUF.cchIn`** - characters `KbdStringIn` actually placed; read straight back to compute the buffer end. | same | 0; written 0 before the call, filled by #753 | none | [OBS-RE] |
| 0x1048 | 10 bytes, `KBDKEYINFO` | `KbdPeek`'s output block (`chChar`/`chScan`/`fbStatus`/`bNlsShift`/`fsState`/`time`), used by `DosQueryFHState` to ask whether a completed character is waiting. Ends exactly where the 254-byte buffer begins, with no gap. | `DOSQUERYFHSTATE` (#276 via UniThunk), `DOSPROTECTQUERYFHSTATE` (#645); pushed by `DOS32READ`/`DOS32PROTECTREAD` | 0; filled by #766 per query | none | [OBS-RE]; layout [DOC-IBM] `bsesub.h` |
| 0x104A (inside the above) | BYTE, `fbStatus` | Tested `& 0x40` - a final character is available; clear => `DosQueryFHState` reports 0x20. | same | by #766 | none | [OBS-RE] test; bit meaning [DOC-IBM] `cp2.txt` |
| 0x1052 | 254 bytes (0xFE) | **The cooked console line buffer**, per process; one line at a time. | `DOSREAD` #137, `DOSPROTECTREAD` (#641), `DOS32READ`, `DOS32PROTECTREAD` - filled by #753, echoed by #788 | 0 | none | [OBS-RE] |
| 0x1150 | <= 1 byte | Slack between the buffer end (0x1052 + 0xFE) and the LF byte; no access found. | - | 0 | - | [unverified] |
| 0x1151 | BYTE | The literal linefeed `VioWrtTTY(ds:0x1151, 1, 0)` echoes after a cooked read - a one-byte constant that exists so the echo has a far address. | `DOSREAD`, `DOSPROTECTREAD`, 32-bit owners | **image 0x0A** | read-only | [OBS-RE] |
| 0x1152 | DWORD flat pointer, `stype=7` fixup -> obj6+0x1052 | **The read cursor.** 16-bit code reads only its low word as an in-segment offset, exact because the object is 64 KB-aligned. | `DOSREAD`, `DOSPROTECTREAD`, `DOSQUERYFHSTATE`, `DOSPROTECTQUERYFHSTATE`, `DOS32READ`, `DOS32PROTECTREAD` | **by the loader's fixup: -> +0x1052** | none | [OBS-RE] |
| 0x1156 | DWORD flat pointer, `stype=7` fixup -> obj6+0x1052 | **The end of valid data.** `cursor == end` is the empty test and the only state that says "refill". | same | **by the loader's fixup: -> +0x1052** | none | [OBS-RE] |
| 0x115A | 2 bytes | Slack before the vector; no access found. | - | 0 | - | [unverified] |
| 0x115C / 0x1160 / 0x1164 / 0x1168 | four 16:16 far pointers; selector halves are the four `stype=2` fixups -> obj4 | **The console entry vector**: `KbdCharIn` #748, `KbdStringIn` #753, `VioWrtTTY` #788, `VioSetAnsi` #774 - the KBD/VIO surface the console path uses, reachable by `call far [mem]` without a fixup at each site. Only +0x1160 and +0x1168 have a `call far [...]` site (in `_strcpyfc`); +0x115C's is not found. | `_strcpyfc` (`call far [0x1160]`, `call far [0x1168]`); `DOSREAD`/`DOSQUERYFHSTATE` reach the same targets by direct `call 0xe026:...` | image offsets + 4 loader fixups | read-only | [OBS-RE] |
| 0x116C | ASCIIZ `"."`, 2 bytes | The current-directory name. | `DOSSEARCHPATH` #151 (`lea si,[0x116c]`) | image `2e 00` | read-only | [OBS-RE] |

**Initialisation.** Nothing in DOSCALL1 initialises this group. The cursor and end are set by the
**loader applying the two `stype=7` fixups** to obj6+0x1052, so at process start
`cursor == end == buffer start` - exactly `DOSREAD`'s "empty, refill" condition. The vector selectors
are the four `stype=2` fixups; +0x1151 comes from the image. A child after `DosExecPgm` gets a fresh
instance object and an empty buffer with no LIBINIT step `[OBS-RE]`.

**Concurrency.** Nothing serialises it. `DOSREAD`, `DOSPROTECTREAD`, `DOSQUERYFHSTATE` and
`DOSPROTECTQUERYFHSTATE` make no semaphore call of any kind (checked for all six semaphore gates). Two
threads of one process reading the console concurrently interleave on one cursor, one end and one
buffer; IBM leaves that race open. The only lock on the path is `_KbdGetSemaphore`/`_KbdClearSemaphore`
inside `KbdStringIn`, which protects the keyboard router's own state in objects 7/8 `[OBS-RE]`.

**Not established (D1):** what return code 0x74 names; the 16-bit ordinals of
`DOSPROTECTREAD`/`DOSQUERYFHSTATE`/`DOSPROTECTQUERYFHSTATE`; `_strcpyfc`'s callers (so which ordinal
drives the vector); whether +0x115C (`KbdCharIn`) is ever called through the vector.

---

### Group D2 - the `DosSearchPath` error lists, `pTLMA0`, and the arena fences (+0x116E..+0x11CF)

**The bound is exact** `[OBS-RE]`. `dospath$ChkValidErrs` (`1C0361EE..1C036206`): `cx = 5`,
`di = 0x116E`, `repne scasw` -> scans +0x116E..+0x1177, stopping at `EndValidErrs` (+0x1178,
0x116E + 5x2); with `cx = 0x19` (25) it scans +0x116E..+0x119F, stopping at `EndNetErrs` (+0x11A0,
0x116E + 25x2). The count rises from 5 to 0x19 when the caller's flag has **bit 0x04** set
(`test word [bp+0x14],0x4`). So the region is **one contiguous array of 25 WORDs**, and the two
symbols mark a prefix boundary: the first 5 are always scanned, the remaining 20 only under the flag.

**The 25 codes** (image, decoded) `[OBS-RE]` bytes, `[DOC-IBM]` Toolkit 4.5 `H/bseerr.h` names:
- **`ValidErrs`, +0x116E, 5 words** - "this path element is simply not here (locally)":
  `2 ERROR_FILE_NOT_FOUND`, `3 ERROR_PATH_NOT_FOUND`, `18 ERROR_NO_MORE_FILES`,
  `206 ERROR_FILENAME_EXCED_RANGE`, `26 ERROR_NOT_DOS_DISK`.
- **The 20 that follow, +0x1178..+0x119F** - "the network redirector could not answer":
  `12 ERROR_INVALID_ACCESS`, `54 ERROR_NETWORK_BUSY`, `56 ERROR_TOO_MANY_CMDS`,
  `57 ERROR_ADAP_HDW_ERR`, `58 ERROR_BAD_NET_RESP`, `59 ERROR_UNEXP_NET_ERR`, `60 ERROR_BAD_REM_ADAP`,
  `64 ERROR_NETNAME_DELETED`, `66 ERROR_BAD_DEV_TYPE`, `69 ERROR_TOO_MANY_SESS`,
  `71 ERROR_REQ_NOT_ACCEP`, `86 ERROR_INVALID_PASSWORD`, `240 ERROR_VC_DISCONNECTED`,
  `51 ERROR_REM_NOT_LIST`, `53 ERROR_BAD_NETPATH`, `55 ERROR_DEV_NOT_EXIST`, `67 ERROR_BAD_NET_NAME`,
  `71 ERROR_REQ_NOT_ACCEP` (**a genuine duplicate in IBM's data**, at +0x1186 and +0x1198),
  `65 ERROR_NETWORK_ACCESS_DENIED`, `5 ERROR_ACCESS_DENIED`. Why 71 appears twice is not established;
  it is harmless to a linear scan, and the scan count (25) and boundary symbols depend on it.

**The grouping is IBM's own flag**: `#define SEARCH_IGNORENETERRS 0x0004` `[DOC-IBM]` Toolkit 4.5
`H/bsedos.h:731`. The second list is the implementation of that flag: with it set, `DosSearchPath`
treats a redirector failure the same way it treats "not found".

**What a caller sees** `[OBS-RE]`. `dospath$ChkValidErrs` returns only **ZF**. Both call sites in
`DOSSEARCHPATH` are:

```
call FindFile ; or ax,ax ; jz <found - build the result and return 0>
call dospath$ChkValidErrs
jz  <continue: try the next directory in the path>      ; ZF=1, the rc IS in the list
jmp <abort: return that rc to the caller unchanged>     ; ZF=0, the rc is NOT in the list
```

So the list is the set of error codes that mean "keep looking": a hit is swallowed and the search
advances; a miss ends the search and the caller gets that exact rc. The lists are part of
`DosSearchPath`'s observable contract. **Owning ordinals:** `DOSSEARCHPATH` **#151** (obj3, two sites)
and `DOS32SEARCHPATH` **#228** (obj2, two sites) - the 32-bit form is a separate implementation with
its own copy of the scan, reading the same object-6 data through a 16:32 `es`, not a UniThunk stub.

**`Dos32SearchPath` scans twice the list - an IBM defect** `[OBS-RE]`. `dospath2$ChkValidErrs32`
(`1C020844..1C02086E`) computes its count as a **byte** difference and feeds it to a **word** scan:
`mov edi,0x116e / mov ecx,0x1178 / sub ecx,edi` -> `ecx = 0x0A`, then `repne scasw`, which decrements
ECX once per word. The default scan therefore covers **10 words** (+0x116E..+0x1181: the five
`ValidErrs` plus the first five network errors), and the `SEARCH_IGNORENETERRS` arm
(`ecx = 0x11A0 - 0x116E = 0x32`) covers **50 words** (+0x116E..+0x11D1), running past `EndNetErrs`
through `pTLMA0`, all six fence cells and the `"PATH"` string. The 16-bit form uses `cx = 5` /
`cx = 0x19` and lands exactly on both end symbols. Consequence `[INF]`: `Dos32SearchPath` #228 ignores,
without the flag, network errors (12, 54, 56, 57, 58) that `DosSearchPath` #151 aborts on; with the flag
it can match a fence or `pTLMA0` value as if it were an error code.

| offset + IBM name | size / type | meaning | routines -> ordinal | initial value | concurrency | prov |
|---|---|---|---|---|---|---|
| 0x116E `ValidErrs` | 5 WORDs | The always-scanned prefix: errors meaning the name is absent at this path element, so the search tries the next one. | `dospath$ChkValidErrs` <- `DOSSEARCHPATH` #151; `dospath2$ChkValidErrs32` <- `DOS32SEARCHPATH` #228 | **image**; never written (the only instructions touching +0x116E are `mov di,0x116e`/`mov edi,0x116e`) | read-only | [OBS-RE] bytes; meanings [DOC-IBM] `bseerr.h` |
| 0x1178 `EndValidErrs` (the 20 network errors) | 20 WORDs | Network-redirector failures, scanned only under `SEARCH_IGNORENETERRS`. The symbol names the boundary, not a separate array. | same | **image** | read-only | [OBS-RE]; flag [DOC-IBM] `bsedos.h:731` |
| 0x11A0 `EndNetErrs` / `pTLMA0` | DWORD | **Two symbols, one address, two unrelated meanings.** As `EndNetErrs` it is the 16-bit scan's limit and is never dereferenced; as `pTLMA0` it is the per-process **TLMA** anchor, `((localIS >> 3) << 16) + 0x2C` on SMP (`+ 0x24` on UNI). | Written by `InitDOSCALL1` (`1C040054`, above its once-per-system guard); read by `_GET_TLMA0`, `_SET_TLMA0`, and flat by 11 32-bit routines including `DOS32CANONICALIZE`, `DOS32PCREATEDIR`, `DOS32PFINDFIRST`, `DOS32PQUERYPATHINFO`, `DOS32PSETFILEINFO`, `DOS32PSETPATHINFO`, `DOS32QUERYQUEUE`, `UT32_CheckFlags`, `UT32_ConvertPointer`, `_xcptRemoveRegistrationHead` | written once per process by `InitDOSCALL1` | single write at init, then reads | [OBS-RE] |
| 0x11A4 `FenceLAddr` / 0x11A8 `FenceShrLAddr` / 0x11AC `FencePckLAddr` | 3 x DWORD | The **tiled linear base** of each fence selector, `(sel >> 3) << 16` - selector index x 64 KB. Live state on the flat<->selector conversion path. | Written by `InitDOSCALL1` only (`1C040168`, `1C04017C`, `1C040190`, `mov [fs:...],eax`); read flat by **`DOS32FLATTOSEL`**; a further 14 sites in the `DosProtect*` family compare against +0x11A4. | once per process, from the LIS | write-once, then reads | [OBS-RE] |
| 0x11B0 `FenceSel` / 0x11B2 `FenceShrSel` / 0x11B4 `FencePckSel` | 3 x WORD | **Copies of the Local InfoSeg's three arena-boundary selectors**: `es = [obj5+0x2]` (`localIS`), then `[es:0x1E]`, `[es:0x20]`, `[es:0x22]` = `LIS_PackSel` / `LIS_PackShrSel` / `LIS_PackPckSel` - "first tiled / above-shared-arena / above-packed selectors". | Written by `InitDOSCALL1` only (`1C04015D`, `1C040171`, `1C040185`); read flat by **`DOS32SELTOFLAT`**. | once per process | write-once, then reads | [OBS-RE] copy and readers; LIS layout [DOC-IBM] DDK `base/h/infoseg.h:212-214` |
| 0x11B6 | 2 bytes | Gap; no access found. | - | 0 | - | [unverified] |
| 0x11B8 | ASCIIZ `"PATH"`, 5 bytes | The environment variable `preDOSQAPPTYPE` searches: `push 3 / push 980F:0x11B8 / push <name> / push ss:<260-byte stack buffer>` - `DosSearchPath(3, "PATH", ...)` after `IsPathAbsolute` says the name is unqualified. Flags = 3 = `SEARCH_CUR_DIRECTORY|SEARCH_ENVIRONMENT`, **without** 0x04, so this search aborts on a network error. | `preDOSQAPPTYPE` -> `DosQueryAppType` #163 (16-bit) / #323 (32-bit); which of the two reaches `preDOSQAPPTYPE` is not traced | image string | read-only | [OBS-RE]; flag values [DOC-IBM] `bsedos.h:728-731` |
| 0x11BD..0x11CF | 19 bytes | +0x11C0 is an **`xchg`-guarded list head** and +0x11C4 its companion pointer, owned by the 32-bit thunk-block allocator pair: **`THK32FREEBLOCK`** (obj2+0x0A14: `xchg ecx,[0x130111c0]` at +0x0A18, `mov edx,[0x130111c4]`, `mov dword [0x130111c0],0x0`) and **`THK32ALLOCBLOCK`** (obj2+0x277C: `xchg eax,[0x130111c0]`, `mov edx,[0x130111c4]`, `mov [0x130111c0],ecx`, `mov edx,0x130111c4`). Both sites sit 4-5 bytes past their symbol's start. The other bytes of the span have no access found. | `THK32ALLOCBLOCK`, `THK32FREEBLOCK` | 0 | `xchg`-guarded, no semaphore | [OBS-RE] |

**Concurrency, D2.** The lists are constants; the fences and `pTLMA0` are written once by
`InitDOSCALL1` before any other thread of the process exists; nothing is taken. The +0x11C0 head is a
lock-free `xchg` structure `[OBS-RE]`.

---

### Group D3 - name strings, the NLS cache, and the segment allocator (+0x11D0..+0x125F)

**The NLS cache** `[OBS-RE]` (`_cache_table`, SMP body `1C037EB0..1C0380C1`, read whole). `_ICACHE_TABLE`
(+0x1238) is the **head node of a singly-linked list of country/code-page information records**, per
process, guarded by `_iCache_sem`. `_cache_table(key1, &key0, &out, key2)`:

1. `DosSemRequest(-1,-1, far _iCache_sem)` (the plain RAM-semaphore family, SMP `e01e:0x610`), the far
   pointer taken as the two halves `[es:0x1222]`/`[es:0x1220]` of `_iNLS_Sem`, with ES loaded from
   object 5's slot +0x244. Return code **0x11 retries the request**; any other non-zero returns at once.
2. Walk from the head at `980F:0x1238`. A node's **next** far pointer is at **+0x0A**; the list ends
   when the DWORD at +0x0A is zero (`mov ax,[es:bx+0xc] / or ax,[es:bx+0xa] / jz`). A node matches
   when three WORD keys agree: node+0x02 == arg4, node+0x00 == *arg2, node+0x06 == arg1.
3. **Hit:** `DosSemClear` (SMP `e01e:0x6cd`), write the node's far address through the out-pointer,
   return 0.
4. **Miss:** `_findinfo` locates the record in the country file (obj5+0x60 `"COUNTRY.SYS"`, via
   `_getctry`), then `_fseek` and two `_fread`s - the second reads a **length WORD** - and
   **`REALLOCSEG(far &lastNode+0x08, length + 0x0E)`** (SMP `e01e:0x80e5`). The new block's offset
   therefore lands in the last node's +0x08; `_copyinfo` fills the payload at new+0x0E; the new node is
   linked by storing its far address into lastNode+0x0A/+0x0C, after which its own +0x08 and +0x0A/+0x0C
   are zeroed and its three keys written. **Node header = 0x0E bytes; payload follows.**
5. Errors **0x18C/0x18D** are returned unchanged; every path clears the semaphore first.

So the NLS cache is allocated by **growing object 6 itself**; each miss enlarges the object by
`length + 0x0E`. **Nothing invalidates or frees it**: +0x1238 has exactly one user in the module, so the
list only grows, is never unlinked, and lives until the process exits. A code-page change does not flush
it; a stale entry cannot occur because the three keys are the identity. `_FSRam_Sem` (+0x1228) and
`_iSize` (+0x1236) have no users outside `REALLOCSEG` (2 and 1 sites). The NLS chain's four ordinals are
the four callers of `_w_cdib`: `DOSCASEMAP` #391, `DOSGETCOLLATE` #392, `DOSGETCTRYINFO` #393 (obj3+0xAA0,
call to `_w_cdib` at `1C030AD5`), `DOSGETDBCSEV` #394 `[OBS-RE]`.

The same obj3 gate offset names different routines in the two builds: obj3+0xA0 is `DOSSEMREQUEST` in
UNI, while SMP obj3+0x60/+0x1CD are `DOSFSRAMSEMREQUEST`/`DOSFSRAMSEMCLEAR` `[OBS-RE]`.

| offset + IBM name | size / type | meaning | routines -> ordinal | initial value | concurrency | prov |
|---|---|---|---|---|---|---|
| 0x11D0 `_device_prefix` | ASCIIZ `"\DEV\"`, 6 bytes | The device-namespace prefix a path is tested against / prefixed with. | `DOSCOPY` x2 (`1C04D0FD`, `1C04D1A5`) -> #201 | image string | read-only | [OBS-RE] |
| 0x11D6 | ASCIIZ `""` (empty), 4 bytes | The empty string, passed where a null path component is wanted. | `_CopyFile` x4 -> #201 | image | read-only | [OBS-RE] |
| 0x11DA / 0x11DC / 0x11DE | ASCIIZ `"*"` / `"."` / `".."` | The wildcard and the two directory self/parent names, for the recursive tree walk. | `_CopyTree` (one site each) -> #201 | image | read-only | [OBS-RE] |
| 0x11E2 | ASCIIZ `"\CONTROL.DEL"`, 13 bytes | The DELDIR control file. | `_EraseFiles` (`1C03E4D3`) | image | read-only | [OBS-RE] |
| 0x11EF | ASCIIZ `"\"`, 2 bytes | Root / separator. | `_EraseFiles` (`1C03E5AD`) | image | read-only | [OBS-RE] |
| 0x11F1 | ASCIIZ `"DELDIR"`, 7 bytes | The **`SET DELDIR=`** environment variable name - OS/2's undelete store. | `_GetEnvironmentVars` (`1C03E66F`), called only from `_EraseFiles` (`1C03E4AC`), which is called from `DOSWRITE` (`1C03E411`, inside DosWrite's own body, which ends `retf 0xc` at +0xE438). Why `DosWrite` needs it is not established. | image | read-only | [OBS-RE] |
| 0x11F8 | ASCIIZ `"LOG$"`, 5 bytes | The system error-log device name (a second copy at +0x16B0, D7). | `DOSLOGREGISTER` (`1C04E05C`) -> #195 | image | read-only | [OBS-RE] |
| 0x11FE `_Log_Pipe_Nm` | ASCIIZ `"\PIPE\LOGDATA\JGRENBLF"`, 22 characters, terminated at +0x1214 | The named pipe the logger connects through - **one** string (symbol span to `_iNLS_Sem` +0x1220 with nothing declared between; one contiguous image run, byte-identical in both builds; `DOSLOGREGISTER` pushes +0x11FE twice and +0x120C zero times). | `DOSLOGREGISTER` x2 (`1C04E0E0`, `1C04E0F3`) -> #195 | image | read-only | [OBS-RE] |
| 0x1220 `_iNLS_Sem` | 16:16 far pointer (fixup at +0x1222 -> obj6) | Not a semaphore: **a far pointer to `_iCache_sem`**, so 16-bit code can pass the semaphore by far address. | `_cache_table` x8 (4 request, 4 clear) | **image `24 12` + fixup -> `980F:1224`** | read-only | [OBS-RE] |
| 0x1224 `_iCache_sem` | 4 bytes, RAM semaphore | **The NLS cache lock**, taken with `DosSemRequest`/`DosSemClear` - the plain 16-bit RAM-semaphore family, not the fast-safe one. Per process. | `_cache_table` <- `_w_nls_apis` <- `_w_cdib` <- #391 `DosCaseMap`, #392 `DosGetCollate`, #393 `DosGetCtryInfo`, #394 `DosGetDBCSEv` | 0 | **It is the lock**; held across the file read and the allocation, released on every path. | [OBS-RE] |
| 0x1228 `_FSRam_Sem` | 14 bytes, fast-safe RAM semaphore (leading WORD 0x000E = its own length) | **The segment-growth lock, and nothing else's** - exactly two sites, both in `REALLOCSEG`. | `REALLOCSEG` <- `_cache_table`, `check_room_to_save` | **image WORD 0x000E**, rest 0 | fast-safe, per process | [OBS-RE]; `FSRST` layout [DOC-IBM] DDK `sem.inc` |
| 0x1236 `_iSize` | WORD | **The object's own current size**, and the bump-allocator cursor (mechanism 2). Exactly one user. | `REALLOCSEG` | **image 0x1DC0 (SMP)** - the object's own initial size, which differs between the builds | under `_FSRam_Sem` | [OBS-RE] |
| 0x1238 `_ICACHE_TABLE` | list head node, 0x0E-byte header | Head of the country/code-page record cache: keys at +0x00/+0x02/+0x06, `REALLOCSEG` out-cell at +0x08, far next at +0x0A, payload at +0x0E. | `_cache_table` only (builds `980F:0x1238` at `1C037EE3`) | 0 | under `_iCache_sem` | [OBS-RE] |
| 0x1246..0x125F | 26 bytes | Tail of the head node (payload area) plus slack before `___acrtused`; not separately established. | - | 0 | - | [unverified] |

**Locking, D3** `[OBS-RE]`. Two semaphore families in one object, and the split is deliberate:
`_iCache_sem` is a plain RAM semaphore (`DosSemRequest`), `_FSRam_Sem` a fast-safe one
(`DosFSRamSemRequest`). **`_iCache_sem` is outside, `_FSRam_Sem` inside**: `_cache_table` holds
`_iCache_sem` across its `REALLOCSEG` call, which takes and releases `_FSRam_Sem` within. The order is
forced because `check_room_to_save` (D6) reaches `REALLOCSEG` without `_iCache_sem`, so the allocator's
lock must be the inner one `[INF]`. Both are per process.

**Not established (D3):** why `DOSWRITE` calls `_EraseFiles`; the meanings of the three cache keys
(country code / code page / record type would need `_findinfo`'s and `_w_cdib`'s argument marshalling);
which of the four NLS ordinals reaches each of `_cache_table`'s three call sites inside `_w_nls_apis`.

---

### Group D4 - C runtime marker, per-process init/exit, and export 414 `_QUEINST_DATA` (+0x1260..+0x1281)

**Export 414 is the per-process instance record of the 16-bit IPC queue subsystem** `[OBS-RE]`
(`_FuncInit` read whole, `1C032788..1C0328D5`). Every 16-bit queue entry calls `_FuncInit` on the way
in - `W_DOSCREATEQUEUE` #681, `W_DOSOPENQUEUE` #680, `W_DOSREADQUEUE` #674, `W_DOSWRITEQUEUE` #679,
`W_DOSPEEKQUEUE` #678, `DOSCLOSEQUEUE` #676, `DOSPURGEQUEUE` #675, `DOSQUERYQUEUE` #677 and the internal
`_Q_Sleep` (real call sites `call 0xe01e:0x2788`) - and `_FuncFree` (obj3+0x2734) at the matching exits.
So the owning ordinals are **#674-#681**, and the record is **built lazily by the first queue call a
process makes**, not by LIBINIT.

`_FuncInit`, in order: DS = obj5, `es = [obj5+0x2A2]`, `les bx,[es:0x206]` (`_ISEG` -> obj6+0x126A); if
the DWORD at `[bx+2]` is non-zero it returns. Otherwise it calls a two-out-pointer kernel gate and stores
the first word of the returned block into `[bx+0]` - **the process's PID**. It then calls a kernel gate
with `(0, ss:&handle, ds:0x1CA)`, obj5+0x1CA being `"\SEM\IPCQUEUE.SEM"`, treating **0xB7 =
`ERROR_ALREADY_EXISTS`** as "then open it" (the same gate again without the leading 0) and 0x64 as
tolerable; anything else becomes **328 (0x148)**. The returned DWORD goes to `[bx+2]`/`[bx+4]`. If
`[bx+6] == 0` it registers **two** exit-list entries - `(0xD081, e026:0xE350)` and
`(0xD001, e026:0xE355)`, which the SMP `.SYM` names `_EXITLISTQUEUE1` and `_EXITLISTQUEUE2` - and on
success writes `[bx+6] = 0xFF`. (The UNI equivalent of the exit-list step is obj3:0x1C25-0x1C59.) The
names of the two kernel gates (PID source, `DosGetInfoBlocks`-shaped; semaphore create/open) are not
established; the field split of the `0xD081`/`0xD001` order codes is not decoded - that both are ADD
registrations differing only in the low byte is `[OBS-RE]`.

| offset + IBM name | size / type | meaning | routines -> ordinal | initial value | concurrency | prov |
|---|---|---|---|---|---|---|
| 0x1260 `___acrtused` | unknown; **never read or written anywhere in obj2/3/4** | The C startup marker symbol; its presence pulls the C runtime's startup module into the link. Compiler bookkeeping, not an OS/2 contract - the only C-runtime cell in the object. | none | n/a | n/a | [OBS-RE] absence of access; [INF] linker role |
| 0x1262 `_InitializedAlready` | WORD | DOSCALL1's **once-guard for the FSD daemon threads**: `cmp word [0x1262],0` -> if set, record exit point 1 and return; else set 1 and proceed. Per process. Subsystem state despite the C-shaped name. | `STARTFSDDAEMONS` (not an export; reached from DOSCALL1's init path) | 0 | **Test-and-set with no lock** - two threads of one process entering together both proceed. | [OBS-RE] |
| 0x1264 `_WaitForThreadSpawned` | DWORD, **16-bit RAM semaphore** | **The thread-spawn rendezvous** (see object 11): `DosSemSet` #143 before the first spawn (`1C03F3C8`) and after each (`1C03F517`), `DosSemWait(-1)` #142 after each `DosCreateThread` (`1C03F50E`), `DosSemClear` #141 by the spawned thread (`1C03F5F1`) after it has copied its parameters. Address-taken only (`push word 0x1264` x3 in `STARTFSDDAEMONS`, x1 in `SPAWNEDTHREAD`). | `STARTFSDDAEMONS`, `SPAWNEDTHREAD` | 0 | it **is** the synchronisation | [OBS-RE] |
| 0x1266 | <= 2 bytes | Gap before `_ExitPoint`; belongs to +0x1264 if that is the 4-byte RAM semaphore (it is a DWORD). | - | 0 | - | [unverified] |
| 0x1268 `_ExitPoint` | WORD | **A breadcrumb recording which return path `STARTFSDDAEMONS` took.** Five writes, values 1/2/3/5/6, each immediately followed by `retf` (`1C03F39F`->`F3A9`, `F3D5`->`F3DF`, `F418`->`F422`, `F57B`->`F585`, `F586`->`F590`). 1 = "already initialised". Diagnostic state, not a function pointer or exit-list hook. | `STARTFSDDAEMONS` | 0 | last writer wins | [OBS-RE] |
| 0x126A `_QUEINST_DATA` - **export 414** | data record; +0x0 WORD, +0x2 DWORD, +0x6 BYTE established | **The per-process IPC-queue instance record.** +0x0 = this process's PID; +0x2 = the DWORD handle of the system semaphore `\SEM\IPCQUEUE.SEM`; +0x6 = exit-list-registered flag, **0xFF** (not 1). A **data** export in a **16-bit** object: what an importer gets is the 16:16 address of this record, not an entry point. No code addresses it by displacement; it is reached only through obj5 `_ISEG` (+0x206; 13 `les bx,[es:0x206]` sites). | `_FuncInit`/`_FuncFree` <- #674-#681; `C_EXITLISTQUEUE1/2` and `_EXITLISTQUEUE1/2` (obj4+0xE350/+0xE355) on process exit | 0; lazily, by the first queue call in the process | `[bx+2] != 0` is the "already done" test, **no lock**: two threads making their first queue call together can both run the create/open (the second gets 0xB7 and opens, benign) and both can register the exit-list pair before either sets `[bx+6]`. | [OBS-RE] |
| 0x1271..0x127F | 15 bytes | Inside 414's `.SYM` span, no use found. | - | 0 | - | [unverified] |
| 0x1280 | WORD | **Not part of 414.** A message-subsystem latch: `PREGETMSG` (a label inside `DOSTRUEGETMESSAGE` #384) tests it for 0 and sets it to **0x3B3 (947)**. | #384 | 0 | see D6 | [OBS-RE] |

**Concurrency, D4.** Nothing takes a lock. The three test-and-set guards (`_InitializedAlready`,
`_FuncInit`'s `[bx+2]` and `[bx+6]`) are plain, unserialised, per process; the four fast-safe/RAM
semaphores object 6 carries cover none of these cells. The races are real and IBM tolerates them
`[OBS-RE]`.

**Importers of 414.** Over a Warp 4.5 installation's `*.DLL`/`*.EXE` (1591 files), no LX module imports
DOSCALLS #414 by ordinal (1384 LX files parsed; the scan does find neighbouring ordinals: #415 x3, #417
x11, #418 x48, #419 x1, #423 x2, #424 x2, #425 x145), and no module of either format contains the string
`_QUEINST_DATA`, so none imports it by name. Whether any of the 207 NE modules imports #414 by ordinal is
not established `[OBS-RE]` (static import scan of an installed Warp 4.5 file set). So 414 is reached in practice
only by DOSCALL1's own code through `_ISEG` `[INF]`.

---

### Group D5 - the message-file machinery: `MKMSGF` signature, country-info block, path buffer (+0x1282..+0x14C1)

**The message subsystem is one assembly routine.** `DOSTRUEGETMESSAGE` (#384) is SMP obj3+0x8580 and
`DOSINSMESSAGE` obj3+0x9540, and every label this group touches lies between them - `chkmore` 0x8672,
`chkcp10` 0x877C, `chkcp14/15/16`, `CLEAN_UP` 0x8972, `FIND_FILE` 0x89F2, `CHK_MSG_FILE` 0x8A80,
`cmploop` 0x8AB9, `getboot` 0x8B18, `savesub` 0x8B9C, `verify_signature` 0x8C66, `code_page_data`
0x8C83, `ROOM_FOR_1` 0x8D55, `GET_MESSAGE` 0x8F69, `FILENAME_OUT` 0x908F, `end_dpath` 0x9388. They are
**labels inside #384, not routines**; the owning ordinal of every one is #384. `TRY_DISK` (0x9E09) and
`c_filename_strip`/`c_FIND_FILE` (0xA038/0xA064) sit outside it `[OBS-RE]`.

**What the 0x12E block is.** +0x128A is `FILECOUNTRYINFO`, 302 bytes, read whole out of the `.MSG` file:
`code_page_data` seeks to the header's `countryinfo` offset and reads 0x12E bytes into object 6
(`DosRead(hf, es:0x128a, 0x12e, ss:&cb)` at `1C038793`, through `e01e:0x5550` = SMP `DOSREAD`; a short
read sets **0x13E = 318**), then rejects the file with **319 `ERROR_MR_INV_MSGF_FORMAT`** if the count at
+0x1291 exceeds 16 (`cmp word [0x1291],byte +0x10` at `1C038CD3`) `[OBS-RE]`. Every field the readers
touch lands on the on-disk structure as osFree defines it from the writer side, and the two agree at 302
bytes `[DOC]` (osFree `mkmsgf.h`):

| obj6 | struct offset | field | seen at |
|---|---|---|---|
| +0x128A | +0x00 | `bytesperchar` u8 | the read target |
| +0x128B | +0x01 | `country` u16 | `chkmore` `1C0386F6`, `chkcp14` `1C03882B`; cached by `savesub` |
| +0x128D | +0x03 | `langfamilyID` u16 | `savesub`/`ROOM_FOR_1` |
| +0x128F | +0x05 | `langversionID` u16 | `savesub`/`ROOM_FOR_1` |
| +0x1291 | +0x07 | `codepagesnumber` u16, **max 16** | `code_page_data` `cmp ...,0x10` -> 319; `chkcp10`/`chkmore` load it as the loop count |
| +0x1293 | +0x09 | `codepages[16]` | `lea si,[0x1293]` in `chkcp10` and `chkmore`; `savesub`/`ROOM_FOR_1` copy it indexed |
| +0x12B3 | +0x29 | `filename[260]` | `lea di,[0x12b3]` (`chkcp14`), `lea si,[0x12b3]` (`ROOM_FOR_1`) |
| +0x13B7 | +0x12D | `filler` u8 | ends exactly at +0x13B8 |

**How the file is opened and cached** `[OBS-RE]`. #384 drives everything: `CHK_MSG_FILE` walks the
per-process **`SAVED`** open-file cache (D6) before touching the filesystem; on a miss `FIND_FILE` builds
the name in +0x13B8, `DO_OPEN` issues `DosOpen(..., fsOpenFlags=1, fsOpenMode=0xA0)` and, failing that,
`OPEN_DPATH` allocates its own 260-byte segment and calls `DosSearchPath(7, "DPATH", ...)` -
`7 = SEARCH_CUR_DIRECTORY|SEARCH_ENVIRONMENT|SEARCH_IGNORENETERRS`. `OPEN_DPATH` and `DOSEXECPGM` (#144,
D0) are the two `SEARCH_IGNORENETERRS` callers found in DOSCALL1, so D2's 20-entry network list serves
both the message-file search and program launch. On an error, `OPEN_DPATH`'s tail `end_dpath` tests the
rc against object 5's 27-word table at obj5+0x300. `VAL_FORMAT` reads the 31-byte header onto the stack,
`verify_signature` compares 8 bytes against +0x1282, and `code_page_data` reads the country-info block
into +0x128A. **Owning ordinals:** #383 `DosPutMessage`, #384 `DosTrueGetMessage`, #385 `DosInsMessage`,
#649 `DosCloseMessageFile`, #389 `DosIQueryMessageCp`. The public `DosGetMessage` (obj3+0x40, a
thunk-stub region) has no ordinal in the export list; its number is not established.

**Locking - `GetFSRamSem` brackets the whole search, per process** `[OBS-RE]`. `FIND_FILE` is the only
request site: `1C0389F8` sets a stack guard byte `[bp-0x67] = 0xFF`, then
`push 980F / push 0x14de / push -1 / push -1 / call e01e:0x60` (`DOSFSRAMSEMREQUEST`). The other seven
sites are clears through `e01e:0x1cd` (`DOSFSRAMSEMCLEAR`) - `CLEAN_UP`, `DOSCLOSEMESSAGEFILE` x2,
`c_filename_strip` x2, `c_FIND_FILE` x2 - each gated on that guard byte. Because the labels are all inside
#384, **the file search, the `SAVED` walk, the open, the header read and the country-info read all
execute inside one `GetFSRamSem` bracket**, which serialises threads of one process and nothing else.
`PutFSRamSem` (+0x1692, D7) is the separate bracket on the put path.

| offset + IBM name | size / type | meaning | routines -> ordinal | initial value | concurrency | prov |
|---|---|---|---|---|---|---|
| 0x1282 `SIGNATURE_MSGF` | 8 bytes | The `\xFF"MKMSGF"\x00` magic every `.MSG` file starts with; compared `repe cmpsb`, `cx=8`, against the 31-byte header read onto the stack; mismatch -> 319. | `verify_signature`, `TRY_DISK` | **image `ff 4d 4b 4d 53 47 46 00`** | read-only, inside the `GetFSRamSem` bracket | [OBS-RE]; format [DOC] osFree `mkmsgf.h` |
| 0x128A | 302 bytes (0x12E), `FILECOUNTRYINFO` | The message file's country/code-page block, read whole and consulted field by field (table above). One buffer per process, overwritten per file examined. | `code_page_data` (read + the <=16 check), `chkcp10`/`chkmore`/`chkcp14/15/16` (code-page match), `savesub`/`ROOM_FOR_1` (copy into the `SAVED` entry) - #384 | 0; filled per file | under `GetFSRamSem` | [OBS-RE]; layout [DOC] osFree |
| 0x1291 (inside the above) | u16 | `codepagesnumber`; `> 16` is a hard reject with 319 - the one validation IBM performs on this block. | `code_page_data` | from the file | as above | [OBS-RE] |
| 0x13B8 | 260 bytes (0x104) | The message-file **path buffer**. `FIND_FILE` measures the caller's name with `cx=0x104 / repne scasb`, then builds the candidate path here with ES=0x980F. | `FIND_FILE` x2, `FILENAME_OUT` x2, `cmploop` - #384 | 0; rebuilt per lookup | under `GetFSRamSem` | [OBS-RE] |
| 0x14BC | 1 byte | Slack; no access found. | - | 0 | - | [unverified] |
| 0x14BD | WORD + BYTE at 0x14BF = a 3-byte save slot | **The in-place path-edit backup.** `end_dpath` backs `es:di` up 3 bytes, saves the 3 bytes it is about to overwrite here, then writes `cx` over the WORD and `'\'` (0x5C) over the third; `getboot` restores all three after `DO_OPEN`. DOSCALL1 splices a drive prefix into a path buffer in place and puts the original characters back. What `cx` holds is not traced (the boot-drive `"X:"` computed from `SIS_BootDrv` is a plausible source, not established). | `end_dpath` (save), `getboot` (restore) - #384 | 0; per lookup | Under `GetFSRamSem`; per process, so it is safe only because the bracket covers every use `[INF]`. | [OBS-RE] |
| 0x14C0..0x14C1 | 2 bytes | Slack; no access found. | - | 0 | - | [unverified] |

**Not established (D5):** `DosGetMessage`'s ordinal; whether `chkcp14`/`chkcp15`/`chkcp16` differ in
the field they compare; what `end_dpath`'s `cx` holds.

---

### Group D6 - message defaults, DBCS/country cells, and the `SAVED` open-file cache (+0x14C2..+0x168F)

No routine in this group has a decompile; all of it is disassembly of labels inside #384.

**The `SAVED` record - 0x143 bytes** `[OBS-RE]`, derived from both sides: the reader (`CHK_MSG_FILE`'s
`repe cmpsb` walk, `[SI+0x113]`, `[SI+0x11F]`, `[SI+BX+0x121]`, `[SI+0x141]`) and the writer
(`check_room_to_save` `1C038CDD`'s `0x143`, `ROOM_FOR_1`'s field-by-field fill, `resiz_ok` `1C038D49`'s
link read-back):

| entry offset | size | field |
|---|---|---|
| +0x000 | 255 | the message file's **name** (`ROOM_FOR_1` copies it from the caller's buffer, or from obj6+0x12B3, `FILECOUNTRYINFO.filename`, scanning with `cx=0x104`) |
| +0x0FF | 31 | **the cached `.MSG` header, verbatim** - every `ROOM_FOR_1` write is `0x0FF + <header offset>`: +0x105/+0x107 = header +0x06/+0x08 (`identifier[3]`), +0x10A `numbermsg`, +0x10C `firstmsg`, +0x10E `offset16bit`, +0x10F `version`, +0x113 `countryinfo`, +0x115...+0x11D `extenblock` and the reserved tail |
| +0x11F | 2 | cached `codepagesnumber` |
| +0x121 | 32 | cached `codepages[16]` |
| +0x141 | 2 | **link** - offset of the next entry, 0 = end |
| | **0x143** | total; a literal in the code (`mov si,0x143`) |

**Growth - the allocation and the link are one call** `[OBS-RE]` (`check_room_to_save`, whole body):
1. `SAVED_COUNT == 0` -> `di = 0x14F0`, the **static** entry, straight to `ROOM_FOR_1`. The first cached
   file always uses the in-image slot; the object does not grow for it.
2. Else a reusable entry found earlier (`[bp-0x28]`) -> use it (where `[bp-0x28]` is set is not read).
3. Else: `si = 0x143` (pushed as the size), `si -= 2` -> 0x141, `si += [0x14ec]` - so the far pointer
   handed to `REALLOCSEG` (`call 0xe01e:0x80e5`) is **the current last entry's link field**. Because
   `REALLOCSEG` writes the old `_iSize` through that pointer, **one call both allocates the 0x143-byte
   block and links it into the chain**. `resiz_ok` then reads the link back
   (`di = [0x14ec]; di = [di+0x141]; [0x14ec] = di`) and advances the cursor.
4. On `REALLOCSEG` failure it sets `[bp-0x64] = 1` and **proceeds without caching** - a degradation, not
   an error return.

`check_room_to_save` is a label inside #384, downstream of `FIND_FILE`'s request on `GetFSRamSem`, so the
growth path holds **`GetFSRamSem` (outer) and takes `_FSRam_Sem` (inner)** inside `REALLOCSEG` - the
same nesting as D3, reached by a different route.

| offset + IBM name | size / type | meaning | routines -> ordinal | initial value | concurrency | prov |
|---|---|---|---|---|---|---|
| 0x14C2 | 1 byte `'\'` | The leading separator of `"\SYSOSO001.MSG"` - one 15-byte image string serving three overlapping symbols. | `FILENAME_OUT`, `PREINSMSG` | image | read-only | [OBS-RE] |
| 0x14C3 `err_component` | 3 bytes `"SYS"` | The **component id** substituted into the filename - the `.MSG` header's `identifier[3]`. `FILENAME_OUT` and `PREINSMSG` take its address so a caller's component (`"SYS"`, `"REX"`, `"NET"`, ...) can be written over it. | `FILENAME_OUT`, `PREINSMSG` -> #385 | **image `"SYS"`** | **Written in place**, under `GetFSRamSem` where reached from #384. | [OBS-RE] |
| 0x14C6 `err_filename` | 11 bytes `"OSO001.MSG"` | The default message filename, the OS/2 system message file. | same | image | read-only | [OBS-RE] |
| 0x14D1 `ram_file_found` | BYTE | Found/not-found latch for the **conforming** search path: `FNSRCH` sets 1, `c_FIND_FILE` clears it and reads it back. | `FNSRCH`, `c_FIND_FILE` (obj3+0xA1F4/+0xA064 - outside #384) | 0 | cleared under `GetFSRamSem` (`c_FIND_FILE` is a clear site) | [OBS-RE] |
| 0x14D2 `COUNTRY_CODE` | 4 bytes, `COUNTRYCODE`: country u16 at +0x14D2, code page u16 at +0x14D4 | The country/code-page pair the message lookup runs under. `PREGETMSG` zeroes both; `chkmore`/`chkcp14` fill them from the file's `FILECOUNTRYINFO`; `CHECK_DBCS` reads both and copies them into obj5+0x25A; `GET_END` passes the pair by address. | `PREGETMSG`, `chkmore`, `chkcp14`, `GET_END` (#384), `CHECK_DBCS` (<- #383/#384/#385/#389) | 0 | Inside the #384 bracket; `CHECK_DBCS` also runs under `PutFSRamSem` on the put path. | [OBS-RE] |
| 0x14D6 `FROM_GETMSG` | BYTE | Which entry point the shared code is serving: `PREGETMSG` and `handle_found` set 1, `PREPUTMSG` sets 0; `PREINSMSG` compares `== 1`; `CHECK_DBCS` tests `!= 0` before copying the country pair to object 5. | `PREGETMSG` (#384), `PREPUTMSG` (#383), `PREINSMSG` (#385), `handle_found`, `CHECK_DBCS` | 0 | **A mode flag shared by three ordinals with no lock between them** - #384's path holds `GetFSRamSem`, #383's holds `PutFSRamSem`, and #385 reads it under neither that was found. | [OBS-RE] |
| 0x14D7 `DBCS_YES` | BYTE | Whether the current code page is DBCS; `handle_found` sets it from `ah` (producing call not traced); `PREINSMSG` compares `== 1`. | `handle_found`, `PREINSMSG` -> #385 | 0 | as above | [OBS-RE] |
| 0x14D8 | 6 bytes `"DPATH"` | The environment variable message files are searched along (`OPEN_DPATH`'s `DosSearchPath(7, "DPATH", ...)`). | `OPEN_DPATH` (#384) | image | read-only | [OBS-RE] |
| 0x14DE `GetFSRamSem` | 14 bytes, fast-safe RAM semaphore (leading WORD 0x000E) | **The message-get bracket's lock** - requested once, in `FIND_FILE`; cleared at seven sites. Per process. | `FIND_FILE` (request); `CLEAN_UP`, `DOSCLOSEMESSAGEFILE` #649, `c_filename_strip`, `c_FIND_FILE` (clears) | **image WORD 0x000E**, rest 0 | it **is** the lock | [OBS-RE]; `FSRST` [DOC-IBM] DDK `sem.inc` |
| 0x14EC | WORD | **The cache cursor** - offset of the current last `SAVED` entry. `check_room_to_save` adds 0x141 to address that entry's link field; `resiz_ok` advances it. | `check_room_to_save`, `resiz_ok` (#384) | **image 0x14F0** - points at the static entry | under `GetFSRamSem` | [OBS-RE] |
| 0x14EE `SAVED_COUNT` | WORD | Number of cached open message files. `ROOM_FOR_1` increments it; `CHK_MSG_FILE` uses it as the walk's loop count; `CLOSE_SAVED_FILES` and `DOSCLOSEMESSAGEFILE` tear the chain down with `DosClose`. | `ROOM_FOR_1`, `CHK_MSG_FILE`, `CLOSE_SAVED_FILES`, `DOSCLOSEMESSAGEFILE` #649 | 0 | under `GetFSRamSem` | [OBS-RE] |
| 0x14F0 `SAVED` | one 0x143-byte entry, +0x14F0..+0x1632; +0x1633..+0x163F slack (no access found) | The head of the open-message-file cache. Entries 2..n are appended by growing object 6. Whether an entry is ever reused rather than appended is not established. | `CHK_MSG_FILE`, `ROOM_FOR_1`, `savesub`, `check_room_to_save`, `resiz_ok`, `CLOSE_SAVED_FILES` - #384 and #649 | 0 | under `GetFSRamSem` | [OBS-RE] reader + writer |
| 0x1640 | 80 bytes (0x50), +0x1640..+0x168F | **Not part of `SAVED`** - an 80-byte work buffer on the **put-message** path: `PREPUTMSG` does `lea di,[0x1640]` then sets a length of 0x50; `POSTPUTMSG` uses it twice. Ends exactly at D7's `RESULT`. Its content is not established. | `PREPUTMSG`, `POSTPUTMSG` -> #383 | 0 | under `PutFSRamSem` | [OBS-RE] |

**Locking, D6.** The message subsystem's locking is the least coherent in object 6 `[OBS-RE]`:
`FROM_GETMSG` is a mode flag three ordinals share across two different per-process brackets, and
`CHECK_DBCS` writes two **shared** object-5 cells (obj5+0x250/+0x25A) under the **per-process**
`PutFSRamSem`.

**Not established (D6):** the content of the 80 bytes at +0x1640 (`POSTPUTMSG`'s two sites not read);
the producing call behind `DBCS_YES`; whether a `SAVED` entry is ever reused.

---

### Group D7 - `RESULT`, the put-message lock, the `DosSMSetTitle` latch, the UniThunk runtime state (+0x1690..+0x16BB)

**The put path mirrors the get path** `[OBS-RE]`. `PutFSRamSem` has one request, in `DOSPUTMESSAGE`
(`1C0397C7` -> `call 0xe01e:0x60`), and a clear in `PREPUTMSG` (`1C039867` -> `e01e:0x1cd`). The SMP map
puts `DOSPUTMESSAGE` at obj3+0x97A0 with `PREPUTMSG` +0x97D4, `POSTPUTMSG` +0x987D, `CHK_LEAD_BYTE`
+0x9BA1 and `CHECK_DBCS` +0x9BD1 all before `DOSIQUERYMESSAGECP` +0x9C30 - so they are labels inside
#383, and the whole put path runs in one per-process bracket.

| cell | bracket |
|---|---|
| +0x1690 `RESULT` | `PutFSRamSem` (`POSTPUTMSG` is inside #383) |
| +0x1692 `PutFSRamSem` | is the bracket |
| +0x16A0 | neither - `DosSMSetTitle` #690 takes no message semaphore |
| +0x16A4/+0x16A7/+0x16A8/+0x16AC | neither - 32-bit UniThunk runtime, which uses an atomic `xchg` |
| +0x16B0 | neither - `LOGOPEN` #430 |

| offset + IBM name | size / type | meaning | routines -> ordinal | initial value | concurrency | prov |
|---|---|---|---|---|---|---|
| 0x1690 `RESULT` | WORD | **The byte-count out-parameter of the message write.** `POSTPUTMSG` does `lea bx,[0x1690]`, checks its own CPL (`mov ax,cs / and ax,3 / cmp ax,3`), calls `0xe026:0x210` = `Do_Write` (exact symbol start), and on rc 0 does `cmp [es:0x1690],cx` - a short-write check against the requested length; rc 0x13 (19, `ERROR_WRITE_PROTECT`) takes the same exit. | `POSTPUTMSG` -> #383 `DosPutMessage` | 0; per write | under `PutFSRamSem` | [OBS-RE] |
| 0x1692 `PutFSRamSem` | 14 bytes, fast-safe RAM semaphore (leading WORD 0x000E) | **The message-put bracket's lock** (`980F:1692`). While holding it, `CHECK_DBCS` writes two shared object-5 cells (+0x250/+0x25A). | request `DOSPUTMESSAGE` #383; clear `PREPUTMSG` | **image WORD 0x000E**, rest 0 | it **is** the lock | [OBS-RE]; `FSRST` [DOC-IBM] DDK `sem.inc` |
| 0x16A0 | WORD | **A per-process once-latch for `DosSMSetTitle`.** The routine first tests obj5+0xBD8; if zero it returns doing nothing. Otherwise it reads `[es:0x16a0]`: non-zero => skip the first-time setup; zero => do it, set the cell to 1, and `push dword [bp+6] / call far [0xbd6]` - an indirect far call through obj5+0xBD6 (`WinSetTitle`'s cell, object 5 group 6). Object 5 holds the callback and its guard; object 6 the per-process "already initialised" bit. What the first-time setup does (`1C03CB9A`..`1C03CBAF`) is not established. | `DOSSMSETTITLE` -> #690 | 0 | **No lock** - a plain test-and-set. | [OBS-RE] |
| 0x16A4 `ulThunkAppType` | DWORD; its top byte at +0x16A7 is used separately | The 32-bit UniThunk runtime's app-type/flags word. `UT_AllocTLM` ORs bit 0x1 into +0x16A7 when the TIB field at `FS:0x1C` is zero; `UT_RogueStack`, `UT_SystemStack` and `UT_UserStack` test or XOR the same byte. No writer of the full DWORD is found. | `UT_AllocTLM`, `UT_RogueStack`, `UT_SystemStack`, `UT_UserStack` (32-bit, flat) - internal, no ordinal | 0 | no lock on the byte | [OBS-RE] |
| 0x16A8 `pThunkTLM` (`_pThunkTLM`) | DWORD pointer | **The per-process thunk Thread-Local-Memory pointer.** `UT_AllocTLM` calls `DOS32ALLOCMEM(_pThunkTLM, 0xF000, 0x53)`, stamps the block's +0xEFC8 with the ASCII signature `'Thun''kTIB'` (`0x6E756854`/`0x4249546B`), copies `FS:[0xC]`'s target into +0xEFE4, and stores the block through `*_pThunkTLM`. The exception dispatcher reads it too: `_xcptVerifyRegistrationRecord` and `_xcptCheckPrevRegistrationRecord` bound registration records against it. | `UT_AllocTLM`, `UT_AllocTS`, `UT_InitTS`, `UT_HaveFS`, `_xcptVerifyRegistrationRecord`, `_xcptCheckPrevRegistrationRecord` | 0; on first thunk use | unguarded | [OBS-RE] |
| 0x16AC `pThunkStacks` | DWORD pointer | **Head of the chain of allocated thunk blocks**, linked through each block's +0xEFE0. `UT_AllocTS` pushes with `xchg eax,[0x130116ac]` (an atomic push); `UT_InitTLM` reads it (`mov esi,[dword 0x130116ac]` at obj2+0x71C0). | `UT_AllocTS` (push), `UT_InitTLM` (read) | 0 | **`xchg` atomic**, not a semaphore | [OBS-RE] |
| 0x16B0 | 5 bytes `"LOG$"` | The system error-log device name - a second copy (D3's +0x11F8 is the 16-bit `DOSLOGREGISTER`'s). Pushed by the **32-bit** `LOGOPEN` (`push dword 0x130116b0`). | `LOGOPEN` -> #430 | image | read-only | [OBS-RE] |
| 0x16B5..0x16B7 | 3 bytes | Slack; no access found. | - | 0 | - | [unverified] |
| 0x16B8 | 4 bytes | **The text JIT daemon's third buffer** (D8): `_JITDispatcherThread` stores its address into +0x16CC (`mov dword [0x130116cc],0x130116b8`). Beyond its image value and that role, what it holds is not established. | `_JITDispatcherThread` (32-bit, flat) | **image 0x20** | none found | [OBS-RE] |

**Not established (D7):** a writer of `ulThunkAppType` as a DWORD; what `DosSMSetTitle`'s first-time
setup does; `Do_Write`'s own contract (obj4+0x210) beyond its out-parameter and the two accepted return
codes.

---

### Group D8 - the JIT (just-in-time **debugger**) block (+0x16BC..+0x1D1F)

**The entire block is 32-bit-only state** `[OBS-RE]`: no 16-bit code in DOSCALL1 touches it by
displacement (the one segment-relative hit, `add [0x17b8],bl` at obj4+0x8579, is data disassembled as
code); 24 flat sites in 3 routines.

**How the daemons start** `[OBS-RE]`:
- `JIT16to32Call` is six bytes - obj2+0x70EC `call 0x1c029a10 / retf` - and `InitDOSCALL1` reaches it
  with `call dword 0x5b:0x1c0270ec` (`1C040112`), inside its once-per-system block, and only if
  `DosScanEnv("NOJIT")` (the name at obj5+0x16) finds nothing.
- `JITInit` creates a thread: `push 0x1000 / push 0 / push 0 / push 0x1c0295c8 (_JITDispatcherThread)
  / push 0x13011dac (&_JITDaemonTid) / call <rel32>`; `JITInit2` is identical for
  `_JITPMDispatcherThread` / `&_JITDaemonTid2`. The call is **DOSCALLS #311**, read from the fixup table
  (`obj2+0x009a27 ... stype=8 ttype=1 -> DOSCALLS.#311`, and the same at +0x009a47): an `E8 00000000`
  import fixup.

**What a JIT session is** `[OBS-RE]`. A JIT session is not started by DOSCALL1. `InitDOSCALL1` only
starts the two daemons, once per system; each daemon then sits on a request packet, launches the named
program with the supplied command line - the PM one through a 60-byte `STARTDATA` for a windowed
session at (30,40) 200x140 - drives it with **`DosDebug` #317**, reports progress, and fills a response
packet. DOSCALL1 hosts the daemons and owns their buffers; **the requester is external** - no writer of
the action packet exists in `DOSCALL1.DLL`, and the module's only `SESMGR` import is used by this
family. The daemons reach `DosExecPgm` #283, `DosDebug` #317, `DosSetPriority` #236,
`DosSystemService` #995 and `SESMGR.#37`; which call is on which daemon is not split.

**The two daemons share the two big buffers and differ only in a third** `[OBS-RE]`:

| daemon | packet-pointer block | -> `PgmName` | -> `PgmInputs` | third buffer |
|---|---|---|---|---|
| `_JITDispatcherThread` (text) | +0x16BC...+0x16D4 | `[+0x16C4] = 0x130116EC` | `[+0x16C8] = 0x130117EC` | `[+0x16CC] = 0x130116B8` |
| `_JITPMDispatcherThread` (PM) | +0x18EC...+0x1904 | `[+0x18F4] = 0x130116EC` | `[+0x18F8] = 0x130117EC` | `[+0x18FC] = 0x1301191A` |

+0x16B8 (image 0x20) is the text daemon's third buffer, and +0x191A (also image 0x20) is its PM twin.

| offset + IBM name | size / type | meaning | routines -> ordinal | initial value | concurrency | prov |
|---|---|---|---|---|---|---|
| 0x16BC `_JITRespPacketPtr` | DWORD, head of a ~0x18-byte block (+0x16BC/+0x16C0/+0x16C4/+0x16C8/+0x16CC) | The **text daemon's outbound response-packet** pointer and the pointer block beside it. `[+0x16C4]`/`[+0x16C8]`/`[+0x16CC]` are set to the two shared buffers and the text third buffer before the loop; `[+0x16C8]` is also tested against 0 as a have-input check. | `_JITDispatcherThread` (internal) | 0; by the daemon at start-up | none found - one daemon owns each block | [OBS-RE] |
| 0x16D4 `_JITActionPacketPtr` | DWORD | The text daemon's **inbound request-packet** pointer; its address is pushed (`push dword 0x130116d4`) to whatever supplies the request. | `_JITDispatcherThread` | 0 | - | [OBS-RE] |
| 0x16EC `_JITPgmNameBytes` | 256 bytes | The program to launch; `STARTDATA.PgmTitle` and `.PgmName` both point here. | both daemons | 0; per request | **Shared by both daemons with no lock.** Whether a text and a PM request can be in flight at once is not established; if they can, the design races `[INF]`. | [OBS-RE] |
| 0x17EC `_JITPgmInputsBytes` | 256 bytes | Its command line - `STARTDATA.PgmInputs`. | both daemons | 0; per request | as above | [OBS-RE] |
| 0x18EC `_JITRespPacketPtr2` | DWORD, block +0x18EC/+0x18F4/+0x18F8/+0x18FC/+0x1900 | The **PM daemon's** response-packet pointer and its pointer block; +0x1900 is read as a WORD (the only sub-DWORD field in either block). | `_JITPMDispatcherThread` | 0 | none found | [OBS-RE] |
| 0x1904 `_JITActionPacketPtr2` | DWORD; real extent ~0x1C bytes, not the 0x4A8 the `.SYM` span implies | The PM daemon's request-packet pointer. | `_JITPMDispatcherThread` | 0 | - | [OBS-RE] |
| 0x191A | 4 bytes | The PM daemon's third buffer (`[+0x18FC] = 0x1301191A`). | `_JITPMDispatcherThread` | **image 0x20** | - | [OBS-RE] |
| 0x1920..0x193B | ~28 bytes | **Not JIT** - `VDMSTARTSESSION` state inside `_JITActionPacketPtr2`'s nominal span: +0x1924 is set to `0x13011928` (a self-pointer), +0x1928 takes `DOS32STARTSESSION`'s return, +0x192C/+0x192E/+0x1938 are pushed to it, +0x1932 a byte, +0x1934 a DWORD. | `VDMSTARTSESSION` (D9) | 0 | - | [OBS-RE] |
| 0x193C..0x1D1F | 996 bytes | No access under either segment-relative or flat scan; most likely the packets' own storage, reached only through the pointers above `[INF]`. | - | 0 | - | [unverified] |

**Initialisation and locking, D8.** This is the one group in object 6 whose initialiser runs **once per
system, not once per process**: `InitDOSCALL1`'s JIT call sits in the once-per-system block (object 5's
+0x14 latch), so in a second process the daemons are not re-created, yet object 6 is INSTANCE, so that
process's copy of every cell above stays zero. **The state and the threads live in different
processes**; only the process that won the once-per-system race has a populated block `[OBS-RE]`
(`INITDOSCALL1` loads DS=0x9807, and the JIT call at `1C040112` sits between `1C0400C6 cmp byte [0x14],0
/ jnz` and `1C040143 mov byte [0x14],1`; `pTLMA0`, by contrast, is written at `1C040054`, above the
guard, so it is per process). No semaphore call appears in either daemon.

**Not established (D8):** the action/response packet layouts and who writes them (not recoverable from
this binary; the external requester's first lead is the `SESMGR` import); the 996 bytes at
+0x193C..+0x1D1F; what +0x16B8/+0x191A hold beyond image 0x20; the per-daemon split of the service calls.

---

### Group D9 - the VDM-start rendezvous, two cached selectors, the MMIO performance-trace pointers (+0x1D20..+0x1DBF)

**+0x1D70..+0x1D85 is a trace emitter, not a device block** `[OBS-RE]` (`DOSLOGREGISTER`,
`1C04DF91..1C04DFE9`, read whole):

```
ax = [0x1d72]; or ax,[0x1d70]      ; lazy-init test on the far pointer
jnz built
  es = [0x1d50]                    ; the cached obj5 selector
  ax = [es:0x0]                    ; obj5+0x00 = globalIS
  [0x1d72] = ax ; [0x1d70] = 0     ; far pointer = GlobalInfoSeg : 0
built:
les bx,[0x1d70] ; bx += 0x52       ; -> GIS+0x52
[0x1d82] = bx ; [0x1d84] = es      ; second far pointer, saved
test byte [es:bx],0x40             ; GIS+0x52
test byte [es:bx+3],0x8            ; GIS+0x55
  bx = [0x1d70] (=0)
  ax = [es:bx+0x4a]                ; GIS+0x4A
  [0x1d76] = ax ; [0x1d74] = 4     ; third far pointer, <that selector> : 4
  les bx,[0x1d74] ; [es:bx] = 0x1c08
```

GIS+0x4A is `SIS_MMIOBase` ("memory-mapped-I/O selector") and GIS+0x52 is `SIS_perf_mec_table[32]`, the
performance MEC table `[DOC-IBM]` DDK `base/h/infoseg.h`. So the sequence caches a far pointer to the
Global InfoSeg, caches a second to its perf-MEC table, tests two MEC enable bits, and if both are set
writes the event word **0x1C08** into the MMIO segment at offset 4. This is the same perf-MEC-gate ->
`SIS_MMIOBase` write shape as the SMP-only MMIO trace in the keyboard/mouse router (object 7), reached
here from `DosLogRegister`/`DosLogRead` - a DOSCALL1-wide instrumentation pattern `[OBS-RE]`. What event
0x1C08 denotes, and which MEC bits GIS+0x52 bit 0x40 and GIS+0x55 bit 0x08 are, is not established.

| offset + IBM name | size / type | meaning | routines -> ordinal | initial value | concurrency | prov |
|---|---|---|---|---|---|---|
| 0x1D20..0x1D27 | 8 bytes | Slack. | - | 0 | - | [unverified] |
| 0x1D28 | ASCIIZ `"\SEM32\VDMSTART\DONE"`, 21 bytes | The **named event semaphore** the VDM start path rendezvouses on. | `VDMSTARTSESSION` (32-bit, flat) | image string | read-only | [OBS-RE] |
| 0x1D3D | DWORD `HEV`, unaligned (immediately after the string) | Its handle. `VDMSTARTSESSION` does `push fState / push flAttr / push &0x1D3D / push &0x1D28 / call DOS32CREATEEVENTSEM` (`0x1c020988`, exact symbol; `add esp,0x10` = 4 arguments, matching `DosCreateEventSem(pszName, phev, flAttr, fState)`), and after `DOS32STARTSESSION` returns, `mov eax,[0x1D3D] / push / call DOS32POSTEVENTSEM` (`0x1c0208d8`). | `VDMSTARTSESSION` - internal, no ordinal; between `DosCreateEventSem` #324 and `DosStartSession` | 0; created on the first VDM start | **It is the synchronisation** - a named system semaphore, so this one coordinates **across processes**; the cell holding its handle is per process. | [OBS-RE] |
| 0x1D50 | WORD SEL, `stype=2` fixup -> obj5 (SMP) | A cached copy of **object 5's selector**, so 16-bit code can reach object 5 without a literal; read only to get `globalIS` from obj5+0x00. In UNI the fixup at this offset targets object 11. | `DOSLOGREGISTER` #195, `DOSLOGREAD` #196 | **loader fixup** (image 0x9807) | read-only | [OBS-RE] |
| 0x1D60 | WORD SEL, `stype=2` fixup -> obj11 (SMP only; UNI has no fixup here) | A cached copy of **object 11's selector** (`_SpawnData`, 48 bytes, INSTANCE), the FSD-daemon thread handoff block. `STARTFSDDAEMONS` loads ES from it and zeroes obj11+0x0C/+0x0E (`bx = 0x0C` at `1C03F3B0`); `SPAWNEDTHREAD` reads `[es:0]`, `[es:4]`, `[es:6]`, `[es:8]`, `[es:0xa]` and the ASCIIZ at `[es:0x10]`. | `STARTFSDDAEMONS` x2, `SPAWNEDTHREAD` (D4's routines, no ordinal) | **loader fixup** (image 0x9837) | none - the guard is D4's `_InitializedAlready` | [OBS-RE] |
| 0x1D70 / 0x1D72 | far pointer (offset / selector) | **`GlobalInfoSeg : 0`**, built lazily once per process from `[obj5+0x00]`. The pair being zero is the "not yet built" test. | `DOSLOGREGISTER` #195, `DOSLOGREAD` #196 | 0; lazily on first call | **unguarded test-and-set** | [OBS-RE] |
| 0x1D74 / 0x1D76 | far pointer (offset 4 / selector) | **`SIS_MMIOBase : 4`** - the MMIO trace window; offset is the literal 4, selector read from GIS+0x4A. | same | 0; built when the MEC bits are set | as above | [OBS-RE]; `SIS_MMIOBase` [DOC-IBM] `infoseg.h` |
| 0x1D82 / 0x1D84 | far pointer | **`GIS + 0x52`** = `SIS_perf_mec_table`, saved so the enable bits can be re-tested without recomputing. | same | 0 | as above | [OBS-RE]; `SIS_perf_mec_table` [DOC-IBM] `infoseg.h` |
| 0x1D86..0x1DAB | 38 bytes | No access under either scan. | - | 0 | - | [unverified] |
| 0x1DAC `_JITDaemonTid` / 0x1DB0 `_JITDaemonTid2` | 2 x DWORD | TIDs of the two JIT dispatcher threads: `JITInit` pushes `&+0x1DAC` and `JITInit2` `&+0x1DB0`, each as the TID out-parameter of the thread create that starts `_JITDispatcherThread`/`_JITPMDispatcherThread`. UNI offsets are 0x30 lower (+0x1D7C). | `JITInit`, `JITInit2` (32-bit, flat) | 0; at JIT init (once per system) | none found | [OBS-RE] |
| 0x1DB4..0x1DBF | 12 bytes | Slack to `_ENDDATA16` (+0x1DC0). SMP-only: UNI's `_ENDDATA16` is +0x1D90. | - | 0 | - | [unverified] |

**Initialisation and locking, D9.** Three initialisers, only one of them code: +0x1D50 and +0x1D60 are
loader fixups; +0x1D28 is an image string; everything else is lazy, on first use, per process. No
semaphore is taken anywhere in this group - `DOSLOGREGISTER` and `DOSLOGREAD` make no call to any of the
four semaphore gates - and the GIS-pointer build is a plain unguarded test-and-set. `VDMSTARTSESSION`'s
own ordinal is not established; it is reached from the VDM path, not exported under that name.

---

### Object 6 - summary

| G | span | what it is | owning ordinals |
|---|---|---|---|
| D0 | +0x0000..+0x1043 | `Init32Entry`'s private 16-bit init stack (4 KB), a WORD ring, `"PATH"` | `DosReadAsync` #149 (ring); `DosExecPgm` #144 (`"PATH"`) |
| D1 | +0x1044..+0x116D | Console line input: `STRINGINBUF`, `KBDKEYINFO`, the 254-byte buffer, cursor/end, the KBD/VIO entry vector | `DosRead` #137; `DosQueryFHState` #276, `DosProtectRead` #641, `DosProtectQueryFHState` #645; 32-bit `DOS32READ`, `DOS32PROTECTREAD` (flat) |
| D2 | +0x116E..+0x11CF | The 25-word `DosSearchPath` error lists, `pTLMA0`, the three arena fences, the thunk-block list head | `DosSearchPath` #151 / #228; `DosFlatToSel` / `DosSelToFlat`; `DosQueryAppType` #163/#323; `THK32ALLOCBLOCK`/`THK32FREEBLOCK` |
| D3 | +0x11D0..+0x125F | Device/pipe name strings, the NLS record cache, the segment allocator's lock and cursor | #391, #392, #393, #394; `DosCopy` #201; `DosLogRegister` #195 |
| D4 | +0x1260..+0x1281 | C runtime marker, FSD-daemon guards, **export 414 `_QUEINST_DATA`** | the IPC queue family #674-#681 |
| D5 | +0x1282..+0x14C1 | `MKMSGF` signature, `FILECOUNTRYINFO` (302 B), the 260-byte path buffer, a 3-byte in-place save slot | `DosTrueGetMessage` #384 |
| D6 | +0x14C2..+0x168F | Message defaults, country/DBCS cells, `GetFSRamSem`, the `SAVED` open-file cache, the put path's 80-byte buffer | #384, `DosCloseMessageFile` #649, `DosPutMessage` #383, `DosInsMessage` #385 |
| D7 | +0x1690..+0x16BB | `RESULT`, `PutFSRamSem`, the `DosSMSetTitle` once-latch, UniThunk runtime state | #383; `DosSMSetTitle` #690; `LogOpen` #430; `UT_*`/`_xcpt*` (internal) |
| D8 | +0x16BC..+0x1D1F | The JIT **debugger** block: two daemons' packet pointers, program-name and command-line buffers | internal daemons; reach `DosExecPgm` #283, `DosDebug` #317 |
| D9 | +0x1D20..+0x1DBF | `"\SEM32\VDMSTART\DONE"` + its HEV, cached obj5/obj11 selectors, the MMIO perf-trace pointers, JIT TIDs | `DosLogRegister` #195, `DosLogRead` #196; `VDMSTARTSESSION` (internal) |

**Per-process concurrency** `[OBS-RE]`. Four semaphore brackets, all per process (object 6 is INSTANCE,
so each serialises threads of one process and nothing else):

| semaphore | bracket | request site |
|---|---|---|
| `GetFSRamSem` +0x14DE | the whole message **get** path - search, `SAVED` walk, open, header read, country-info read | `FIND_FILE`, one site, inside #384 |
| `PutFSRamSem` +0x1692 | the whole message **put** path | `DOSPUTMESSAGE` #383, one site |
| `_iCache_sem` +0x1224 | the NLS record cache | `_cache_table`, via `DosSemRequest` (plain RAM-semaphore family) |
| `_FSRam_Sem` +0x1228 | segment growth only - two sites, both in `REALLOCSEG` | `REALLOCSEG` |

Nesting: `_iCache_sem` **outside** `_FSRam_Sem` (D3), and `GetFSRamSem` **outside** `_FSRam_Sem` (D6) -
the allocator's lock is innermost because its two consumers arrive by different routes. **Two lock-free
`xchg` structures**: `pThunkStacks` (+0x16AC) and the thunk-block list head (+0x11C0/+0x11C4).
**Unguarded test-and-sets, five:** `_InitializedAlready`, `_FuncInit`'s `[bx+2]` and `[bx+6]` (D4), the
`DosSMSetTitle` latch (D7), the GIS-pointer build (D9). **One genuinely cross-process object:** the named
event semaphore `"\SEM32\VDMSTART\DONE"`, whose HEV is at +0x1D3D. DOSCALL1 locks shared state and leaves
instance state unserialised.

**Per-process initialisation** `[OBS-RE]`:
- **Loader fixups** - no instruction writes these: D1's two `stype=7` flat pointers (+0x1152/+0x1156 ->
  +0x1052) and four `stype=2` vector selectors (+0x115C...+0x1168 -> obj4); D3's `_iNLS_Sem` selector
  (+0x1222 -> obj6); D9's +0x1D50 -> obj5 and +0x1D60 -> obj11.
- **Image values** - the strings, the error lists, `SIGNATURE_MSGF`, the three 0x000E semaphore lengths,
  the ring pointers, `_iSize`, the `SAVED` cursor, the LF byte, the two JIT third buffers.
- **Lazy on first use** - `_FuncInit`'s queue record (first queue call), the NLS cache, the `SAVED`
  cache, D9's GIS/MMIO pointers, D7's thunk TLM.
- **Once per process by `InitDOSCALL1`** - `pTLMA0` and the three fence pairs.
- **Once per system, over instance state** - the whole of D8 (the JIT daemons and their working set).

**Cells whose meaning requires a non-zero initial value** `[OBS-RE]`:

| cell | value and why |
|---|---|
| +0x101C / +0x101E ring pointers | both **0x1020** - the empty state; zero is not empty |
| +0x1152 / +0x1156 cursor / end | both -> **+0x1052**; `cursor == end` is the refill condition |
| +0x1151 | **0x0A**, the linefeed `VioWrtTTY` echoes - it exists so the echo has a far address |
| +0x115C...+0x1168 | the four KBD/VIO entry points |
| +0x116C, +0x103C, +0x11B8, +0x11D0...+0x1213, +0x14C2, +0x14D8, +0x11F8, +0x16B0, +0x1D28 | the strings |
| +0x116E...+0x119F | the 25 error codes |
| +0x1220 | far pointer -> +0x1224 |
| +0x1228 / +0x14DE / +0x1692 | each semaphore's leading WORD **0x000E** (its own length) |
| +0x1236 `_iSize` | the object's own current size - the allocator's cursor (0x1DC0 in SMP) |
| +0x1282 | `\xFF"MKMSGF"\x00` |
| +0x14EC | **0x14F0** - points at the static `SAVED` entry; zero would make the first entry unreachable |
| +0x16B8 / +0x191A | 0x20, the two JIT daemons' third buffers |
| +0x1D50 / +0x1D60 | object 5's and object 11's selectors |

**Growth.** Object 6 is not fixed-size. Two consumers grow it through `REALLOCSEG` (the NLS cache and
the `SAVED` cache); the first cached message file does not grow it (it uses the static slot), so a
process that opens exactly one message file never calls `REALLOCSEG` for it. `REALLOCSEG`'s out-pointer
contract (old size written through a caller-supplied far pointer) is what D6's allocate-and-link relies
on `[OBS-RE]`.

**Not established - object 6:** `DosGetMessage`'s ordinal; the 16-bit ordinals of
`DosProtectRead`/`DosQueryFHState`/`DosProtectQueryFHState`; the name of return code 0x74;
`VDMSTARTSESSION`'s ordinal; the JIT action/response packet layouts and who writes them; the MMIO event
word 0x1C08 and the two `SIS_perf_mec_table` bits; the three NLS cache keys' meanings;
`ulThunkAppType`'s DWORD writer; what `end_dpath` splices; the +0x1640 buffer's contents; the
`DosReadAsync` ring's contents; whether the +0x1033 stack and the ring can be live together; and the
byte ranges marked `[unverified]` above.

---

## Object 7 - `OS2CHAR_GROUP` / `BVSGLOBAL` (shared)

| property | value | prov |
|---|---|---|
| LX object | 7 of `DOSCALL1.DLL` | [OBS-RE] |
| group / segment names | `OS2CHAR_GROUP`, `BVSGLOBAL` | [OBS-RE] (`.sym`) |
| SMP link base / size | 0x13020000 / **0x0F24** | [OBS-RE] |
| UNI size | 0x0E66 (3686) | [OBS-RE] |
| sharing | **SHARED** - one copy per system | [OBS-RE] (LX object flags) |
| image selector | 0x9817 | [OBS-RE] |

- **SMP vs UNI layout.** Nothing in either `.sym` is named below +0x0C0. Every symbol from
  `_bms_localinfo` onward sits **+0xBE** later in SMP than in UNI. The difference is entirely four
  **SMP-only** variables - `_mmio_sel`, `_mmio_buffer`, `_mou_mmio_codes` (0x68 bytes),
  `_kbd_mmio_codes` (0x50 bytes), at SMP +0xD64..+0xE21 - which exist only in the SMP `.sym`. They
  are SMP *behaviour*, not just layout: the KBD/MOU router path gains an MMIO trace that the UNI
  build does not have (see G11). [OBS-RE]
- **Object 7 is not addressed from the 32-bit code object.** obj2 carries 12 fixups to object 7,
  all `stype=2` on the immediate of a `mov ax,0x53` in `_PackGEA`, `_UnpackGEA`, `_krn_memmove` and
  the nine ring-3 exception routines (`DOS32R3EXCEPTIONDISPATCHER`, `_xcptR3ExceptionDispatcher`,
  `_xcptUnwindDispatcher`, `_xcptExecuteUserExceptionHandler`, `_xcptR3ExceptionHandler`,
  `_xcptR3UnwindHandler`, `_xcptGPFDefaultAction`, `_xcptVerifyRegistrationRecord`,
  `_xcptCheckPrevRegistrationRecord`), each followed by `mov ds,eax / mov es,eax`. In
  `_xcptR3ExceptionHandler` (1C02A330..A362) every DS access is through a caller-supplied 32-bit
  pointer (`[eax+0x4]`, `[ecx+0x8]`, `mov [eax],ecx`) and none is a constant displacement into a
  0xF24-byte segment, so no object-7 cell is named from 32-bit code. No flat `0x1302xxxx` operand
  occurs in obj2. [OBS-RE] What selector the loader actually supplies for those 12 fixups is not
  established.
- **How 16-bit code reaches object 7.** The literal `0x9817` occurs 262 times in the SMP code (257 in
  obj4, 3 in obj3). Most object-7 access is **not** through that literal: BVS/VIO/KBD/MOU code loads
  `ES` from a cached selector slot in G0 (`mov es,[0x18]`). Some routines load it through another
  register (`mov bx,0x9817 / mov es,bx` in `VIOSHELLINIT`). Routines with the most literal loads:
  `VREADENVVARS` 12, `viorout` 11, `UINITGENERICVDH` 9, `BVSDINIT` 8, `VIOREGISTER`/`VIOPOPUP` 6,
  `ROUTPROCESSINIT` 5. [OBS-RE]
- **Offsets that collide with object 8.** Many VIO routines run with **DS = object 8**
  (`mov ax,0x981f / mov ds,ax`), so a DS-relative operand there is an object-8 cell even where its
  offset falls in an object-7 group. Likewise an `[es:...]` operand is object 7 or object 8 according
  to which G0 slot ES was loaded from (a `0x981F` slot makes it object 8, e.g. slot +0x50 in `ROUTER`).
  [OBS-RE]
- **Object 7 grows at run time** - `PCHGROWGLOBAL` reallocates it (see G7 and queued trace 1).
  [OBS-RE]

### Group map

| group | span (SMP) | contents | owning routines |
|---|---|---|---|
| G0 | +0x000..+0x0BF | cached-selector slot table: WORD slots holding `0x9817` (obj7) or `0x981F` (obj8) | every obj4 BVS/VIO/KBD/MOU routine that does `mov es,[slot]`; `ROUTER` `mov es,[0x50]` |
| G1 | +0x0C0..+0x103 | SGCB registry (`SMQueueRamSem` +0xC0, `SMArray` +0xCE, `SMPIDArray` +0xD2, `SMArraySize` +0xD6, `SMInitialized` +0xD7 = exports 858/859/860/862/861), `MemorySegments`/`SegmentSizes` +0xD8..+0xEF, the `kill*` block +0xF0..+0xF9, `Ggvs_*`/`dirty` +0xFA..+0x103 | #684 `DOSSMGETSGCB`, #685 `DOSSMINITSGCB`, `DOSSMADDSGCB`/`DOSSMDELSGCB`, #703, `VIOHETINIT`, `SSGETSGCB` |
| G2 (+G6) | +0x104..+0x1A9, +0x8B6..+0x8F3 | popup / shell-init / print-screen scalars; `hPopXBlockSem` + its name, `WndwConfig` | `VIOPOPUP`/`VIOENDPOPUP`, `VIOSHELLINIT` (#822), `VIOSETCP`, `VIOHETINIT`, `VIOINITSESSION`, `AVS_PRTSC`, `VIOSAVREDRAWWAIT`, `InitConfig` |
| G3 | +0x1AA..+0x35F | VIO registration masks + `map_*` function-code table | `VIOREGISTER`/`VIODEREGISTER`/`VIOREGEXIT`, `viorout`, `ROUTER` |
| G4 | +0x360..+0x4B5 | `bvsgdata` (export 863) | `BVSGLOBALINIT`, `BVSDINIT`, `GetBVSCB`, `BvsInit`, `VIOPRTSC`/`AVS_PRTSC`, `VIOINITPROCESS` |
| G5 | +0x4B6..+0x8B5 | `bvsgSelTable`, 0x400 bytes | `GetBVSCB`, `TrackSellist`, `BvsFree`, `VIOSRFBLOCK`/`UNBLOCK` |
| G7 | +0x8F4..+0xAC3 | video-handler / device tables | #822 chain -> `BVSDINIT`, `BVSGETVIDEOCALLTABLES`, `UINITGENERICVDH`, `VREADENVVARS`, `VGETTAGVALUE`, `FISPOWERUP`, `FISDEVICEDRIVER`, `DOSLOADVIDEOHANDLER`/`DOSUNLOADVIDEOHANDLER`, `ULOADWINTHORNVDH`, `PCHGROWGLOBAL`, `UGROWDEVGROUP`, `VFREEDEVTABLEENTRY` |
| G8 | +0xAC4..+0xC15 | VIO code page / modes / ANSI, `SysModes` | `VIOSETCP`/`VIOGETCP`, `BvsSetMode`, `VIOWRTTTY`/`VDHWRTTTY`, `VIOSHIELDINIT`/`TERM` |
| G9 | +0xC16..+0xC5D | keyboard shield import vector (PMVIOP entry points bound at run time) + `Shield_DLL` | `VIOSHIELDINIT`, keyboard shield routines, `_KBDBASESUBSYS` |
| G10 | +0xC5E..+0xD13 | keyboard code page / translate | `KBDSETCP`/`KBDGETCP`/`KBDXLATE`/`KBDSETCUSTXT` |
| G11 | +0xD14..+0xE21 | KBD/MOU router base, SMP-only `_mmio_*` block | `ROUTSMINIT`, `ROUTPROCESSINIT`, `ROUTER`, `_KBDBASESUBSYS`/`_MOUBASESUBSYS`/`_CHARINBASESUBSYS`/`_STRINGINBASESUBSYS`/`_GETFOCUS*`/`_FREEFOCUS*` |
| G12 | +0xE22..+0xF23 | base mouse subsystem (BMS), its dispatch tables, the mouse shield | `MOUSEOPEN`, `BMS_SET_POINTER_DRAW`, the `Mou*` base entries |

All spans and owners [OBS-RE] (`.sym` names and the code that addresses them). G6 is described
with G2.

---

### G0 - the cached-selector slot table (+0x000..+0x0BF)

**What a slot is.** A WORD holding a **segment selector for one of DOSCALL1's own data objects**,
written by the LX loader through an internal fixup (`stype=2`, `ttype=0`, target `obj7+0x0` or
`obj8+0x0`); the image bytes are the link-time values of those same selectors. 16-bit code with
DS = obj7 loads ES from a slot (`mov es,[0x18]`) instead of `mov ax,SEG / mov es,ax`. Slots are laid
out in **code order of the routines that use them** (BVS init chain first, then the KBD/MOU router,
then the base mouse subsystem), several routines sharing a slot where they are adjacent.
[OBS-RE] It is plausibly a per-source-module segment-reference table emitted by IBM's toolchain, like
the slot table in object 5 [INF]; no IBM document on it is known. It carries **no OS/2 state**: no
store to the table exists in any code object, and its content is a pure function of which object
each code site addresses. [OBS-RE] for the absence of writers in the non-indexed listing and of
register-relative stores below 0xC0; stores through an inherited DS or through ES loaded by a callee
are not covered by that search.

| offset (SMP) | size/type | what it is | readers -> owning ordinals | initialiser | prov |
|---|---|---|---|---|---|
| +0x000..+0x03F | WORD selector x32; obj8 at +0x26, +0x2A, +0x32, +0x34, obj7 elsewhere | slots for the **video-handler / BVS init chain** | `BVSDINIT`, `BVSGLOBALINIT`, `VREADENVVARS`, `BVSGETVIDEOCALLTABLES`, `UINITGENERICVDH`, `ULOADWINTHORNVDH`, `DOSLOADVIDEOHANDLER`, `DOSDRIVERENABLE`, `FADDDEVICE`, `FFINDDEVICE`, `FHASADDRESSABILITY`, `FMAKEDEVADDRESSABLE`, `FGETFREECALLTABLE`, `FGETFREEDEVTABLEENTRY`, `PCHGROWGLOBAL`, `UGROWDEVGROUP` -> **#845 `BVSMAIN`** (via `BVSDINIT`, `BVSGETVIDEOCALLTABLES`; and #822's chain), **#847 `BVSGETPTRDRAWNAME`**; also `Init_CP` (+0x00/+0x02) and `Search_CP` (+0x10) <- `SetCodepage` <- `KBDGETCP` #747, `KBDFLUSHBUFFER` #757 | loader fixup; object is SHARED so the one copy is set once per system [INF on who applies it] | [OBS-RE] bytes + fixups + readers |
| +0x040..+0x043 | WORD selector x2, both obj8 | temp-buffer slots | `FGETTEMPBUF`, `VFREETEMPBUF`, `FINITTEMPBUFS`, `VRELEASETEMPBUFS` -> reached from the #845/#847 chain via `DOSLOADVIDEOHANDLER`/`VREADENVVARS` | as above | [OBS-RE] |
| +0x044..+0x04F | 12 zero bytes | **no fixup, no reader** in obj2/3/4 (the `mov si,0x4e` in `ClearScreen`/`BvsSetMode` is a CS-relative table index for `call [cs:si+0x6f4d]`, not a read); whether padding or six slots whose users were removed is not established | - | zero in image | [OBS-RE] (absence) |
| +0x050..+0x07F | WORD selector x24; obj8 at +0x50..+0x62, +0x6C, +0x74, +0x78, +0x7A; obj7 at +0x64..+0x6A, +0x6E..+0x72, +0x76, +0x7C, +0x7E | slots for the **KBD/MOU router** | `ROUTER`, `KBDCHARIN` #748, `KBDSTRINGIN` #753, `KBDFREEFOCUS` #762, `KBDGETFOCUS` #756, `KBDREGISTER` #752, `KBDDEREGISTER` #764, `KBDSETFGND` #765, `KBDSWITCHFGND` #759, `KBDSYNCH` #751, `MOUREGISTER` #741, `MOUDEREGISTER` #731, `MOUSYNCH` #740, `MOUINITREAL` #744, `ROUTSMINIT` <- `KBDSHELLINIT` #760 / `MOUSHELLINIT` #723, `ROUTPROCESSINIT`/`_SessionInit`/`_GlobalInit` <- **#718 `OS2BASEINIT`**, `ROUTEXITLIST` (exit-list routine, no static caller), `_Kbd/_Mou{Get,Clear}Semaphore`, `_Kbd/_MouCheckProcType`, `_Kbd/_MouReloadAltSubSys`; **SMP-only** `_MMIOKBDTrace`/`_MMIOMOUTrace` (+0x66, +0x68, +0x7C, +0x7E) | as above | [OBS-RE] |
| +0x080..+0x0BB | WORD selector x30; obj8 at +0x80..+0x8A, +0x90..+0x9E, +0xA2; obj7 at +0x8C, +0x8E, +0xA0, +0xA4..+0xBA | slots for the **base mouse subsystem (BMS) and mouse shield** | **#852 `BMSMAIN`**, `BMSINIT`/`GLOBALINIT` <- #718, `SGCBINIT` <- `BMSINIT`/#852, `BMSEXITLIST`, `BMSOPEN`, `BMSCLOSE`, `BMSREADEVENTQUE`, `BMSGETSETTHRESHOLD`, `SHLD*` (10 routines). `BMSOPEN`..`SHLD*` have no static caller; they are reached through `BMSMAIN`'s `_FunctionTable` (G12) | as above | [OBS-RE]; the indirect dispatch [INF], settled in G12 |
| +0x0BC..+0x0BF | 4 zero bytes | no fixup, no reader | - | zero | [OBS-RE] |

- **Totals.** SMP: 88 slot fixups (53 -> obj7, 35 -> obj8); 94 slots minus 6 zero slots in the hole.
  UNI: 84 (49 -> obj7, 35 -> obj8), the table ending at UNI +0xB3. Every non-zero slot carries a fixup in
  both builds. UNI and SMP differ from +0x60 on: the 4 extra SMP slots are the `_MMIO*Trace` slots
  (+0x66/+0x68/+0x7C/+0x7E), and UNI's following slots sit 8 bytes lower (UNI +0x78 `BMSMAIN` =
  SMP +0x80). [OBS-RE]
- **Locking:** none, and none needed: no store to the table exists, and the values are selectors of
  objects whose selectors never change for the life of the system. [OBS-RE] / [INF]
- **Not established:** whether any code outside DOSCALL1 reads +0x00..+0xBB (it has no export; the
  first object-7 export is #858 at +0xC0); the DS in force at the 10 slot reads made under a popped or
  inherited DS (e.g. `Init_CP` `push word [0x2]`/`[0x0]` at `1C04B0F6/FA`, `Search_CP`
  `push word [0x10]` at `1C04B1B0`, pushed as a selector argument - obj7 by inference, since `Init_CP`
  loads DS = obj7 elsewhere in its body [INF]).

### G1 - SGCB registry, `DOSSMGETMEM` segments, the kill block, `RamSem_SGID`, `Ggvs`, `dirty` (+0x0C0..+0x103)

Export names `CHRQueueRamSem`, `CHRArray`, `CHRPIDArray`, `CHRArraySize`, `CHRInitialized` (858-862)
are IBM's, from the OS/2 Debugging Handbook [DOC-IBM]; the cells' `.sym` names are given in each row.
Kernel ordinals cited: #5 DOSEXIT, #10 DOSKILLPROCESS, #13 DOSHOLDSIGNAL, #15 DOSFLAGPROCESS, #34
DOSALLOCSEG, #38 DOSREALLOCSEG, #121 DOSGETSEG [DOC] (osFree names). Object 5's `SGCB_*` far pointers
target this group's exported cells. In the VIO routines `VIOSRFBLOCK`, `VIOSRFUNBLOCK`,
`VIOREDRAWSIZE`, `VIOSCRLOCK`, `VIOREGEXIT`, `VIOFREE`, `VIOSSWSWITCH`, `VIOFSRAMEXIT`, `VIOGLOBALREG`,
`VIOHETINIT`, DS is **object 8**, so `viorout`'s DS-relative `[0xd8]`, `[0xe0]`, `[0xe6]`, `[0xea]`,
`[0xf6]` and the `0xd8`/`0xe2`/`0xec` semaphores are object-8 cells, not these. [OBS-RE]

| offset + IBM name | size/type | what it is | routines -> owning ordinals | initial value | concurrency (SMP) | prov |
|---|---|---|---|---|---|---|
| +0x0C0 `SMQueueRamSem` (**export 858**, `CHRQueueRamSem`) | 14 bytes, DOSFSRSEM | Fast-safe semaphore guarding the SGCB registry. First word = **0x000E**, the structure's own length (as for every DOSFSRSEM). | `DOSSMGETSGCB` **#684** request/clear with DS = obj7 (`1C03525A`/`1C0352E3`); via object 5's `SGCB_QueueRamSem`: `DOSSMDELSGCB`, `DOSSMGETSTATUS` **#703**, `DOSSMSGSET` | length word 0x000E required; rest 0; SHARED -> once per system | it IS the lock; SMP request/clear take `DC1hSpinLock` | [OBS-RE] |
| +0x0CE `SMArray` (**export 859**, `CHRArray`) | DWORD far ptr | Far pointer to the SGCB table: a `DOSSMGETMEM` block whose 2-byte header is its size word, then 8-byte entries; `+2+sgid*8` -> that SG's SGCB far pointer. | written by `DOSSMINITSGCB` **#685** (allocates 0xC8 = 25x8); read `DOSSMGETSGCB` #684 (`les di,[0xce]`, selector half `[0xd0]`); grown/used via object 5's pointer by `DOSSMADDSGCB`, `DOSSMDELSGCB`, `DOSSMCHILDWAIT` | 0 until #685 | read in #684 under `SMQueueRamSem`; **written by #685 with no lock** | [OBS-RE] |
| +0x0D2 `SMPIDArray` (**export 860**, `CHRPIDArray`) | DWORD far ptr | Far pointer to the parallel PID table, 2 bytes per SG after the 2-byte size header; #684 with flags low byte 1 scans it to find an SGCB by pid. | written #685 (0x32 = 25x2); read #684 (`les di,[0xd2]`); `DOSSMSGSTART` stores pids via object 5's pointer | 0 until #685 | as `SMArray` | [OBS-RE] |
| +0x0D6 `SMArraySize` (**export 862**, `CHRArraySize`) | BYTE | Capacity of both tables, in entries. | set **0x19** by #685; compared by #684 (`cmp al,[0xd6]` x2); +8 per growth by `DOSSMADDSGCB`; read by `DOSSMDOAPPREQ` #692, `REQUESTBLOCKALOC` | 0 until #685 | as `SMArray` | [OBS-RE] |
| +0x0D7 `SMInitialized` (**export 861**, `CHRInitialized`) | BYTE | "Registry built" latch. | tested by #684 (`1C035233`, **before** its semaphore request) and by `DOSSMADDSGCB`, each calling #685 when 0; set **1** by #685 as its last store | 0 | **tested and set with no lock** | [OBS-RE] |
| +0x0D8 `MemorySegments` | WORD selector x4 (+0xD8..+0xDF) | Selectors of up to **four** shared segments that `DOSSMGETMEM` sub-allocates from. Empty slot = 0; `verw` + `DOSGETSEG` #121 re-attaches a non-zero one in the calling process. | `DOSSMGETMEM` **#682** only: `DOSALLOCSEG` #34 (size 0x1000, flags 3) writes the selector through `lea ax,[si+0xd8]`, `si` = 0,2,4,6 | 0; filled lazily by the first allocation that needs a segment, once per system (object is SHARED) | **no lock inside #682** | [OBS-RE]; meaning of flags 3 not established |
| +0x0E0 `SegmentSizes` | WORD x4 used (+0xE0..+0xE7); +0xE8..+0xEF no reader found | Current size of each segment in `MemorySegments`, index-parallel. | #682: 0x1000 after allocation; +0x1000 via `DOSREALLOCSEG` #38 when a sub-allocation fails, stopping at a carry past 64K, then `DOSSUBSET`; the next segment is tried when that fails | 0 | as above | [OBS-RE] |
| +0x0F0 `killSG` | WORD | Screen group of a process asking to be terminated: the caller's LIS +0x08. | written by `suicide` (`[es:0xf0] = LIS[+8]`), reached from `viorout`, `VIOPOPUP`, `vioattach` (every VIO API through `viorout`) when object 8's current SG > 3; obj7:0x00F0 is the OUT far pointer **#803 `VIOHETINIT`** returns to its caller | 0 | written **under `killRAMsem`** (request `1C045CDA`, store `1C045CF4`) | [OBS-RE]; LIS+8 = current SG [INF] (`infoseg.md`) |
| +0x0F2 `killPID` | WORD | Pid of that process: LIS +0x00. | `suicide` (`[es:0xf2] = LIS[+0]`) | 0 | under `killRAMsem` | [OBS-RE]; LIS+0 = pid [INF] |
| +0x0F4 `killRAMsem` | DWORD RAM semaphore | Hand-off between a dying VIO client and the process registered by #803. | `suicide`: `DOSSEMREQUEST` it, `DOSHOLDSIGNAL` #13(0), fill `killSG`/`killPID`, `DOSFLAGPROCESS` #15 to `HETPID` (+0x120, G2) with ES as the argument, retried until 0; then `DOSSEMWAIT` on it; then `DOSKILLPROCESS` #10(0, pid); `DOSEXIT` #5(1,0). Who clears it and reads the two cells is the flagged process, reached through #803's OUT pointer - not in DOSCALL1's code | 0 | it IS the lock; taken with no other DOSCALL1 lock visible in `suicide` | [OBS-RE] for the sequence; the flagged side [unverified] |
| +0x0F8 `RamSem_SGID` | WORD SGID, **-1 = none** | The SG whose SGCB+0x68 fast-safe semaphore a switch is **waiting to acquire**. | `VIOSRFBLOCK` **#786** stores the low byte of its SG argument **before** `DOSFSRAMSEMREQUEST` on SGCB+0x68, and stores 0xFFFF after acquiring; `viorout` (after releasing its own SG's semaphore) reads it and, when it equals object 8's current SG, backs off through DOSCALLS #32; read by `VIOSRFUNBLOCK` #785, `VIOREGISTER` #813, `VIODEREGISTER` #775, `VIOREGEXIT`, `VIOFREE` #773, `VIOSSWSWITCH` #805, `VIOFSRAMEXIT` | **image 0xFFFF** - the "none" value is part of the meaning. Zero is a valid SGID: a zero cell would make every SG-0 VIO client back off until the first `VIOSRFBLOCK` runs [INF] | **written with no lock** (a flag published ahead of the wait); #785/#786's caller is `DOSSMGSWITCH`, under object 5's `SwitchRamSem` [INF] | [OBS-RE] for the compare and image value |
| +0x0FA `Ggvs_count` | WORD | Number of global VIO registrations recorded in the `Ggvs` block. | `VIOGLOBALREG` **#838** `inc`; `vioattach` reads it and replays entries this process has not attached (object 8 +0x14A = its count); also read by `VIOREGISTER` #813 and `VIODEREGISTER` #775 | 0 | #838 holds **obj8+0xEC**, a per-process RAM semaphore; `viorout` reads it with no lock | [OBS-RE] |
| +0x0FC `Ggvs_AddrLo` / +0x0FE `Ggvs_AddrHi` | far ptr (offset / selector) | Block of 0x34-byte global-registration entries after a 2-byte header (`vioattach`: `bx = n*0x34 + [0xfc] + 2`). | allocated through #682 by #838 (`push es / push 0xfc`); read by #838 (`lds si`), `vioattach` | 0 | as `Ggvs_count` | [OBS-RE] |
| +0x100 `Ggvs_size` | WORD | Size last requested for the `Ggvs` block. | #838 writes `bx` after a successful #682; read by #838 | 0 | as `Ggvs_count` | [OBS-RE] |
| +0x102 `dirty` | WORD counter | Pending "full redraw needed" for the shell. | `inc`: `VIOSRFUNBLOCK` #785 (when that SGCB's +0x4E or +0x52 dword is non-zero), `VIOSCRLOCK` **#792** (when the lock's SG equals object 8's current SG); **#837 `VIOREDRAWSIZE`**: rejects a caller != `SHELLPID` (+0x11E) with **402** (0x192), else if `dirty` > 0 zeroes it and returns 0xFFFF:0xFFFF in the caller's ULONG | 0 | **no semaphore, and `inc word [es:0x102]` (`1C040FE5`, `1C044137`) has no `lock` prefix** | [OBS-RE] |

**The registry as `DOSSMINITSGCB` (#685) builds it** [OBS-RE] (whole body). DS = obj7, ES = obj8.
Allocations all go through #682:
1. `SMArray` <- 0xC8 bytes. The selector half is also copied to **object 8 +0xAF**, a per-process cell.
2. `SMArraySize` = 0x19.
3. `SMPIDArray` <- 0x32 bytes.
4. Two SGCBs of 0xDA bytes are allocated, into entries `+2` (SG 0) and `+0x1A` (SG 3). They get
   SGCB+0x0A = 0x100 and 0x103 respectively, and SGCB+0x10 = 1 in both.
5. `SMInitialized` = 1.

No lock, no failure check on any #682 return. The SGCB record (0xDA bytes) lives outside object 7.

- **Agreement with object 5's `SGCB_*` pointers:** entries at `+2+sgid*8` (`SGCB_Array`), `+2+sgid*2`
  (`SGCB_PIDArray`), `SGCB_ArraySize` seeded 0x19, `SGCB_Initialized` -> #685 when 0; the 2-byte header
  is `DOSSMGETMEM`'s size word. [OBS-RE]
- **#684's flags:** 0x8000 suppresses the semaphore, low byte 1 = pid scan, not found returns 0x173;
  consistent with the code (`les di,[0xd2]`, semaphore at DS:0xC0). [OBS-RE]

**Locking - G1**

| lock | kind | guards | holders |
|---|---|---|---|
| `SMQueueRamSem` (+0xC0) | DOSFSRSEM (SMP: `DC1hSpinLock` inside) | SGCB registry lookup / unlink | #684, and via object 5: `DOSSMDELSGCB`, #703, `DOSSMSGSET` |
| `killRAMsem` (+0xF4) | RAM semaphore | `killSG`/`killPID` and the hand-off wait | `suicide` |
| object 8 +0xEC | RAM semaphore in the **per-process** object | #838's update of `Ggvs_*`, `vioattach`'s replay | per process only - two processes do not exclude each other over these SHARED cells [OBS-RE] for the pushes (`push ds / push word 0xec` with DS = obj8, `1C04613A`, `1C043DFD`); the consequence [INF] |
| - | none | `SMArray`/`SMPIDArray`/`SMArraySize`/`SMInitialized` at init, `MemorySegments`/`SegmentSizes`, `RamSem_SGID`, `dirty` | - |

Order: object 5 `SwitchRamSem` -> SGCB+0x68 fast-safe semaphore on the #785/#786 path [INF].

Consequences [INF]: two first callers of #684/`DOSSMADDSGCB` can both run #685, which allocates new
tables and overwrites `SMArray`/`SMPIDArray` (the latch is tested before the semaphore request). #682
has no lock of its own though it grows segments shared system-wide and is exported; its callers hold
different locks or none. On SMP the unlocked `inc` of `dirty` is not atomic across CPUs, so a
concurrent unblock + scrlock can lose a count; the consumer only tests for > 0.

**Not established (G1):** who clears `killRAMsem` and reads `killSG`/`killPID`; `DOSFLAGPROCESS`'s
argument order as pushed (`HETPID`, 1, 0, ES); DOSCALLS #32 in `viorout`'s back-off and `DOSALLOCSEG`
flags 3; a reader of `SegmentSizes` +0xE8..+0xEF; the `Ggvs` 0x34-byte entry layout and whether #838
frees the old block on growth; the meaning of SGCB +0x4E/+0x52 (the `dirty` condition) and +0x0A/+0x10
(set by #685); readers of +0xC0..+0xD7 outside DOSCALL1 (through exports 858-862).

### G2 (+ G6) - popup, shell-init, `SYIsetmode*`, `SHELLPID`/`HETPID`, print-screen, DBCS country, `hPopXBlockSem`, `WndwConfig` (+0x104..+0x1A9, +0x8B6..+0x8F3)

Kernel ordinals cited [DOC] (osFree names): #23 DOSCLOSESEM, #24 DOSCREATESEM, #25 DOSOPENSEM, #44
DOSLOADMODULE, #45 DOSGETPROCADDR, #130 DOSGETCP. `DOSOPENVDD` is DOSCALL1 obj3 code (`.sym`). UNI
offsets equal SMP's in this region. [OBS-RE]

**Object 8 collisions.** Within +0x104..+0x1A9 the VIO code's DS-relative `[0x124]`, `[0x126]`,
`[0x12a]`, `[0x12c]`, `[0x12e]`, `[0x134]`, `[0x138]`, `[0x13c]`, `[0x19e]`, `[0x1a2]`, `[0x1a6]` are all
**object 8** (DS = 0x981F). Nearly all `push ds / push word 0x1xx` sites in VIO routines likewise pass
object-8 addresses (`VIOINITPROCESS` 0x138/0x13C/0x19E/0x1A6/0x12E/0x12C, `VIOPOPUP` 0x134/0x1A2,
`VIOREGISTER` 0x104/0x106, `VIO(END)POPUP` 0x10E/0x112); pushes of these values in `KBD*`/`DOS*`/
`FindFile`/`_CopyTree` are ordinal or length constants. An offset in this range named without its
segment is ambiguous. [OBS-RE]

| offset + IBM name | size/type | what it is | routines -> owning ordinals | initial value | concurrency (SMP) | prov |
|---|---|---|---|---|---|---|
| +0x104 `PUgetmode` (+0x106 `PUMTYPE`, +0x107 `PUMCOLORS`, +0x108 `PUAROWS`, +0x10A `PUACOLS`, +0x10C `PUHRES`, +0x10E `PUVRES`) | 12-byte VIOMODEINFO-shaped block, **cb word = 0x000C in image** | The popup's saved video mode: the buffer `VIOPOPUP` **#780** and `VIOENDPOPUP` **#770** hand to the BVS entry (`call far [0xfc]`, object 8's `BVSCALLS` ordinal-3 pointer), with function code 5 pushed. | `push es / push word 0x104` with ES = obj7 at `1C045446` (#780) and `1C04590A` (#770) | cb = 0x0C required (the length a VIOMODEINFO call reads before writing); rest 0; SHARED -> once per system | none of its own. **One shared buffer for all popups**, relying on popups being serialised elsewhere (the object-5 `PopUpBlockSem` / `\SEM\VIOPOPUP` path) [INF] | [OBS-RE]; function 5 = GetMode is [INF] from G3's `map_*` order (`map_getmode` is the 6th entry); field names = VIOMODEINFO layout [INF] |
| +0x110 `SYIsetmode` | 8-byte VIOMODEINFO, **image {cb 8, fbType 1, color 4, col 80, row 25}** | The boot text mode the first VIO writer in SG 0 sets: 80x25, 16 colours, text. | `VIOWRTTTY` **#788**: `push es / push 0x110 / push 0` -> `VIOSETMODE` (`1C044000`) | image values name the meaning (80x25 colour text); SHARED | under the `SYIsetmodefl` one-shot (no semaphore) | [OBS-RE] |
| +0x118 `SYIsetmodefl` | WORD tri-state, **image 0xFFFF** | Boot video-mode latch: **0xFFFF = boot mode not yet set; 1 = set** (shell initialised, or first SG-0 write done). `VIOSETCP` #810 does nothing unless it is 1. | written 1 by **#822 `VIOSHELLINIT`** (unconditional, `1C045BDC`) and by **#788** when the caller's SG (object 8 +0x12A) is 0 **and** it reads 0xFFFF (`1C043FEE/F6`), after which #788 sets `SYIsetmode` and then the code page; read by **#810** (`1C043F3F`) | **0xFFFF required**: #788's test is `== -1`, so a zero cell never takes the boot path | #788's test-and-set has **no lock**: two first SG-0 writers can both run `VIOSETMODE` and `VIOSETCP` [INF] | [OBS-RE] |
| +0x11A `SYICP` / +0x11C `SYICPlength` | WORD / WORD | The code page read at the boot mode set, and the count `DOSGETCP` returned. | #788: `DOSGETCP` #130 (cb 2, ES:0x11A, ES:0x11C), then `VIOSETCP(0, [es:0x11a], 0)` (`1C044009..21`) | 0 | as `SYIsetmodefl` | [OBS-RE]; argument roles from push order [INF] |
| +0x11E `SHELLPID` | WORD pid | Pid of the process that called #822. | written by **#822** (`1C045BD8`, value = LIS +0 of the caller); read by `VIOSAVREDRAWWAIT` #794, `VIOREDRAWSIZE` #837 (402 if caller !=), `VIORESTORE` #809, `VIOPOPUP` #780, `VIOSAVE` #789, `VIOFREE` #773, `VIOGLOBALREG` #838 | 0; **overwritten on every #822 call** (no latch, unlike `HETPID`) | no lock | [OBS-RE]; LIS+0 = pid [INF] (`infoseg.md`) |
| +0x120 `HETPID` | WORD pid | Pid latched by the first caller of #803; the process `suicide` flags (G1). | written once by **#803**; read by `viorout`, #809, #780 (three sites: a non-HET caller gets **0x1E0 = 480** at `1C045247` in the window where `SHELLPID` is set and `shellVSRW_done` = 0), #770, #789, #773, `suicide` | 0; once per system (test-then-latch) | test-and-latch unlocked | [OBS-RE] |
| +0x122 `shellVSRW_done` | WORD flag | "The shell has issued its first `VioSavRedrawWait`." | set 1 by **#794** only when it is 0 and caller pid (object 8 +0x126) = `SHELLPID` (`1C040E8A..A2`); read by #780 (`1C045235`: when `SHELLPID` != 0 and this is 0, only `HETPID` may pop up) | 0 | unlocked one-shot | [OBS-RE]; the policy reading [INF] |
| +0x124 `regramsem` | DWORD RAM semaphore | Serialises VIO registration (`VioRegister`/`VioDeRegister` and the exit-time cleanup). | `push word 0x9817 / push word 0x124` -> `DOSSEMREQUEST`/`CLEAR`: `VIOREGISTER` **#813** (`1C044AE1`, `1C044C5B`, `1C044ECF`), `VIOREGEXIT` (`1C0451E8`) | 0 (free) | it IS the lock (plain RAM semaphore, not fast-safe) | [OBS-RE] for the pushes; what it spans not established |
| +0x128 `oldfgsgID`, +0x12A `poppersSGID`, +0x12C `hard_err` | WORD x3 | **No object-7 reader or writer found** (VIO code's `[0x12a]`/`[0x12c]` are object 8 - the current SG and the LIS selector). Names suggest popup bookkeeping. Possibly dead in this build. | - | 0 | - | [OBS-RE] (absence, three instruments); meaning [unverified] |
| +0x12E `tkbuf` | 64 bytes | **No reader or writer found** (`VIOINITPROCESS` `push word 0x12e` at `1C040230` is after `push ds`, i.e. object 8). | - | 0 | - | [OBS-RE] (absence) |
| +0x16E `tkstack` | WORD (a saved SP) | `AVS_PRTSC` **#783** saves SP here before `call far [0xe6]` (an object-8 far pointer, inherited DS), and restores SP from it afterwards (`1C045EAB`, `1C045EC3`), so a callee that does not return SP intact is survived. | #783 only | 0 | **shared cell holding a per-thread stack pointer, no lock**: two threads in #783 at once would restore each other's SP [INF]; presumably excluded by `\SEM\VIOPRTSC` [unverified] | [OBS-RE]; the reason [INF] |
| +0x170 `bvs_ep` | WORD, **image 3** | Ordinal of the BVS entry point imported from `bvs_mod`. | `VIOINITPROCESS` (<- **#718 `OS2BASEINIT`**): `DOSGETPROCADDR` #45(handle obj8 +0xFA, 0, `[es:0x170]`, -> obj8 +0xFC) (`1C0402C7`) | 3 required | read-only | [OBS-RE] |
| +0x172 `bvs_mod` | char[10], **image "BVSCALLS"** | Module whose ordinal 3 is the per-process BVS entry (object 8 +0xFC, called by #822, #780, #770). | `VIOINITPROCESS`: `DOSLOADMODULE` #44(`push es / push 0x172`, handle -> obj8 +0xFA) (`1C0402B2`) | string required | read-only | [OBS-RE] |
| +0x17C `pucsrrow` / +0x17E `pucsrcol` | WORD x2 | **No reader or writer found.** Popup cursor by name. | - | 0 | - | [OBS-RE] (absence) |
| +0x180 `dbcsctrycode` | 4-byte COUNTRYCODE (all 0 = current country/CP) | Country argument for `DOSGETDBCSEV`, which fills a BVSCB/SGCB DBCS vector. | `check_dbc` (<- #788) `push es / push 0x180` (`1C045C77`), `VIOINITSESSION` (<- #822, `VIOINITPROCESS`) (`1C04041B`) | 0 = "default" | read-only | [OBS-RE]; COUNTRYCODE shape [INF] (4 bytes, zero, passed as `pcc`) |
| +0x184 `popupsem` | char[14], **image "\SEM\VIOPOPUP"** | Name of the system semaphore serialising popups. | `VIOINITPROCESS`: `DOSOPENSEM` #25 (`push ds / push 0x138` handle -> **object 8** +0x138, `push es / push 0x184`) x3 sites (`1C040318`, `...32B`, `...33C`) | string required | the name only; the handle is per process (object 8) | [OBS-RE]; the creator not established |
| +0x192 `prtscsem` | char[14], **image "\SEM\VIOPRTSC"** | Name of the print-screen system semaphore. | `VIOINITPROCESS`: `DOSOPENSEM` #25 (handle -> object 8 +0x13C) x3, skipped when object 8 +0x124 = 4 (`1C04034A`) | string required | name only | [OBS-RE]; creator and the meaning of obj8 +0x124 = 4 not established here |
| +0x1A0 `vdd1` | char[10], **image "VVIDEO1$"** | Name of the virtual video device driver that `VIOPOPUP` opens. | #780: `DOSOPENVDD`(`push es / push 0x1a0`, handle -> obj8 +0x134) when obj8 +0x134 is 0 (`1C0452CB`) | string required | name only | [OBS-RE] |
| +0x8B6 `hPopXBlockSem` | DWORD system-semaphore handle | Handle cell for `\SEM\POPXBLOK.SEM`. | `InitConfig` (<- `BvsInit`, `BVSMAIN` **#845**, `BvsSetMode`, `SetConfigNum`), DS = obj7: if 0, `DOSCREATESEM` #24(1, &cell, name) and zero the cell on failure; if non-zero, `DOSOPENSEM` #25(&cell, name) and on success the `.sym`-named `DOSSEMSET`(cell); at the end `DOSSEMCLEAR` and `DOSCLOSESEM` #23 (`1C041755..185E`) | 0 | the cell is the semaphore; **a per-process system-semaphore handle is stored in a SHARED cell**: after the first process the cell is non-zero system-wide, and each later process takes the open path with its own result written back over it | [OBS-RE] for the sequence; which process's handle a later caller uses [INF]; whether 16-bit system-semaphore handles are process-local here [unverified] |
| +0x8BA `namePopXBlockSem` | char[18], **image "\SEM\POPXBLOK.SEM"** | Its name. | `InitConfig` (`push ds / push 0x8ba`, DS = obj7) x2 | string required | - | [OBS-RE] |
| +0x8CC `WndwConfig` (+0x8CE, rest to +0x8F3) | 40 bytes, **image cb = 0x0028**, +0x8EC = 1, +0x8F0 = 1 | A cached **VIOCONFIGINFO-sized** block for the windowed configuration. +0x8CE is compared with the config index in `bx`; when they match (`InitConfig`) or differ (`BVSMAIN` fn 0x44), the cb is reset to 0x28 and `AllVDH` fills it with function 0x104. | `InitConfig` (`1C04182D..44`, only when BVSCB +0x326 = 1); **#845 `BVSMAIN`** fn 0x44 (`1C0418C5..E4`) | cb 0x28 and the two 1s required; SHARED | written between `hPopXBlockSem` set and clear in `InitConfig` (linear: `1C041797` set -> `1C04183E` store -> `1C041854` clear); under what lock `BVSMAIN` fn 0x44 writes it is not established | [OBS-RE]; VIOCONFIGINFO identity [INF] (cb 0x28); the meaning of the image 1s [unverified] |

**Locking - G2/G6**

| lock | kind | guards | holders |
|---|---|---|---|
| `regramsem` (+0x124) | RAM semaphore in shared object 7 | VIO registration | #813, `VIOREGEXIT` |
| `\SEM\POPXBLOK.SEM` (handle +0x8B6) | named system semaphore, opened per call | `InitConfig`'s config init, including the `WndwConfig` fetch | `InitConfig` (#845 and the BvsInit/SetMode paths) |
| `\SEM\VIOPOPUP`, `\SEM\VIOPRTSC` | named system semaphores, handles in object 8 | popups / print screen | `VIOINITPROCESS` opens them; use sites not established |
| - | none | `SYIsetmodefl` test-and-set, `SHELLPID`, `HETPID` latch, `shellVSRW_done`, `tkstack` | - |

Object 5's `PopVioRamSem` is a different semaphore from `\SEM\VIOPOPUP`; their relation is not
established. [OBS-RE]

**Not established (G2/G6):** users of `oldfgsgID`, `poppersSGID`, `hard_err`, `tkbuf`, `pucsrrow`,
`pucsrcol` (indexed access and an inherited DS are not ruled out); who creates `\SEM\VIOPOPUP` /
`\SEM\VIOPRTSC` and where they are requested; that popup function code 5 is GetMode, and why #770 passes
the same code; the meaning of object 8 +0x124 = 4; why `InitConfig` follows a successful create with an
open, and whether `DOSSEMSET` there is the exclusion or a semaphore set; whether `BVSMAIN` fn 0x44
writes `WndwConfig` under `\SEM\POPXBLOK.SEM`.

### G3 - VIO dispatch masks and the `map_*` function-code table (+0x1AA..+0x35F)

There are **no fixups** in this range and **no writer** anywhere: it is constant policy data, and every
read of it is register-indexed. [OBS-RE] Error names (Toolkit `bseerr.h`) [DOC-IBM]: 426
ERROR_VIO_REGISTER, 430 ERROR_VIO_ILLEGAL_DURING_POPUP, 465 ERROR_VIO_DETACHED, 494
ERROR_VIO_EXTENDED_SG, 495 ERROR_VIO_NOT_PRES_MGR_SG.

**The `map_*` table** (+0x1CA..+0x35F) [OBS-RE]:
- One 4-byte entry `{WORD group_index (raw 0/2/4/6/8), WORD function_bit}` per VIO function code; 99
  codes, `map_getphysbuf` = code 0 at +0x1CA ... `map_queryconsole` at +0x352 = code 98, with holes named
  `fillNN`. The `.sym` name at each offset is the `map_*` symbol for that code.
- Only raw groups 0/2/4/8 are used; raw 6 (group 3) never. Distribution: 0 x19, 2 x16, 4 x9, 8 x58.
- Codes 80-98 carry bit 0 (AVIO functions not registerable); `map_register`/`map_deregister` carry bit 0.
- Each of the 48 distinct VIO router stubs loads its function bit into AX and it equals the table bit
  (`VIOCHECKCHARTYPE` is exported twice, #840 and #843, so the export list has 49 rows). For 47 the AX
  value and the pushed code were both read and match; for `XVIOCHECKCHARTYPE` (the SMP label at obj4
  +0x4287) AX = 0x4000 was read and its pushed code was not.

**How it is indexed** [OBS-RE]. Every read indexes by the VIO function code in `[bp+0x6]` shifted left 2:
`mov di,[bp+0x6] / shl di,2 / (mov bx,0x1ca; [es:bx+di]) | (add di,0x1ca; [es:di], [es:di+2])`, with ES
loaded `0x9817` in the same routine. `[bp+0x6]` is the code the caller pushed - router stubs push it
literally (`VIOGETPHYSBUF`: `mov ax,0x10 / push byte 0 / call viorout`); the real-body functions
`VIOWRTTTY`, `VIOPOPUP`, ... push their own code before reaching the shared path. The group word then
indexes the three mask tables (`[es:0x1ac+group]`, ...) and the SGCB (`[gs:0x34+group]`). `[es:di+2]` is
copied to `[bp-0x2]` at the `add di,0x1ca` sites (`viorout` x4, #813, #775, #780, #770); at the
`mov bx,0x1ca` site (`viorout` only) the stub's AX supplies the bit. No code in the windows read
range-checks the code before indexing; an out-of-range code would read past +0x35F into `bvsgdata` -
callers are trusted. [OBS-RE] for the absence in the windows read.

**`viorout`'s decision sequence** (`1C040460..1C0405C3`) [OBS-RE]:
- `typeProcess` 4 -> 465. AVIO range 0x31-0x5F is allowed only when `procTYPE` (object 8 +0x124) = 3 or
  the current SG = 1, else 495 (`1C04049A..A6`, `1C040501..1B`).
- `bit & ext_mask[group]` (the value in AX at the `and ax,[bp-0x2]`, `1C0404D7..F9`) gates **494** when
  `procTYPE` != 0.
- The popup gate (`1C040523..3B`), then the registration test `bit & viossmask[group]` (`1C0405A3`), then
  `& [SGCB+0x34+group]` (`1C0405B6`).
- `SGCB+0x34..+0x3D` holds **five per-group masks** (`mov dx,[gs:di]` saved to `[bp-8]`, then
  `and ax,[bp-0x8]`, `1C0404E4`, `1C0405B6`), not per-group entry points.
- SMP `viorout` starts at `1C040460`, loads obj7 at `1C0404A9`, takes the SGCB from **object 8 +0x19E**,
  and has a `viopretrace` call gated on BVSCB `[+0x33] & 8`.

| offset + IBM name | size/type | what it is | routines | initial value | prov |
|---|---|---|---|---|---|
| +0x1AA `beg_names` | WORD, image 0 | Label at the head of the mask block. **No reader established**: no G3 constant load besides the `mov bx`/`add di` forms above uses it. Two routines load the constant 0x1AA with a DS not established - `BvsSetCAState` (obj4+0x6C11/+0x6C14: `mov bx,0x1aa / mov di,0x1aa`, then `cmp word [bx],byte -0x1`) and `ManageCAS` (obj4+0x65A5: `mov si,0x1aa` beside `mov di,0x192`, `cmp di,[0x1b8]`, `mov si,[0x1b8]`). If their DS is object 7 they read this cell (and G3 has a constant-load reader); if object 8 they do not. Not established | - | 0 | [OBS-RE] |
| +0x1AC `loestpopupmask`, +0x1AE `lopopupmask`, +0x1B0 `hipopupmask`, +0x1B2 `hiestpopupmask`, +0x1B4 `fill_popupmask` | WORD x5 = groups raw 0/2/4/6/8; **image 0xFE67, 0x41BF, 0x1FFC, 0, 0** | **Functions permitted while a popup is active.** `viorout`: `cx = bit & popupmask[group]`; if object 8 +0xF6 = 1 and `cx` = 0 and the caller's pid != `HETPID` (+0x120) -> **430 ERROR_VIO_ILLEGAL_DURING_POPUP** (`1C040523..3B`). Names are per group: loest = group 0 ... hiest = group 3, fill = group 4 | `viorout` (every routed VIO API); after the `add di,0x1ca` walks in #813/#775/#780/#770 too [INF: they reuse the same decision block] | image values ARE the policy: each bit names a permitted function; SHARED, read-only | [OBS-RE] for the gate; object 8 +0xF6 = "popup active for this process" [INF] |
| +0x1B6 `loestviossmask` ... +0x1BE `fill_viossmask` | WORD x5; **image 0, 0x1E00, 0x0003, 0, 0** | **Functions an alternate VIO subsystem may take over.** `viorout`: `cx = bit & viossmask[group]`; if 0 -> skip the registration path (`jz 0x959`, `1C0405AD`); else `ax = bit & SGCB[+0x34+group]` (this SG's registered mask); if non-zero -> the registered path (`1C0405B6..BB`) | `viorout` | as above | [OBS-RE] for the tests; that `0x959` is the BVS path and `0x773` the registered-subsystem path is [INF] |
| +0x1C0 `loest_ext_mask` ... +0x1C8 `fill_ext_mask` | WORD x5; **image 0x0010, 0x1E00, 0x01C7, 0, 0** | **Functions valid only in a full-screen process** (`procTYPE` = 0): `ax = bit & ext_mask[group]`; if `procTYPE` != 0 and `ax` != 0 -> **494 ERROR_VIO_EXTENDED_SG** (`1C0404D4..F9`). Group-0 bit 0x0010 = `VIOGETPHYSBUF` (code 0) | `viorout` | as above | [OBS-RE]; "EXTENDED_SG" = full-screen-only is [INF] from the name and the `procTYPE` = 0 test |
| +0x1CA..+0x35F `map_*` / `fillNN` | 99 x {WORD group, WORD bit} | the function-code table above | `viorout`, #813 `VIOREGISTER`, #775 `VIODEREGISTER`, #780 `VIOPOPUP`, #770 `VIOENDPOPUP`; the 48 router stubs through `viorout` | image values ARE the table; SHARED, read-only | [DOC] + [OBS-RE] |

The 15 mask words and 198 table words are the policy deciding which VIO calls fail with 430/494 and which
a registered subsystem can take over. [OBS-RE] The SGCB per-group mask that `viossmask` is ANDed with is
written by `VioRegister`/`VioDeRegister` (G2's `regramsem`). [OBS-RE]

**Not established (G3):** `XVIOCHECKCHARTYPE`'s pushed code; what `viorout` does at `0x959` (not
subsystem-routable) and `0x773` (routable but not registered); object 8 +0xF6, the popup-active cell;
#813's argument checks (`[bp+0xc]` < 0x200, `[bp+0xe]` < 0x8000 -> a 426-family error path at
`1C044DEA`) against the masks - #813 does not read the mask tables; whether any routine range-checks
`[bp+0x6]` before the index.

### G4 - `bvsgdata` (export 863), +0x360..+0x4B5

**Meaning from IBM's DDK `bvsgdata STRUC`** (`base/inc/bvscb.inc`, lines 259-308, and `seltable STRUC`,
430-438) [DOC-IBM]. The DDK carries two distinct `bvscb.inc` files (COMBASE = the COMVIDEO copy, and
COMDBCS), but the `bvsgdata` block is byte-identical in all three copies. [OBS-RE] (compared)

**Struct vs image: the layout agrees everywhere.** Every `bvsgdata` field, laid out from +0x360 by the
STRUC's declared sizes, lands on the `.sym` symbol of the matching name, and the image holds the STRUC's
initialisers [OBS-RE]:
- `bvsgBvscbSize` = **0x033E** (830), the STRUC's `0FFFEh AND (1+SIZE bvscb)`;
- `bvsgPrtsc_Buffer` is 134 spaces;
- `bvsgCprTemp` = `1B '[00;00R' 0D`;
- the name and title strings match;
- `bvsgCPrtscTitlelen` = 0x0B and `bvsgPrtscTitleLen` = 0x0D, the STRUC's `$ - label` arithmetic;
- the alignment byte at +0x4AF = 0;
- `bvsgSelTable` ends at +0x8B6; `bvsgdata` is 1366 bytes.

No field the struct names disagrees with the image, and the struct names every byte of the range. The
one STRUC line with no storage is commented out (`;bvsgWndwConfig dw 0 ;Config number in use by Shell`,
line 306); the image keeps `WndwConfig` outside the struct instead, at +0x8CC (G2/G6). There are **no
fixups** in the range. [OBS-RE]

`BVSMAIN` runs with **DS = object 8** (`1C04189D mov cx,0x981f / mov ds,cx`); its `[0x326]`..`[0x34a]` are
object 8 `BVSINSTANCE` fields (`.sym`: `bvsi_bvssel` +0x320, `bvsi_sgnum` +0x326, `bvsi_gdtsel` +0x328,
`bvsi_ldtsel` +0x32A, `bvsi_flags` +0x32E, `bvsi_retlen` +0x33E, `bvsi_scrhandle` +0x340,
`bvsi_prthandle` +0x342, `bvsi_pop_*` +0x344..), not G4 cells. [OBS-RE] Kernel ordinals cited [DOC]
(osFree names): #8 DOSGETINFOSEG, #35 DOSALLOCSHRSEG, #36 DOSGETSHRSEG, #39 DOSFREESEG, #59 DOSCLOSE,
#70 DOSOPEN.

Quoted text in the "what it is" column is the DDK field comment.

| offset + IBM name (DDK / `.sym`) | size/type | what it is (DDK comment + code) | routines -> owning ordinals | initial value | concurrency (SMP) | prov |
|---|---|---|---|---|---|---|
| +0x360 `bvsgCallTables` / `bvsg_calltables` (**export 863**) | DWORD far ptr x16 | *"Allow for WDH and 15 real devices"*: the per-video-device call vector table pointers. Slot 1 is written by `UINITGENERICVDH` (`[es:0x364]:[es:0x366]`, `1C049009/0D`). The array's address is passed to `BVSGETVIDEOCALLTABLES` (`push 0x9817 / push 0x360`, `BVSDINIT` x3; `push es / push 0x360`, `BvsInit` `1C04137E`, `BVSMAIN` `1C041909`) | #822 chain -> `BVSDINIT`; **#845 `BVSMAIN`**; `BvsInit` (<- #845) | 0 (image); filled by the call-table routines; SHARED, once per system | no semaphore call in these routines | [OBS-RE] + [DOC-IBM]; slot 0 = WDH per the DDK comment, not seen written |
| +0x3A0 `bvsgFlags` | WORD bitfield | *"Global flags"*. **Bit 0x1** = MOUSE$ opened: `BVSMAIN` fn 0x44 `DOSOPEN` #70 on `bvsgMouddName` (`push es / push 0x45f`), sets 0x1 on success, then `DOSCLOSE` #59 (`1C041945..70`). **Bit 0x2** is tested by `NotifyMouse` (`1C041C9C`) and cleared by `BvsRestore` (`1C041DE0`); its setter is not established. **Bit 0x4** set by `BvsInit` (`1C0413CC`). **Bit 0x8** set/cleared by `BvsSave` (DL = 5, `1C047A20..5B`) and tested by `BvsInit`. **0x4 and 0x8** cleared by `BvsInit` (`1C0413F4`) and `BVSMAIN` (`1C041ABB`). Read by `InitBVSCB`, `BvsSetMode` | #845 and the BVS worker routines | 0 | unlocked read-modify-write on shared bits (`or`/`and word [es:0x3a0]` in `BvsInit`, `BvsSave`, `BvsRestore`, `BVSMAIN`); on SMP an `or mem` is not atomic across CPUs | [OBS-RE]; meaning of bits 0x4/0x8 [unverified] |
| +0x3A2 `bvsgInstance` | WORD selector | *"Instance Selector"*: `BVSMAIN` stores **DS = object 8's selector** (`mov [es:0x3a2],ds`, `1C0418B1`) when `FSHELLINITED` (+0xAA9) equals BL | #845 | 0 | unlocked | [OBS-RE]; the BL value there [INF] |
| +0x3A4 `bvsgBvscbSize` | WORD, **image 0x033E** | *"Size of the BVSCB"*: the `DOSALLOCSHRSEG` #35 size in `GetBVSCB` (`1C04146F`), the zero-fill length (`1C0414A6`), `InitBVSCB`'s copy length, and `InitConfig`'s last store (G2) | `GetBVSCB`, `InitBVSCB`, `InitConfig` (<- #845) | **0x33E required** (`0FFFEh AND (1+SIZE bvscb)`) | read-only | [DOC-IBM] + [OBS-RE] |
| +0x3A6 `bvsgSISsel` / +0x3A8 `bvsgLISsel` | WORD selector x2 | *"System InfoSeg GDT selector" / "Local InfoSeg LDT selector"*: filled by `DOSGETINFOSEG` #8 with address-taken pushes (`push 0x9817 / push 0x3a6`, `push 0x9817 / push 0x3a8`, `1C0488E4..F0`); copied by `BVSMAIN` into object 8 `bvsi_gdtsel`/`bvsi_ldtsel` (`1C0418ED..F4`) and used as `gs`/`ds` | `BVSGLOBALINIT` (<- `BVSDINIT` <- #822 chain), #845 | 0 until `BVSGLOBALINIT` | unlocked; written once per init. **The LIS selector is per-process data in a shared cell**: filled by whichever process runs `BVSGLOBALINIT` and copied to every process's `bvsi_ldtsel`; whether the LIS selector value is the same in every process is [unverified] (see `infoseg.md`) | [OBS-RE] |
| +0x3AA `bvsgMaxBase` | WORD | *"Maximum Base session number"* = **GIS +0x19 (`SIS_MaxScrnGrp`) - 1** (`1C04890A..18`; UNI `1C047C5B..66`); compared with the SG number in `BvsInit` (`1C04136E`), `BvsShowBuf`, `BVSGETVIDEOCALLTABLES` | `BVSGLOBALINIT`; readers as listed | 0 until init | unlocked | [OBS-RE] |
| +0x3AC `bvsgInitPid` | WORD pid | *"Process ID at initialization time"*: `BVSMAIN` fn 0x44 stores `[bvsi_ldtsel:bx]` = LIS +0 (`1C041936..3D`) | #845 fn 0x44 | 0 | unlocked | [OBS-RE]; LIS+0 = pid [INF] |
| +0x3AE `bvsgScrHandle` | WORD handle | *"Base Video Subsystem File Handle"*. **No reader or writer found.** `GetScrHandle` opens `bvsgScrddName`; the handle cell it uses is not established (object 8 has its own `bvsi_scrhandle` +0x340) | - | 0 | - | [OBS-RE] (absence) |
| +0x3B0 `bvsgSg0Flag` / +0x3B2 `bvsgSg0Bvssel` / +0x3B4 `bvsgSg0Envsel` / +0x3B6 `bvsgSg0Lvbsel` | WORD x4 | *"SG0 on behalf of other SG"* + SG0's BVSCB / ENVB / LVB selectors. `finis` (<- #845's exit path): if `bvsgSg0Flag` equals the function number `[bp+0x50]`, it swaps object 8 `bvsi_bvssel`/`bvsi_lvbsel` for `bvsgSg0Bvssel`/`bvsgSg0Lvbsel` around a call, then **stores BX into `bvsgSg0Flag`** (`1C041BC1..EE`). `bvsgSg0Envsel`: no reader found | `finis` | 0 | unlocked | [OBS-RE]; the swap's purpose [INF] from the DDK comment; the writer of `Sg0Bvssel`/`Sg0Lvbsel` not established |
| +0x3B8 `bvsgOpen_a` | WORD | *"Open action return field"*: `OpenPrt` passes it as DOSOPEN's action cell (`push ds / push 0x3b8`, `1C047859`) | `OpenPrt` (<- print screen) | 0 | shared scratch, unlocked | [OBS-RE] for the push; DS = obj7 there [INF] |
| +0x3BA `bvsgPrtsclen` / +0x3BC `bvsgPrtsc_Buffer` | WORD / 134 bytes, **image spaces** | *"Print screen length / buffer"*: `VDHPRTSC` stores a length from `[bx+0x24]` into `[es:0x3ba]` (`1C047779`) and passes both addresses (`push es / push 0x3bc`, `push es / push 0x3ba`, `1C04777E..82`, `...2D..32`) | `VDHPRTSC` (<- `AVS_PRTSC` #783 path) | spaces required (a print line buffer); SHARED | one shared buffer, no lock seen; `\SEM\VIOPRTSC` presumably serialises it [unverified] | [OBS-RE] |
| +0x442 `bvsgCprTemp` | 9 bytes, **image `ESC [00;00R CR`** | *"Template for CurPos Report"* (the ANSI DSR reply): `InitBVSCB` copies +0x442..+0x44A into the new BVSCB at +0x6C (`mov si,0x442 / mov di,0x6c / mov cx,0x44b; sub cx,...`, `1C041672..78`) | `InitBVSCB` (<- `InitConfig` <- #845) | template bytes required | read-only | [OBS-RE]; the ANSI use of BVSCB+0x6C [INF] |
| +0x44B `bvsgBvscbName` | 20 bytes, **image `\SHAREMEM\BVS\BVSsg`** | *"Name of BVSCB"*: `GetBVSCB` copies it to the stack, overwrites the last 2 characters with the SG number in hex, then **`DOSALLOCSHRSEG` #35 (size `bvsgBvscbSize`)**, else **`DOSGETSHRSEG` #36**, into object 8 `bvsi_bvssel`; on a fresh allocation it zero-fills and sets BVSCB +0x12 = 1 (`1C041434..14AC`) | `GetBVSCB` (<- `BvsInit`, #845) | string required | no lock around the alloc-or-get, but tolerant: `DOSALLOCSHRSEG` fails for a second creator, which then `DOSGETSHRSEG`s; the zero-fill and BVSCB +0x12 = 1 run only on the creator's arm | [OBS-RE] |
| +0x45F `bvsgMouddName` | 7 bytes, **image `MOUSE$`** | *"Mouse DD name"*: `BVSMAIN` fn 0x44's DOSOPEN probe (bit 0x1 above) | #845 | string required | read-only | [OBS-RE] |
| +0x466 `bvsgPrtName` | 4 bytes, **image `PRN`** | *"Printer name"*: `OpenPrt` DOSOPEN (`push ds / push 0x466`, `1C047853`) | `OpenPrt` | string required | read-only | [OBS-RE] for the push; DS = obj7 [INF] |
| +0x46A `bvsgScrddName` | 8 bytes, **image `SCREEN$`** | *"Screen DD name"*: `GetScrHandle` (`push word 0x9817 / push word 0x46a`, `1C046F1B`) | `GetScrHandle` | string required | read-only | [OBS-RE] |
| +0x472 `bvsgBlanks` | 8 spaces | *"Blanks for tab removal"*: `VDHWRTTTY` loads `di,0x472` after `mov es,ax` (`1C048014`, `1C048025`) | `VDHWRTTTY` (<- `VIOWRTTTY` #788 path) | spaces required | read-only | [OBS-RE] for the load; ES = obj7 [INF] |
| +0x47A `bvsg3xBcPos` | WORD | *"3X Box cursor position save area"*. **No reader or writer found** | - | 0 | - | [OBS-RE] (absence) |
| +0x47C `bvsgParmPkt`, +0x47D `bvsgPjTitleLen`, +0x47F `bvsgPjTitleOff`, +0x481 `bvsgPjTitleSel` | BYTE + WORD x3 | *"parameter packet area / print job title length, offset, segment"*: `BvsPrtSc` and `PrinterInit` fill Len/Off/Sel with the title's length byte and far pointer, then pass `ds:0x47d` and `ds:0x47c` to a call (`1C0476B2..CD`, `1C0484B0..CB`) | `BvsPrtSc`, `PrinterInit` (<- `BvsWrtTTY`) | 0 | shared packet, unlocked | [OBS-RE] (DS loaded 0x9817 at `1C0476AB`, `1C0484A9`) |
| +0x483 `bvsgCPrtscTitle` / +0x48E `bvsgCPrtscTitlelen` | 11 bytes `Ctrl PrtSc` + BYTE **0x0B** | Ctrl-PrtSc print-job title | `PrinterInit` (`lea si,[0x483]`, `mov dl,[0x48e]`) | string + length required | read-only | [DOC-IBM] + [OBS-RE] |
| +0x48F `bvsgPrtscTitle` / +0x49C `bvsgPrtscTitleLen` | 13 bytes `Print Screen` + BYTE **0x0D** | PrtSc print-job title | `BvsPrtSc` (`lea si,[0x48f]`, `mov dl,[0x49c]`) | as above | read-only | [DOC-IBM] + [OBS-RE] |
| +0x49D `bvsgVdd1` / +0x4A6 `bvsgVdd2` / +0x4AF align / +0x4B0 `bvsgVddhandle` | 9 + 9 bytes `VVIDEO1$`/`VVIDEO2$`, BYTE 0, DWORD | *"primary / secondary display for MVDM"* and *"MVDM VDD handle"*: `BvsMVDMTranPop` passes each name with `lea ax,[0x4b0]` as the handle cell (`1C0473D3..1E`) | `BvsMVDMTranPop` | strings required; handle 0 | shared handle cell, unlocked | [OBS-RE] for the pushes; ES = obj7 [INF] |
| +0x4B4 `bvsgSelTablesz` | WORD | *"Selector table entry size"* - **computed, not constant**: `BVSGLOBALINIT` stores **(max(CVIDEODEVICES, 1) + 1) x 4** (`[es:0x98c]`, `1C048961..7F`). `CVIDEODEVICES` (G7, +0x98C) is written by `VREADENVVARS` earlier in the same `BVSGLOBALINIT`, so the size is a function of `SET VIDEO_DEVICES=`. It is the `DOSSMGETMEM` size of each `bvsgSelTable` block (`GetBVSCB` `1C0414CB`), and `BvsFree` derives the walk count from it (`1C047B67..71`) | `BVSGLOBALINIT`; `GetBVSCB`, `BVSMAIN`, `BvsFree` | 0 until init | unlocked | [OBS-RE] |
| +0x4B6 `bvsgSelTable` | DWORD x256 (to +0x8B5) | see G5 | - | - | - | - |

**`bvsgSelTable` vs `seltable STRUC`.** `bvscb.inc` declares `bvsgSelTable dd 256 dup (0)`, *"Selector
table offset"*, and a separate 14-byte `seltable STRUC` (`selt_size`, `selt_bvscb`, `selt_flags`,
`selt_envb`, `selt_lvb`, `selt_nextenvb`, `selt_nextlvb`; DCR 549 *"Seltable changes due to rangeless
sessions"*) [DOC-IBM]. They are **not the same object**:
- `bvsgSelTable` is **256 far pointers**, indexed by **SG number x 4**. `GetBVSCB` does `shl si,2 / cmp
  dword [si+0x4b6],0`, then `DOSSMGETMEM(size = bvsgSelTablesz, dest = ds:si+0x4b6)` (`1C0414B8..CF`),
  with `si` = its SG argument. `BvsInit` reads entry 3 as `lgs di,[es:0x4c2]` (`1C04139F`). [OBS-RE]
- Each pointer addresses a **variable-size block** of `bvsgSelTablesz` = (devices + 1) x 4 bytes; see G5.

**Locking - G4.** No semaphore call appears in any G4 accessor (`BVSGLOBALINIT`, `BVSMAIN`, `BvsInit`,
`GetBVSCB`, `InitBVSCB`, `BvsSave`, `BvsRestore`, `finis`, `VDHPRTSC`, `PrinterInit`, `BvsPrtSc`,
`NotifyMouse`, `BvsSetMode`, `BvsShowBuf`, `BvsFree`). [OBS-RE] Serialisation, if any, is by the callers -
`viorout`'s per-SG fast-safe semaphore (object 8 +0xD4), `\SEM\POPXBLOK.SEM` around `InitConfig` (G2) -
not established for these cells.

**Not established (G4):** the setter of `bvsgFlags` bit 0x2 and the meaning of bits 0x4/0x8; writers of
`bvsgSg0Bvssel`/`bvsgSg0Lvbsel`; any reader of `bvsgSg0Envsel`, `bvsgScrHandle`, `bvsg3xBcPos`; DS in
`OpenPrt`, `VDHWRTTTY`, `BvsMVDMTranPop` at the address-taken sites (obj7 by inference from the names);
which lock, if any, the callers hold across these stores.

### G5 - `bvsgSelTable` and the per-SG selector-table block (+0x4B6..+0x8B5)

Field names from the DDK `seltable STRUC` (`base/inc/bvscb.inc`, 430-438) [DOC-IBM]; everything else
from the SMP code [OBS-RE]. DOSCALL1 object-3 routines that address +0x4B4/+0x4C2 (`DOSSMSGSTART`,
`DOSSMDOAPPREQ`, `DOSSGSWITCHFOREGROUND`, `DOSSMGETSTATUS`, `DOSSMINITALLOC`, `DOSSGSWITCHPOPUP`,
`DOSSMHDEPOPUP`, `DOSSMPOPUPTLECHG`) run with DS = object 5; those are **object 5** cells. `DOSSMGETMEM`
(#682) rounds the size `(n + 6) & ~3`, zero-fills the block, and sets its first WORD to the rounded size;
`DOSSMFREEMEM` is **#683**. Kernel ordinals: #39 DOSFREESEG, #121 DOSGETSEG. [OBS-RE]

**The table (+0x4B6).** 256 x DWORD far pointer, **index = SG number x 4** (`shl si,2 / [si+0x4b6]`
everywhere). A zero entry means that SG has no selector-table block. Entry 3 is also addressed directly
as `[0x4c2]`. [OBS-RE]

**The block.** Allocated by #682 with size `bvsgSelTablesz` = **(max(CVIDEODEVICES, 1) + 1) x 4** (G4),
so the allocation is `(tablesz + 6) & ~3` = **tablesz + 4** bytes, i.e. **4,N + 8** for N =
max(devices, 1). [OBS-RE]

| block offset | DDK `seltable` name | what the code does | writers | readers | prov |
|---|---|---|---|---|---|
| +0x0 | `selt_size` *"size of this structure"* | **the #682 allocation size** (4N+8), stored by the allocator | #682 | not read by the BVS users | [OBS-RE] + [DOC-IBM] name |
| +0x2 | `selt_bvscb` *"Master BVSCB selector"* | selector of `\SHAREMEM\BVS\BVSsgNN` | `GetBVSCB` `mov [gs:si+0x2],es` right after allocating (`1C0414EC`) | `BvsInit` (`verw`/`verr` validity test, `1C0412A5..D9`; `1C0413A5`); `BVSMAIN` fn 0x44 (`mov ds,[gs:di+2]`, clears BVSCB +2, `1C04198E..92`); `BvsSave` (`1C0479F7`); `BvsFree` (`test [bx],0x300` on it, then `DOSFREESEG`, `1C047B58..8B`) | [OBS-RE] |
| +0x4 | `selt_flags` *"Active config flags"* | **bit (1 + cfg) = configuration `cfg` active**: `InitConfig` computes `dx = 2 << cfg` and tests `[gs:si+4] & dx` (`1C041721..4C`); cfg = BVSCB +0x12 (`bvs_curconfig`) - 1 (`1C041709..0E`) | `BvsInit` clears it for SG 3 (`mov word [gs:si+0x4],0`, `1C041260`, when `[bp+0x59]` = 4); `BvsSave` sets bit 0x2 on SG 3 (`1C0479F2`) | `InitConfig` | [OBS-RE] |
| +0x6 + 4,cfg | `selt_envb` (cfg 0), `selt_nextenvb` (cfg 1) *"master ENVB selector"* | ENVB selector of configuration `cfg` | filled by the video handlers: `GetBVSCB` calls `AllVDH` fn **0x104** with `di` = block +6 (`1C041529..43`) [INF: the handler stores into the pair array] | `InitConfig` -> object 8 `bvsi_envsel` (`1C04172E..32`); `BvsSave` (cfg 0, `1C0479FB`); `GetBVSCB` `DOSGETSEG`s the first one (`1C041547..59`); `BvsFree` frees each | [OBS-RE] for readers; writer [INF] |
| +0x8 + 4,cfg | `selt_lvb` (cfg 0), `selt_nextlvb` (cfg 1) *"master LVB selector"* | LVB selector of configuration `cfg` | as ENVB | `InitConfig` -> object 8 `bvsi_lvbsel` (`1C04173C..40`); `BvsSave` (cfg 0, `1C0479FF`); `BvsFree` | same |
| +(4N+6)..+(4N+7) | - | 2 bytes of rounding slack, never addressed | - | - | [OBS-RE] (arithmetic) |

- **Pair count** = `(bvsgSelTablesz - 4) / 2` WORDs = **2N**, one {ENVB, LVB} pair per configuration,
  N = `CVIDEODEVICES` (min 1). `BvsFree`'s loop bound: `cx = ([0x4b4] + 2 - 6) >> 1`, walking from +6
  (`1C047B64..82`). [OBS-RE]
- **The DDK STRUC is the N = 2 instance.** The 14-byte `seltable STRUC` is exactly this block for N = 2
  (6-byte header + 2 pairs); `selt_nextenvb`/`selt_nextlvb` are configuration 1's pair, and the STRUC's
  comment *"Next master ENVB selector, if any"* matches a second video device being optional. The binary
  generalises the STRUC to N configurations, sized from `SET VIDEO_DEVICES=`, so a block fixed at 14
  bytes would not hold more than two devices. [DOC-IBM] + [OBS-RE]; the index is the configuration
  number (`bvs_curconfig` - 1), which the code equates with the device slot [INF: `bvsgSelTablesz` is
  derived from `CVIDEODEVICES`].
- **The block holds selectors in shared memory, and readers re-attach them.** `GetBVSCB` `DOSGETSEG`s the
  #682 segment and the first ENVB before use (`1C041503`, `1C041559`), which is how one process's
  allocation is made usable by another: master selectors plus per-process `DosGetSeg`. [OBS-RE]

**Lifecycle per screen group** [OBS-RE] (from the code windows read):
1. **Allocate, BVSCB path:** `GetBVSCB(sg)` (<- `BvsInit`, #845) creates or attaches
   `\SHAREMEM\BVS\BVSsgNN`. If `bvsgSelTable[sg]` = 0 it allocates the block with #682 and stores
   `selt_bvscb`. If non-zero it `DOSGETSEG` #121s the block's selector (entry +2 of the far pointer),
   unless it equals object 8 +0xAF - the #682 segment this process already holds (G1 `DOSSMINITSGCB`). It
   then sets BVSCB +0x12 = 1 (or 0 when sg > `bvsgMaxBase`) and calls `AllVDH` fn 0x104 over the pair
   array (`1C0414BD..1543`).
2. **Allocate at shell init:** `BVSMAIN` fn 0x44 loops `GetBVSCB` over **SG 0, 1 and 3 (skipping 2)**,
   clears each BVSCB +2, then `InitConfig` and `NotifyMouse` (`1C041979..AD`).
3. **Allocate without a BVSCB:** `BVSMAIN` fn **0x51**, for a PM process (`typeProcess` = 3) or SG 1, and
   only for **sg > 1**: #682 into `bvsgSelTable[sg]`, error 479 on failure, then `AllVDH` fn 0x114
   (`1C0419B5..A0A`).
4. **Use:** `InitConfig` publishes the current configuration's ENVB/LVB into object 8
   (`bvsi_envsel`/`bvsi_lvbsel`) and tests `selt_flags`. `BvsSave` marks SG 3's configuration 0 active and
   reads its selectors.
5. **Free, normal:** `BvsFree` (SG from `[bp+0x56]`) calls `AllVDH` fn 0x114, then - **unless BVSCB word 0
   has bits 0x300** - `DOSFREESEG`s every ENVB/LVB pair and the BVSCB. It zeroes object 8
   `bvsi_bvssel/envsel/lvbsel`, then `DOSSMFREEMEM` #683 (the far pointer) and zeroes the table entry
   (`1C047B35..B7`).
6. **Free, stale:** `BvsInit` with function 0x43, when the entry's `selt_bvscb` fails `verw` (the BVSCB is
   gone), frees the block with #683 and zeroes the entry (`1C0412A9..D3`).

`BvsSave` and `BvsFree` have **no static caller or address reference** anywhere in DOSCALL1's 16-bit
objects (objects 3 and 4, far calls included), and neither is an export, so they are not entry-table
targets. [OBS-RE] They are reached through `BVSMAIN`'s function dispatch [INF]; their function numbers
are not established.

| offset + IBM name | size/type | what it is | routines -> owning ordinals | initial value | concurrency (SMP) | prov |
|---|---|---|---|---|---|---|
| +0x4B6 `bvsgSelTable` | DWORD far ptr x256 (index SG x 4) | Per-screen-group pointer to a #682 block `{selt_size, selt_bvscb, selt_flags, N x {ENVB, LVB}}` - the **master selectors** of that SG's BVSCB and of each configuration's ENVB/LVB | writers: `GetBVSCB`, `BVSMAIN` fn 0x51 (via #682's `dest`), `BvsFree`/`BvsInit` fn 0x43 (zero); readers: `BvsInit`, `GetBVSCB`, `InitConfig`, `BVSMAIN` fn 0x44, `BvsSave`, `BvsFree` - all reached from **#845 `BVSMAIN`** (and `VIOSHELLINIT` #822's chain) | 0 (image); entries created lazily per SG; SHARED, one table per system | **no lock** in any of these routines, and #682/#683 have none. The test-then-allocate in `GetBVSCB` and `BVSMAIN` fn 0x51 is unlocked: two processes initialising the same SG can both allocate, the second store winning and the first block leaked [INF] | [OBS-RE] + [DOC-IBM] (field names) |

**Locking - G5.** None found: all accessors run inside `BVSMAIN`'s function handlers with no semaphore
call, and the shared allocator has none. The only candidate serialisers are external:
`\SEM\POPXBLOK.SEM` around `InitConfig` (G2, covering only the `InitConfig` read), and whatever `viorout`'s
per-SG fast-safe semaphore covers (not established). [OBS-RE]

**Not established (G5):** who writes the ENVB/LVB pairs (the handler side of `AllVDH` fn 0x104 - BVH
`DEVENABLE` call-vector entries); the meaning of `AllVDH` fn 0x114 (called by `BVSMAIN` fn 0x51 after
allocating and by `BvsFree` before freeing); the `BVSMAIN` function numbers that dispatch to `BvsSave` and
`BvsFree`; BVSCB word 0 bits 0x300 (they suppress freeing the selectors); `[bp+0x59]` = 4 in `BvsInit`
(it clears SG 3's `selt_flags`); why SG 2 is skipped in the fn 0x44 loop.

### G7 - video-handler device tables (+0x8F4..+0xAC3)

Kernel ordinals: #38 DOSREALLOCSEG, #126 DOSSIZESEG [DOC]. The `BVSDINIT` function-0x44 arm is at SMP
`1C0485A7` (UNI `1C0478F5`). [OBS-RE]

**`BVSDINIT`** (`1C048576..8608`) [OBS-RE]: `SAVEREGS`; `GLOBALFLAGS & 0x08` gates `BVSGLOBALINIT`, whose
failure is not propagated; function 0x44 -> `FFILLDEVBLK` = 1, `ULOADWINTHORNVDH(&calltables)`,
`BVSGETVIDEOCALLTABLES(0x360, 0x9CE, 0xA0E)` (pushes at `1C0485C8..DA`), and `FSHELLINITED` = 1 only
when rc = 0; else-arm guard `FFILLDEVBLK == 0` -> `FFILLDEVBLK` = 3. `BVSDINIT`, `BVSGETVIDEOCALLTABLES`
and `DOSLOADVIDEOHANDLER` bracket their bodies with `SAVEREGS`/`RESTOREREGS` (a register spill).

**Winthorn gate** [OBS-RE] (`1C048EB6..ED7`): `FSHELLINITED != 0 && bvsi_sgnum > bvsg_maxbase` -
`cmp byte [es:0xaa9],0 / jz / es=[0x24] / ax=[es:0x3aa] / es=[0x26] / cmp [es:0x326],ax / jna / call
ULOADWINTHORNVDH`, with object 8 `bvsi_sgnum` at SMP +0x326 (UNI +0x2D6). `ULOADWINTHORNVDH` tests
`FSHELLINITED` and stores AX into `PSZWINDOWBVH` (`cmp byte [es:0xaa9],0` then `mov [es:0xa90],ax`,
`1C048F84`, `...96`); the value stored is not established.

**Device selection** (`FISPOWERUP` poll, promote/swap to slot 0, `UINITGENERICVDH` fallback): verified
only as far as the generic fallback names being loaded in `UINITGENERICVDH` (`mov ax,0x93c/0x94b/...`) and
`SZDEFPTRDEV` (0x971) loaded in `BVSGETVIDEOCALLTABLES` (`1C048BB6`, `...CEF`). [OBS-RE] The rest of the
algorithm is not established here.

| offset + IBM name | size/type | what it is | routines -> owning ordinals | initial value | concurrency (SMP) | prov |
|---|---|---|---|---|---|---|
| +0x8F4 `ILASTVDH` | WORD | Index of the last loaded VDH. Written by `BVSGETVIDEOCALLTABLES`; read by `InitBVSCB`, `BVSGETPTRDRAWNAME`, `GetBVSCB` (config count, G5) | #822 -> `BVSDINIT`, #845 | 0; SHARED | inside `SAVEREGS`/`RESTOREREGS` (no semaphore) | [OBS-RE] |
| +0x8F6 `MaxRedrawSize` | DWORD | Largest redraw buffer size: `BVSREDRAWSIZE` and `UpdateLVBSize` read and raise it | `BVSREDRAWSIZE` (<- `VIOREDRAWSIZE` #837), `UpdateLVBSize` | 0 | unlocked compare-and-raise | [OBS-RE]; "largest" [INF] |
| +0x8FA..+0x979 `SZ*` | strings, image byte for byte: `DEVENABLE`, `VIDEO_DEVICES`, `DEVICE(`, `PTRDEVR(`, `PTRDEVP(`, the generic BVH chains, `POINTER$`, `SZDEVPREFIX` empty | Users: `SZDEFENTRY` (`DOSLOADVIDEOHANDLER`/`DOSUNLOADVIDEOHANDLER`, `push 0x9817 / push 0x8fa`); `SZVIDEODEVICES`, `SZDEVICETAG`, `SZPTRDEVRTAG`, `SZPTRDEVPTAG` (`VREADENVVARS`, which pushes +0x904/+0x912/+0x91A/+0x923); `SZGENERIC*` (`UINITGENERICVDH`); `SZDEFPTRDEV` (`BVSGETVIDEOCALLTABLES`); `SZDEVPREFIX` (`FISDEVICEDRIVER`) | as listed | strings required | read-only | [OBS-RE] |
| +0x97A `MASKFILLDEVBLK` | DWORD | Read as one pair (+0x97A:+0x97C) by `DOSLOADVIDEOHANDLER` (`1C0492B8/BC`); **no writer found** (image 0) | `DOSLOADVIDEOHANDLER` | 0 | read-only as far as found | [OBS-RE]; meaning [unverified] |
| +0x97E `FFILLDEVBLK` | **DWORD** (+0x980 is its high word) | Device-fill mode: **1** = windowed/Winthorn init (set by `BVSDINIT` fn 0x44, `ULOADWINTHORNVDH`, `BVSGETVIDEOCALLTABLES` x2); **3** = ordinary (`BVSDINIT` else-arm, only while 0); passed as one 32-bit argument by `DOSLOADVIDEOHANDLER` (pushes +0x980 then +0x97E, `1C0492E7/EC`) | as listed | 0 | inside `SAVEREGS` regions; no semaphore | [OBS-RE] (`.sym` + code) |
| +0x982 `PSZGENERICVDH` / +0x986 `PCHGENCALLTBL` | far ptr / far ptr | Generic-VDH name pointer and generic call table: `UINITGENERICVDH` tries each `SZGENERIC*` in turn, storing the candidate in +0x982 and loading it; +0x986 is read. It also fills `bvsg_calltables[1]` (G4) | `UINITGENERICVDH` (<- `BVSGETVIDEOCALLTABLES`) | 0 (no fixups) | as above | [OBS-RE]; per-candidate loop shape [INF] |
| +0x98A `GLOBALFLAGS` | WORD | **0x08** = `BVSGLOBALINIT` done (`BVSDINIT`); **0x04** = generic VDH initialised (`UINITGENERICVDH` test/or, `1C048FC4..DD`) | `BVSDINIT`, `UINITGENERICVDH` | 0 | unlocked `or` | [OBS-RE] |
| +0x98C `CVIDEODEVICES` | WORD | Count of configured devices: `VREADENVVARS` increments it per accepted `DEVICE(` entry (`1C048826`); `BVSGETVIDEOCALLTABLES` rewrites it; `BVSGLOBALINIT` sizes `bvsgSelTablesz` from it (G4) | `VREADENVVARS` (<- `BVSGLOBALINIT` <- `BVSDINIT`), `BVSGETVIDEOCALLTABLES` | 0 | as above | [OBS-RE] |
| +0x98E / +0x9CE / +0xA0E `PSZDEVICESTRING` / `PSZPROTPTRNAMES` / `PSZREALPTRNAMES` | far ptr x16 each | Three parallel tables passed as `BVSGETVIDEOCALLTABLES`' three arrays. **Image:** `PSZDEVICESTRING` all 0; **both pointer-name tables pre-filled by 32 fixups with obj7:0x0971 (`SZDEFPTRDEV` "POINTER$")**. `BVSGLOBALINIT` copies entry 1 -> entry 0 in all three after `VREADENVVARS` (`1C04891F..5C`) | `VREADENVVARS`, `BVSGLOBALINIT`, `BVSGETVIDEOCALLTABLES`, `BVSGETPTRDRAWNAME`, `BVSDINIT` (`push word 0x9817 / push word 0x9ce` and `...0xa0e` at obj4+0x85D1/0x85D7 and again at +0x8618/+0x861E) | **defaults required:** 16 + 16 far pointers to "POINTER$" | inside `SAVEREGS` regions | [OBS-RE] (image + fixups) |
| +0xA4E `PDEVGROUPS` / +0xA8E `CDEVGROUPS` | far ptr x16 / WORD | Device-group block pointers and their count. `UGROWDEVGROUP` does `PCHGROWGLOBAL(0x334)` and stores the result at `PDEVGROUPS[CDEVGROUPS]` (`1C049DCF..EA`), writes the new block's +0x22A, then `CDEVGROUPS++` (`1C049E3E..55`). Readers: `FFINDDEVICE`, `FGETFREECALLTABLE`, `FGETFREEDEVTABLEENTRY`. Each block is 0x334 bytes inside object 7's grown tail (queued trace 1) | `UGROWDEVGROUP` (<- `FGETFREECALLTABLE`, `FGETFREEDEVTABLEENTRY` <- `DOSLOADVIDEOHANDLER`, `UINITGENERICVDH`) | 0 / 0 | as above | [OBS-RE] |
| +0xA90 `PSZWINDOWBVH` / +0xA94 `SZWINDOWBVH` / +0xA9C `SZVIDEOWINDOW` | far ptr / "BVHWNDW" / "VIDEO_WINDOW" | `PSZWINDOWBVH` is **0 in the image** (no fixup). `VREADENVVARS` sets it at run time to a `PCHGROWGLOBAL` copy of the `VIDEO_WINDOW` value (`1C04872A..35`), or **defaults it to obj7:0x0A94 (`SZWINDOWBVH`) when null** (`1C04875C..6E`) | `VREADENVVARS`, `ULOADWINTHORNVDH` | pointer 0 then set at init; strings required | as above | [OBS-RE] |
| +0xAA9 `FSHELLINITED` | BYTE | Shell-initialised latch. **One writer**: `BVSDINIT` fn 0x44 (`1C0485EA`); **four readers**: `BVSMAIN` `1C0418AA`, `BVSGETPTRDRAWNAME` `1C0489E0`, `BVSGETVIDEOCALLTABLES` `1C048EB6`, `ULOADWINTHORNVDH` `1C048F84` | writer `BVSDINIT` fn 0x44 (#822 -> #845 -> `BVSDINIT`) | 0 | set once; unlocked | [OBS-RE] |
| +0xAAA `CBBVSGSEG` | WORD, **image 0x0F23** (SMP; UNI 0x0E65) - object size - 1 | **High-water mark of object 7's own bump allocator.** `PCHGROWGLOBAL(n)` rounds `n` to even, uses `DOSSIZESEG` #126 on object 7, `DOSREALLOCSEG` #38 **grows object 7** when `CBBVSGSEG + n` exceeds it (64 KB cap), returns **obj7:`CBBVSGSEG`**, adds `n`, and zero-fills (`1C049D22..DBD`). Callers: `UGROWDEVGROUP` (0x334 blocks), `VREADENVVARS` (environment-string copies), `VGETTAGVALUE`. The heap begins at the end of the static data - so the starting value is build-specific | `PCHGROWGLOBAL` | 0x0F23 = end of the SMP image object (-1) required | **no lock** | [OBS-RE] |
| +0xAAC..+0xAC3 (unnamed; the `.sym` puts it inside `CBBVSGSEG`'s span) | string, **image `\SHAREMEM\DOS\CDIB`** | No obj4 address-taken reference found; it sits beside G8's `CDIBSel` (+0xAC4). See G8 | - | string present | - | [OBS-RE] (image) |

**Object 7 is growable, and part of its state lives past its static end.** `PCHGROWGLOBAL` reallocates
object 7 and bump-allocates from `CBBVSGSEG`; the `PDEVGROUPS` blocks (0x334 each), the `VIDEO_WINDOW`
string copy and `VGETTAGVALUE`'s data live there. The object therefore grows with `DosReallocSeg` at a
fixed base. No lock guards the allocator. [OBS-RE]

**Locking - G7.** No semaphore anywhere in the chain. Serialisation is by the callers: #822's chain runs
once, and #845's per-call path is behind `FSHELLINITED`/`FFILLDEVBLK` latches, not locks. [OBS-RE] /
[INF]

**Not established (G7):** `MASKFILLDEVBLK`'s writer and meaning; the value `ULOADWINTHORNVDH` stores into
`PSZWINDOWBVH` on failure; the promote/swap logic of device selection; who uses `\SHAREMEM\DOS\CDIB` at
+0xAAC (see G8); what +0x22A in a device-group block is.

### G8 - code pages, ANSI mode table (`SysModes`), shared-name templates, keyboard edit tables (+0xAAC..+0xC15)

**No fixups** in the range. No flat `0x13020AB0..0x13020AFF` operand in obj2. Object-3 routines that
address these offsets (`DOSSMSGSTART`, `DOSSMNOTIFYDD*`, `DOSSMGSWITCH`, `DOSSGSWITCH*`,
`DOSSMCHILDEXIT`, `DOSSMOPENDD`, `DOSPROTECTQUERYFHSTATE`) run with DS = object 5 - those are object-5
cells. `PCHGROWGLOBAL` has exactly three callers (`call 0x9d22` at `VGETTAGVALUE` 1C04869C,
`VREADENVVARS` 1C04872A, `UGROWDEVGROUP` 1C049DD2), so no G8 routine allocates from object 7's grown
tail. Kernel ordinals [DOC]: #36 DOSGETSHRSEG, #44 DOSLOADMODULE, #53 DOSDEVIOCTL, #70 DOSOPEN, #130
DOSGETCP. [OBS-RE]

**`SysModes` - 17 x 14-byte mode records** [OBS-RE]. Span +0xAFC..+0xBEB (0xF0 = 240 bytes, to `CP1` at
+0xBEC). The image splits into **17 records of 14 bytes** (+0xAFC..+0xBE9) followed by **0xFFFF at
+0xBEA**, which is **not part of the table** but the first word of `ANSIINIT`'s `DOSGETCP` buffer. Each
record's first word is 0x0008, 0x000C or 0x000E, and the bytes follow the VIOMODEINFO order: cb, fbType,
color, col, row, hres, vres, fmt_ID, attrib - e.g. record 0 is `{08 00, 05, 04, 40, 25, 320, 200, 00,
01}`, records 15-16 are `{0E 00, 01, 01|04, 80, 25, 1040, 725, 01, 01}`. The record layout and the
ANSI-mode mapping are given in full in queued trace 2 below.

**The only reader is `doRM`** (ANSI set/reset mode):
`imul bx,bx,0xe / lea si,[bx+0xafc] / push 0x9817 / push si / push di / call VIOSETMODE`
(`1C04A87F..8B`). The index is the ANSI mode number in BX: modes 0..6 map to themselves; mode 7 is
handled separately (clears bit 0x10 of `[es:0]`); modes 8..12 are ignored; modes 13..19 map to 7..13;
mode 0x28 (40) maps to 15; mode 0x2F (47) maps to 16; index 0 is forced when `[es:0x68]` = 0. If
`VIOSETMODE` fails at index 16, it retries index 14 (`1C04A89B..A7`). Every index is in 0..16, so exactly
17 records. The record is handed to `VIOSETMODE` whole. `doRM` has no static caller; it is reached from
the ANSI interpreter's escape dispatch [INF: `ANSIINTERP` #850]. `[es:0x68]` and `[es:0]` in `doRM` are
BVSCB cells (see object 8, I6).

| offset + IBM name | size/type | what it is | routines -> owning ordinals | initial value | concurrency (SMP) | prov |
|---|---|---|---|---|---|---|
| +0xAAC..+0xAAF (unnamed) | 4 bytes, 0 | Padding before the CDIB string; no reference | - | 0 | - | [OBS-RE] (absence) |
| +0xAB0 (unnamed, inside `CBBVSGSEG`'s `.sym` span) | string **`\SHAREMEM\DOS\CDIB`** | **Unused copy.** No obj4 reference in any instruction form. obj3's `_get_CDIB`/`_w_cdib` run with DS = object 5 (`1C030FDC`, `1C030E1F`) and use object 5's own copy (object 5 +0x70). No obj2 flat reference | - | string present | - | [OBS-RE] (absence, three searches) |
| +0xAC4 `CDIBSel` | WORD | **No reference found** (same three searches) | - | 0 | - | [OBS-RE] (absence) |
| +0xAC6 `NumCP` | WORD, image 2 | Number of code pages returned by `DOSGETCP`: `ANSIINIT` passes it as the returned-length cell, then halves it (bytes -> entries) and copies it to object 8 +0x386 | `ANSIINIT` (<- **#718 `OS2BASEINIT`**) | overwritten at the first `ANSIINIT`; image 2 is evidence of a two-entry list, not a required value | once per system via the +0xBEA sentinel; unlocked | [OBS-RE] |
| +0xAC8 `bvsSegLabel`, +0xAD9 `bvs_CP_ID` | string **`\SHAREMEM\BVS\BVS00`**, 2 chars overlaid | Name template for the **per-SG BVSCB** (the same object as G4's `bvsgBvscbName`). `AccessBVSCB` writes **the caller's SG** (LIS +0x08, `BinToHx`) into the two characters at +0xAD9 (`mov [es:bx+0x11],ax`, `bx=0xac8`), then `DOSGETSHRSEG` #36 into object 8 +0x38A (`1C04A3BB..D3`). **Despite the `.sym` name "CP_ID", what is stored there is the screen-group number, not a code page** | `AccessBVSCB` (<- **#848 `ANSIINJECT`**, **#849 `ANSIKEYDEF`**) | template required | **the shared name is patched in place, no lock**: two processes can build each other's name [INF] | [OBS-RE]; LIS+8 = SG [INF] |
| +0xADC `KdSegLabel`, +0xAED `KdSeg_SG_ID`, +0xAEF `KdSeg_CP_ID` | string **`\SHAREMEM\ANSI\KD0000`**, 2+2 chars overlaid | Name template for the ANSI **key-definition segment per (SG, code page)**. `AccessKeyDefSeg` writes hex(LIS +0x08) at +0xAED and hex(BX) at +0xAEF, then `DOSGETSHRSEG` #36 (`1C04A1B2..D2`) | `AccessKeyDefSeg` (<- #849 `ANSIKEYDEF`) | template required | patched in place, no lock | [OBS-RE]; BX = the code page [INF] from the name |
| +0xAF2 `szVioMod` | string **`VIOCALLS`** | **No reference found** in obj4 or flat obj2 | - | string present | - | [OBS-RE] (absence) |
| +0xAFC `SysModes` | 17 x 14-byte records (+0xAFC..+0xBE9) | ANSI display-mode table (above) | `doRM` -> `VIOSETMODE` | **the 17 records' values ARE the table** | read-only | [OBS-RE] |
| +0xBEA (unnamed, inside `SysModes`' span) / +0xBEC `CP1` / +0xBEE `CP2` | WORD x3; image **0xFFFF**, 0, 0 | The `DOSGETCP` buffer. +0xBEA = 0xFFFF means "not fetched yet". `ANSIINIT`: if +0xBEA = -1, `DOSGETCP` #130(cb 6, obj7:0xBEA, obj7:0xAC6), then **+0xBEA := 0**, `NumCP >>= 1`, and on success copies `NumCP`/`CP1`/`CP2` into object 8 +0x386/+0x390/+0x392 (`1C041FC0..F5`) | `ANSIINIT` (<- #718) | **0xFFFF sentinel required**: a zero cell skips `DOSGETCP` entirely, leaving `NumCP` at 0 instead of the fetched count [INF] | test-then-fetch-then-clear on a shared cell, no lock | [OBS-RE]; that `DOSGETCP`'s first entry is the current CP and the rest are prepared CPs (so CP1/CP2 the prepared pair) is [INF] |
| +0xBF0 `Shared_Handle` | WORD handle | A keyboard device handle **copied from this process's instance data** (`[0x3da]`, object 8) by `Init_CP` when `[es:0xc71]` (`CDIB_Sel`, G10) != 0 (`1C04B011..14`). Used by `Search_CP` and `Download` as the handle for `DOSDEVIOCTL` #53 category 4, function 0x77 (`1C04B140..4B`) | `Init_CP` (<- `SetCodepage` <- `KBDGETCP` #747 / `KBDFLUSHBUFFER` #757), `Search_CP`, `Download` | 0 | **a per-process handle stored in a SHARED cell**, unlocked: copied by whichever process ran `Init_CP` last and used by every process's `Search_CP`/`Download` IOCTL | [OBS-RE] for the store and the IOCTL push; ES = obj7 at those sites [INF] |
| +0xBF2 `Dev_Name` / +0xBFB `Action_Taken` | string **`KBD$    `** (8 + NUL) / WORD | Name and action cell for `DOSOPEN` #70 of the keyboard device (`push es / push 0xbf2`, `push es / push 0xbfb`) | `HandleOpen`, `BKSMAIN` (**#851**), `GetHWID`, `Init_CP` | string required | the action cell is shared scratch, unlocked | [OBS-RE] for the pushes; ES = obj7 [INF] |
| +0xBFD `ESCTAB` | 13 bytes: `00 3B 3C 3D 3E 3F 40 41 4B 4D 52 53 53` | Extended-key scan codes the keyboard line editor recognises (F1-F7, Left, Right, Ins, Del), scanned 13 entries long (`mov cx,0xd / mov di,0xbfd`) | `GETCH` (BKS string input) | table required | read-only | [OBS-RE] for the scan; key names [INF] from the scan codes |
| +0xC0A `EDITTAB` | 8 bytes: `06 7F 08 17 0A 1B 1A 0A` | ASCII editing characters, scanned 8 long (`mov cx,0x8 / mov di,0xc0a`) | `GETCH` | table required | read-only | [OBS-RE]; per-byte meanings [unverified] |
| +0xC12 `ShieldEntries` / +0xC14 `ShieldHandle` | WORD / WORD | `LoadWinthorn` (<- `BKSMAIN` #851): `DOSLOADMODULE` #44 of `Shield_DLL` (+0xC56, G9) with handle cell obj7:0xC14 (`lea si,[0xc14]`), then `xchg cx,[es:0xc12]` (`1C0421A1..B9`) | `LoadWinthorn` | see G9 | unlocked | [OBS-RE]; continued in G9 |

`\SHAREMEM\DOS\CDIB` (+0xAB0), `CDIBSel` (+0xAC4) and `VIOCALLS` (+0xAF2) have no reference in DOSCALL1's
code (obj2/obj3/obj4 searched): bytes present, no behaviour attached. [OBS-RE]

**Locking - G8.** None. Every write is a one-shot sentinel, a template patch or a handle store on shared
cells, with no semaphore in any routine read. [OBS-RE]

**Not established (G8):** `DOSGETCP`'s buffer semantics (first entry = current CP); where
`HandleOpen`/`GetHWID` keep their `KBD$` handle (settled in object 8, I7); the meaning of IOCTL category
4 function 0x77; the per-byte meaning of `EDITTAB`; whether anything outside DOSCALL1 reads `CDIBSel`,
`szVioMod` or the object-7 CDIB copy.

### G9 - the PMVIOP keyboard-shield vector (+0xC16..+0xC5D)

**No fixups** in the range. The vector is **16** far-pointer cells (+0xC16..+0xC55) followed by the
module name `Shield_DLL` (+0xC56); `ShieldEntries` (+0xC12, G8) = 16 confirms the count. There are 18
`call far [es:0xc..]` sites in obj4 plus `LoadWinthorn`'s `push 0xc56`; ES = obj7 is seen loaded at 9 of
them (`BKSMAIN` x2, `SetCustCP`, `GetCharIn`, `GetStatus`, `SetStatus`, `OUTSKIP` x3), and the other 9
inherit ES from `BKSMAIN`'s dispatch [INF]. [OBS-RE]

**How the vector is filled - `LoadWinthorn`** [OBS-RE] (whole body `1C0421A1..21EE`):
1. `DOSLOADMODULE` #44(fail buffer 0, name **obj7:0xC56 = "PMVIOP"**, handle -> **obj7:0xC14
   `ShieldHandle`**).
2. On success, `xchg cx,[es:0xc12]`: take `ShieldEntries` (image **0x0010 = 16**) and **leave 0 behind**.
   `jcxz` -> return.
3. Loop 16 times with `si` walking +0xC16 in 4-byte steps: `DOSGETPROCADDR` #45(hmod = `ShieldHandle`,
   name = **0000:`[es:si]`** - selector 0, so the image word is taken as an **ordinal**, -> a stack slot).
   On success `pop [es:si] / pop [es:si+2]` **overwrites that same cell with the resolved far pointer**. On
   the first failure it stops.

So **each cell starts as a PMVIOP ORDINAL and is replaced in place by the entry point**; the image
carries only the ordinal (no fixup, no name). Resolution happens **once per system**: `ShieldEntries` is
zeroed by the first caller, so later processes still `DOSLOADMODULE` PMVIOP but skip the loop and use the
pointers the first process wrote. That relies on PMVIOP's entry points having the same far address in
every process [INF: a loaded DLL's code selectors are global]. Because the count is cleared before the
loop, a `DOSGETPROCADDR` failure part-way leaves the remaining cells as raw ordinals for the life of the
system, with no retry [OBS-RE] / [INF]; a second process arriving between the `xchg` and the end of the
loop sees cells still holding ordinals [INF].

`BKSMAIN`'s dispatch table is at obj4 +0x1FFE, called as `call [cs:si+0x1ffe]` (`1C042191`); dispatch
index = KBD router function code - 0x100. Its 17 entries: 0 `GetCharIn`, 1 `PeekAtIt`, 2 `FlushBuffer`, 3
`GetStatus`, 4 `SetStatus`, 5 `GetStringIn`, 6 `HandleOpen`, 7 `HandleClose`, 8 `GetFocus`, 9 `FreeFocus`,
10 `GetCodepage`, 11 `SetCodepage`, 12 `Translate`, 13 `SetCustCP`, 14-15 **0**, 16 `GetHWID`; the words
after slot 16 are code, not table. `GetStringIn` (#753 KBDSTRINGIN) and `GetHWID` (#768) make no shield
call. [OBS-RE]

Cell names are DOSCALL1's `.sym` names, independently confirmed against PMVIOP's own exports in queued
trace 3. The PMVIOP ordinal is the image word.

| offset + IBM name | PMVIOP ordinal (image) | called by (obj4 site) | `BKSMAIN` slot -> KBD API ordinal | prov |
|---|---|---|---|---|
| +0xC16 `WINSYNCWITHPS` | 3 | `OUTSKIP` `1C04BC68` | - (VIO output path; `OUTSKIP` has no static caller) | [OBS-RE] |
| +0xC1A `WINCONSOLEOPENKBD` | 4 | `HandleOpen` `1C04B3DA` (when SG `dx` > `[0x3cc]`; else `DOSOPEN` `KBD$`, G8) | 6 -> KBDOPEN **#767** | [OBS-RE]; `[0x3cc]` = object 8's base-SG limit (I7) |
| +0xC1E `WINCONSOLECLOSEKBD` | 5 | `HandleClose` `1C04AB4E` | 7 -> KBDCLOSE **#761** | [OBS-RE] |
| +0xC22 `WINCONSOLESETSTATUS` | 6 | `SetStatus` `1C04B633` | 4 -> KBDSETSTATUS **#755** | [OBS-RE] |
| +0xC26 `WINCONSOLEGETSTATUS` | 7 | `GetStatus` `1C04AEF7` | 3 -> KBDGETSTATUS **#754** | [OBS-RE] |
| +0xC2A `WINCONSOLESETCP` | 8 | `SetCodepage` `1C04B56C` | 11 -> KBDSETCP **#749** | [OBS-RE] |
| +0xC2E `WINCONSOLEGETCP` | 0x0A | `GetCodepage` `1C04AEBA` | 10 -> KBDGETCP **#747** | [OBS-RE] |
| +0xC32 `WINCONSOLEKBDXLATE` | 0x0B | `Translate` `1C04BEB1` | 12 -> KBDXLATE **#758** | [OBS-RE] |
| +0xC36 `WINCONSOLESETCUSTXT` | 0x0C | `SetCustCP` `1C04ABDB` | 13 -> KBDSETCUSTXT **#745** | [OBS-RE] |
| +0xC3A `WINCONSOLEGETFOCUS` | 0x0D | `GetFocus` `1C04AD43` | 8 -> KBDGETFOCUS **#756** | [OBS-RE] |
| +0xC3E `WINCONSOLEFREEFOCUS` | 0x0E | `FreeFocus` `1C04AD99` | 9 -> KBDFREEFOCUS **#762** | [OBS-RE] |
| +0xC42 `WINCONSOLEREADKEYEVENT` | 0x0F | `GetCharIn` `1C04AE35`, `PeekAtIt` `1C04B4BC` | 0 -> KBDCHARIN **#748**; 1 -> KBDPEEK **#766** | [OBS-RE] |
| +0xC46 `WINCONSOLEFLUSHKEYEVENTS` | 0x10 | `FlushBuffer` `1C04AD1F` | 2 -> KBDFLUSHBUFFER **#757** | [OBS-RE] |
| +0xC4A `LOCKVIOPS` | 0x1B | `OUTSKIP` `1C04BC5A` | - (VIO output path) | [OBS-RE] |
| +0xC4E `UNLOCKVIOPS` | 0x1C | `OUTSKIP` `1C04BC74` | - | [OBS-RE] |
| +0xC52 `WINCONSOLEGETKBDHANDLE` | 0x1F | `BKSMAIN` `1C0420B7`, `1C0420D1` | **#851 `BKSMAIN`** itself | [OBS-RE] |
| +0xC56 `Shield_DLL` | string **`PMVIOP`** (+ 2 bytes 0) | `LoadWinthorn` (`push es / push 0xc56`) | <- #851 | [OBS-RE] |

**Common to the 16 pointer rows:** WORD ordinal in the image, then a 16:16 far pointer after
resolution; the PMVIOP entry point a windowed session's keyboard (and VIO echo) call is diverted to;
initialised from the image ordinal and resolved once per system by the first `LoadWinthorn` (<- `BKSMAIN`
#851); `ShieldEntries` is handed off by a single `xchg` - an atomic take on one CPU but not locked.
[OBS-RE]

**Locking - G9.** None. One-shot `xchg` on `ShieldEntries`, then unlocked in-place writes of 16 far
pointers into shared object 7. [OBS-RE]

**Not established (G9):** when `OUTSKIP` runs (its caller) and so when its `LOCKVIOPS`/`WINSYNCWITHPS`
path is taken; what a second process sees if it arrives mid-resolution beyond the [INF] above.

### G10 - keyboard code pages, `KEYBOARD.DCP` download, custom-CP ownership (+0xC5E..+0xD13)

Meaning of the KBD$ category 4 packets: `vio-kbd-mou.md` section 3.6/section 3.7 (from IBM's keyboard driver source
`kbdioct.asm`/`kbdddr.inc`) [DOC-IBM]. **No fixups** in the range. The code-page routines inherit
ES = obj7 from `BKSMAIN`'s dispatch (G9). Kernel ordinals [DOC]: #7 DOSEXITLIST, #8 DOSGETINFOSEG, #34
DOSALLOCSEG, #36 DOSGETSHRSEG, #39 DOSFREESEG, #52 (name not established), #53 DOSDEVIOCTL, #58
DOSCHGFILEPTR, #59 DOSCLOSE, #70 DOSOPEN; `DOSREAD` and `DOSGETCTRYINFO` are DOSCALL1 obj3 code (`.sym`).
Owning ordinals via `BKSMAIN`'s dispatch: slot 11 `SetCodepage` -> **#749 KBDSETCP**; slot 13 `SetCustCP`
-> **#745 KBDSETCUSTXT**; slot 9 `FreeFocus` -> **#762 KBDFREEFOCUS**; `BKSMAIN` **#851**. Call chain
[OBS-RE] (on the call encodings): `Init_CP` <- `SetCodepage`; `Search_CP` <- `Init_CP` (`call 0xb13d` at
1C04B122); `Check_CntryID` <- `Search_CP` (`call 0xb2ac` at 1C04B1CC); `Load_CP` <- `Search_CP`
(`call 0xb30f` at 1C04B296); **`Download` <- `Load_CP`, called twice** (`call 0xb355` at 1C04B336 and
1C04B343).

**The chain** [OBS-RE]:
1. **`BKSMAIN` (#851)** attaches the system code-page information block when `CDIB_Sel` = 0:
   `DOSGETSHRSEG` #36(`CDIB_Label` "\SHAREMEM\DOS\CDIB" -> `CDIB_Sel`) (`1C042171..80`). It also fills
   `GlobalSeg`/`LocalSeg` via `DOSGETINFOSEG` #8 when `LocalSeg` != its argument, and sets `LBaseSG` =
   GIS +0x19 (`SIS_MaxScrnGrp`) - 1. It copies `LBaseSG` into object 8 +0x3CC and the current SG (LIS +8)
   into object 8 +0x3CA (`1C042032..079`). **"SG > object 8 +0x3CC" is the windowed test** that routes
   every code-page call to the PMVIOP shield (G9) instead of KBD$.
2. **`SetCodepage` (#749)**:
   - first call per system: if `CP_InitFlag` bit 0x1 is clear and a CP is given, it sets the bit and runs
     `Init_CP` (`1C04B501..16`);
   - no tables loaded: if bit 0x2 (tables downloaded) is clear -> **0x1BC = 444** (`1C04B53A..46`);
   - unprepared CP: the requested CP must be in `Kbd_CP0..` (`repne scasw` over `Num_of_CP` words at
     +0xD01), else **0x1C0 = 448** (`1C04B54D..58`, `...5B9`);
   - windowed -> `WINCONSOLESETCP` (G9);
   - full-screen -> `KBDFLUSHBUFFER` if the CP changes, then **KBD$ category 4 function 0x58
     `SetInUseCP`** on this process's handle (object 8 +0x3DA) with the CP at object 8 +0x58C
     (`1C04B573..96`); on success `Handle0CP_Save` := 0xFFFF and `Handle0CCP_PID` := AX (`1C04B59F..B4`).
3. **`Init_CP`**: with DS = `CDIB_Sel`, copies `Shared_Handle` (G8), then the prepared CP list into
   `Kbd_CP1..` (+0xD03), capping `Num_of_CP` at 5 (`1C04B02C..4A`); copies the 6-byte country + subtype
   into `Cntry_ID`/`Subtype` (+0xC81, `rep movsw` x3, `1C04B067..71`); calls #52 twice into `PC_Model`
   (+0xCB9, item 5) and `PC_Submodel` (+0xCBA, item 4) (`1C04B075..88`); **`DOSOPEN`s the translate-table
   file** (name far pointer from the CDIB [INF: `KEYBOARD.DCP`]) with handle -> `Xlate_Handle` (+0xC77) and
   action -> `Action_Taken` (`1C04B08D..9F`); `DOSALLOCSEG`s **0x1000 bytes -> `Xlate_Tbl_Sel`** (+0xC7B),
   `Xlate_Tbl_Start` (+0xC79) = offset (`1C04B0B3..C0`); reads the header, seeks to the directory, reads
   it, runs `Search_CP`, and finally `DOSFREESEG`s the buffer and `DOSCLOSE`s the file (`1C04B0D9..135`).
4. **`Search_CP`**: issues **KBD$ category 4 function 0x77** on `Shared_Handle` and calls `DOSGETCTRYINFO`
   (`1C04B140..65`); walks the directory - `Check_CntryID` compares each entry's country / subtype with
   `Cntry_ID`/`Subtype` (`1C04B2AC..308`), and entries whose code page is in `Kbd_CP1..` are marked for
   download (`1C04B1F3..286`); runs `Load_CP`, and on success sets `CP_InitFlag` bit 0x2 (`1C04B291..9D`).
5. **`Load_CP` -> `Download`** (per marked CP): `Xlate_Tbl_CP` (+0xC7D) := the CP and `Xlate_Tbl_Index`
   (+0xC7F) += 1 (`1C04B325..2C`); `DOSCHGFILEPTR` to the table, then `DOSREAD` into
   `Xlate_Tbl_Start:Xlate_Tbl_Sel`; then **KBD$ category 4 function 0x5C `SetCodePage`** on
   `Shared_Handle` with **the parameter packet at obj7 +0xC79** (`push es / push 0xc79 / push 0x5c /
   push 4`, `1C04B355..3C4`).

**The 0x5C packet fits IBM's.** `SetCodePage`'s packet is *"{ DWORD far pointer to the caller's table;
WORD code page value; WORD CPCB index }"* [DOC-IBM]; obj7 +0xC79..+0xC80 is exactly `Xlate_Tbl_Start`
(WORD offset) + `Xlate_Tbl_Sel` (WORD selector) + `Xlate_Tbl_CP` + `Xlate_Tbl_Index`, and the index
increments once per prepared CP - *"0x5C, once per prepared code page"*. So DOSCALL1 contains an issuer
of 0x5C, reached lazily from the first `KbdSetCp` rather than at a fixed boot step. [OBS-RE] Whether it is
the boot-time issuer is not established.

| offset + IBM name | size/type | what it is | routines -> owning ordinals | initial value | concurrency (SMP) | prov |
|---|---|---|---|---|---|---|
| +0xC5E `CDIB_Label` | string **`\SHAREMEM\DOS\CDIB`** | Name of the code-page information block | `BKSMAIN` #851 | string required | read-only | [OBS-RE] |
| +0xC71 `CDIB_Sel` | WORD selector | CDIB selector, attached once; `Init_CP` runs only when it is non-zero | `BKSMAIN` (write), `Init_CP` (read) | 0 -> set on first `BKSMAIN` | test-then-attach, unlocked | [OBS-RE] |
| +0xC73 `Num_of_CP` | WORD, image 1 | Count of prepared CPs in `Kbd_CP*`, capped at 5 | `Init_CP` (W); `Search_CP`, `SetCodepage` (R) | overwritten by `Init_CP`; image 1 is evidence of a one-entry list | unlocked | [OBS-RE] |
| +0xC75 `CP_InitFlag` | WORD bitfield | **0x1** = `Init_CP` attempted; **0x2** = translate tables downloaded | `SetCodepage` (0x1 test/set, 0x2 test); `Search_CP` (sets 0x2) | 0; once per system | test-and-set unlocked | [OBS-RE] |
| +0xC77 `Xlate_Handle` | WORD file handle | The open translate-table file | `Init_CP` (open/close), `Search_CP`, `Load_CP`/`Download` (read/seek) | 0 | **a per-process file handle in a SHARED cell**, used for the whole download in one process | [OBS-RE]; file = `KEYBOARD.DCP` [INF] |
| +0xC79 `Xlate_Tbl_Start` / +0xC7B `Xlate_Tbl_Sel` / +0xC7D `Xlate_Tbl_CP` / +0xC7F `Xlate_Tbl_Index` | WORD x4 = **KBD$ category 4 function 0x5C packet** | Far pointer to the 4 KB buffer the table is read into; the CP value; the CPCB index | `Init_CP` (alloc), `Load_CP` (CP, index++), `Download` (read + IOCTL) | 0 | shared packet, unlocked | [OBS-RE] + [DOC-IBM] (packet shape) |
| +0xC81 `Cntry_ID` / +0xC83 `Subtype` | WORD / 4 bytes (6 bytes, copied as 3 WORDs) | Country code and keyboard subtype from the CDIB; `Check_CntryID` treats an all-blank subtype (`0x2020` x3) as a wildcard | `Init_CP` (W), `Check_CntryID` (R) | 0 | unlocked | [OBS-RE] |
| +0xC89 `UK166`, +0xC95 `FR189`, +0xCA1 `IT141`, +0xCAD `CS243` | 12 bytes each: **`KU166 KU168 `, `RF189 RF120 `, `TI141 TI142 `, `SC243 SC245 `** | Byte-swapped layout-ID pairs - **the `.sym` names are unswapped, the data swapped** (the two-letter half is stored byte-swapped, as in the keyboard driver's own tables). **No reader found** | - | strings present | - | [OBS-RE] (image, `.sym`); users [unverified] |
| +0xCB9 `PC_Model` / +0xCBA `PC_Submodel` | BYTE / BYTE | Outputs of DOSCALLS #52 items 5 and 4 | `Init_CP` | 0 | unlocked | [OBS-RE]; #52's name and item meanings not established |
| +0xCBB `Handle0CP_Save` | 32 bytes, **image all 0xFF** | Saved CP for KBD handle 0 while a custom CP is active; 0xFFFF = none. `SetCodepage` resets it to 0xFFFF; `SetCustCP` saves the prior CP; `CustomCP_Exit` restores | `SetCodepage` #749, `SetCustCP` #745, `CustomCP_Exit` | **0xFF fill required** (0xFFFF = no saved CP); a zero fill would make `CustomCP_Exit` treat every SG as holding a saved CP [INF] | unlocked | [OBS-RE]; per-SG indexing (16 x WORD) [INF] |
| +0xCDB `Handle0CCP_PID` | 32 bytes, 0 | Pid owning the custom CP: `SetCustCP` stores LIS +0 via `LocalSeg`; `CustomCP_Exit` (registered with `DOSEXITLIST` #7) restores only when the exiting pid matches | same | 0 | unlocked | [OBS-RE]; per-SG indexing [INF] |
| +0xCFB `GlobalSeg` / +0xCFD `LocalSeg` | WORD selector x2 | `DOSGETINFOSEG` output (GIS / LIS selectors) | `BKSMAIN` (W), `SetCustCP`, `CustomCP_Exit` (R) | 0 | **LIS selector stored in shared memory** (as `bvsgLISsel`, G4) | [OBS-RE] |
| +0xCFF `LBaseSG` | WORD | **GIS +0x19 (`SIS_MaxScrnGrp`) - 1**: SMP `BKSMAIN` `1C042050..5B` reads `mov al,[si+0x19] / dec al / cbw / mov [es:0xcff],ax` with DS = the GIS selector - matching DDK `bvscb.inc` `LastBaseSG ;(MaxBaseSG_from_InfoSeg - 1)`. Copied to object 8 +0x3CC as the windowed threshold | `BKSMAIN` | 0 | unlocked | [OBS-RE] + [DOC-IBM] |
| +0xD01 `Kbd_CP0`, +0xD03..+0xD0A `Kbd_CP1..Kbd_CP4` | WORD x5 | Prepared code-page list, scanned by `SetCodepage` (from +0xD01, `Num_of_CP` long) and filled by `Init_CP` (from +0xD03). `FreeFocus` passes obj7:0xD01 as the packet for **KBD$ category 4 function 0x57** | `Init_CP`, `Search_CP`, `Load_CP`, `SetCodepage`, `FreeFocus` #762 | 0 | unlocked | [OBS-RE]; function 0x57's meaning [unverified] |
| +0xD0B (unnamed), +0xD0C / +0xD0E / +0xD10 / +0xD12 (unnamed, inside `Kbd_CP4`'s `.sym` span) | BYTE / WORD x4 | **Saved return addresses** for `_MOUBASESUBSYS`, `_MOUALTSUBSYS`, `_KBDBASESUBSYS`, `_KBDALTSUBSYS`: each does `pop word [0xd0c...]` on entry and `push word [0xd0c...] / ret` to leave, with DS = obj7 (`push 0x9817 / pop ds`) | the four trampolines (G11's router family) | 0 | **a per-call return address in SHARED memory, no lock**: two threads entering the same trampoline concurrently would swap return addresses [INF] | [OBS-RE] |

The download uses shared cells for per-process resources (`Xlate_Handle`, the `Xlate_Tbl` packet,
`Shared_Handle`), protected only by `CP_InitFlag`'s unlocked one-shot; it works because a single process
performs the whole download. [OBS-RE] / [INF]

**Locking - G10.** None: one-shot flags (`CP_InitFlag`), shared scratch packets, shared handle and
selector cells; every store is unlocked in the code read. [OBS-RE]

**Not established (G10):** DOSCALLS #52's name and its items 4/5; KBD$ category 4 **function 0x77** (in
`Search_CP`) and **function 0x57** (in `FreeFocus`); readers of the byte-swapped layout-ID strings
(+0xC89..+0xCB8); the index register behind `Handle0CP_Save`/`Handle0CCP_PID`; the error names for 442
(0x1BA), 444 (0x1BC), 445 (0x1BD), 448 (0x1C0); whether the translate-table file is `KEYBOARD.DCP` (the
name comes from the CDIB, not read).

### G11 - keyboard/mouse router base and the SMP-only MMIO trace (+0xD14..+0xE21)

The one region where object 7's layout differs between SMP and UNI; what matters is the behaviour. **No
fixups** in the range. Kernel ordinals [DOC]: #8 DOSGETINFOSEG, #44 DOSLOADMODULE, #45 DOSGETPROCADDR,
#46 DOSFREEMODULE. GIS fields used (`infoseg.md`) [DOC-IBM]: `+0x26 SIS_mec_table[32]` *"RAS Major Event
Code table"*, `+0x4A SIS_MMIOBase` *"memory-mapped-I/O selector"*, `+0x4C SIS_MMIOAddr`.

**SMP vs UNI** [OBS-RE]: UNI (`.sym` `WARP45_U`) has **no `_MMIOKBDTrace`/`_MMIOMOUTrace`** and no
`_mmio_*` cells. Instruction counts SMP/UNI for routines with trace calls: `ROUTER` 142/110 (4 calls);
`KBDCHARIN` 124/73 (1 inline block); `ROUTSMINIT` 84/56 (4); `KBDREGISTER` 189/175 (2); `MOUREGISTER`
187/174 (2). Routines with no trace calls have identical counts: `_SessionInit` 33/33, `ROUTPROCESSINIT`
134/134.

**The SMP-only MMIO trace** [OBS-RE]:
- **Setup, once per system:** `_GlobalInit` (called once via `_global_initflag`, from `_SessionInit`):
  `_mmio_sel` := `[_global_info]+0x4A` - `_global_info` is the far pointer GIS:0, so this is
  `SIS_MMIOBase`; `_mmio_buffer` := far pointer `SIS_MMIOBase:0x0004` (the offset 4 is a literal,
  `mov word [es:0xd66],0x4`); `_global_initflag` := 1 (`1C0435DE..616`).
- **Gate per call:** `ROUTER`, `KBDREGISTER`, `MOUREGISTER`, `ROUTSMINIT` and `KBDCHARIN` first test a GIS
  bit - keyboard `les bx,[_global_info] / test byte [es:bx+0x32],0x8`; mouse `test byte [es:bx+0x33],0x20`
  (`1C042397..A0`, `...458..461`). GIS +0x32/+0x33 are **`SIS_mec_table` bytes 12 and 13**.
- **Emit:** `_MMIOKBDTrace(code, base)` / `_MMIOMOUTrace(code, base)` do nothing when `_mmio_sel` = 0;
  otherwise `ax = table[(code + base) x 2]` and **one WORD is written to `[_mmio_buffer]`**
  (`1C043AAC..AEB`, `...AEC..B20`). `ROUTER` passes `base` = 0 before dispatch and 0x14 (keyboard) / 0x1A
  (mouse) after (`1C0423A5..AA`, `...44A..4F`, `...466..6B`, `...510..15`). So the keyboard table (+0xDD2, 40
  WORDs) is 20 entry codes then 20 exit codes, and the mouse table (+0xD6A, 52 WORDs) is 26 + 26. Image
  values: keyboard entries `0x6403..0x6415`, exits `0x6483..0x6495`; mouse entries `0x6A02..0x6A1C`, exits
  `0x6A82..0x6A9C` - **high byte 0x64 = 100 for KBD, 0x6A = 106 for MOU; low byte = sub-function, bit
  0x80 on exit.**
- **`KBDCHARIN`'s extended record:** after the exit code (`_kbd_mmio_codes` entry 20, +0xDFA) it **sets
  `_mmio_buffer`'s offset to 0x000C** (`mov word [0xd66],0xc`), then writes the return code and the
  KBDKEYINFO bytes one WORD at a time to the same far pointer (`1C04262E..670`). The offset change is a
  store into the SHARED `_mmio_buffer`, not restored in the code through `1C042670`, so later single-word
  emits system-wide go to MMIO +0xC rather than +4 (possibly the intended data-vs-code port) [INF].
- **No concurrency control:** each emit is an unlocked write to a memory-mapped register; a multi-word
  `KBDCHARIN` record from two threads interleaves; and the router semaphores (`_KbdGetSemaphore`/
  `_MouGetSemaphore`, object-8 slots) are released **before** the exit trace (`call _KbdClearSemaphore`
  precedes the emit at `1C042439`/`...43C`), so the trace write is outside every lock.
- With `SIS_MMIOBase` = 0 the SMP code does nothing (`_mmio_sel` = 0 short-circuits every emit) - the only
  condition under which the SMP layout is behaviourally inert.

**What UNI does instead** [OBS-RE]: UNI's `_GlobalInit` is `push ds / ds = obj7 / es = [slot] / mov word
[es:0xd5a],1 / xor ax,ax / pop ds / ret` - it sets `_global_initflag` only (`1C043290..2A4`); UNI's
`KBDCHARIN` tail goes straight from `_KbdClearSemaphore` to storing the return code and `retf 8`
(`1C04253F..558`). UNI emits no trace at these points and has no MMIO cells; everything else in the router
is the same code.

Interpretation [INF]: a memory-mapped RAS trace port for the SMP kernel, keyed on `SIS_mec_table` major
codes 100/106. That the 0x64/0x6A high bytes are those major codes, and that the bits tested (0x08 in
byte 12, 0x20 in byte 13) are their enable bits (MSB-first: 96 + 4 = 100, 104 + 2 = 106), is arithmetic
over the table's documented name; the MEC bit order is not established.

| offset + IBM name | size/type | what it is | routines -> owning ordinals | initial value | concurrency (SMP) | prov |
|---|---|---|---|---|---|---|
| +0xD14 `_BMS_Addr` / +0xD18 `_BKS_Addr` | far ptr x2 | Entry point of the **mouse / keyboard base subsystem** in use. `ROUTPROCESSINIT` `DOSLOADMODULE`s `_bms_modname` "BMSCALLS" / `_bks_modname` "BKSCALLS", then `DOSGETPROCADDR` **ordinal 1** (name 0000:0001) into the cell. If the result is DOSCALL1's own `BMSMAIN` (obj4 +0x3B22) / `BKSMAIN` (+0x2020) - i.e. no alternate subsystem - it sets bit 0x8 / 0x10 in `_InitFlag` (+0xE22, G12) and `DOSFREEMODULE`s (`1C043702..7AE`). Called through by `_MOUBASESUBSYS`, `_KBDBASESUBSYS`, `_CHARIN/_STRINGIN/_GETFOCUS/_FREEFOCUSBASESUBSYS` | `ROUTPROCESSINIT` (<- **#718 `OS2BASEINIT`**); callers <- `ROUTER` (every KBD/MOU API) | 0; **rewritten by every process's `ROUTPROCESSINIT`** - far pointers resolved per process stored in SHARED memory | unlocked | [OBS-RE] |
| +0xD1C `_moudd_name` / +0xD28 `_kbddd_name` | strings **`\DEV\MOUSE$`**, **`\DEV\KBD$`** | Device names; `ROUTSMINIT` `push ds / push 0xd1c` | `ROUTSMINIT` (<- #760/#723) | strings required | read-only | [OBS-RE] |
| +0xD32 `_bms_entrypoint` / +0xD44 `_bks_entrypoint` | strings **`BMSMAIN`**, **`BKSMAIN`** | **No reader found**: the entry is resolved by ordinal 1, not by these names | - | strings present | - | [OBS-RE] (absence) |
| +0xD3A `_bms_modname` / +0xD4C `_bks_modname` | strings **`BMSCALLS`**, **`BKSCALLS`** | `DOSLOADMODULE` names above | `ROUTPROCESSINIT` | required | read-only | [OBS-RE] |
| +0xD56 `_moudd_exists` / +0xD58 `_sesmgr_pid` | BYTE / WORD | Run-time latches set by `ROUTSMINIT`; read by `_MouCheckProcType`, `KBDSWITCHFGND`, `MOUINITREAL` | `ROUTSMINIT` (<- #760 `KBDSHELLINIT`, #723 `MOUSHELLINIT`) | 0 | not established | [OBS-RE] |
| +0xD5A `_global_initflag` | WORD | One-shot for `_GlobalInit` | `_GlobalInit` (W), `_SessionInit` (R) | 0; once per system | unlocked test-then-init | [OBS-RE] (both builds) |
| +0xD5C `_global_info` | far ptr **GIS:0000** | `ROUTPROCESSINIT` stores offset 0 and the `DOSGETINFOSEG` #8 global selector (`1C043694..6B1`). Read for the MEC trace gate (+0x32/+0x33) and `SIS_MMIOBase` (+0x4A) by `ROUTER`, `KBDCHARIN`, `KBDSTRINGIN`, `KBDFREEFOCUS`, `KBDGETFOCUS`, `KBDREGISTER`, `KBDDEREGISTER`, `KBDSETFGND`, `ROUTSMINIT`, `MOUREGISTER`, `MOUDEREGISTER`, `KBDSYNCH`, `MOUSYNCH` | `ROUTPROCESSINIT` (<- #718) | 0; rewritten per process (the GIS selector is global) | unlocked | [OBS-RE] |
| +0xD60 `_mourout_ret` / +0xD62 `_kbdrout_ret` | WORD x2 | **No reader found.** The router trampolines park their return offsets at +0xD0C..+0xD12 (G10) instead | - | 0 | - | [OBS-RE] (absence) |
| **+0xD64 `_mmio_sel`** - SMP only | WORD selector | `SIS_MMIOBase`; 0 = trace disabled | `_GlobalInit` (W), `_MMIO*Trace`, `KBDCHARIN` (R) | 0 -> set once | unlocked | [OBS-RE] |
| **+0xD66 `_mmio_buffer`** - SMP only | far ptr (offset +0xD66, selector +0xD68) | Trace register: `SIS_MMIOBase:0004`; `KBDCHARIN` rewrites the offset to **0x000C** | `_GlobalInit`, `KBDCHARIN` (W); `_MMIO*Trace` (R) | 0 -> set once | **unlocked; the offset change is system-wide** | [OBS-RE] |
| **+0xD6A `_mou_mmio_codes`** - SMP only | WORD x52 | Mouse trace codes: 26 entry (`0x6Axx`) + 26 exit (`0x6A8x`) | `_MMIOMOUTrace` | **image values are the codes** | read-only | [OBS-RE] |
| **+0xDD2 `_kbd_mmio_codes`** - SMP only | WORD x40 | Keyboard trace codes: 20 entry (`0x64xx`) + 20 exit (`0x648x`) | `_MMIOKBDTrace`, `KBDCHARIN` (entry 20 at +0xDFA) | image values required | read-only | [OBS-RE] |

No router site compares a screen group with `LBaseSG` or `bvsgMaxBase`; the keyboard windowed comparison
lives in the BKS layer (object 8 +0x3CC), not in `ROUTER`. [OBS-RE]

**Not established (G11):** the MEC bit order; what device is behind `SIS_MMIOBase:0004/000C`, and whether
`SIS_MMIOAddr` (+0x4C) is used anywhere (not seen); whether `KBDCHARIN` restores `_mmio_buffer` to 4
after `1C042670`; the full `KBDCHARIN` record length; the meaning of `_moudd_exists`/`_sesmgr_pid` beyond
their setter and readers.

### G12 - base mouse subsystem (BMS), its dispatch tables and the mouse shield (+0xE22..+0xF23)

**No fixups**; the dispatch tables hold near code offsets and bytes, not far pointers. Kernel ordinals
[DOC]: #8 DOSGETINFOSEG, #44 DOSLOADMODULE, #45 DOSGETPROCADDR, #53 DOSDEVIOCTL, #59 DOSCLOSE, #70
DOSOPEN. Owners: **#852 `BMSMAIN`** (via `ROUTER` for every Mou API; `_BMS_Addr`, G11). `BMSINIT` <-
**#718 `OS2BASEINIT`**; `GLOBALINIT` <- `BMSINIT`; `SGCBINIT` <- `BMSINIT`, `BMSMAIN`; `MOUSEOPEN` <-
`BMSOPEN`, `GLOBALINIT`, `SGCBINIT`; `BMS_SET_POINTER_DRAW` <- `BMSOPEN`. The `BMS*`/`SHLD*` workers have
no static caller: they are reached through `_FunctionTable`. [OBS-RE]

**Dispatch - `BMSMAIN`** [OBS-RE]. `call [bx+0xe9e]` with **`bx` = `[bp-0xc]` + `[bp-0x1e]`**, doubled
(the preceding `shl bx,1`, `1C043D26`). `[bp-0x1e]` is the **MOU function code**; `[bp-0xc]` is **0 for
the direct (full-screen) arm and 0x16 = 22 for the shield (windowed) arm** (`mov word [bp-0xc],0x16` on
the shield path, `1C043BC5` context). So `_FunctionTable` is **2 x 22 near code offsets**: 22 function
codes x {direct, shield}. Before the call, `_ParmTable[code]` picks which caller arguments are forwarded
(`1C043CC9..D1B`): **0x10** = the first far pointer (`[bp+0x24]`) is the parameter packet; **0x01** = the
first far pointer is the data packet; **0x02** = the second far pointer (`[bp+0x28]`) is the data packet.
The direct worker `BMSFUNCTIONS` issues **`DOSDEVIOCTL` #53, category 7, function `_IoctlTable[code]`**
on the mouse handle (`1C043D65..74`); `BMSREADEVENTQUE` does the same (`1C04C89C..A7`). No bound check on
the code was visible [INF: `ROUTER` limits the code range].

| code | MOU API (ordinal) | `_FunctionTable[code]` direct | `[22+code]` shield | `_IoctlTable` (cat 7 fn) | `_ParmTable` |
|---|---|---|---|---|---|
| 0 | MOUGETNUMBUTTONS #726 (also MOUSHELLINIT #723 at code 0) | BMSFUNCTIONS | SHLDGETNUMBUTT | 0x60 | 0x10 |
| 1 | MOUGETNUMMICKEYS #721 | BMSFUNCTIONS | SHLDGETNUMMICK | 0x61 | 0x10 |
| 2 | MOUGETDEVSTATUS #739 | BMSFUNCTIONS | SHLDGETDEVSTATUS | 0x62 | 0x10 |
| 3 | MOUGETNUMQUEEL #730 | BMSFUNCTIONS | SHLDGETNUMQUEEL | 0x64 | 0x10 |
| 4 | MOUREADEVENTQUE #737 | BMSREADEVENTQUE | BMSREADEVENTQUE | 0x63 | 0x12 |
| 5 | MOUGETSCALEFACT #724 | BMSFUNCTIONS | SHLDGETSCALEFACT | 0x66 | 0x10 |
| 6 | MOUGETEVENTMASK #732 | BMSFUNCTIONS | SHLDGETEVENTMASK | 0x65 | 0x10 |
| 7 | MOUSETSCALEFACT #729 | BMSFUNCTIONS | SHLDALWAYSGOOD | 0x53 | 0x01 |
| 8 | MOUSETEVENTMASK #733 | BMSFUNCTIONS | SHLDSETEVENTMASK | 0x54 | 0x01 |
| 9 | MOUGETTHRESHOLD #722 | BMSGETSETTHRESHOLD | SHLDGETSETTHRESHOLD | 0x69 | 0x10 |
| 10 | MOUSETTHRESHOLD #728 | BMSGETSETTHRESHOLD | SHLDGETSETTHRESHOLD | 0x55 | 0x01 |
| 11 | MOUOPEN #734 | BMSOPEN | BMSOPEN | 0x00 | 0x00 |
| 12 | MOUCLOSE #727 | BMSCLOSE | SHLDCLOSE | 0x00 | 0x00 |
| 13 | MOUGETPTRSHAPE #719 | BMSFUNCTIONS | SHLDGETSETPTRSHAPE | 0x68 | 0x12 |
| 14 | MOUSETPTRSHAPE #720 | BMSFUNCTIONS | SHLDGETSETPTRSHAPE | 0x56 | 0x12 |
| 15 | MOUDRAWPTR #743 | BMSFUNCTIONS | SHLDALWAYSGOOD | 0x57 | 0x00 |
| 16 | MOUREMOVEPTR #735 | BMSFUNCTIONS | SHLDALWAYSGOOD | 0x58 | 0x01 |
| 17 | MOUGETPTRPOS #736 | BMSFUNCTIONS | SHLDGETPTRPOS | 0x67 | 0x10 |
| 18 | MOUSETPTRPOS #738 | BMSFUNCTIONS | SHLDSETPTRPOS | 0x59 | 0x01 |
| 19 | - (no MOU export at this code) | BMSFUNCTIONS | SHLDALWAYSGOOD | 0x5B | 0x00 |
| 20 | MOUFLUSHQUE #725 | BMSFLUSHQUE | SHLDFLUSHQUE | 0x00 | 0x00 |
| 21 | MOUSETDEVSTATUS #742 | BMSFUNCTIONS | SHLDALWAYSGOOD | 0x5C | 0x01 |

[OBS-RE] for all table values (image bytes decoded through the obj4 symbol names, and read indexed by
the code in `BMSMAIN`/`BMSFUNCTIONS`/`BMSREADEVENTQUE`). **The shield arm answers "always good" for
set-scale-factor, draw/remove pointer, code 19 and set-device-status** - the windowed console owns
those. The category-7 function values are consistent with `GLOBALINIT`'s own direct uses: 0x60 ->
`_NumButtons`, 0x61 -> `_NumMickeys`, 0x6A -> `_MouseVer`. The 44 code offsets, 22 IOCTL function bytes and
22 parameter-flag bytes are the policy deciding what every Mou API does in a full-screen versus windowed
session.

| offset + IBM name | size/type | what it is | routines -> owning ordinals | initial value | concurrency (SMP) | prov |
|---|---|---|---|---|---|---|
| +0xE22 `_InitFlag` | WORD bitfield | **0x1** `GLOBALINIT` done (`1C04C190`, tested by `BMSINIT`); **0x2** set by `VIOINITPROCESS` (`1C0402E9`) - the shared latch "BVSCALLS ordinal 3 resolves to DOSCALL1's own `e026:1887`", set unlocked by the first process (object 8 I1, `bvs_off`); idempotent; **0x4** mouse shield resolved (`BMSMAIN` `1C043C5E`); **0x8/0x10** BMSCALLS/BKSCALLS resolve back to DOSCALL1's own mains, i.e. no alternate subsystem (`ROUTPROCESSINIT`, G11) | as listed | 0; each bit set once | `or byte` on a shared cell, unlocked | [OBS-RE] |
| +0xE24 `_bms_localinfo` | far ptr | Stored by `SGCBINIT` after `DOSGETINFOSEG` (`1C04C1C6..CB`); read by `BMSMAIN`, `BMSEXITLIST` | `SGCBINIT` (<- `BMSINIT`, #852) | 0 | per-process infoseg value in a SHARED cell | [OBS-RE] for the store; the pointer's target [INF: LIS-derived] |
| +0xE28 `_MouseFileName` | string **`\DEV\MOUSE$ `** | `MOUSEOPEN`'s `DOSOPEN` name (`push 0x9817 / push 0xe28`) | `MOUSEOPEN` | string required | read-only | [OBS-RE] |
| +0xE36 `_MouseVer` | WORD | `GLOBALINIT`: category 7 function **0x6A** into it (`1C04C131..40`); read by `BMSOPEN` | `GLOBALINIT` (<- `BMSINIT` <- #718) | 0 -> once per system | unlocked; a hardware fact fetched once by the first `BMSINIT` and served to every process | [OBS-RE]; "version" = the `.sym` name |
| +0xE38 `_SkeletonPtrName` | string **`\DEV\` + 8 blanks** | Pointer-draw device name template (`push 0x9817 / push 0xe38` in `BMS_SET_POINTER_DRAW`) | `BMS_SET_POINTER_DRAW` (<- `BMSOPEN`) | template required | patched in place if filled, like G8's templates [INF] | [OBS-RE] for the push; the fill not established |
| +0xE46 `_NumButtons` / +0xE48 `_NumMickeys` | WORD x2 | `GLOBALINIT`: category 7 function **0x60** / **0x61** into them; returned by the shield arm's `SHLDGETNUMBUTT`/`SHLDGETNUMMICK` | `GLOBALINIT`; `SHLD*` | 0 -> once per system | unlocked; fetched once, served system-wide | [OBS-RE] |
| +0xE4A `_Shield_DLL` / +0xE52 `_ShieldHandle` | string **`PMVIOP`** / WORD | `BMSMAIN`: `DOSLOADMODULE` #44(`_Shield_DLL`, handle -> `_ShieldHandle`) (`1C043BCF..DD`) | #852 | string / 0 | unlocked | [OBS-RE] |
| +0xE54..+0xE77 `_WINCONSOLEFLUSHPOINTEREVENTS` ... `_WINCONSOLEDETACHMOUSEUSER` | far ptr x9 | The mouse half of the PMVIOP shield vector, called by `SHLD*` (`call far [es:0xe5c]`, `...e60`, `...e70`, `...e74`, `...e54`, `...e58`, ...). Cell-by-cell pairing in queued trace 3 | #852 -> the `SHLD*` arm | 0 -> resolved once | same resolve-in-place, zeroed-count scheme as G9 (no retry) | [OBS-RE] |
| +0xE78 `_ShieldEntries` | WORD, **image 9** | Count for the resolve loop: `BMSMAIN` `DOSGETPROCADDR`s by ordinal (name `0000:[entry]`) and `dec word [0xe78]` per entry until 0. It sets `_InitFlag` 0x4, or returns **0x1F5 = 501** on failure (`1C043BE9..C5E`) | #852 | **9 required** | one-shot, unlocked | [OBS-RE] |
| +0xE7A..+0xE9D `_Shield_33`, `_32`, `_23`, `_22`, `_21`, `_20`, `_18`, `_17`, `_19` | DWORD x9, **image = PMVIOP ordinals 0x21, 0x20, 0x17, 0x16, 0x15, 0x14, 0x12, 0x11, 0x13** | The ordinals the loop resolves. **The `.sym` names ARE the decimal ordinals**, which confirms the values independently of PMVIOP | `BMSMAIN` | image values required | read-only | [OBS-RE] |
| +0xE9E `_FunctionTable` | near offset x44 | Dispatch table above | #852 `BMSMAIN` | **image values are the dispatch** | read-only | [OBS-RE] |
| +0xEF6 `_IoctlTable` | BYTE x22 | MOUSE$ category 7 function per MOU code (table above) | `BMSFUNCTIONS`, `BMSREADEVENTQUE`, `BMSGETSETTHRESHOLD` | image values required | read-only | [OBS-RE] |
| +0xF0C `_ParmTable` | BYTE x22 | Argument-forwarding flags per MOU code (0x10 / 0x01 / 0x02) | `BMSMAIN` | image values required | read-only | [OBS-RE] |
| +0xF22 `_end_CDATA` | label (2 bytes, 0) | End of object 7's image; `CBBVSGSEG` = 0x0F23 (G7) points here | - | - | - | [OBS-RE] |

**Locking - G12.** None in any routine read: `GLOBALINIT`'s one-shot, the shield resolve, `_InitFlag`
bits and `_bms_localinfo` are all unlocked stores on shared cells; the dispatch tables are read-only.
[OBS-RE]

**Not established (G12):** the code-range bound before `call [bx+0xe9e]`; `_bms_localinfo`'s exact
target; `_SkeletonPtrName`'s fill; code 19's API (no MOU export at code 0x13); the category-7 function
names; error 502 (0x1F6) at `1C043CB3`.

### Object 7 trace 1 - the `PDEVGROUPS` device-group block (0x334 bytes, in object 7's grown tail)

[OBS-RE] throughout unless marked. Routines: `UGROWDEVGROUP`, `FGETFREECALLTABLE`,
`FGETFREEDEVTABLEENTRY`, `FFINDDEVICE`, `VINITIALIZEENTRY`, `FHASADDRESSABILITY`, `FADDDEVICE`,
`FREGISTERDEVICE`, `DOSUNLOADVIDEOHANDLER`, `FMAKEDEVADDRESSABLE`, `FGETENABLEENTRY`,
`VFREEDEVTABLEENTRY`, `DOSLOADVIDEOHANDLER` (`1C04923D..32F`), `DOSDRIVERENABLE` (`1C0493F0..4C8`).
obj4 names used: +0x91A6 `UERRORFUNCTION`, +0x7757 `VDHPRTSC`, +0x7F46 `VDHWRTTTY`. Kernel ordinals [DOC]:
#44/#45/#46 load/getprocaddr/free module, #53 DOSDEVIOCTL, #59 DOSCLOSE, #70 DOSOPEN.

**Two pointer kinds escape into the block:** **E = block + 2**, the *device entry*, returned by
`FGETFREEDEVTABLEENTRY` and `FFINDDEVICE`; **T = block + 0x2CC**, the *call table*, returned by
`FGETFREECALLTABLE`. Offsets below are from the block start and, where a routine addresses E, also
E-relative.

**Allocation.** `UGROWDEVGROUP` runs only when no existing group has a free call table
(`FGETFREECALLTABLE`) or a free device entry (`FGETFREEDEVTABLEENTRY`) (`1C049EA7..AE`, `...F7E..85`):
1. `PCHGROWGLOBAL(0x334)` (bump-allocated from object 7's own tail, zero-filled - G7).
2. `PDEVGROUPS[CDEVGROUPS]` := the far pointer; on a zero pointer return **479**.
3. Block +0 := 0.
4. `VINITIALIZEENTRY(E)`.
5. Block +0x22A := `CDEVGROUPS` (the group's own index).
6. `CDEVGROUPS++` (`1C049DC0..E6A`).

- **How many groups:** `PDEVGROUPS` holds 16 far pointers (+0xA4E..+0xA8D), but **`UGROWDEVGROUP` never
  checks `CDEVGROUPS` < 16** before indexing; a 17th group would overwrite `CDEVGROUPS` itself (+0xA8E)
  and beyond [INF]. The other limit is `PCHGROWGLOBAL`'s 64 KB cap on object 7.
- **One block = one device entry + one call table, allocated independently.** A group's call table can be
  in use while its device entry is free, and vice versa (separate in-use markers, below).
- **Lifecycle:** blocks are **never freed**. `DOSUNLOADVIDEOHANDLER` -> `FFINDDEVICE` ->
  `VFREEDEVTABLEENTRY` frees the entry's modules (`DOSFREEMODULE` #46 on each component handle) and re-runs
  `VINITIALIZEENTRY` (`1C049FE1..A002`). Nothing observed clears block +0 bit 0x8, so a call table once
  taken stays taken, and repeated load/unload grows groups - and object 7 - without bound [INF].
- **Owning ordinals:** the whole family is reached from **#845 `BVSMAIN`** / the **#822 `VIOSHELLINIT`**
  chain: `BVSDINIT` -> `BVSGETVIDEOCALLTABLES` / `UINITGENERICVDH` / `ULOADWINTHORNVDH` ->
  `DOSLOADVIDEOHANDLER` / `DOSUNLOADVIDEOHANDLER`.
- **Locking:** none. Every routine on the path runs inside `SAVEREGS`/`RESTOREREGS` (a register spill);
  no semaphore call appears. Serialisation is the #822/#845 callers' one-shot latches (`FSHELLINITED`,
  `FFILLDEVBLK`).

| block off | E off | width | field | meaning | writers | readers | prov |
|---|---|---|---|---|---|---|---|
| +0x000 | - | WORD | group flags | **bit 0x8 = this group's call table is allocated** | `UGROWDEVGROUP` (:= 0); `FGETFREECALLTABLE` (`or byte [es:bx],0x8`, `1C049EF2`) | `FGETFREECALLTABLE` (`test byte [es:bx],0x8`) | [OBS-RE] |
| +0x002 | +0x000 | char[0x200] | device string | First string of the entry: `FADDDEVICE` `_strcpy`s the device name into it; `FFINDDEVICE` `_strcmp`s it with its first name argument (`1C049607..14`); `VINITIALIZEENTRY` clears the first byte | `FADDDEVICE`, `VINITIALIZEENTRY` | `FFINDDEVICE` | [OBS-RE]; that it holds the `VIDEO_DEVICES` component string is [INF] (from `FADDDEVICE`'s arguments) |
| +0x202 | +0x200 | char[0x20] | second name | `FFINDDEVICE` compares it with its second name argument (`add ax,0x202`, `1C04962E..39`); `FADDDEVICE` copies into it; cleared by `VINITIALIZEENTRY` | `FADDDEVICE`, `VINITIALIZEENTRY` | `FFINDDEVICE` | [OBS-RE]; meaning [unverified] |
| +0x222 | +0x220 | WORD | key word 1 | Compared by `FFINDDEVICE` with its `[bp+6]`; written by `FADDDEVICE`; read by `FMAKEDEVADDRESSABLE` | `FADDDEVICE`, `VINITIALIZEENTRY` (0) | `FFINDDEVICE`, `FMAKEDEVADDRESSABLE` | [OBS-RE]; meaning [unverified] |
| +0x224 | +0x222 | WORD | key word 2 | Compared by `FFINDDEVICE` with `[bp+4]`; written by `FADDDEVICE`; read by `FMAKEDEVADDRESSABLE` | same | same | [OBS-RE] |
| +0x226 | +0x224 | WORD | **entry in use** | Non-zero = the device entry is taken. `FGETFREEDEVTABLEENTRY` sets 1 (`mov word [es:bx+0x224],1` on E, `1C049FB8`); `FFINDDEVICE`/`FGETFREEDEVTABLEENTRY` skip groups where it is 0 / non-0 | `FGETFREEDEVTABLEENTRY`, `VINITIALIZEENTRY` (0) | `FFINDDEVICE`, `FGETFREEDEVTABLEENTRY` | [OBS-RE] |
| +0x228 | +0x226 | WORD | **component count** | Number of components in the device string: `FADDDEVICE` stores it last (`1C04989A`); `DOSDRIVERENABLE` loops `si` < it (`1C049464..6C`) | `FADDDEVICE`, `VINITIALIZEENTRY` (0) | `DOSDRIVERENABLE` | [OBS-RE] |
| +0x22A | +0x228 | WORD | **group index** | This block's `PDEVGROUPS` index, set once at allocation. Used as the index into a **per-process addressability byte array at object 8 +0x360** (`FHASADDRESSABILITY` reads, `FMAKEDEVADDRESSABLE` sets 1, `DOSDRIVERENABLE` clears; ES = slot 0x34 = obj8) - a per-process "has this group's modules loaded" byte indexed by a shared group index | `UGROWDEVGROUP` | `FHASADDRESSABILITY`, `FMAKEDEVADDRESSABLE`, `FADDDEVICE` | [OBS-RE] |
| +0x22C + 10,k (k = 0..15) | +0x22A + 10,k | 10 bytes x **16** | **component record k** | Cleared by `VINITIALIZEENTRY` for k < 16 (`1C0494F1..1C`) | `FADDDEVICE`, `VINITIALIZEENTRY` | `DOSDRIVERENABLE`, `VFREEDEVTABLEENTRY`, `FMAKEDEVADDRESSABLE` | [OBS-RE] |
| &nbsp;&nbsp;rec +0 / +2 | +0x22A / +0x22C | WORD x2 | device-driver IOCTL | For a **device-driver component** (`FISDEVICEDRIVER`): `DOSDRIVERENABLE` `DOSOPEN`s the component name, then issues `DOSDEVIOCTL` with rec +2 / rec +0 pushed as category / function, then closes (`1C0493F0..44D`) | `FADDDEVICE` (`1C0497C4`, `...D6`) | `DOSDRIVERENABLE` | [OBS-RE] for the pushes; which word is category vs function [INF] from push order |
| &nbsp;&nbsp;rec +4 | +0x22E | far ptr | **DEVENABLE entry** | For a **DLL component**: `FGETENABLEENTRY` (`DOSLOADMODULE` + `DOSGETPROCADDR`) stores it; `DOSDRIVERENABLE` `call far [es:bx+0x22e]` with 6 arguments when non-null (`1C049498..BC`) | `FADDDEVICE` (`1C049825..2A`) | `DOSDRIVERENABLE`, `FMAKEDEVADDRESSABLE` | [OBS-RE]; the name `DEVENABLE` from `SZDEFENTRY` (G7), which `DOSLOADVIDEOHANDLER` pushes |
| &nbsp;&nbsp;rec +8 | +0x232 | WORD | module handle | `DOSFREEMODULE` #46 on free (`VFREEDEVTABLEENTRY` `1C049FE4..F1`, `FMAKEDEVADDRESSABLE` `1C049C94`); a per-process value stored in SHARED object 7 | `FADDDEVICE` (`1C049810`) | `VFREEDEVTABLEENTRY`, `FMAKEDEVADDRESSABLE` | [OBS-RE] |
| +0x2CC..+0x333 | - | far ptr x **26** | **call table T** (the handler's CVT) | `FGETFREECALLTABLE` initialises all 26 slots to **obj4 `UERRORFUNCTION`**, slot 21 (+0x54) to **`VDHPRTSC`** and slot 22 (+0x58) to **`VDHWRTTTY`** (`1C049EFB..F39`). `DOSLOADVIDEOHANDLER` builds a 0x11A-entry scratch table (entries 0..0xFF = `UERRORFUNCTION`, entries **0x100..0x119** = T's current slots), calls `DOSDRIVERENABLE`(..., `DEVENABLE`, `FFILLDEVBLK`, parameters {`MASKFILLDEVBLK`, scratch table}) and copies entries 0x100..0x119 back into T (`1C04924F..32F`). **So slot n = CVT function 0x100 + n, i.e. functions 256..281** | `FGETFREECALLTABLE`, `DOSLOADVIDEOHANDLER` | the call tables referenced from `bvsg_calltables` (G4) [INF] | [OBS-RE]; the enable sub-function values pushed (3, 0x73) not decoded |

**0x334 = 2 + 0x200 + 0x20 + 6x2 + 16x10 + 0x68**, closing exactly on the block size, so the layout is
fully accounted for. [OBS-RE] (arithmetic)

**Not established:** the meanings of the second name (+0x202) and the two key words (+0x222/+0x224);
which component-record word is IOCTL category vs function; the DEVENABLE call's 6 arguments and the (3,
0x73) pushed by `DOSLOADVIDEOHANDLER`; how T gets into `bvsg_calltables` (G4's slot writers -
`UINITGENERICVDH` slot 1 - not traced to T); whether anything clears block +0 bit 0x8.

### Object 7 trace 2 - `SysModes` record fields and the ANSI mode -> display mode mapping

**Sources.**
- **`VIOMODEINFO`** [DOC-IBM] - Toolkit `bsesub.h` (lines 498-514), packed: `USHORT cb; UCHAR fbType;
  UCHAR color; USHORT col; USHORT row; USHORT hres; USHORT vres; UCHAR fmt_ID; UCHAR attrib;` then `ULONG
  buf_addr, buf_length, full_length, partial_length; PCH ext_data_addr`. Constants (488-490) `COLORS_2`
  0x0001, `COLORS_4` 0x0002, `COLORS_16` 0x0004; (521-523) `VGMT_OTHER` 0x01, `VGMT_GRAPHICS` 0x02,
  `VGMT_DISABLEBURST` 0x04.
- **ANSI set / reset mode** [DOC-IBM] - the DDK Display reference, "Set Mode (SM)" / "Reset Mode (RM)":
  `ESC [=#h` parameters **0** 40x25 B&W, **1** 40x25 colour, **2** 80x25 B&W, **3** 80x25 colour, **4**
  320x200 colour, **5** 320x200 B&W, **6** 640x200 B&W, **7** wrap at end of line; RM takes the same
  parameters, and 7 resets wrap. **The book documents no other parameter.**
- **Records:** image obj7 +0xAFC..+0xBE9 decoded as 17 x 14 bytes. [OBS-RE]
- **Code:** `doSM` (`1C04A822..82F`: mode 7 sets `[es:0]` bit 0x10, else `jnz 0xa840`) and `doRM` (whole).
  **`doSM` joins `doRM`'s body at `1C04A840`**, so set and reset share one table walk and differ only on
  mode 7. [OBS-RE]

**The record is the first 14 bytes of `VIOMODEINFO`, and `cb` limits what VioSetMode reads.** Each
record's bytes line up exactly with `cb`, `fbType`, `color`, `col`, `row`, `hres`, `vres`, `fmt_ID`,
`attrib` (2+1+1+2+2+2+2+1+1 = 14). The whole record is passed to `VIOSETMODE`, and `cb` tells VioSetMode how
much of it to read: **cb 8** (records 0-3) passes only `fbType`, `color`, `col`, `row` - those records
still carry `hres`/`vres`/`fmt_ID`/`attrib` bytes that VioSetMode is not asked to read; **cb 12** (records
4-14) also passes `hres`/`vres`; **cb 14** (records 15-16) also passes `fmt_ID`/`attrib`. `fbType`
decomposes into `VGMT_*` bits, and `color` matches the `COLORS_*` encoding (1 = 2 colours, 2 = 4, 4 = 16);
the values 0 (monochrome) and 8 (256) are the same encoding extended [INF]. Behaviour depends only on the
first `cb` bytes [INF from VioSetMode's `cb` contract], but the unused bytes are part of the image.
[OBS-RE]

| rec | +off | cb | fbType (VGMT bits) | color | colxrow | hresxvres | fmt / attr | reached from ANSI mode | IBM doc for that mode |
|---|---|---|---|---|---|---|---|---|---|
| 0 | +0xAFC | 8 | 0x05 OTHER\|DISABLEBURST | 4 | 40x25 | (320x200) | (0/1) | **0**, and any mode in a sequence with no parameters | 40x25 B&W yes (burst off = B&W) |
| 1 | +0xB0A | 8 | 0x01 OTHER | 4 | 40x25 | (320x200) | (0/1) | **1** | 40x25 colour yes |
| 2 | +0xB18 | 8 | 0x05 OTHER\|DISABLEBURST | 4 | 80x25 | (640x200) | (0/1) | **2** | 80x25 B&W yes |
| 3 | +0xB26 | 8 | 0x01 OTHER | 4 | 80x25 | (640x200) | (0/1) | **3** | 80x25 colour yes |
| 4 | +0xB34 | 12 | 0x03 OTHER\|GRAPHICS | 2 (4 col) | 40x25 | 320x200 | 0/1 | **4** | 320x200 colour yes |
| 5 | +0xB42 | 12 | 0x07 OTHER\|GRAPHICS\|DISABLEBURST | 2 | 40x25 | 320x200 | 0/1 | **5** | 320x200 B&W yes |
| 6 | +0xB50 | 12 | 0x03 OTHER\|GRAPHICS | 1 (2 col) | 80x25 | 640x200 | 0/1 | **6** | 640x200 B&W yes (2 colours) |
| 7 | +0xB5E | 12 | 0x03 | 4 (16) | 40x25 | 320x200 | 0/1 | **13** | *not documented* |
| 8 | +0xB6C | 12 | 0x03 | 4 | 80x25 | 640x200 | 0/1 | **14** | *not documented* |
| 9 | +0xB7A | 12 | 0x02 GRAPHICS (no OTHER) | 0 | 80x25 | 640x350 | 0/1 | **15** | *not documented* |
| 10 | +0xB88 | 12 | 0x03 | 4 | 80x25 | 640x350 | 0/1 | **16** | *not documented* |
| 11 | +0xB96 | 12 | 0x03 | 1 | 80x30 | 640x480 | 0/1 | **17** | *not documented* |
| 12 | +0xBA4 | 12 | 0x03 | 4 | 80x30 | 640x480 | 0/1 | **18** | *not documented* |
| 13 | +0xBB2 | 12 | 0x03 | 8 | 40x25 | 320x200 | 0/1 | **19** | *not documented* |
| 14 | +0xBC0 | 12 | 0x03 | 2 | 80x25 | 640x350 | 0/1 | **retry only**: mode 16 when `VIOSETMODE` fails | - |
| 15 | +0xBCE | 14 | 0x01 OTHER (text) | 1 | 80x25 | 1040x725 | **1/1** | **40** | *not in the ANSI book*; IBM's DBCS "EPOCH Mono" mode |
| 16 | +0xBDC | 14 | 0x01 OTHER (text) | 4 | 80x25 | 1040x725 | **1/1** | **47** | *not in the ANSI book*; IBM's DBCS "EPOCH Color" mode |

Records 15-16, the only cb = 14 records, are IBM's DBCS "EPOCH Mono" / "EPOCH Color" modes (DDK
`VDHVGAJ` `vdhdata.h`, lines 196-206) [DOC-IBM].

**The mapping, as `doRM` builds it** [OBS-RE]:
- **Mode 7:** `doSM` sets / `doRM` clears bit 0x10 of `[es:0]` (wrap) and returns. No mode set.
- **Modes 0-6** -> records 0-6. **Modes 8-12** are ignored (fall through to exit, `jc 0xa8a9`).
- **Modes 13-19** -> mode - 6 -> records 7-13. **Mode 40 (0x28)** -> 40 - 25 -> record 15. **Mode 47 (0x2F)** ->
  47 - 6 - 25 -> record 16. Any other value -> exit.
- **Forced record 0:** when `[es:0x68]` = 0 the index is zeroed before multiplying (`1C04A873..7D`).
  `[es:0x68]` is the BVSCB's `bvs_ParmCount`, so record 0 (40x25 B&W) is forced only for a sequence with no
  parameters.
- **Result:** AL = 0x4A is set on **success** (then `'J'`: clear and home). A failure is ignored, except
  for parameter 16, which retries once with record 14 (`1C04A89B..A7`) - 640x350 at 4 colours instead of
  16.
- **Checks:** documented modes 0-6 all agree with IBM's table on geometry and B&W/colour (B&W =
  `VGMT_DISABLEBURST` or a 2-colour `color`). Modes 13-19, 40, 47 and the retry record are not in the ANSI
  reference; their rows are what the records say, not IBM names. So `SysModes` supports 13 ANSI modes the
  reference book does not document, plus a silent 16 -> 640x350 4-colour retry.

### Object 7 trace 3 - PMVIOP export names for the keyboard (G9) and mouse (G12) shield vectors

**Method** [OBS-RE]. Three independent sources joined by address: (1) PMVIOP.DLL's own LX entry table -
**all 25 ordinals exist, all 16-bit entries in object 1**; the resident name table holds only the module
name, so **the export names are not in the resident name table** (the non-resident table was not
examined) and a by-name import of these entry points cannot assume a resident name; DOSCALL1 imports
them by ordinal; (2) IBM's `PMVIOP.SYM` for Warp 4.5 UNI (segment 1 = object 1), giving segment:offset ->
name; (3) a decompile of PMVIOP whose routine names and offsets match (2) (e.g. `WINCONSOLEOPENKBD` at
1:49CA, `LOCKVIOPS` at 1:0250). Each ordinal's entry-table offset (1) equals the offset of a symbol (2):
**all 25 match exactly**, which is what establishes that the names fit the PMVIOP.DLL examined (a different
build from the one the `.sym` was made for) for these entry points.

**Keyboard vector (G9, obj7 +0xC16..+0xC55)** - every cell's DOSCALL1 `.sym` name equals PMVIOP's name for
the ordinal in the image:

| obj7 cell (DOSCALL1 `.sym`) | PMVIOP ordinal (obj7 image) | PMVIOP entry (obj1 offset) | PMVIOP name | agrees |
|---|---|---|---|---|
| +0xC16 `WINSYNCWITHPS` | 3 | 0x6220 | `WINSYNCWITHPS` | yes |
| +0xC1A `WINCONSOLEOPENKBD` | 4 | 0x49CA | `WINCONSOLEOPENKBD` | yes |
| +0xC1E `WINCONSOLECLOSEKBD` | 5 | 0x4A4E | `WINCONSOLECLOSEKBD` | yes |
| +0xC22 `WINCONSOLESETSTATUS` | 6 | 0x4B31 | `WINCONSOLESETSTATUS` | yes |
| +0xC26 `WINCONSOLEGETSTATUS` | 7 | 0x4D5C | `WINCONSOLEGETSTATUS` | yes |
| +0xC2A `WINCONSOLESETCP` | 8 | 0x4E6F | `WINCONSOLESETCP` | yes |
| +0xC2E `WINCONSOLEGETCP` | 0x0A | 0x46B4 | `WINCONSOLEGETCP` | yes |
| +0xC32 `WINCONSOLEKBDXLATE` | 0x0B | 0x4FDD | `WINCONSOLEKBDXLATE` | yes |
| +0xC36 `WINCONSOLESETCUSTXT` | 0x0C | 0x50F7 | `WINCONSOLESETCUSTXT` | yes |
| +0xC3A `WINCONSOLEGETFOCUS` | 0x0D | 0x524A | `WINCONSOLEGETFOCUS` | yes |
| +0xC3E `WINCONSOLEFREEFOCUS` | 0x0E | 0x52D8 | `WINCONSOLEFREEFOCUS` | yes |
| +0xC42 `WINCONSOLEREADKEYEVENT` | 0x0F | 0x4775 | `WINCONSOLEREADKEYEVENT` | yes |
| +0xC46 `WINCONSOLEFLUSHKEYEVENTS` | 0x10 | 0x491B | `WINCONSOLEFLUSHKEYEVENTS` | yes |
| +0xC4A `LOCKVIOPS` | 0x1B | 0x0250 | `LOCKVIOPS` | yes |
| +0xC4E `UNLOCKVIOPS` | 0x1C | 0x0288 | `UNLOCKVIOPS` | yes |
| +0xC52 `WINCONSOLEGETKBDHANDLE` | 0x1F | 0x48DE | `WINCONSOLEGETKBDHANDLE` | yes |

**Mouse vector (G12, obj7 +0xE54..+0xE77): the resolve loop** [OBS-RE] (`BMSMAIN` `1C043BE9..C4F`, read
unfiltered), with N = `_ShieldEntries` = 9: **destination** `[bp-4]` = -(4,N - 0xE78) = **+0xE54**, then
**+4** per pass (`1C043BFE..0D`, `...C43`); **source** `[bp-0x1a]` = 0xE78 + 4,N - 2 = **+0xE9A**, then
**-4** per pass (`1C043C10..17`, `...C47`). `DOSGETPROCADDR` is passed the source DWORD as the name far
pointer, `[es:bx+2]:[es:bx]` = `0000:ordinal`, and writes into the destination (`1C043C27..3B`). So the
first destination pairs with the last source, and `_ShieldEntries` counts down to 0.

| obj7 cell (DOSCALL1 `.sym`) | filled from source cell | ordinal (image) | PMVIOP entry | PMVIOP name | agrees |
|---|---|---|---|---|---|
| +0xE54 `_WINCONSOLEFLUSHPOINTEREVENTS` | +0xE9A `_Shield_19` | 0x13 | 0xB197 | `WINCONSOLEFLUSHPOINTEREVENTS` | yes |
| +0xE58 `_WINCONSOLEQUEUEDPOINTEREVENTS` | +0xE96 `_Shield_17` | 0x11 | 0xB05E | `WINCONSOLEQUEUEDPOINTEREVENTS` | yes |
| +0xE5C `_WINCONSOLEREADPOINTEREVENT` | +0xE92 `_Shield_18` | 0x12 | 0xB0C0 | `WINCONSOLEREADPOINTEREVENT` | yes |
| +0xE60 `_WINCONSOLEGETPOINTERFILTERMASK` | +0xE8E `_Shield_20` | 0x14 | 0xB1D5 | `WINCONSOLEGETPOINTERFILTERMASK` | yes |
| +0xE64 `_WINCONSOLESETPOINTERFILTERMASK` | +0xE8A `_Shield_21` | 0x15 | 0xB215 | `WINCONSOLESETPOINTERFILTERMASK` | yes |
| +0xE68 `_WINCONSOLEGETPTRPOS` | +0xE86 `_Shield_22` | 0x16 | 0xB28C | `WINCONSOLEGETPTRPOS` | yes |
| +0xE6C `_WINCONSOLESETPTRPOS` | +0xE82 `_Shield_23` | 0x17 | 0xB356 | `WINCONSOLESETPTRPOS` | yes |
| +0xE70 `_WINCONSOLEATTACHMOUSEUSER` | +0xE7E `_Shield_32` | 0x20 | 0xB4AC | `WINCONSOLEATTACHMOUSEUSER` | yes |
| +0xE74 `_WINCONSOLEDETACHMOUSEUSER` | +0xE7A `_Shield_33` | 0x21 | 0xB50C | `WINCONSOLEDETACHMOUSEUSER` | yes |

Three independent agreements per mouse cell: the loop's pairing gives the ordinal; PMVIOP's entry table
plus the `.sym` give that ordinal's name, which equals DOSCALL1's `.sym` name for the destination cell; and
the source cell's `.sym` name `_Shield_NN` equals the ordinal in decimal. **The ordinal values in object 7's
image are the whole contract; the names are confirmation.**

### Object 7 - summary

Object 7 (SMP base 0x13020000, 0x0F24 bytes in the image, SHARED, selector 0x9817) is DOSCALL1's **BVS/VIO
global object plus the keyboard/mouse subsystem globals**. This summary adds nothing to the group
sections and upgrades no [INF].

| group | span | what | owning ordinals | locking |
|---|---|---|---|---|
| G0 | +0x000..+0x0BF | 88 cached segment selectors (obj7/obj8), set by fixups | every BVS/VIO/KBD/MOU routine in obj4 (#845, #847, KBD #748-#765, MOU #721-#744, #852, #718) | none; read-only after load |
| G1 | +0x0C0..+0x103 | SGCB registry (exports 858-862), `DOSSMGETMEM` segments, kill block, `RamSem_SGID`, `Ggvs`, `dirty` | #684, #685, #682, #703 (via object-5 pointers), #803, #786/#785, #838, #837, #792 | `SMQueueRamSem` (fast-safe); `killRAMsem`; object 8 +0xEC **per-process** semaphore over shared `Ggvs`; none on registry init, segments, `RamSem_SGID`, `dirty` |
| G2 + G6 | +0x104..+0x1A9, +0x8B6..+0x8F3 | popup mode, boot mode set, SHELL/HET pids, registration semaphore, print screen, BVSCALLS entry, semaphore / VDD names, `hPopXBlockSem`, `WndwConfig` | #822, #788, #810, #803, #794, #780/#770, #813, #783, #718, #845 | `regramsem` (RAM semaphore); `\SEM\POPXBLOK.SEM`; `\SEM\VIOPOPUP` / `\SEM\VIOPRTSC` (handles in object 8); none on `SYIsetmodefl`, pids, `shellVSRW_done`, `tkstack` |
| G3 | +0x1AA..+0x35F | VIO dispatch masks (popup-permitted / subsystem-routable / full-screen-only) and the 99-code `map_*` table | `viorout` (every routed VIO API), #813, #775, #780, #770 | none; read-only policy data |
| G4 | +0x360..+0x4B5 | `bvsgdata` (export 863), matching DDK `bvscb.inc` field for field | #822 -> `BVSGLOBALINIT`, #845, `GetBVSCB`, print screen | none |
| G5 | +0x4B6..+0x8B5 | `bvsgSelTable`: 256 far pointers to per-SG `{size, bvscb, flags, Nx{ENVB, LVB}}` blocks (4N + 8 bytes) | #845 (`GetBVSCB`, fn 0x44/0x51, `BvsInit`, `BvsFree`) | none |
| G7 | +0x8F4..+0xAC3 | video-handler device tables, `FFILLDEVBLK`, `FSHELLINITED`, the object-7 bump allocator `CBBVSGSEG` | #822 -> `BVSDINIT` chain, #845 | none; `SAVEREGS` register spills and one-shot latches |
| G8 | +0xAAC..+0xC15 | code-page list, `SysModes` (17 records), shared-name templates, keyboard edit tables, `Shared_Handle` | #718 `ANSIINIT`, #848, #849, ANSI #850 (`doSM`/`doRM`), #851, #747, #757 | none |
| G9 | +0xC16..+0xC5D | 16-entry PMVIOP keyboard-shield vector, resolved in place from ordinals | #851 `LoadWinthorn`; KBD APIs via `BKSMAIN` slots | one-shot `xchg`, unlocked |
| G10 | +0xC5E..+0xD13 | CDIB attach, prepared code pages, `KEYBOARD.DCP` download (KBD$ category 4 function 0x5C packet), custom-CP ownership, subsystem trampoline return slots | #749, #745, #762, #851 | none |
| G11 | +0xD14..+0xE21 | KBD/MOU router base (`_BMS_Addr`/`_BKS_Addr`, `_global_info`) and the SMP-only MMIO trace | #718 `ROUTPROCESSINIT`, #760/#723 `ROUTSMINIT`, `ROUTER` (all KBD/MOU APIs) | none; trace emitted after the router semaphore is released |
| G12 | +0xE22..+0xF23 | base mouse subsystem: `_InitFlag`, cached mouse facts, 9-entry mouse-shield vector, `_FunctionTable` (44), `_IoctlTable` (22), `_ParmTable` (22) | #852 `BMSMAIN`, #718 `BMSINIT` | none |
| trace 1 | grown tail | `PDEVGROUPS` 0x334-byte device-group blocks (device entry + 16 components + 26-slot CVT) | #845 / #822 -> `DOSLOADVIDEOHANDLER` / `DOSUNLOADVIDEOHANDLER` | none |

**Lock order observed - objects 5 and 7 together.**
- Object 5's order: `PopUpBlockSem` -> `SMRoutSem` -> `SwitchRamSem` -> `NotDD_RamSem`, with `DC1hSpinLock`
  innermost inside every fast-safe request/clear. [OBS-RE]
- `SwitchRamSem` (object 5) -> the target SG's SGCB +0x68 fast-safe semaphore - `VIOSRFBLOCK` #786 /
  `VIOSRFUNBLOCK` #785, called from `DOSSMGSWITCH`. [INF] (per call site)
- `regramsem` (object 7 +0x124) -> the caller SG's fast-safe semaphore (object 8 +0xD4 -> SGCB +0x68) -
  `VIOREGISTER` #813 requests `regramsem` (`1C044AEA`), then `DOSFSRAMSEMREQUEST *0xd4` (`1C044C4B`), and
  releases in reverse (`1C044EA7`, `...ED2`). [OBS-RE] (linear)
- **Object 5's `SGCB_QueueRamSem` and object 7's `SMQueueRamSem` (+0xC0) are ONE lock**: object 5's five
  `SGCB_*` far pointers target object 7 +0xC0..+0xD7. Its position relative to the object-5 chain is not
  established; #684 takes it on its own. [OBS-RE]
- `\SEM\POPXBLOK.SEM` brackets `InitConfig` under #845; its order against the per-SG fast-safe semaphore
  held by `viorout` is not established.
- `killRAMsem` is taken alone in `suicide`, with no other DOSCALL1 lock visible. [OBS-RE]
- Object 8's per-process RAM semaphores (+0xEC, the `_Kbd/_MouGetSemaphore` slots) exclude only within a
  process, so they cannot participate in a cross-process order. [INF]
- Everything else in object 7 is lock-free: groups G3, G4, G5, G7-G12 and trace 1 have no semaphore in
  any routine read. [OBS-RE]

**Cells whose meaning requires a defined, non-zero initial value** (the image value is evidence of what
the meaning requires; a zero-filled object 7 is wrong at every one) [OBS-RE]:
- **Segment selectors:** G0's 88 slots - each the selector of the object that slot's code site
  addresses (object 7 or object 8).
- **Semaphore headers and sentinels:** `SMQueueRamSem` length word 0x000E; `RamSem_SGID` = 0xFFFF;
  `SYIsetmodefl` = 0xFFFF; +0xBEA `DOSGETCP` sentinel = 0xFFFF; `Handle0CP_Save` = 0xFF x 32.
- **Sizes and counts:** `PUgetmode` cb 0x000C; `WndwConfig` cb 0x0028 (plus +0x8EC = 1 and +0x8F0 = 1,
  meanings unverified); `bvsgBvscbSize` 0x033E; `bvsgCPrtscTitlelen` 0x0B, `bvsgPrtscTitleLen` 0x0D;
  `CBBVSGSEG` = image end (0x0F23); `ShieldEntries` = 16; `_ShieldEntries` = 9. Not required: `NumCP`
  (image 2) and `Num_of_CP` (image 1) are overwritten at run time.
- **Mode / policy data:** `SYIsetmode` {8, 1, 4, 80, 25}; G3's 15 mask words and 99 `{group, bit}`
  records; `SysModes` 17 records; `ESCTAB` (13) and `EDITTAB` (8); `_IoctlTable` (22) and `_ParmTable`
  (22); (SMP) `_kbd_mmio_codes` (40 words) and `_mou_mmio_codes` (52).
- **Default far pointers:** 32 x obj7:0x0971 "POINTER$" in G7's two pointer-name tables.
- **Import ordinals** (resolved in place at run time): G9's 16 PMVIOP ordinals; G12's 9.
- **Strings:** G2 - `BVSCALLS` + `bvs_ep` = 3, `\SEM\VIOPOPUP`, `\SEM\VIOPRTSC`, `VVIDEO1$`,
  `\SEM\POPXBLOK.SEM`; G4 - the print-screen buffer (134 spaces), `ESC[00;00R CR`, `\SHAREMEM\BVS\BVSsg`,
  `MOUSE$`, `PRN`, `SCREEN$`, 8 blanks, the two print-job titles, `VVIDEO1$` / `VVIDEO2$`; G7 - the BVH
  name namespace (`DEVENABLE`, `VIDEO_DEVICES`, the tags, the generic BVH chains, `POINTER$`, `BVHWNDW`,
  `VIDEO_WINDOW`); G8 - `\SHAREMEM\BVS\BVS00`, `\SHAREMEM\ANSI\KD0000`, `KBD$    `; G9 - `PMVIOP`;
  G10 - `\SHAREMEM\DOS\CDIB` and the byte-swapped layout IDs; G11 - `\DEV\MOUSE$`, `\DEV\KBD$`,
  `BMSCALLS`, `BKSCALLS`; G12 - `\DEV\MOUSE$ `, `\DEV\` + 8 blanks, `PMVIOP`.
- **Code addresses, not data:** G12's `_FunctionTable` (44 near offsets into DOSCALL1's code), and the far
  pointers that G9/G12 resolve and G11 fills, name DOSCALL1 routines; what they encode is the dispatch of
  the owning entry points (#852 / #851 / `ROUTER`). [INF]
- **Present in the image with no behaviour:** the object-7 CDIB copy, `CDIBSel`, `VIOCALLS`; the
  `_bms_entrypoint`/`_bks_entrypoint` names; the layout-ID strings (no reader found).

**Object 7 grows at run time.** `PCHGROWGLOBAL`: `DOSSIZESEG` on object 7, `DOSREALLOCSEG` **of object 7
itself** when `CBBVSGSEG + n` exceeds it, then a bump allocation from `CBBVSGSEG` (start 0x0F23 on SMP),
zero-filled, **64 KB cap, never freed, no lock**. Users: `UGROWDEVGROUP` (0x334-byte `PDEVGROUPS` blocks;
unbounded, trace 1); `VREADENVVARS` (`VIDEO_WINDOW` and other environment-string copies);
`VGETTAGVALUE`. So object 7 is grown in place at its fixed base, up to 0x10000 bytes, and the growth is
visible to every process, because the object is SHARED and far pointers into the tail are stored in it.
[OBS-RE] / [INF]

**SMP behavioural differences in object 7.**
1. **The MMIO RAS trace emitter (G11)** - the only layout difference: `_mmio_sel`, `_mmio_buffer` and the
   two code tables (+0xD64..+0xE21, 0xBE bytes). UNI's `_GlobalInit` sets only `_global_initflag`; there
   are no `_MMIO*` routines and no trace calls; otherwise the code is identical. [OBS-RE]
2. **Fast-safe semaphores use `DC1hSpinLock` on SMP** (`cli`/`sti` on UNI) - `SMQueueRamSem` and every
   SGCB +0x68 semaphore requested by the object-7 VIO routines. [OBS-RE]
3. No other SMP/UNI behavioural difference was found in object 7; every other region was checked by
   name translation (UNI and SMP symbols at the same offsets below +0xD64). [OBS-RE]

---

## Object 8 - `OS2CHAR_I_GROUP` / `SMGINSTANCE` + `BVHINSTANCE` (per-process)

| property | value | prov |
|---|---|---|
| LX object | 8 of `DOSCALL1.DLL` | [OBS-RE] |
| group / segment names | `OS2CHAR_I_GROUP`; contains `SMGINSTANCE` (+0x000) and `BVHINSTANCE` | [OBS-RE] (`.sym`) |
| SMP link base / size | 0x13030000 / **0x5D0** (`_end_IDATA` SMP +0x5D0) | [OBS-RE] |
| UNI size | 0x580 (`_end_IDATA` UNI +0x580) | [OBS-RE] |
| sharing | **INSTANCE** - one copy per process | [OBS-RE] |
| image selector | 0x981F | [OBS-RE] |
| exports | **864** `CHRSMGINSTANCE` = obj8+0x000; **865** `CHRBVHINSTANCE` = obj8+0x1B0 (SMP; UNI +0x160) | [OBS-RE]; names [DOC-IBM] (OS/2 Debugging Handbook) |

- **Size seen by an application:** on real OS/2 a 16-bit `DosSizeSeg` on the selector of export 864
  returns **1488 (0x5D0)** - exactly object 8's LX size. [OBS] (16-bit `DosSizeSeg` probe against export
  864's selector, run on a real OS/2 system, recorded by 2026-09-17)
- **SMP vs UNI layout.** Unlike object 7, the `.sym` names object 8 from +0x000 (187 distinct offsets).
  UNI is identical through `oldtimes` +0x132. There are **two** SMP-only enlargements, so no single
  stride converts a UNI offset: (1) `trace1..trace5plus` (SMP +0x152..+0x19D, 0x4C bytes) move `SGCB`
  (UNI +0x152 -> SMP +0x19E) and `SGCB_pop` (+0x15A -> +0x1A6) by **+0x4C**; (2) `SGCB_pop`/`pu_sdata` then
  spans 0xA bytes on SMP against 6 on UNI, moving everything from `BVHINSTANCE` on by a further 4, i.e.
  **+0x50** (UNI +0x160 -> SMP +0x1B0, `BVSINSTANCE` +0x2D0 -> +0x320, `_end_IDATA` +0x580 -> +0x5D0). A
  UNI offset converted with +0x4C lands 4 bytes inside `bvhidata`. The two `.sym` files must be read
  against each other. The SMP code does not access the trace region (I2): what SMP changes is where
  `SGCB` and the later cells sit, not behaviour. [OBS-RE]
- **How code reaches object 8.** Literal `0x981f`: 127 sites (124 obj4, 3 obj3). Fixups to `obj8+0x0`:
  obj3 x3 (`DOSSMGETSGCB` #684 `1C03522E`, `OS2BASEINIT` #718 `1C035DCA`, `DOSSMINITSGCB` #685
  `1C03F847`), object 5 x1 (`SMG_INSTANCE` +0xB14), object 7 x35 (the G0 slots +0x26...+0xA2 whose value is
  `981f`), obj2 (32-bit) **0**; and no flat `0x1303xxxx` operand in obj2. So object 8 is not addressed
  from 32-bit code. Object 8 is **mostly reached with an inherited DS** - `viorout` loads DS = object 8
  and the VIO workers it calls run on it; `BKSMAIN`'s helpers likewise. [OBS-RE]
- **Image bytes** (SMP) are almost all zero. Non-zero: +0x84 `PMWIN`, +0x8C `PMSHAPI`, +0x96 `PMVDMP`,
  +0x9D..+0xA1 `12 01 10 00 0D`; +0x112 `\SEM\POPXBLOK.SEM`; +0x1CA WORD 2; +0x31A WORD 0x033E; +0x39A
  `0123456789ABCDEF` (`HexDigit`); +0x3C6 `EC`; +0x3CA WORD 0xFFFF; +0x3CE 8; +0x3DC 1; +0x3E5 0x0D;
  +0x3F2/+0x3F4/+0x3F6 WORD **0x03FE** x3 (= `KeyDefBuf`'s own offset); +0x3FB 1. Evidence of meaning.
  [OBS-RE]
- **IBM meaning sources:** DDK `bvscb.inc` line 332 "BVS Instance Data Segment" (`bvsidata`, commented
  out `;@T52` - prose layout only) and line 436 `bvhidata STRUC` (37 fields). [DOC-IBM]
- Each process gets a fresh instance object, so cells are either image-valued or filled by that
  process's LIBINIT (`InitDOSCALL1` -> `OS2BASEINIT` #718 -> `VIOINITPROCESS`, `ANSIINIT`, `BMSINIT`,
  `ROUTPROCESSINIT`); a child after `DosExecPgm` starts from the image again. See the object 8 summary.
  [OBS-RE] / [INF]

### I1 - VIO/SM per-process linkage: the SG's fast-safe semaphore, the alternate video subsystem, popup state, BVS entry, print-screen stacks (+0x0AF..+0x123)

Offsets +0x0AF..+0x132 are identical in UNI and SMP. [OBS-RE]

**The shape of the group** [OBS-RE]. Every VIO API enters `viorout` with DS = object 8. Before dispatch
it **requests the current screen group's fast-safe RAM semaphore**, whose address it keeps in this
process's object 8 (+0xD4, = SGCB+0x68), and records the semaphore it actually got (+0xD8). The far
pointer can be **re-pointed by a popup on another thread of the same process** (`VIOPOPUP` swaps
`SGCB`<->`SGCB_pop` and rewrites +0xD4), so every request is a loop: `DOSFSRAMSEMREQUEST([0xd4], -1)`, retry
on 0x5F, then `cmp bx,[0xd4] / cmp cx,[0xd6]` and **re-request if the pointer moved** (`viorout`
+0x652..+0x678, +0x846..+0x86C, +0xC2E..+0xC54). Then it calls either the registered alternate video
subsystem (`call far [0xe6]`, only when the function's bit is registered) or the BVS entry (`call far
[0xfc]`, AX = `avs_bvs_bits` normally, 0 while `pop_mode` != 0), and clears the semaphore it recorded
(`push dword [0xd8] / DOSFSRAMSEMCLEAR`). The HET process (object 7 +0x120) skips the request and the
clear (`VIOPOPUP` +0x53E8, `VIOENDPOPUP` +0x5778).

| offset + name | size/type | what it is | routines -> ordinal | initialiser (per process) | concurrency | prov |
|---|---|---|---|---|---|---|
| +0x0AF `ArraySeg` | WORD selector | This process's addressability copy of object 7 `SMArray`'s selector. | `DOSSMINITSGCB` #685 stores it (`1C03F86B`); `DOSSMGETSGCB` #684 compares with the current `SMArray` selector and, if different, `DOSGETSEG` #121 then stores (`1C035265..72`), **under object 7 `SMQueueRamSem` +0xC0** (`push ds/push 0xc0` DS = obj7, `1C035250`); `BvsFree` skips freeing a selector equal to it (object 7 G5) | 0 in image; filled lazily on first `DOSSMGETSGCB`/`DOSSMINITSGCB` in the process - a child starts at 0 and re-attaches | written under a **system-wide** semaphore (object 7 +0xC0), so also thread-safe within the process; re-checked against shared state on every #684 call | [OBS-RE] |
| +0x0D0 `origSG` | WORD SGID | Screen group before `VioPopUp` switched the process to the popup SG. | `VIOPOPUP` #780 (`1C0453CC`, from `currsg`) | written per popup | written inside `DOSENTERCRITSEC` #13 (`1C0453C4`) - serialises threads of this process | [OBS-RE] |
| +0x0D2 `origTYPE` | WORD process type | `procTYPE` before the popup; **4 = detached** skips the alternate-subsystem notify on end. | `VIOPOPUP` #780 writes (`1C0453D2`); `VIOENDPOPUP` #770 and `VIOENDPOPEXIT1` test `== 4` (`1C0457A4`) | per popup | inside critsec #13 | [OBS-RE] |
| +0x0D4 `fsRAMoff` / +0x0D6 `fsRAMsel` | far ptr (off, sel) | Address of **the current SG's fast-safe RAM semaphore = SGCB+0x68** (the SGCB is shared). | written: `VIOINITPROCESS` (<- **#718**) `1C040307`/`1C0403C5` (both arms), `VIOSHELLINIT` **#822** `1C045C00`, `VIOPOPUP` #780 `1C045550`/`1C0455A1` (after swapping SGCB<->SGCB_pop), `VIOENDPOPUP` #770 `1C045903` (swap back); read by `viorout` (all VIO APIs), #780, #770, `VIOREGISTER` #813, `VIODEREGISTER` #775, `VIOREGEXIT` | LIBINIT: `VIOINITPROCESS` from `SGCB` (+0x19E, I2); a child rebuilds it at its own LIBINIT | **Within-process race is designed for**: a popup on thread A rewrites it while thread B is requesting, so readers re-compare after acquiring and retry. Writes in #780/#770 are inside critsec #13. It holds an address into a *shared* SGCB - correct only while that SGCB's selector is addressable in this process (`ArraySeg`/#121 above) | [OBS-RE] |
| +0x0D8 `rqdSEMoff` / +0x0DA `rqdSEMsel` | far ptr | **The SG semaphore this thread actually acquired**, released later through this copy. | `viorout` (`1C04067E`/`1C04067A`, `...0872`, `...0C5A`) writes after the re-check; clears via `push dword [0xd8]`; #780 (`1C04540B`, `1C04560A`), #770 (`1C04579B`, `1C0459A3`) | per call | written **while holding** that semaphore, so a second thread of the process is blocked on it and cannot interleave - except the HET process, which neither requests nor writes | [OBS-RE] |
| +0x0DC `rqdPOPoff` / +0x0DE `rqdPOPsel` | far ptr | The **popup** SG's semaphore, captured by `VioEndPopUp` before swapping back, then **cleared N times** (`[gs:di+0x6]` = its nest count) so no hold survives the popup. | #770 only (`1C0458E0`, `1C04592C..5956`) | per end-popup | inside critsec #13 (`1C045887`..`1C045964`) | [OBS-RE] |
| +0x0E0 `procCP` / +0x0E2 `procCPlength` | WORD code page / WORD length | The process's code page from `DOSGETCP` #130 (buffer +0xE0, length out +0xE2). | `initCP` (<- `VIOINITPROCESS`) address-taken `push ds/push 0xe0`, `push ds/push 0xe2` (`1C04044F..54`, when `procTYPE` is 0 or 2); `viorout`, on the first VIO call in an SG: `VIOSETCP(0,[0xe0],0)` and on success copies it into SGCB+0x5A (`1C04058A..9C`); KBD `_SessionInit` (<- `ROUTPROCESSINIT`) pushes it to `KBDSETCP` through slot +0x6C (`1C04365E`) | LIBINIT (`initCP`); a child re-queries | read-mostly after LIBINIT; the SGCB+0x5A copy is guarded by SGCB+0x42 bit 2 (one-shot per SG) - consistency flows **out** of this cell into shared state | [OBS-RE] |
| +0x0E4 `avs_hand` | WORD module handle | Handle of the **alternate video subsystem** module named to `VioRegister`. | `VIOREGISTER` #813 `DOSLOADMODULE` #44 -> address-taken (`1C044BF0`), freed #46 on failure (`1C044DD1`); **`vioattach` re-loads it in every other process** (#46 old, #44 new, `1C043D91..3DBA`) | 0; loaded by #813 in the registering process, by `vioattach` in the others when SGCB+0x44 != object 8 `oldtimes` +0x132 (I2) | the registration lives in the **shared SGCB** (+0x34 function mask, +0x36, +0x3C bits, +0x3E name block); this cell is the per-process **binding** of it, refreshed lazily | [OBS-RE] |
| +0x0E6 `avs_off` / +0x0E8 `avs_sel` | far ptr | Entry point of the registered alternate video subsystem. | #813 `DOSGETPROCADDR` #45 (`1C044C0B`); `vioattach` same (`1C043DCE`); called by `viorout` when the function's bit is registered (`1C040687`, `1C040C6D`), #780 (`1C045432`), #770 (`1C0457D0`), `AVS_PRTSC` **#783** (`1C045EBA`), `AVS_PRTSCTOGGLE` **#807** (`1C045F5B`); #813's failure path zeroes `avs_sel` (`1C044DCB`) | as `avs_hand` | as `avs_hand`; called **with the SG semaphore held** in `viorout` | [OBS-RE] |
| +0x0EA `avs_bvs_bits` | WORD bit set | Packed from #813's two mask arguments (`1C044C6B..8F`, also written to SGCB+0x3C); passed **in AX to the BVS entry** so BVS knows which functions the alternate subsystem took. | written #813 (`1C044C8F`), zeroed #775 (`1C045030`), `vioattach` (`1C043DE1`, from the SGCB); read before every `call far [0xfc]`: `viorout`, `VIOSAVE` #789, `VIORESTORE` #809, `VIOFREE` #773, `VIOSHELLINIT` #822 | 0; set per process as above | per-process copy of shared SGCB+0x3C, refreshed by `vioattach` | [OBS-RE] |
| +0x0EC `Igvs_ramsem` (to +0x0EF) | RAM semaphore | Per-process RAM semaphore guarding the shared `Ggvs_*` block (object 7 G1). | #838, `vioattach` | - | a per-process lock over shared cells: two processes do not exclude each other [INF] | [OBS-RE] |
| +0x0F0 `gvs_hand` / +0x0F2 `gvs_off` / +0x0F4 `gvs_sel` | handle + far ptr | Per-process binding of a **global** VIO registration (`VioGlobalReg`): module handle and entry. | `VIOGLOBALREG` **#838** #44 -> +0xF0 (`1C0461C0`), #45 -> +0xF2 (`1C0461DA`), failure zeroes +0xF4 and frees (`1C046264..6E`); `vioattach` replays into +0xF0 with #44/#45 for each `Ggvs` entry (`1C043E63..7A`) | 0; per process; replay driven by `Igvs_count` +0x14A vs object 7 `Ggvs_count` (I2) | #838 holds `Igvs_ramsem` (+0xEC) around it (`1C04613B..6144`, clear `1C04627E`) - within-process only | [OBS-RE] |
| +0x0F6 `pop_mode` | WORD count/flag | **Popup active in this process.** `inc` on a successful `DOSSMSGDOPOPUP`, zeroed by `VioEndPopUp`. Gates: `viorout` returns **430 ERROR_VIO_ILLEGAL_DURING_POPUP** (0x1AE) for a non-popup function when = 1 and caller != HET pid; selects AX = 0 (not `avs_bvs_bits`) into BVS; #770 returns **405** (0x195) when 0 | #780 `inc` (`1C0454C5`), #770 `mov 0` (`1C04588E`), `viorout` `1C040529`, `1C040C7F` | 0; not inherited by a child | written inside critsec #13 in both | [OBS-RE] |
| +0x0F8 `popexit` | WORD 0/1/2 | **Why `VioEndPopUp` is running**: 1/2 = entered from the popup's **exit-list routine** (`VIOENDPOPEXIT` sets 1, `VIOENDPOPEXIT1` sets 2 - process ending with a popup open); 0 = normal call. 2 skips the SG-semaphore re-request; >= 1 makes #770 remove the exit-list entry and reset it to 0 (`1C045A55..6F`, `DOSEXITLIST` #7 type 3). | exit routines `1C0456ED`/`1C0456FC`; #770; registered by #780 (`push word 0x56f6`/`0x56e7`, `1C04535C`/`536D`) | 0 | exit-list code runs on the exiting thread; not otherwise shared | [OBS-RE] |
| +0x0FA `bvs_hand` / +0x0FC `bvs_off` / +0x0FE `bvs_sel` | handle + far ptr | Per-process binding of **BVSCALLS ordinal 3** (the BVS entry) - every VIO API dispatches through +0xFC. Loaded by `VIOINITPROCESS` from object 7's `bvs_mod`/`bvs_ep` (G2). `VIOINITPROCESS` skips the load when `procTYPE` = 4; when object 7 **+0xE22 bit 1** is set it writes `e026:1887` directly; otherwise it loads, and if the resolved address is `e026:1887` it sets that bit and **`DOSFREEMODULE`s the handle** (`1C040297..F3`) - after the first process confirms BVSCALLS.3 forwards into DOSCALL1 itself, later processes hardwire it. #770 treats `bvs_sel` = 0 as "not initialised" -> 405 (`1C045732`) | LIBINIT `VIOINITPROCESS`; a child re-does it (fast path via the shared bit) | the object-7 +0xE22 bit is a **shared latch set unlocked**; benign (idempotent value) | [OBS-RE] |
| +0x100 `smg_hand` | WORD | **No reader or writer** found | - | - | - | [OBS-RE] (absence) |
| +0x102 `detachpop` | WORD flag | "This process has run `OS2BASEINIT` for a popup." For `procTYPE` >= 3 (PM or detached), `VioPopUp` calls **`OS2BASEINIT` #718** once (`suicide` on failure) before using the popup SG, then sets 1. | #780 `1C045517..2A`, `1C045561..74` | 0; per process | inside critsec #13 | [OBS-RE] |
| +0x104 `prtsc_SSsel` / +0x106 `prtsctog_SSsel` | WORD selector x2 | **Stack segments (0x1000 bytes) for the two print-screen threads** an alternate subsystem gets when it registers the print-screen bits: `DOSALLOCSEG` #34 -> address-taken, then `DOSCREATETHREAD` #145 with stack `[sel]:0xFFF` and entry `cs:5E38` / `cs:5EE7` (the `AVS_PRTSC`/`AVS_PRTSCTOGGLE` thread bodies [INF] from placement), thread ids stored in the **shared** alternate-registration block (`es:di+0x16/+0x18`). Freed `DOSFREESEG` #39 on failure and in #775. | #813 (`1C044CE3..4D57`, mask `0x100`/`0x8000` of argument +0x12), #775 (`1C044FCC`, `1C04500A`) | 0; only in the registering process | #813 runs with the SG semaphore held; the thread handoff uses DOSSEMSET/WAIT on the shared block | [OBS-RE] |
| +0x108 `prtsc_ThID` / +0x10A `prtsctog_ThID` / +0x10C `tst_sel` | WORD x3 | **No reader or writer** (the thread ids go to the shared block instead) | - | - | - | [OBS-RE] (absence) |
| +0x10E `hVioXBlockSem` / +0x112 `nameVioXBlockSem` | DWORD system-semaphore handle / char[18], **image `\SEM\POPXBLOK.SEM`** | Per-process handle to the **popup-exclusion** system semaphore: `VioPopUp`/`VioEndPopUp` `DOSOPENSEM` #25 it, `DOSSEMWAIT` forever, `DOSCLOSESEM` #23 - i.e. wait until whoever blocks popups (object 7 `hPopXBlockSem`, `InitConfig`) releases. Same semaphore as object 7's (both images read `POPXBLOK`) | #780 (`1C045473..99`), #770 (`1C04585C..82`) | handle 0; opened and closed around each wait, so never stale | system-wide exclusion; the handle is transient per call | [OBS-RE] |

**Locking - I1** [OBS-RE]:
- **SG fast-safe semaphore (SGCB+0x68)** - the lock every VIO API holds; its address is kept here and
  re-validated after acquiring because a same-process popup can move it. SMP differs only in the
  primitive (`DC1hSpinLock`).
- **`DOSENTERCRITSEC` #13** brackets all popup-state writes (+0xD0/D2/D4/F6/102, the SGCB swap).
- Object 7 `SMQueueRamSem` (system-wide) guards the `ArraySeg` refresh; `Igvs_ramsem` (per process)
  guards the global-registration replay.
- Order observed: critsec #13 -> SG semaphore (#780, #770); SG semaphore -> call AVS/BVS. No new
  cross-object order.

The cells are per-process **bindings of shared registrations** (AVS/GVS/BVS entry, code page) plus
**per-process popup state**; they are rebuilt by each process's init (the #718 chain) and refreshed by
`vioattach` whenever the shared SGCB generation (+0x44) moves. [OBS-RE] / [INF]

**Not established (I1):** which exit routine (`0x56E7` -> 2 vs `0x56F6` -> 1) #780 registers in which case
(sites `1C04535C`/`536D`); the owner of two more registration sites `1C0456B1`/`56C1` in a routine before
`VIOENDPOPEXIT1`; the `.sym` match of the thread entries `cs:5E38`/`5EE7`.

### I2 - process identity, popup/print-screen semaphore handles, global-registration replay, the SMP trace gap, the SGCB pointers (+0x124..+0x1AF)

Offsets +0x124..+0x151 are identical UNI/SMP; UNI `SGCB` +0x152 / `SGCB_temp` +0x156 / `SGCB_pop` +0x15A
= SMP **+0x19E / +0x1A2 / +0x1A6**; the SMP-only `trace1..trace5plus` occupy +0x152..+0x19D. [OBS-RE]

**The SMP trace region is not accessed** [OBS-RE] (absence): no DS- or ES-relative access, constant or
indexed, to +0x152..+0x19D in any SMP VIO/KBD/MOU routine; the only code that touches offsets in that
range (`W_DOSREADQUEUE`, `W_DOSWRITEQUEUE`, `_Q_*`, `_L_*`, `_El_Delete`, `_FuncInit`,
`C_EXITLISTQUEUE`, `GetDBCSInfo`, `_F_Syntax`, and `es:` overrides in `AVS_PRTSC`/`VIOINITPROCESS`) runs
on other data segments (object 5) or loads from object 7. The SMP trace facility does not use it either:
`viopretrace`/`vioposttrace` test **object 7** `[es:0x26]` bit 0x40 and call `MMIO_pre`/`MMIO_post`
(object 7 G11). `trace1..trace5plus` are named space with no accessor - layout only; what SMP changes is
where `SGCB` sits.

| offset + name | size/type | what it is | routines -> ordinal | initialiser (per process) | concurrency | prov |
|---|---|---|---|---|---|---|
| +0x124 `procTYPE` | WORD | Caller's **process type**, copied from LIS `typeProcess` (+0x0E). 4 = detached -> `viorout` returns **465 ERROR_VIO_DETACHED**; 3 = PM gates the AVIO range; 0 enables alternate-subsystem dispatch; `OS2BASEINIT` does its VIO init only for < 3; the PRTSC semaphore open is skipped when 4. | written `VIOINITPROCESS` (<- #718, `1C040248`) and **refreshed from the LIS on every call** by `viorout` (all VIO APIs), `VIOREGISTER` #813, `VIODEREGISTER` #775, `VIOPOPUP` #780; `VIOENDPOPUP` #770 after `DOSSMSGENDPOPUP`; read by `_KbdCheckProcType`/`_MouCheckProcType` (KBD/MOU router bracket), `BMS*` #852, `initCP`, `SGCBINIT` | LIBINIT; a child re-reads its own LIS | per process; each writer stores the same LIS value; the only non-LIS store is #770's (inside critsec #13). No lock needed | [OBS-RE] |
| +0x126 `currpid` | WORD pid | This process's pid, from LIS `pidCurrent` (+0x00). Compared with object 7 `SHELLPID`/`HETPID` and with SGCB owner cells (+0x4C/+0x50/+0x6A, alt-block +0x1A). | written **once**, `VIOINITPROCESS` `1C04024F`; read by `viorout`, #780, #770, `VIOFREE` #773 (only SHELLPID/HETPID may call it, else 402), `VIOHETINIT` #803 (latches it into object 7 +0x120), #789, #809, `VIOSAVREDRAWWAIT`, `VIOMODEWAIT`, KBD/MOU/BMS | LIBINIT; a child gets its own | immutable after init | [OBS-RE] |
| +0x128 `fgsg` | WORD | **No reader or writer** | - | - | - | [OBS-RE] (absence) |
| +0x12A `currsg` | WORD SGID | Caller's **screen group**, from LIS `sgCurrent` (+0x08). Selects the SGCB; `< 0x10` and `!= 0` gates the global-registration replay; `= 1` skips the per-SG first-call setup. | written `VIOINITPROCESS`, refreshed from the LIS by `viorout`, #813, #775, `VIOGLOBALREG` #838, #780, `VIOSHELLINIT` #822; #770 after end-popup | LIBINIT; a child re-reads | as `procTYPE` | [OBS-RE] |
| +0x12C `InfoSegL` / +0x12E `InfoSegG` | WORD selector x2 | The process's **Local and Global InfoSeg selectors**. | `DOSGETINFOSEG` #8 in `VIOINITPROCESS` (address-taken `push ds/0x12e`, `push ds/0x12c`, `1C04022F..37`); the LIS is read by every refresher above; the GIS by #780 (`[es:0x18]`, `SIS_CurScrnGrp`, the foreground SG) and `VIOINITPROCESS` | LIBINIT | read-only after init; the GIS is the system's, the LIS per process (`infoseg.md`) | [OBS-RE] |
| +0x130 `mmio_sel` | WORD selector | Copy of GIS **`SIS_MMIOBase`** (+0x4A). | `VIOINITPROCESS` `1C04025D..61`; `VIOREGISTER` `mov es,[0x130]` (`1C044B0A`) | LIBINIT | read-only copy of a system value | [OBS-RE] (SMP); UNI use not established |
| +0x132 `oldtimes` | WORD | **This process's view of the SG's registration generation** - `vioattach` stores SGCB+0x44 into it (`1C043DE8`); a mismatch on the next call makes `viorout`/#780/#770/`AVS_PRTSC` #783/`AVS_PRTSCTOGGLE` #807 call `vioattach` to rebind the AVS module (I1 +0xE4..+0xEA). | as stated | 0 -> the first VIO call attaches | the generation lives in the **shared** SGCB; this is the per-process "last seen" copy. Attach runs under the SG semaphore in `viorout`'s path (I1) | [OBS-RE] |
| +0x134 `vddhandle` | DWORD handle | Handle of **`VVIDEO1$`** (object 7 +0x1A0): when the popup's target SG is a VDM (`SGCB+0x10 == 4`), #780 `DOSOPENVDD` (only if the cell is 0), `DOSREQUESTVDD(h, sg, 4, ...)`, `DOSCLOSEVDD(h)` (`1C0452C2..5310`) | #780 only | 0; opened on first VDM popup | inside #780's critsec. **No store to +0x134 exists apart from the address-taken open**, so the cell is not zeroed after `DOSCLOSEVDD`; a second VDM popup in the same process would request through a closed handle [INF] - not observed on a real VDM popup | [OBS-RE] (SMP) for the missing store |
| +0x138 `pu_sem_lo/hi` | DWORD system-semaphore handle | Handle to **`\SEM\VIOPOPUP`**, the system-wide popup serialiser. #780 `DOSSEMREQUEST(h, bit0 of wait flag ? -1 : 0)`, retry on 0x5F, rc other than 0/105 -> **406**; released `DOSSEMCLEAR` on #780's failure paths and at the end of #770 | opened by `VIOINITPROCESS` (object 7 +0x184); use `1C04539B`, `1C0455B1/BD`, `1C045958` | LIBINIT open (create-if-absent) | **system-wide** exclusion between processes; per-process handle | [OBS-RE] (SMP) |
| +0x13C `prtscsemlo/hi` | DWORD system-semaphore handle | Handle to **`\SEM\VIOPRTSC`**. `VIOSRFBLOCK` #786 requests it forever before blocking a switch and `VIOSRFUNBLOCK` #785 clears it - a screen switch excludes print-screen; `viorout` takes it forever on one path (`1C04099F`) and clears it (`1C040B82`) | opened by `VIOINITPROCESS` `1C040353..7F` (open, else create, else open), **skipped when `procTYPE` = 4** | LIBINIT | system-wide exclusion; SMP targets `DOSSEMREQUEST`/`DOSSEMCLEAR` (obj3 +0x610/+0x6CD) | [OBS-RE] |
| +0x140 `prtsc_avshand` | WORD | **No reader or writer** | - | - | - | [OBS-RE] (absence) |
| +0x142 `exitlist` | WORD flag | **"The priority exit-list pass is running."** `VIOINITPROCESS` registers two exit routines (`DOSEXITLIST` #7 with codes `0xC081` -> `VIOFSRAMEXIT0` `cs:5DA6`, `0xC001` -> `VIOFSRAMEXIT` `cs:5DB3`). `VIOFSRAMEXIT0` sets the flag and falls into `VIOFSRAMEXIT`, which - **if this process owns the SG fast-safe semaphore** (SGCB+0x68+2 = pid) - takes it with timeout 0, forces its count (+6) to 1 and clears it, so a dying process cannot leave its SG locked; sleeps if object 7 `RamSem_SGID` = currsg; clears the flag if it was 1 | exit routines only | 0; registered at LIBINIT | runs on the exiting thread at process exit | [OBS-RE] (`1C045DA6..5E24`) |
| +0x144 `Igvs_end` | WORD | **No reader or writer** | - | - | - | [OBS-RE] (absence) |
| +0x146 `Igvs_last`, +0x148 `Igvs_quit`, +0x14A `Igvs_count`, +0x14C `gvs_cntr`, +0x14E/+0x150 `gvsCURoff/sel` | WORD x4 + far ptr | **This process's replay of global VIO registrations (`VioGlobalReg`).** `vioattach` appends one **16-byte entry per `Ggvs` registration past the end of object 8** - `DOSREALLOCSEG` #38 on DS by +0x10 (`1C043E49..4E`), `inc Igvs_count` (`1C043E9B`), `Igvs_last` = entry address (`1C043EB4`); entries: +0 far entry, +4 active mask (refreshed per call from +6 & the function's group mask). Each VIO call with `Igvs_count != 0` and `0 < currsg < 16` walks them: `gvs_cntr` index, `gvsCUR` = entry, calls it, `Igvs_quit` = 1 when counter = count; result **402** (0x192) = "no global handler took it". The table starts at the end of object 8 (UNI `VIOREGISTER`/`VIODEREGISTER` use `0x580` = UNI `_end_IDATA`; SMP #770 uses `bx = 0x5d0` = SMP `_end_IDATA`) | `vioattach` (builds), `viorout`, #780, #770, #813, #775 (walk) | 0; built lazily per process, compared with object 7 `Ggvs_count` | **the walk cells are written by every VIO call with no lock of their own.** #770's walk holds the SG semaphore (`1C045984..5A32`); `viorout`'s ordering is not established. Two threads of one process on different SGs would race [INF] | [OBS-RE] |
| +0x152..+0x19D `trace1..trace5plus` (SMP only) | 0x4C bytes | **No accessor** (above) | - | - | - | [OBS-RE] (absence) |
| +0x19E `SGCB` (`_SGData`) | far ptr | **The current screen group's SGCB** (shared; object 5/7 registry). | `DOSSMGETSGCB` #684 into it (address-taken): `VIOINITPROCESS` `1C040388` (currsg), `VIOSHELLINIT` #822 `1C045BE4`, `VIOFREE` #773 `1C045B1C` (temporary, below); swapped with `SGCB_pop` by #780/#770 (I1). Read by every VIO API and by `_Kbd/_MouGet/ClearSemaphore`, `BMSMAIN`/`BMSOPEN`/`BMSEXITLIST`, `SGCBINIT` via ES from an object-7 G0 slot (`[es:0x19e]`/`[es:0x1a0]`) | LIBINIT; a child re-fetches | a far pointer into shared data; swaps in critsec #13; `VIOFREE`'s temporary repoint below | [OBS-RE] |
| +0x1A2 `SGCB_temp` | far ptr | **Save slot / scratch SGCB**: `VIOFREE` saves `SGCB` here, re-points `SGCB` at the SG it is freeing, calls BVS, restores (`1C045AF7..B00`, `...5B9A..BA3`); `viorout` (`1C0409C7`), #780 (the foreground SG when it differs, `1C04529F`) and `VIOSSWSWITCH` (`1C045D4D`, then uses its +0x68 semaphore) fetch another SG's SGCB into it | as stated | per call | per call. No critsec is visible around `VIOFREE`'s repoint (`1C045AF2..5BA3`, SHELLPID/HETPID callers only; the middle of the routine was not read): a second thread of the shell process calling a VIO API meanwhile would dispatch against the freed SG [INF] | [OBS-RE] |
| +0x1A6 `SGCB_pop` (`pu_sdata`) | far ptr | The **popup SG's SGCB**: `VIOINITPROCESS`, when `currsg != 3`, does `DOSSMGETSGCB(&SGCB_pop, 3, 0)` and seeds `SGCB` from it before fetching its own (`1C04026B..89`); I1's swap uses it | #718 chain, #780, #770 | LIBINIT | swap under critsec #13 | [OBS-RE] (SMP) |

**Locking - I2** [OBS-RE]: identity cells are LIS copies, rewritten idempotently - safe without a lock.
`\SEM\VIOPOPUP` (+0x138) and `\SEM\VIOPRTSC` (+0x13C) are system semaphores: the only I2 cells that
exclude other processes. The global-registration walk cells (+0x146..+0x150) have no lock of their own.
The exit routines release a fast-safe SG semaphore the dying process still owns - the recovery path for
I1's lock.

**Object 8 grows at run time** by 0x10 per global VIO registration (`vioattach` -> `DOSREALLOCSEG` #38 on
DS), the same shape as object 7's growth. [OBS-RE]

**Not established (I2):** whether `viorout`'s global-registration walk runs holding the SG semaphore (as
#770's does); why `VIOINITPROCESS` asks for **screen group 3** as `SGCB_pop`; the order/function split of
`DOSEXITLIST` codes `0xC081`/`0xC001`; the condition of `viorout`'s path that takes `\SEM\VIOPRTSC`
(`1C04099F`; a `HETPID` compare is suggested).

### I3 - `BVHINSTANCE` (export 865) = DDK `bvhidata STRUC` (+0x1B0..+0x325)

**Meaning:** DDK `base/inc/bvscb.inc` lines 433-495, `bvhidata STRUC` - 37 named fields, "Instance data
used by the BVH Device Handlers" [DOC-IBM]. All three DDK copies carry the same `bvhidata` tail
(`addr_list 129 dup`, `wdhi_wininits 32 dup`, `avio_entry`/`avio_filler` commented out); COMBASE and
COMVIDEO are byte-identical, COMDBCS differs elsewhere in the file. [OBS-RE] (compared)

**Placement, anchored twice by the SMP image** [OBS-RE]: laying the STRUC from `BVHINSTANCE` +0x1B0 puts
`cell_size` (`dw 2`) at **+0x1CA**, and the image holds WORD 2 there; it puts `cmn_bvscbsize`
(`0FFFEh AND (1+SIZE bvscb)`) at **+0x31A**, and the image holds **0x033E** there, the same value as
object 7 `bvsgBvscbSize`. Those are the only two non-zero bytes in +0x1B0..+0x32F. The STRUC is **0x176
bytes**, so it **runs 6 bytes into `BVSINSTANCE`**: `bvsi_bvs/env/lvb` (+0x320/+0x322/+0x324) are the same
words as I4's `bvsi_bvssel/envsel/lvbsel` - the STRUC comment's *"MUST BE KEPT TOGETHER"* and *"BESURE ALL
CHANGES ARE REFLECTED IN BVSMAIN ALSO"* [DOC-IBM]. (UNI: +0x160..+0x2D5, same size.)

**DOSCALL1 never touches +0x1B0..+0x31F** [OBS-RE] (absence, three searches: the object-8 access listing,
the decompiles - first hit at UNI +0x2D0 = `bvsi_bvssel` - and the address-taken scan). No fixup targets
`obj8+0x1B0` (all object-8 fixups are to `+0x0`). The block is used by the BVH video handlers: in the DDK,
the windowed handler (`VDHWNDW`) reaches it through `bvh_instance dd BVHINSTANCE` (`wdhmain.asm` line
186) and passes `DS:BX -> BVHINSTANCE data` (`avio.asm` line 189); the VGA-family handler (`video/vdh`)
through a `_hScreenDD` far pointer; unpublished notes line 143: `hScreenDD (Global nonshared): handle to
SCREEN$` [DOC-IBM]. The handler runs inside BVS's dispatch, i.e. with the caller's SG fast-safe semaphore
held (I1) [INF]. It holds per-process handles and selectors, which is why the block is INSTANCE [INF].

"Handler" = the DDK source directories that name the field.

| offset + IBM name | size | what it is (DDK comment) | DOSCALL1 | handler (DDK) | initialiser (per process) | concurrency / consistency | prov |
|---|---|---|---|---|---|---|---|
| +0x1B0 `bvhi_ScreenDD` | WORD | *Screen DD handle* - `SCREEN$` handle, "Global nonshared" (unpublished notes 143); opened by DevEnable `if (!(*hScreenDD)) DosOpen(...)` (unpublished notes 187) | none | `video/vdh` via the `_hScreenDD` far pointer (the field name is not used) | 0 in image; the handler opens it in **each** process on its first DevEnable | a per-process file handle - invalid in any other process | [DOC-IBM]; line 187 [unverified] (quoted, not re-read) |
| +0x1B2..+0x1BC `bvhi_PVBAddrLo/Hi`, `PVBSizeLo/Hi`, `PVBOffset`, `PVBSel` | WORD x6 | *BVH physical address / PVB buffer size / PVB virtual address* | none | `video/vdh` | handler (`GetPhysBuf` path) | per-process mapping of a physical buffer; a selector valid only here | [DOC-IBM] |
| +0x1BE `LastBaseSG` | WORD | *(MaxBaseSG_from_InfoSeg - 1)* - start of WDH instance data | none | no DDK source names it | - | derived from a GIS value | [DOC-IBM]; use: absence |
| +0x1C0/+0x1C2 `Scratch_Area1/2` | WORD x2 | *keep together* with `LastBaseSG` | none | `VDHWNDW`, `video/vdh` | handler | per-process scratch | [DOC-IBM] |
| +0x1C4 `save_viohandle` | WORD | *needed when 'enterb' is used* | none | no DDK source names it | - | - | [DOC-IBM]; use: absence |
| +0x1C6 `ppbvs_sema4` (= `wdhi_sema4`) | WORD | *0 = clear, 1 = set* - handler-side flag | none | `VDHWNDW`, `video/vdh` (as `wdhi_sema4`) | handler | a per-process flag, not a system semaphore | [DOC-IBM] |
| +0x1C8 `ppbvs_pssel` (= `wdhi_pssel`) | WORD selector | *PS selector for base vio* | none | `VDHWNDW`, `video/vdh` | handler | selector valid only in this process | [DOC-IBM] |
| +0x1CA `cell_size` | WORD, **image 2** | *2 or 4 dependent on defined num_attr* | none | `VDHWNDW`, `video/vdh` | **image value 2** (assembled default); the handler may change it | must match the LVB cell format the handler writes | [DOC-IBM] + [OBS-RE] (image) |
| +0x1CC/+0x1CE `attr1`/`attr2` | WORD x2 | *first/second attr word* | none | `VDHWNDW`, `video/vdh` | handler | per process | [DOC-IBM] |
| +0x1D0..+0x2D1 `addr_list` | WORD x129 | *list of Avio PS segments* | none | `VDHWNDW`, `video/vdh` | handler | per-process selectors | [DOC-IBM] |
| +0x2D2..+0x2D9 `ppbvs_bvssel`, `ppbvs_lvbsel`, `ppbvs_gdtsel`, `ppbvs_ldtsel` | WORD x4 | *BVSCBsg / LVBsg / DOS Info GDT / LDT selectors* - the handler's own copies | none | `VDHWNDW`, `video/vdh` | handler | copies of shared (BVSCB, LVB) and system (GIS) selectors, refreshed by the handler, not by DOSCALL1 | [DOC-IBM] |
| +0x2DA..+0x2F9 `wdhi_wininits` | BYTE x32 | *Threads that called WinInitialize* | none | `VDHWNDW`, `video/vdh` | handler | **per-thread bookkeeping inside a per-process block** - the only field keyed by thread | [DOC-IBM] |
| +0x2FA..+0x319 `wdhi_start_row`...`wdhi_vert_count` (6 x DWORD), `wdhi_fill_cell_off/sel`, `wdhi_Scratch` | 0x20 bytes | `wdhi_GreDat` sub-structure (`equ wdhi_start_row`): scroll/fill geometry passed to GRE, filler cell pointer, scratch | none | `VDHWNDW`, `video/vdh` (`wdhi_fill_cell_off` itself unnamed there) | handler, per call | per call | [DOC-IBM] |
| +0x31A `cmn_bvscbsize` | WORD, **image 0x033E** | *Size of the BVSCB* - assemble-time constant | none | `VDHWNDW`, `video/vdh` | **image value**, identical in every process | equals object 7 `bvsgBvscbSize` | [DOC-IBM] + [OBS-RE] (image) |
| +0x31C/+0x31E `cmn_SISsel`/`cmn_LISsel` | WORD x2 | *System / Local InfoSeg selector* - *"MUST BE KEPT TOGETHER"* with the next three | none | `VDHWNDW`, `video/vdh` | who fills them is not established (not DOSCALL1; BVS keeps its own `bvsi_gdtsel/ldtsel` at +0x328/+0x32A, I4) | the GIS selector is system-wide; the LIS per process | [DOC-IBM] |
| +0x320/+0x322/+0x324 `bvsi_bvs`/`bvsi_env`/`bvsi_lvb` | WORD x3 | *WDH needs this* - **the same words as `BVSINSTANCE`'s first three** | **written by BVS** as `bvsi_bvssel/envsel/lvbsel` (I4) | `VDHWNDW`, `video/vdh` read them | per process, by BVS (`InitConfig`, object 7 G5) | the BVS<->BVH handoff of this process's BVSCB/ENVB/LVB selectors | [DOC-IBM] + [OBS-RE] |

**Not established (I3):** who fills `cmn_SISsel`/`cmn_LISsel`; the handler-side meaning of
`ppbvs_sema4`, `save_viohandle`, `LastBaseSG` beyond their DDK comments (`save_viohandle`, `LastBaseSG`,
`wdhi_fill_cell_off` are named by no DDK source outside `bvscb.inc`).

### I4 (+ I5) - `BVSINSTANCE`, temp buffers, per-process device/VDH latches (+0x320..+0x37F)

UNI `BVSINSTANCE` +0x2D0 = SMP +0x320 (all fields +0x50). [OBS-RE]

**`GetBVSCB`'s data segment** [OBS-RE]. `GetBVSCB` (SMP `1C041430`) loads DS = object 7 (`push word
0x9817 / pop ds`). At `1C0414C3 jnz 0x14f2` and `1C0414D6 jz 0x14e7` it branches **around** the only
`mov ds,0x981f` (`1C0414D8..DB`), whose block stores `[0x32c]` and leaves via `jmp 0x1b69` (`1C0414E4`).
So `1C0414E7..1C04154C` runs with **DS = object 7**: its `[si+0x4b6]`, `[si+0x4b8]`, `[0x8f4]`
(`ILASTVDH`), `[0x3aa]` and `[si+0x6]` are object-7 cells; only `1C0414DD mov [0x32c],bx` is object 8.

| offset + name | size/type | what it is | routines -> ordinal | initialiser (per process) | concurrency / consistency | prov |
|---|---|---|---|---|---|---|
| +0x320 `bvsi_bvssel` / +0x322 `bvsi_envsel` / +0x324 `bvsi_lvbsel` | WORD selector x3 | **This process's current BVSCB, ENVB and LVB selectors** - and the same words as the handler's `bvsi_bvs/env/lvb` (I3). `InitConfig` publishes the configuration's ENVB/LVB from the per-SG selector block (+6/+8, object 7 G5); `GetBVSCB` sets them after allocating/attaching the BVSCB; the fn 0x51 / popup arms of `BVSMAIN` load the popup set; `BvsFree` and every `finis` zero them (on 479 when `currsg > 3`, and on fn 0x53) | **#845 `BVSMAIN`** and its internal `GetBVSCB`, `InitConfig`, `BvsInit`, `BvsSave`, `BvsFree`, `finis`; read by `AllVDH`, `NotifyMouse`, `BvsCAExitList`, `CallTbl` | 0; built on the process's first BVS call in an SG; a child re-runs it | each is a per-process copy of a **shared** BVSCB/ENVB/LVB selector; addressability via `ArraySeg`/#121 (I1) and G5's `DOSGETSEG`. Writes happen inside BVS dispatch, i.e. under the SG fast-safe semaphore (I1) | [OBS-RE] |
| +0x326 `bvsi_sgnum` | WORD SGID | **The SG BVS believes this process is in**: from LIS +8 on first init; **3 is folded to 0**; set 1 when the SG-1 BVSCB is cached; `BvsMVDMTranPop` stores a VDM popup's SG; `BvsInit` stores the target SG for a detached caller (465). Gates: foreground test `GINFOSEG.sgCurrent == bvsi_sgnum` -> **429 ERROR_VIO_IN_BG**; the Winthorn load `FSHELLINITED && bvsi_sgnum > bvsg_maxbase` (object 7 G7); `InitBVSCB`'s high-session arm (`>= sgMax`, or 1 with `bvsi_sg1_bvssel`) | `BVSMAIN` #845, `InitBVSCB`, `AllVDH`, `BvsSetMode`, `UpdateLVBSize`, `BvsMVDMTranPop`, `BVSGETVIDEOCALLTABLES` (#822 chain), `InitConfig`, `GetBVSCB` | LIBINIT-independent: the first `BVSMAIN` entry with `bvsi_gdtsel` = 0 | per process; compared with the system's foreground SG | [OBS-RE] |
| +0x328 `bvsi_gdtsel` | WORD selector | **GIS selector, and the per-process "BVS initialised" latch**: `BVSMAIN` runs its init block only when it is 0, copies object 7 `bvsgSISsel`, and zeroes it again if the init call fails; `finis` restores it; `InitBVSCB` loads DS from it to read GIS `sgMax` | #845, `InitBVSCB`, `finis`; zeroed by `BvsInit`/`BvsSave` error arms when `currsg > 3` | 0 -> first BVS call | copy of a system-wide selector | [OBS-RE] |
| +0x32A `bvsi_ldtsel` | WORD selector | **LIS selector** copied from object 7 `bvsgLISsel` at init (so one process's LIS selector is copied into every process - object 7 G4); DS for LIS reads in `BvsCAExitList`, `finis` (`bvsgInitPid` = LIS+0 in fn 0x44) | #845, `BvsCAExitList`, `finis` | with `bvsi_gdtsel` | per-process LIS | [OBS-RE] |
| +0x32C `bvsi_level` | WORD | **BVS nesting level**: `BVSMAIN` `dec` on exit (`1C041B64`); `GetBVSCB`, `InitConfig`, `BvsSave`, `finis` store BX; `NotifyMouse` acts only at level < 2 / = 1; `BvsInit`/`BvsSave` zero it on 479 | #845 path | 0 | per process; a second thread entering BVS in the same process shares it - serialised only by the SG semaphore (I1) | [OBS-RE] |
| +0x32E `bvsi_flags` | WORD bits | Per-process BVS flags. **Bit 0x10** = "compatibility/alternate attribute state active": tested by `RedrawCAS`, `ClearScreen`, `Flush`, `ScrollMaybe`, `SetForcedCP`, `VDHPRTSC`, `BvsSetMode`, `BvsDestroyCA`; set/cleared by `BvsCreateCA`/`BvsDestroyCA`; part of #845's 421 permission test | #845 CA sub-functions | 0 | per process | [OBS-RE] |
| +0x330..+0x33D `bvsi_pvbsel`, `biosel`, `physaddrl/h`, `length`, `lenhigh`, `srflen`; +0x340 `bvsi_scrhandle` | WORD x8 | **No reader or writer** | - | - | - | [OBS-RE] (absence) |
| +0x33E `bvsi_retlen` / +0x342 `bvsi_prthandle` | WORD x2 | Out-parameters of **fn 0x44**'s `DOSOPEN` of the name at object 7 +0x45F (`bvsgMouddName`, `MOUSE$`): action -> `retlen`, handle -> `prthandle`; `BVSMAIN` pushes and restores `prthandle` around a call (`1C04196C..75`) | #845 fn 0x44 (<- #822) | per shell init | per-process handle | [OBS-RE] |
| +0x344 `bvsi_pop_sgnum` / +0x346 `bvsi_pop_bvssel` | WORD x2 | The popup's SG and BVSCB selector; `BvsInit` sets `bvsi_bvssel = bvsi_pop_bvssel` on its popup arm | #845 (`1C041AC1/C9`), `BvsInit` | per popup | per process | [OBS-RE] |
| +0x348 `bvsi_pop_popsel` | WORD selector | **Cached BVSCB of the popup SG (3)**: `GetBVSCB` stores `bvsi_bvssel` here when allocating for SG 3 while `bvsi_sgnum` = 3, and branches on it being 0 | `GetBVSCB` (`1C041551`, `...D2`, `...163B`) | 0 | per process | [OBS-RE] |
| +0x34C..+0x34F `bvsi_tty_dbcs`, `_dbcsl`, `_dbcst`, `_flag` | BYTE x4 | **`VioWrtTTY` DBCS state across calls**: `_flag` bit 0 = "a lead byte is pending" (toggled per byte), `_dbcst` = the pending lead byte, `StrScan` sets `_dbcsl` and the flag | `VDHWRTTTY` (<- `VioWrtTTY`), `StrScan` | 0 | per process - two threads writing TTY in one process share the pending lead byte (serialised only by the SG semaphore) | [OBS-RE] |
| +0x350 `bvsi_register` | WORD | **AX at `BVSMAIN` entry** = the `avs_bvs_bits` `viorout` passes (I1 +0xEA) - which functions an alternate subsystem owns; `RegSave` reads it | #845 first statement, `RegSave` | per call | per call | [OBS-RE] |
| +0x352 `bvsi_sg1_bvssel` | WORD selector | **SG 1's BVSCB selector**: `InitBVSCB`'s second route into its high-session arm; `BVSMAIN`/`BvsInit`/`finis` call `TrackSellist` when `bvsi_sgnum` = 1 and it is non-zero | read `BVSMAIN`, `InitBVSCB`, `finis`, `BvsInit`, `BvsSave` | writer not found | per process | [OBS-RE] |
| +0x35A `PTMPMEMBLOCK` | far ptr (off +0x35A, sel +0x35C) | **This process's temp-buffer segment**: `FINITTEMPBUFS` `DOSALLOCSEG` #34 of **0x5020** bytes into +0x35C (address-taken `push 0x981f / push 0x35c`), writes `0x1234`/`0x5678` into +0x35A/+0x35C on one arm (meaning not established); `VRELEASETEMPBUFS` `DOSFREESEG` #39 and zeroes both when the use count is 0 | `FGETTEMPBUF`, `VFREETEMPBUF`, `FINITTEMPBUFS`, `VRELEASETEMPBUFS` <- `DOSLOADVIDEOHANDLER`/`VREADENVVARS` (object 7 G0 slot +0x40) | 0; allocated lazily | per process; ES from object 7 G0 slots +0x40/+0x42 | [OBS-RE] (SMP) |
| +0x35E `CTMPMEMUSECOUNT` | WORD | Outstanding temp-buffer allocations: `inc` in `FGETTEMPBUF`, `dec` in `VFREETEMPBUF` (then release) | as above | 0 | **unlocked counter** in a per-process object - two threads of one process in the #822/#845 handler-load chain would race [INF] | [OBS-RE] (SMP) |
| +0x360 `FDEVVALID` | BYTE x16 | **Per-process "device group k is addressable" array**, indexed by the SHARED device block's group index (object 7 trace 1, block +0x22A): `FHASADDRESSABILITY` reads, `FMAKEDEVADDRESSABLE`/`FADDDEVICE` set 1, `DOSDRIVERENABLE` clears all 16 | #822 chain / #845 -> `DOSDRIVERENABLE`, `FADDDEVICE`, `FHASADDRESSABILITY` | cleared once per process (next row) | per process over shared device blocks | [OBS-RE] (SMP) |
| +0x370 `FPERPROCDATAVALID` | BYTE | **Once-per-process latch**: `DOSDRIVERENABLE` zeroes `FDEVVALID[0..15]` the first time it runs in a process, then sets this to 1 (`1C049366..84`) - so a child (fresh object 8) re-validates every group | `DOSDRIVERENABLE` | 0 | per process; unlocked | [OBS-RE] (SMP) |
| +0x371 `FISGENERICVDHINITED` | BYTE | **Once-per-process latch** for `UINITGENERICVDH` (`1C048FB5` test, `1C049199` set) | `UINITGENERICVDH` (#822 chain) | 0 | per process; unlocked | [OBS-RE] (SMP) |

**Locking - I4/I5.** No lock of its own. All `bvsi_*` writes run inside `BVSMAIN`, i.e. after `viorout`
took the SG fast-safe semaphore (I1) - which serialises threads of one process only while they are in
the same SG. The temp-buffer counter and the two latches are written unlocked on the handler-load path,
which a multi-threaded process can enter twice [INF]. [OBS-RE]

**Not established (I4/I5):** the writer of `bvsi_sg1_bvssel` (+0x352) (possibly an indexed or
`TrackSellist` store); the `0x1234`/`0x5678` stores in `FINITTEMPBUFS` (`1C04A15E/65`) - which arm and why.

### I6 - ANSI / code-page / key-definition / DBCS per-process cells (+0x380..+0x3C7)

UNI = SMP - 0x50 (UNI +0x330..+0x377). [OBS-RE]

**`doRM`'s `[es:0x68]` and `[es:0]` are BVSCB cells, not object 8.** `ANSIINTERP` (#850) loads DS =
object 8 (`mov bx,0x981f / mov ds,bx`, `1C04A22D..30`), takes the caller's BVSCB selector as ES and stores
it in object 8 `BvscbSel` +0x38A (`1C04A235`). `DoAnsiFn` reloads `es,[0x38a]` (`1C04A544`) in the same
block that ends `jmp [cs:bp+0x0]` (`1C04A55A`) - the dispatch that reaches `doRM` (nothing in object 4
references `doRM`'s address `0xa831` by call, jump or literal). So in `doRM`, ES = the SG's BVSCB:
`[es:0x68]` is **`bvs_ParmCount`** *"count of parameters saved"* (DDK `bvscb.inc` line 142) - no parameter
given => mode index 0; `[es:0]` is the BVSCB's first word, whose bit 0x10 mode 7 clears. `ANSIINTERP`
itself also uses `[es:0x62]`/`[es:0x66]`/`[es:0x68]` = `bvs_TTYLen`/`bvs_AIStatus`/`bvs_ParmCount`.
[OBS-RE] segment state + [DOC-IBM] meaning. That `doRM` is reached from `ANSIINTERP`'s escape dispatch
specifically is [INF]; the dispatch table's bytes were not read.

| offset + name | size/type | what it is | routines -> ordinal | initialiser (per process) | concurrency / consistency | prov |
|---|---|---|---|---|---|---|
| +0x380 `kbdCP` | WORD code page | The **keyboard's current code page**, from `KBDGETCP` (`push ds / push 0x380`, `1C04A8DF..E4`); -1 or an error => `ANSIKEYDEF` fails | **#849 `ANSIKEYDEF`** | refreshed per call | per call | [OBS-RE] |
| +0x382 `Max_Row` / +0x384 `Max_Col` | WORD x2 | **Last row / column of the session's screen** for ANSI cursor clamping: BVSCB+0x26 - 1 and BVSCB+0x24 - 1, stored by `DoAnsiFn` before dispatching each escape function (`1C04A548..55`) | `DoAnsiFn` <- **#850 `ANSIINTERP`** | refreshed per escape | per call; copies of shared BVSCB geometry | [OBS-RE] (SMP) |
| +0x386 `Num_of_CPs` | WORD | Number of entries in the process's code-page list (+0x38E); copied from object 7 `NumCP` (G8 +0xAC6) | `ANSIINIT` (<- **#718**, `1C041FE7`); used as the scan count by #849 | LIBINIT, only after object 7's one-time `DOSGETCP` (+0xBEA != -1) | copy of a system-wide value fetched once | [OBS-RE] |
| +0x388 `CPIndex` | WORD | Index of `kbdCP` in the code-page list; selects `KdSeg[idx]` and the per-CP key table at BVSCB +0x176 + 6,idx | #849 (`1C04A90E`) | per call | per call | [OBS-RE] |
| +0x38A `BvscbSel` | WORD selector | **ANSI's own copy of the SG's BVSCB selector** - set by #850 from its argument; if 0, #848/#849 obtain it with `AccessBVSCB` (`\SHAREMEM\BVS\BVSsg` via the object-7 G8 +0xAC8 template). Distinct from I4's `bvsi_bvssel` (+0x320), obtained by name rather than from BVS | #850 (`1C04A235`), **#848 `ANSIINJECT`**, #849 (`1C04A8C7..D3`), `DoAnsiFn` | 0; set on first ANSI call | per-process selector to the **shared** BVSCB; obtained lazily, never refreshed on an SG change by the routines read | [OBS-RE] |
| +0x38C `KdSegSel` | WORD | **No reader or writer** (the selectors used are `KdSeg0..2`) | - | - | - | [OBS-RE] (absence) |
| +0x38E `Num_CP0` / +0x390 `Num_CP1` / +0x392 `Num_CP2` | WORD x3 | **The process's code-page list** scanned for `kbdCP` (`repne scasw` from +0x38E, `1C04A8FD..09`): +0x390/+0x392 copied from object 7 `CP1`/`CP2` by `ANSIINIT` (`1C041FEE`/`F5`); +0x38E is never written, so it stays 0 - mirroring object 7 +0xBEA, which `ANSIINIT` sets to 0 in the fetched buffer [INF] | #718 `ANSIINIT`; #849 | LIBINIT | copies of system values | [OBS-RE] |
| +0x394 `KdSeg0` / +0x396 `KdSeg1` / +0x398 `KdSeg2` | WORD selector x3 | **Per-code-page ANSI key-definition segment selectors** (`\SHAREMEM\ANSI\KDsgcp`, object 7 G8 +0xADC): #849 addresses `KdSeg[CPIndex]` (`lea di,[di+0x394]`, `1C04A927`) as the output cell for `AccessKeyDefSeg` | #849, `AccessKeyDefSeg` | 0; obtained lazily per (SG, CP) | per-process selectors to **shared** segments; the name template is patched in shared object 7 | [OBS-RE] |
| +0x39A `HexDigit` | char[16], **image `0123456789ABCDEF`** | Lookup table for `BinToHx` (`mov al,[bx+0x39a]`), which produces the hex SG/CP digits `AccessBVSCB`/`AccessKeyDefSeg` patch into the shared names | `BinToHx` <- `AccessBVSCB`, `AccessKeyDefSeg` (DS = object 8 in #849) | **image value** | read-only | [OBS-RE] (SMP) + image |
| +0x3AA `KeyDefHdr` (6 bytes) | WORD + BYTE + WORD | **Header of one key definition being stored**: +0x3AA key code (DX), +0x3AC length (<= 0x80), +0x3AD word 0 - written by `kdb3` before copying the definition into the KD segment | #849 via `kdb3` | per call | per call | [OBS-RE] (SMP `1C04AA4C..58`; UNI +0x35A..+0x35D) |
| +0x3B0 `InputData` | 8 bytes | **No reader or writer** | - | - | - | [OBS-RE] (absence) |
| +0x3B8 `country` / +0x3BC `dbcsev` | 4 bytes / 12 bytes | `COUNTRYCODE` and the **DBCS environment vector** returned by `DOSGETDBCSEV` (cb 10, `push es / push 0x3b8`, `push es / push 0x3bc`, ES = object 8 by `push 0x981f / pop es`, `1C04A6E0..EE`); `dbcsev[0] != 0` => DBCS lead-byte handling in SGR | `doSGR` <- #850 | per call | per call; the answer is system NLS data | [OBS-RE] |

**Locking - I6.** No lock of its own. #850 runs inside the VIO TTY path (BVS dispatch under the SG
semaphore, I1); `ANSIINIT` runs at LIBINIT. Every cell is per process; the shared objects it points at
(BVSCB, KD segments) and the shared name templates (object 7 G8) are the concurrency hazard. [OBS-RE]

**Not established (I6):** whether `BvscbSel` / `KdSeg*` are refreshed when the process changes screen
group (none seen; a stale per-process selector would address another SG's BVSCB); whether #848/#849 take
any lock.

### I7 - base keyboard subsystem per-process state (+0x3C8..+0x597)

UNI = SMP - 0x50. Every routine here runs on **DS = object 8 inherited from `BKSMAIN`** (`mov ax,0x981f /
mov ds,ax`, `1C042028..2B`, ES = object 7), which dispatches through `call [cs:si+0x1ffe]` (`1C042191`).
[OBS-RE]

**Three object-7 questions this group settles** [OBS-RE]:
1. **`HandleOpen`'s limit cell** (`cmp dx,[0x3cc]`, `1C04B3CA`) is object 8 **`LastBaseSG`** +0x3CC =
   `SIS_MaxScrnGrp - 1`, copied by `BKSMAIN` from object 7 `LBaseSG` on every call (`1C042076`); DX =
   object 8 `KBD_SG` (LIS +8, `1C042079`). **SG above it => windowed => PMVIOP shield** (`call far
   [es:0xc1a]`); else `DOSOPEN` `KBD$`.
2. **`HandleOpen` does not keep the handle**: `DOSOPEN` #70 writes into the **caller's** `PHKBD`
   (`[bp+0xe]:[bp+0x10]`, `1C04B3E2..FA`). It then sets that handle's code page from the process CP
   (`DOSGETCP` #130, `DOSDEVIOCTL` #53 category 4 function **0x5D** issued on `Dev_Handle`,
   `1C04B403..29`), and on success counts it in `Open_Count` +0x57D; the first open registers `OpenExit`
   with `DOSEXITLIST` #7.
3. **The custom-CP array index** is object 8 **`KBD_SG` +0x3CA, doubled**: `SetCodepage` does `mov
   bx,[0x3ca] / shl bx,1` then `[es:0xcbb+bx] := 0xFFFF` and `[es:0xcdb+bx] := AX` (`1C04B59F..B4`), AX
   being 0 on that path (the IOCtl succeeded) - so object 7's `Handle0CP_Save`/`Handle0CCP_PID` are
   **16-entry WORD arrays per screen group**, and success clears the owner pid. `SetCustCP` indexes
   `0xcbb` by the same value.

| offset + name | size/type | what it is | routines -> ordinal | initialiser (per process) | concurrency / consistency | prov |
|---|---|---|---|---|---|---|
| +0x3C8 `Shield_Scratch` | WORD | `SetStatus` stores the caller's `KBDINFO.fsMask & 0x1FF` here; `GetCodepage` passes it (address-taken `1C04AEB7`) as scratch to the shield | `SetStatus`, `GetCodepage` <- #851 | per call | per call | [OBS-RE] |
| +0x3CA `KBD_SG` | WORD SGID | Caller's SG, **LIS +8 copied on every `BKSMAIN` call**; index for the per-SG object-7 custom-CP arrays | `BKSMAIN` #851 (`1C042079`), `SetCodepage`, `CustomCP_Exit`, `OUTSKIP` | refreshed per call | per-call LIS copy | [OBS-RE] |
| +0x3CC `LastBaseSG` | WORD | `SIS_MaxScrnGrp - 1` from object 7 `LBaseSG`; **the windowed-session threshold** tested by every function (`HandleOpen`, `GetCharIn`, `SetCodepage`, `SetCustCP`, `GetFocus`, `HandleClose`, `FlushBuffer`, `Translate`, ...) | #851 | refreshed per call | copy of a system value | [OBS-RE] |
| +0x3D0 `Proc_Hand` | WORD | `BKSMAIN`'s caller argument `[bp+0xe]` (the KBD handle of the call), stored on entry (`1C042035`); `ReadChar` reads it | #851 | per call | per call; **overwritten by any concurrent thread of the process** - two threads of one process in *different* screen groups (not serialised by the per-SG KBD semaphore) would overwrite it mid-call [INF] | [OBS-RE] (SMP) |
| +0x3D2 `Win_Handle` / +0x3D4 `hConsole` | WORD x2 | For a windowed SG: `hConsole` from `VIOQUERYCONSOLE` (`1C042097..A0`) after `LoadWinthorn`; `Win_Handle` filled by the shield's `call far [es:0xc52]` with `push 0x981f / push 0x3d2` (`1C0420AC..B7`, and a second such push at `1C0420CE`, both in `BKSMAIN`); ~~both passed to every shield call~~ **corrected 2026-10-29 (Rule 1.7), from the bytes: every base routine passes `hConsole` and the CALLER'S hkbd; `Win_Handle` is obtained and passed by none** (unpublished notes) | #851 (`BKSMAIN`), all windowed arms (object 7 G9 vector) | lazily, first windowed KBD call in the process | per-process console handles; a child re-queries | [OBS-RE] |
| +0x3DA `Dev_Handle` | WORD handle | **This process's own `KBD$` handle**: opened by `BKSMAIN` on first use (`DOSOPEN` #70 of object 7's `KBD$` name +0xBF2, action object 7 +0xBFB, `1C042101..17`); **re-opened when `DOSDEVIOCTL` category 4 function 0x71 returns 6 or 0x16** (`1C04211E..5B`) - an inherited or stale handle is detected and replaced; used by every KBD$ IOCtl (`GetCharIn` function 0x74, `SetCodepage` 0x58, `HandleOpen` 0x5D, `OpenExit` 0x5E), and copied to object 7 `Shared_Handle` by `Init_CP` | #851 | 0 -> first non-windowed call | a per-process file handle; the function-0x71 probe is IBM's own recovery for a handle that is not open in this process | [OBS-RE] |
| +0x3DE `Entry_Count` | BYTE | **Re-entry depth of `BKSMAIN`** in this process: `inc` before the dispatch, `dec` after (`1C042187/96`); the lazy `Dev_Handle` open and `ValidateInHand` run only at depth 0 (`1C0420F1`) | #851 | 0 | a per-process counter, **not a lock** - two threads increment it unsynchronised | [OBS-RE] (SMP) |
| +0x3E0 `Transfer_Count` (+0x3E2 `StartPos`, +0x3E3 `CurrentPos`, +0x3E4 `TA_Type`, +0x3E5 `TA_Char`) | WORD + BYTE x4 | `GetCharIn`/`PeekAtIt` pass +0x3E0 as the IOCtl category 4 function **0x74** packet head; the turnaround type/char and edit positions are `InString`'s line-editing state | `GetCharIn` (KbdCharIn), `PeekAtIt`, `InString` and its helpers (`GETCH`, `ENDLIN`, `POPTAB`, `FIGTAB`, `PUTNEW`, `OUT_`, `SKIPREP`) | per call | per call | [OBS-RE] |
| +0x3E6..+0x3EF `Char_Code`, `Scan_Code`, `Status`, `Shift_State`, `TimeStamp` (aliases `CPR_BufO/S`, `CPR_Length`, `CPR_Action`) | 10 bytes | **A `KBDKEYINFO` record** - the key being processed (`chChar` +0x3E6, `chScan` +0x3E7, `fbStatus`...); the `CPR_*` aliases reuse the same bytes for the ANSI cursor-position-report string | `InString`, `GetKeyDef`, `KeyDefChk`, `GetStatus`/`SetStatus`, `RawFilBuf`, `ReadChar`, `OUTSKIP` | per call | per call | [OBS-RE] |
| +0x3F0 `ANSI_State`, +0x3F2 `Buf_Position`, +0x3F4 `Buf_End` (**image 0x03FE x2**), +0x3F6 `KeyDefBufO` (**image 0x03FE**) / +0x3F8 `KeyDefBufS`, +0x3FA `Buf_Length`, +0x3FB `Action`, +0x3FC `KeyDefChar`, **+0x3FE `KeyDefBuf` (0x80)** | - | **The ANSI key-redefinition replay buffer.** When `ANSI_State` = 1 and the buffer is empty, `KeyDefChk` sets `Buf_Length` = 0x80, `KeyDefBufS:O` = DS:`KeyDefBuf`, `KeyDefChar` = (scan, char) and asks for that key's definition; then `Buf_Position` = `KeyDefBuf`, `Buf_End` += length. `GetKeyDef` returns one byte per call into `Char_Code`/`Scan_Code` and, when `Buf_Position` reaches `Buf_End`, resets both to `KeyDefBuf` and `Buf_Length` to 0. **The image's three 0x03FE cells are that empty state** (the cursors hold the buffer's own offset) | `KeyDefChk`, `GetKeyDef`, `InString` (<- KbdCharIn/KbdStringIn through #851), `ValidateInHand` (address-taken +0x3FC) | **image values** (empty buffer); a zero fill would start with position/end not pointing at `KeyDefBuf` | per process; a key definition in progress is shared by all threads reading KBD in the process | [OBS-RE] + image |
| +0x47E `WorkBuf` (0xFF) | 255 bytes | Readers show only its **first 4 bytes**: `InString` stores 10 at +0x47E and tests bit 3 of +0x480 - a `KBDINFO` (`cb` = 10, `fsMask`) at the head of the buffer ([INF] from the `cb` value and bit meaning). No constant reference reaches +0x482..+0x57C | `InString` | per call | per call | [OBS-RE] |
| +0x57D `Open_Count` | WORD | Number of logical KBD handles opened by this process (`HandleOpen` `inc`, `HandleClose`); `OpenExit` (exit list) sets it to 0xFFFF and issues category 4 function **0x5E** on `Dev_Handle` with `&Open_Count` - releasing the process's handles at exit | `HandleOpen` (KbdOpen **#767**), `HandleClose` (KbdClose), `OpenExit` | 0 | per process; the exit path runs on the exiting thread | [OBS-RE] (SMP) |
| +0x57F `Bond_Handle` / +0x581 `Flag` | WORD / BYTE | **The KBD handle this process has bound (focus) and custom-CP state**: `Flag` bit 0x80 = a handle is bound (= `Bond_Handle`), bit 0 = its custom code page is active; `HandleClose`, `SetCustCP`, `GetFocus`/`FreeFocus`, `ValidateInHand` compare the caller's handle with `Bond_Handle` | #851 functions 7-11 (G9 list), `SetCustCP` (KbdSetCustXt **#745**) | 0 | per process | [OBS-RE] |
| +0x582 `Custom_Tbl_Off` / +0x584 `Custom_Tbl_Sel` | far ptr | The caller's custom translate table passed to `KbdSetCustXt` (address-taken `1C04AC57`) | `SetCustCP` #745 | per call | a pointer into the caller's memory | [OBS-RE] (SMP) |
| +0x586 `Previous_CP` / +0x588 `CP_Index` | WORD x2 | `SetCustCP` saves the SG's `Handle0CP_Save[KBD_SG]` into `Previous_CP` when it is -1; `GetCodepage` returns `Previous_CP` while bit 0 of `Flag` is set | `SetCustCP` #745, `GetCodepage` | per custom-CP activation | per process; the object-7 per-SG array is shared (unlocked) | [OBS-RE] |
| +0x58A `CCode` / +0x58C `CP_ID` / +0x58E `CRange` (10 bytes) | WORD, WORD, 10 bytes | `CP_ID`: the code page for `KbdSetCp` - `KBDGETCP` output (`1C04B525`), then the IOCtl category 4 function **0x58** argument (`1C04B58B..96`); `GetDBCS_String` passes `&CCode`/`&CP_ID` (`1C04BE7C/8F`), and `CRange` is presumably its DBCS range output [INF] | `SetCodepage` (KbdSetCp **#749**), `Translate`, `GetDBCS_String` | per call | per call | [OBS-RE] (SMP) |
| +0x3CE `Cooked_Mode`, +0x3D8 `PS_Sel`, +0x3DC `Echo_Mode`, +0x3DD `Insert_Mode`, +0x3DF `Sentinel` | mixed | Candidate readers named by constant references, segment not verified per site: `SetStatus`/`GetStatus` (`Cooked_Mode`, `Echo_Mode`), `OUTSKIP` (`PS_Sel`), `COPYEACH`/`EXITINS`/`NEWLIN`/`OLDBAK`/`SAVECHAR` (`Insert_Mode`), `GETCH`/`RawFilBuf`/`SKIPREP` (`Sentinel`) | as named | - | - | [OBS-RE] (candidate readers only) |
| +0x3D6 `Moufilter` (writer) / +0x482..+0x57C (rest of `WorkBuf`) | - | **No constant-reference writer** found for `Moufilter`; no reference into the `WorkBuf` tail | - | - | - | [OBS-RE] (absence) |

**Locking - I7.** None. `BKSMAIN` keeps a depth counter (`Entry_Count`), not a lock; `ROUTER`'s
`_KbdGetSemaphore` bracket is what serialises KBD calls **per screen group**. Threads of one process in
one SG are serialised by that; the per-call cells (`Proc_Hand`, the `KBDKEYINFO`, the replay buffer) rely
on it. [OBS-RE]

**Not established (I7):** which KBD API maps to each `BKSMAIN` function beyond the object 7 G9 list; the
key-definition fetch inside `KeyDefChk` (an unnamed call); the `WorkBuf` interior beyond
+0x04.

### I8 - KBD/MOU router per-process state: alternate-subsystem entries, thunk save slots, windowed mouse (+0x598..+0x5CF)

UNI = SMP - 0x50 (UNI +0x548..+0x57F). Router code reaches object 8 through the object-7 G0 slots (+0x58,
+0x60, +0x74, +0x78 -> object 8). The alternate-subsystem registration record is in the SGCB (+0x9C
keyboard / +0xB2 mouse; `session-manager.md`). [OBS-RE]

**How the per-process vectors relate to object 7 G11's shared cells** [OBS-RE]:

| cell | object | holds | same in every process? |
|---|---|---|---|
| `_BKS_Addr` / `_BMS_Addr` (object 7 +0xD18/+0xD14) | **shared** | the **base** KBD/MOU subsystem entry: BKSCALLS/BMSCALLS ordinal 1 (normally DOSCALL1's own `BKSMAIN`/`BMSMAIN`), rewritten by every process's `ROUTPROCESSINIT` | yes by value, when both modules resolve to DOSCALL1 |
| `_AKS_Addr` / `_AMS_Addr` (object 8 +0x59E/+0x5A2) | **per process** | the **alternate** subsystem entry registered by `KbdRegister`/`MouRegister` - the registration (mask SGCB +0x84/+0x86, record SGCB +0x9C) is **shared per screen group**; this cell is this process's *binding* of it | no - a module handle/entry resolved in this process |
| the eight `_<fn>_BASEIP/BASEDS/ALTIP/ALTDS` pairs (object 8 +0x5A6..+0x5C4) | **per process** | the **caller's return IP and DS**, saved by the `KbdGetFocus`/`KbdFreeFocus`/`KbdCharIn`/`KbdStringIn` thunks around a call through `_BKS_Addr` (base) or `_AKS_Addr` (alt) | no - per call |
| object 7 +0xD0C..+0xD12 (G10) | **shared** | the same kind of save, for the generic `_KBD/_MOU BASE/ALT SUBSYS` trampolines | - |

So the design splits **which subsystem is registered** (shared SGCB), **where the base entry is** (shared
object 7) and **where the alternate entry is in this process, and where to return** (object 8) - the same
shape as I1's `avs_*` binding of a shared VIO registration, refreshed on demand.

| offset + name | size/type | what it is | routines -> ordinal | initialiser (per process) | concurrency / consistency | prov |
|---|---|---|---|---|---|---|
| +0x598 `_ProcessInitFlag` | WORD | **"Router per-process init done."** `_KbdCheckProcType`/`_MouCheckProcType` call `ROUTPROCESSINIT` when it is 0; `ROUTPROCESSINIT` sets it to 1 as its last store on success (`mov es,[0x74] / mov word [es:0x598],1`, `1C0437E4..E8`) | `_KbdCheckProcType` / `_MouCheckProcType` <- `ROUTER` (every KBD/MOU API); `ROUTPROCESSINIT` (also <- #718) | 0 -> first KBD/MOU call (or LIBINIT); a child re-inits | per process; unlocked test-then-init, but idempotent | [OBS-RE] |
| +0x59A `_LocalInfo` | far ptr **LIS:0000** | The process's Local InfoSeg: offset 0 + the `DOSGETINFOSEG` #8 local selector (`1C0436B5..C3`, ES = slot +0x60) - the per-process twin of object 7 `_global_info` (GIS:0000), stored three instructions earlier | `ROUTPROCESSINIT` | per process | per process | [OBS-RE] (SMP) |
| +0x59E `_AKS_Addr` (off +0x59E, sel +0x5A0) | far ptr | **This process's entry for the alternate keyboard subsystem**, filled on two paths. **Eagerly, in the registering process**: `KBDREGISTER` (obj4+0x2B82) `push word 0x981f / push word 0x59e` into `DosGetProcAddr` #45, with the module handle from the SGCB registration record (`[es:bx+0x9c]` -> +0x04) and the **procedure name from the caller's own arguments** (`push [bp+0x1e] / push si`). **Lazily, in every other process of the screen group**: `_KbdReloadAltSubSys` - if the SG's registration mask (SGCB +0x84/+0x86) is non-zero **and** this cell is 0 - `DOSLOADMODULE` #44 the module named in the record (SGCB +0x9C -> +0x04) and `DOSGETPROCADDR` #45 the entry name from the record (+0x06, `lea ax,[bx+0x6]`) into this cell (`1C043981..39DC`, ES = slot +0x78). Zeroed by `KBDDEREGISTER` (**#764**) along with SGCB +0x84/+0x9C/+0x9E (`1C042D4C..63`, ES = slot +0x58). `KBDSYNCH` (**#751**) compares `(sel \| 3)` with the caller's CS ("is the caller the alternate subsystem"). Called through by `_KBDALTSUBSYS` and the four `_*ALTSUBSYS` thunks (`call far [0x59e]`, `1C04BF06`) | `KBDREGISTER`, #764, #751, `ROUTER` (every KBD API) | 0; bound eagerly in the registering process, lazily in the others on their first call after a registration | **per-process binding of per-SG shared state**: reloaded only when zero, and a deregistration zeroes only the deregistering process's copy, so another process keeps calling its old binding after a re-registration [INF] | [OBS-RE] |
| +0x5A2 `_AMS_Addr` (off +0x5A2, sel +0x5A4) | far ptr | Mouse twin, byte-for-byte parallel: `MOUREGISTER` fills it eagerly at obj4+0x3058 via `DosGetProcAddr` #45 (record at SGCB +0xB2 -> +0x04, name from the caller); `_MouReloadAltSubSys` lazily (`1C043A35..39`); zeroed by `MOUDEREGISTER` (`1C043227..2B`); compared by `MOUSYNCH` (`1C043343`); called by `_MOUALTSUBSYS` (`1C04BEE1`) | MOU router APIs | as `_AKS_Addr` | as `_AKS_Addr` | [OBS-RE] |
| +0x5A6..+0x5C4 `_getfocus_BASEIP/DS`, `_getfocus_ALTIP/DS`, `_freefocus_*`, `_charin_*`, `_stringin_*` | WORD x16 | **Return-context save slots**, not function pointers: each `_<fn>BASESUBSYS` / `_<fn>ALTSUBSYS` loads DS = object 8, `pop`s the caller's return IP and DS into its pair, calls `_BKS_Addr` (base, `call far [0xd18]` with DS = object 7) or `_AKS_Addr` (alt), then `push`es the pair back to return (`1C04BF1C..BF52` for GetFocus-base) | `_GETFOCUS*` (KbdGetFocus **#756**), `_FREEFOCUS*` (**#762**), `_CHARIN*` (KbdCharIn **#748**), `_STRINGIN*` (KbdStringIn **#753**) | per call | **per process, not per thread**: these calls run inside `ROUTER`'s per-SG `_KbdGetSemaphore` bracket, so two threads of one process in different SGs could overwrite a saved **return address** [INF] | [OBS-RE] |
| +0x5C6 `_hConsole`, +0x5CC `_MouOpenCnt`, +0x5CE `_WTMouseHandle` | WORD x3 | **Windowed-VIO mouse**: for `procTYPE` = 2, `BMSOPEN` opens the real mouse once per process (`MOUSEOPEN(&_WTMouseHandle)` when `_MouOpenCnt` = 0), calls the PMVIOP mouse shield open (object 7 G12), counts the open and returns `_hConsole` as the caller's mouse handle. Every `SHLD*` routine passes `_hConsole` to the shield; `SHLDCLOSE` decrements `_MouOpenCnt` and at 0 closes and zeroes `_hConsole` (`1C04C8F1..90A`) | `BMSOPEN` / `SHLD*` <- **#852 `BMSMAIN`** (MouOpen/MouClose/... for a windowed session) | 0; per process | per-process handles; the count is unlocked | [OBS-RE] |
| +0x5C8 `_moufilter` / +0x5CA `_PS_Sel` | WORD x2 | **No reader or writer.** `_hConsole`'s writer was not found either (not address-taken by constant) | - | - | - | [OBS-RE] (absence) |

**Locking - I8.** None of its own. KBD/MOU calls run inside `ROUTER`'s `CheckProcType -> GetSemaphore ->
dispatch -> ClearSemaphore` bracket, whose semaphore is per screen group; the object-8 save slots and
bindings rely on it. [OBS-RE]

**Not established (I8):** the writer of `_hConsole` (+0x5C6), presumably the shield open through a
pointer; whether `_KbdReloadAltSubSys` ever re-binds a non-zero `_AKS_Addr` after another process
re-registers; the routine `ROUTPROCESSINIT`'s two `DOSEXITLIST` #7 registrations add (`0xB081`, entry
`e026:3486`).

### I0 - `SMGINSTANCE`, export 864: the session manager's per-process block (+0x000..+0x0CF)

The structure's readers reach +0xC7, so `SMGINSTANCE` runs to about +0xC8 and **contains** `ArraySeg`
(+0xAF, listed under I1) and the +0xB1..+0xCF cells. Identical image in UNI and SMP. [OBS-RE]

**The pointer and the loader contract.** Object 5's `SMG_INSTANCE` (+0xB12) is **`981F:0000`** in the
image (object 5 +0xB12 = `00 00`, +0xB14 = `1f 98` with the fixup), so every offset a session-manager
routine reads through it is an object-8 offset with no bias. The session-manager routines that use it are
in obj3 (16 `[0xb12]` load sites in 12 routines, obj3/obj4). **`DOSWINPROC`'s convention** (as object 5's
own three calls use it): `SI` = the HMODULE cell, with the ASCIIZ module name at `SI+2`; `BX` = an array
of export **ordinals**; `DX` = the array of far pointers to fill; `CX` = how many. Object 5 uses it for
the system-wide OS2SM/PMVIOP callbacks; object 8 uses **the same routine** for this process's own PM
bindings - which is what the three module names in the image are for. `DOSWINPROC` used against both
objects is the cleanest statement of what object 8 is: the per-process half of the session manager's
state, with object 5 holding the system-wide half. [OBS-RE]

| offset + name | size/type | what it is | routines -> ordinal | initialiser (per process) | concurrency / consistency | prov |
|---|---|---|---|---|---|---|
| +0x000..+0x07F | 32 x DWORD far ptr | **This process's request-block table**: `REQUESTBLOCKALOC` allocates a block with `DOSSMGETMEM` into slot `[count]` (`mov di,[fs:bx+0x80] / shl di,2 / add di,bx`, `1C035173..81`); `PARENTEXITLIST` walks `count` slots, `les di,[si]` each, and marks every block (`[es:di+0x1e] = 1`); `APPSENDREQUEST` walks them from +0x04 | `REQUESTBLOCKALOC`, `APPSENDREQUEST`, `PARENTEXITLIST`, `SSTHAWPIDS`, `DOSSTARTSESSION` **#702** | 0; grown per request | per process; the blocks themselves are `DOSSMGETMEM` (shared-arena) memory | [OBS-RE] (SMP) |
| +0x080 | WORD | **Number of entries in use** in that table: `REQUESTBLOCKALOC` indexes with it; `APPSENDREQUEST` decrements it when releasing (`dec word [di+0x80]`, `1C035085`); `PARENTEXITLIST` uses it as the walk count | as above | 0 | per process; unlocked | [OBS-RE] (SMP) |
| +0x082 HMODULE, +0x084 name **`PMWIN`** | WORD + 6 bytes | Module handle + name for this process's **PMWIN** binding | `APPSENDREQUEST`: `lea bx,[si+0x9d] / lea dx,[si+0xa3] / lea si,[si+0x82] / cx=1 / call DOSWINPROC` (`1C034E05..15`), taken only when a request flag bit 0 is set | 0 + image name; bound on demand | per-process module handle - invalid in any other process | [OBS-RE] (SMP) + image |
| +0x08A HMODULE, +0x08C name **`PMSHAPI`** | WORD + 8 bytes | The same pair for **PMSHAPI** | **no user found** (all five `DOSWINPROC` sites, and a scan for the offsets); the ordinal at +0x9F (**0x0010**) likewise has no reader | image name only | - | [OBS-RE] (absence) |
| +0x094 HMODULE, +0x096 name **`PMVDMP`** | WORD + 7 bytes | The same pair for **PMVDMP** (the PM VDM-process DLL) | `DOSSTARTSESSION` **#702**: `lea dx,[bx+0xab] / lea si,[bx+0x94] / lea bx,[bx+0xa1] / cx=1 / call DOSWINPROC` (`1C0346BE..CA`), **only when +0xAD is 0** (`1C0346B0`) | 0 + image name; bound on the first DosStartSession that needs it | per-process handle | [OBS-RE] (SMP) + image |
| +0x09D / +0x09F / +0x0A1 | WORD x3, **image 0x0112, 0x0010, 0x000D** | **Export ordinals** passed to `DOSWINPROC`: +0x9D (0x0112 = 274) for the PMWIN binding, +0xA1 (13) for the PMVDMP binding; +0x9F unused | as the two rows above | **image values** - `DOSWINPROC` loads by these names and resolves by these ordinals, so a zero block binds nothing | read-only | [OBS-RE] (SMP) + image |
| +0x0A3 / +0x0AB (far ptrs; selector halves +0x0A5 / +0x0AD) | DWORD x2 | **The resolved per-process entry points**: `DOSWINPROC` fills +0xA3 (PMWIN) and +0xAB (PMVDMP); the **selector half is the "already bound" test** - `DOSSTARTSESSION` skips the load when +0xAD != 0, `APPSENDREQUEST` loads `bx = [fs:si+0xa5]` and calls through it | #702, `APPSENDREQUEST` | 0 | per process; the same lazy-binding shape as I1's `avs_*` and I8's `_AKS_Addr` | [OBS-RE] (SMP) |
| +0x0AF `ArraySeg` | WORD | The `SMArray` addressability copy (I1 row); a cell **inside this structure** | `DOSSMGETSGCB` #684, `DOSSMINITSGCB` #685 | - | - | [OBS-RE] |
| +0x0B1 / +0x0B3 | WORD x2 | **Per-process "next session start" request bits**: `DOSSTARTSESSION` ORs 0x0001 into the new session's option word when +0xB1 = 1 and 0x0100 when +0xB3 = 1, then **clears +0xB3** (one-shot) (`1C034792..AD`). No writer found in the twelve `SMG_INSTANCE` routines | #702 | 0 | per process | [OBS-RE] (SMP; writer absent) |
| +0x0B5 / +0x0B7 | WORD x2 | **Screen-lock ownership**: `DOSSCRLOCK` **#695**, while holding object 5's fast-safe semaphore at +0xC95, registers an exit-list routine (`DOSCLEANUP`, `cs:0xD094`, order `0xC001`) and stores **LIS +8 (SG)** into +0xB5 and **LIS +0 (pid)** into +0xB7 (`1C03D2CD..D300`); `DOSSCRUNLOCK` **#691** and `DOSCLEANUP` compare them; `DOSMODEWAIT` **#704**, `DOSMODEUNDO` **#701** and `DOSSAVREDRAWUNDO` **#697** test +0xB5 as "do I hold it" | #695/#691/#704/#701/#696/#697, `DOSCLEANUP` | 0 | **taken under object 5's group-5 semaphore at +0xC95** - the lock is system-wide, this is the per-process record of holding it | [OBS-RE] (SMP) |
| +0x0BB | WORD | An offset stored with the lock; `DOSSCRUNLOCK`/`DOSCLEANUP` load it into DI and test `[di+4]` before releasing | same | 0 | as above | [OBS-RE] (SMP); what DI addresses not established |
| +0x0C5 / +0x0C7 | WORD x2 | **Outstanding `DosModeWait` / `DosSavRedrawWait`**: cleared by `DOSMODEUNDO` (+0xC5, `1C03DB0A`) and `DOSSAVREDRAWUNDO` (+0xC7, `1C03DC40`); `DOSCLEANUP` reads +0xC7 at process exit | #701, #697, #704, #696, `DOSCLEANUP` | 0 | per process; the setter was not found | [OBS-RE] (SMP) |

**Locking - I0.** The session-manager cells are written inside object 5's group-5 fast-safe semaphore at
+0xC95 (`DOSSCRLOCK`, `DOSCLEANUP`, `DOSMODEWAIT`, `DOSSAVREDRAWWAIT` all take it first). The request-block
table and its count, and the PM bindings, are written with no lock of their own. [OBS-RE]

**Not established (I0):** writers of +0xB1/+0xB3 and setters of +0xC5/+0xC7; what DI addresses in the
+0xBB path; why the PMSHAPI pair and the +0x9F ordinal exist with no reader (a third binding never taken,
or one reached from a module other than DOSCALL1).

### Object 8 - summary

Object 8 (`OS2CHAR_I_GROUP`, SMP base 0x13030000, size 0x5D0, **INSTANCE**, selector 0x981F, exports **864**
`SMGINSTANCE` +0x0 and **865** `BVHINSTANCE` +0x1B0 SMP / +0x160 UNI) is **the per-process half of
everything objects 5 and 7 hold system-wide**: the session manager's per-process block, the BVH/BVS
instance data, and every per-process *binding* of a registration that lives in shared memory.

| group | span | subject | owning ordinals |
|---|---|---|---|
| I0 | +0x000..+0x0CF | session-manager per-process block: request-block table + count, PM module bindings (PMWIN/PMVDMP via `DOSWINPROC`), screen-lock ownership, ModeWait/SavRedrawWait state | #702, #695, #691, #696, #697, #701, #704, #684, #685, `APPSENDREQUEST`/`PARENTEXITLIST`/`DOSCLEANUP` |
| I1 | +0x0AF..+0x123 | VIO linkage: the SG fast-safe semaphore address, the semaphore held, alternate-video-subsystem binding, popup state, BVS entry, print-screen thread stacks, popup-exclusion semaphore | #718, #780, #770, #813, #775, #838, #822, #773, #783, #807, #789, #809 |
| I2 | +0x124..+0x1AF | identity (procTYPE/currpid/currsg/InfoSegs), popup & print-screen semaphore handles, VDD handle, global-registration replay, SGCB/SGCB_temp/SGCB_pop | as I1, plus #852, `viorout` (every VIO API) |
| I3 | +0x1B0..+0x325 | `BVHINSTANCE` = DDK `bvhidata` (37 fields): SCREEN$ handle, PVB mapping, WDH/AVIO state - **handler-owned; DOSCALL1 touches none of it** | export 865; BVHVGA/BVHWNDW |
| I4+I5 | +0x320..+0x37F | `BVSINSTANCE` (BVSCB/ENVB/LVB selectors, sgnum, GIS/LIS selectors, level, flags, popup cells, register), temp buffers, per-process device/VDH latches | #845, #822 chain |
| I6 | +0x380..+0x3C7 | ANSI: code-page list, key-definition segments, BVSCB selector, DBCS vector | #718, #848, #849, #850 |
| I7 | +0x3C8..+0x597 | base keyboard subsystem: KBD$ handle, windowed console handles, `KBDKEYINFO`, ANSI key-replay buffer, focus/custom-CP state | #851, #767, #745, #749 |
| I8 | +0x598..+0x5CF | KBD/MOU router: per-process init flag, LIS pointer, alternate-subsystem entries, thunk return-save slots, windowed mouse | #718, #748, #751, #753, #756, #762, #764, #852 |

**Concurrency - the per-process model.** What serialises object 8: (1) the **screen group's fast-safe
semaphore** (SGCB+0x68, address cached at +0xD4) - every VIO API takes it in `viorout`, so I1/I2/I4/I6
writes are serialised *per screen group*; (2) `ROUTER`'s `CheckProcType -> GetSemaphore -> ... ->
ClearSemaphore` bracket, also per screen group, for I7/I8; (3) `DOSENTERCRITSEC` #13 around popup state;
(4) object 5's +0xC95 semaphore for I0's lock cells. [OBS-RE] **The hazard is the same shape three times:
per-process state under a per-screen-group lock.** Two threads of one process in different screen groups
are serialised by none of the above, and share `Proc_Hand`/`Entry_Count` (I7), the eight thunk
return-address pairs (I8), and the temp-buffer count and VDH latches (I4/I5). None is established as
reachable; all three are stores read at the site. [OBS-RE] stores / [INF] reachability

**Cells kept consistent with shared state in objects 5/7** [OBS-RE]:

| object 8 cell | shared source | how it is kept in step |
|---|---|---|
| `ArraySeg` +0xAF | object 7 `SMArray` selector | re-checked on every #684 under object 7's `SMQueueRamSem` |
| `avs_hand/off/sel`, `avs_bvs_bits` +0xE4..+0xEA | SGCB registration (+0x34/+0x3C/+0x3E) | `vioattach` rebinds when SGCB+0x44 != `oldtimes` +0x132 |
| `gvs_*` +0xF0..+0xF4 and the grown replay tail | object 7 `Ggvs_*` | replay when object 7 `Ggvs_count` != `Igvs_count` |
| `bvs_off/sel` +0xFC | object 7 `_InitFlag` bit | one-shot shared latch, idempotent |
| `fsRAMoff/sel` +0xD4, `SGCB` +0x19E | the SGCB itself | re-fetched by #684 per process; swapped under critsec for popups |
| `bvsi_bvssel` +0x320 **and** ANSI's `BvscbSel` +0x38A | one BVSCB | **two independent copies**, one from BVS, one obtained by name |
| `_AKS_Addr`/`_AMS_Addr` +0x59E/+0x5A2 | SGCB alternate-subsystem registration | bound eagerly in the registering process and lazily (only when zero) in the others; a deregistration elsewhere does not clear this process's copy |
| `LastBaseSG` +0x3CC | object 7 `LBaseSG` | re-copied on every `BKSMAIN` call |

**Per-process initialisation** [OBS-RE]:
- **LIBINIT (#718 `OS2BASEINIT` -> `VIOINITPROCESS`, `initCP`, `ANSIINIT`, `ROUTPROCESSINIT`):** InfoSeg
  selectors, identity (I2), `SGCB`/`SGCB_pop`, the fsRAM pointer, the `\SEM\VIOPOPUP` / `\SEM\VIOPRTSC`
  handles, the BVSCALLS entry, the code page (I6), the router's `_LocalInfo` and `_ProcessInitFlag`.
- **Lazy, on first use:** `ArraySeg`; the AVS/GVS bindings; `bvsi_*` (first `BVSMAIN` with
  `bvsi_gdtsel` = 0); `KdSeg*`/`BvscbSel`; `Dev_Handle`; the PM module bindings (I0); `_AKS_Addr`/
  `_AMS_Addr` in non-registering processes; temp buffers.
- **Exit lists undo:** `VIOFSRAMEXIT0`/`VIOFSRAMEXIT` release a held SG semaphore; `OpenExit` releases
  KBD handles; `VIOENDPOPEXIT`/`...1` end a popup left open; `DOSCLEANUP` releases the screen lock;
  `CustomCP_Exit` restores a custom code page; `ROUTPROCESSINIT` adds two more (routine not named).
- **A child after `DosExecPgm`** gets a fresh object 8 from the image and redoes all of it: new handles,
  new module bindings, `FPERPROCDATAVALID` re-validates every device group, `Dev_Handle` is re-opened
  (and IBM's own function-0x71 probe catches a stale one).

**Cells whose meaning requires a non-zero initial value** [OBS-RE] (image; nothing else in 0x000..0x5D0
is non-zero):

| cell | value | why |
|---|---|---|
| I0 +0x84/+0x8C/+0x96 module names, +0x9D/+0x9F/+0xA1 ordinals | `PMWIN`, `PMSHAPI`, `PMVDMP`; 0x0112, 0x0010, 0x000D | `DOSWINPROC` loads by these names and resolves by these ordinals |
| I1 +0x112 | `\SEM\POPXBLOK.SEM` | the name #780/#770 open |
| I3 +0x1CA `cell_size`, +0x31A `cmn_bvscbsize` | 2, 0x033E | both read by both handler source trees |
| I6 +0x39A `HexDigit` | `0123456789ABCDEF` | `BinToHx` builds the shared segment names from it |
| I7 +0x3F2/+0x3F4/+0x3F6 | 0x03FE (= `KeyDefBuf`'s own offset) | the empty state of the key-replay buffer |

**Object 8 grows at run time.** `vioattach` `DOSREALLOCSEG`s **DS** by +0x10 per global VIO registration
and appends a 16-byte entry past +0x5D0 (entry + active mask); `Igvs_last` +0x146 tracks the end. So the
per-process object is grown in place at its fixed address. [OBS-RE]

**SMP vs UNI.** The two layout enlargements are given at the head of this section; no SMP code reads or
writes the trace region (the MMIO trace uses object 7 +0x26 and object 7's `_mmio_*`). The only
behavioural SMP difference reaching object 8 is the fast-safe-semaphore primitive (`DC1hSpinLock`).
[OBS-RE]

**Attribution between objects 7 and 8** [OBS-RE]. The eight displacements object-7 G2 assigns to object 8
in `VIOINITPROCESS`/`VIOPOPUP` all exist as coherent object-8 cells (`InfoSegL/G` +0x12C/+0x12E,
`vddhandle` +0x134, `pu_sem` +0x138, `prtscsem` +0x13C, `SGCB` +0x19E, `SGCB_temp` +0x1A2, `SGCB_pop`
+0x1A6). Between the two objects' access listings there are exactly 7 (routine, offset) pairs claimed by
both - `BVSMAIN|0x4B6`, `GetBVSCB|0x4B6`, and +0x002 under `viorout`, `VIOPOPUP`, `VIOENDPOPUP`,
`VIOREGISTER`, `VIODEREGISTER` - and all seven are register-indexed, so no non-indexed access is
ambiguous between them. Constant loads of object-8 negative offsets in `DOSSMSGSTART`, `AllBuffer`,
`SyncCursor`, `BvsGetCurType`, `BvsGetFont`, `_CopyFile`, `SyncModeCursor`, `BvsGetMode`,
`BvsMVDMTranPop`, `AllGetVarInfo` come from routines whose DS is established as neither object; in
`SetForcedCP`, `mov di,0x10c / call 0x1bfd` passes 0x10C as an argument, not a displacement - so every
object-8 "no reader" stands.

## Objects 9 and 10 - the 16-bit IPC queue heaps (`_QSEG1` / `_QSEG2`)

They are the smallest objects in the module and the only two with **no named cell at all** - no symbol
in any DOSCALL1 `.SYM`; they are identified by their consumer. Their content is a **heap**, so what is
documented here is the heap contract and the records in it.

**Header** `[OBS-RE]` (LX object table, SMP):

| obj | base | vsize | flags | mapsize | selector |
|---|---|---|---|---|---|
| 9 | `0x13040000` | `0x1000` | `0x1023` = READ\|WRITE\|16:16-alias\|**SHARED** | **0** | `0x9827` |
| 10 | `0x13050000` | `0x1000` | `0x1023` - same | **0** | `0x982F` |

`mapsize = 0`: neither object has a page-map entry, so neither has any image bytes; the loader creates a
zero-filled 4 KB segment and nothing else. The entire content of both is produced at run time by
`DosSubAlloc`. Both are SHARED: one copy each per system, which is what makes a queue record created by
process A readable by process B at the same selector.

**How they are reached** `[OBS-RE]`. No routine ever loads either selector into a segment register:
there is no segment-relative access, no `0x9827`/`0x982F` selector literal anywhere in the four code
objects, and no flat `0x1304xxxx`/`0x1305xxxx` access. The only fixups whose target is object 9 or 10 are
three, all in object 5:

```
obj5+0x000200  stype=2 -> internal obj9+0x0      (_QSEG,  the CURRENT heap selector)
obj5+0x000202  stype=2 -> internal obj9+0x0      (_QSEG1)
obj5+0x000204  stype=2 -> internal obj10+0x0     (_QSEG2)
```

So objects 9 and 10 are reachable only through object 5's three selector cells, and every access to
their contents goes through a far pointer `DosSubAlloc` returned (`les bx,[bp-0x4]` after a
`DosSubAlloc`). No scan over a static listing can enumerate a `DosSubAlloc` heap; the record layouts
below were read out of the routines.

### The allocator: `_FindMem` (SMP obj3+0x2E36; UNI obj3:0x21EE) `[OBS-RE]`

```
USHORT cdecl _FindMem(WORD cb /*[bp+6]*/, FARPTR far *out /*[bp+8]*/)
```

1. `DosSubAlloc(_QSEG[0x200], &off, cb)` - #147. Success -> write `off:_QSEG` through `out`, return 0.
2. Failure -> try to **grow the current segment**: if `_statseg+0x11` (obj5+0x1EF) is non-zero,
   `ax = size; ah += 0x10` (i.e. +0x1000), `DosReallocSeg(newsize, _QSEG)` (#38), then
   `DosSubSet(_QSEG, 0, newsize)` (#146, flag 0 = extend an existing pool) and store `newsize` back into
   obj5+0x1EF. `DosReallocSeg` failure -> **334** (0x14E, `ERROR_QUE_NO_MEMORY`); `DosSubSet` failure ->
   **328** (0x148, `mov ax,0x148` at obj3+0x2EC7).
3. `_statseg+0x11 == 0` -> the segment is at its 64 KB maximum, so switch heaps:
   `_QSEG = (_QSEG == _QSEG2) ? _QSEG1 : _QSEG2`. If the new `_QSEG` is `_QSEG2` **and** obj5+0x1DC is
   non-zero, `DosSubSet(_QSEG2, 1, 0x1000)` **creates object 10's pool** and sets
   `_statseg+0x11 = 0x1000`, `[0x1DC] = 0` (test at `1C032F09`, clear at `1C032F2E`).
4. The whole thing is a two-pass loop (`[bp-0xc]` starts at 1): the "cannot grow" arm returns 334
   unless this is the first pass, so each call tries at most one segment switch.

**Why `_statseg+0x11 == 0` means "full".** `ah += 0x10` adds 0x1000 to a WORD; at 0xF000 the next grow
yields 0x0000, so the size word reaching 0 means the segment has reached 64 KB, the 16-bit segment
maximum. The arithmetic and branch are `[OBS-RE]`; the sentence is `[INF]` with no competing reading -
there is no other assignment to that cell.

**The grow path allocates twice and leaks the first block** `[OBS-RE]` control flow, behaviour not
observed. At `1C032EBE` the grown-pool retry calls `DosSubAlloc`; on success (`jz 0x2f31`) it falls into
the pass-counter tail, which jumps back to the loop top at `1C032E45` and calls `DosSubAlloc` again, and
it is that second block whose offset reaches the caller. No competing reading was found.

**The free side** - `DosSubFree(sel, off, cb)` (#148), every call site:

| site | frees | size pushed |
|---|---|---|
| `_Q_Delete` `1C03EDBF` | a queue record | `_farstrlen(rec+0x20) + 0x21` |
| `_FuncInit` `1C032D5E` | a queue record, during owner-died recovery | same expression |
| `C_EXITLISTQUEUE1` `1C035BC1` | a queue record, on process exit | (same family) |
| `_L_Remove` `1C03F048` | a link record | `0x0A` |
| `_El_Delete` `1C03F231`, `1C03F2B5` | an element | `0x18` |
| `W_DOSREADQUEUE` `1C032452` | the element just consumed | `0x18` |

The free list is `DosSubSet`/`DosSubAlloc`'s own, not the queue package's: there is no free-list head in
object 5 and no block header the queue code writes. The queue package knows only the size it allocated,
which is why every free recomputes `strlen(name) + 0x21` rather than reading a length back.

### The heap contract

| question | answer | provenance |
|---|---|---|
| allocation scheme | 16-bit `DosSubSet`/`DosSubAlloc`/`DosSubFree` suballocation inside a 16-bit selector; the pool is the object, the blocks are the records | [OBS-RE] `_FindMem`, `_DYNAINIT` |
| free discipline | the suballocator's; the caller supplies the size on free | [OBS-RE] six `DosSubFree` sites |
| initial size | **obj9: 0x1000, created by `_DYNAINIT` once per system. obj10: nothing - its pool is created lazily by `_FindMem` the first time obj9 is full** | [OBS-RE] `1C03F0FB` vs `1C032F10` |
| growth | `DosReallocSeg` + `DosSubSet(sel,0,new)` in 0x1000 steps, per segment | [OBS-RE] |
| ceiling | **64 KB per segment, 128 KB total**, system-wide, for every queue, opener and element in the system. `_FindMem` grows with `add ah,0x10` at obj3+0x2E72 and its only test is `cmp word [es:0x1ef],byte +0x0` at obj3+0x2E66; no constant compare against a ceiling exists. The 64 KB is the WORD wrapping to zero after 0xF000; the 128 KB is that times the two fixed heaps. | [INF], one inference deep from the [OBS-RE] instructions |
| when full | **`_Q_Tbl` and `_L_Tbl` each write 334 `ERROR_QUE_NO_MEMORY` themselves** on the allocation-failure arm, discarding `_FindMem`'s AX: `_Q_Tbl` obj3+0x1599 is `or ax,ax / jz` then `mov ax,0x14e / pop ds / leave / retf`; `_L_Tbl` obj3+0x1945 is the same with an extra `pop si`. So `_FindMem`'s 328 (its `DosSubSet`-failure arm) never reaches their callers. Neither failure arm frees anything. `W_DOSWRITEQUEUE`'s failure arm is not read. | [OBS-RE] |
| shrink | **never** - no `DosReallocSeg` downward and no `DosSubUnset` anywhere in the package (every #38 / `DOSSUBSET` / `DOSSUBFREE` call site attributed to its routine) | [OBS-RE] |
| which heap holds what | **neither is specialised**: all three record kinds go to whichever segment `_QSEG` currently names; obj9 takes everything until it reaches 64 KB and obj10 is pure overflow | [OBS-RE] `_FindMem` |

**The other `DosSubAlloc` consumer is a different pool** `[OBS-RE]`. `DOSSMGETMEM`/`DOSSMFREEMEM`
(session manager) run on a segment the session manager allocates itself with `DosAllocSeg` (#34) and
caches at **obj7+0xD8**, with its size at **obj7+0xE0** (`DOSSMGETMEM` `1C0352FA..1C035397`), created on
first use and grown the same way. IBM keeps the two pools apart.

### What is in them - three record types `[OBS-RE]`

`_FindMem`'s only callers are `_Q_Tbl` (`0x21` + name), `_L_Tbl` (`0x0A`) and `W_DOSWRITEQUEUE` (`0x18`),
so every byte of objects 9 and 10 is one of three records.

#### Record A - the queue record, `strlen(name) + 0x21` bytes

Allocated by `_Q_Tbl` (<- `W_DOSCREATEQUEUE`, #681); freed by `_Q_Delete`, `_FuncInit`'s recovery arm and
`C_EXITLISTQUEUE1`.

| off | size | meaning | written by -> ordinal | read by | prov |
|---|---|---|---|---|---|
| +0x00 | BYTE | **Queue flags.** Set from `W_DOSCREATEQUEUE`'s `[bp+6]`, the byte above the 16-bit flags word. Bit 0x2 is set by `_L_Tbl` when a non-owner opener exists. Bit 0x4 selects the **32-bit event-semaphore** notification path over the 16-bit RAM/system one (`_OPEN16EVENTSEM`/`_POST16EVENTSEM`/`_CLOSE16EVENTSEM` vs `DosSemClear`). Bit 0x8 is read by `W_DOSREADQUEUE` and forces the returned status word to 4. Which `DosCreateQueue` argument bit reaches `[bp+6]` is not established. | `_Q_Tbl` #681, `_L_Tbl` #680 | `W_DOSREADQUEUE` #674, `W_DOSWRITEQUEUE` #679 | [OBS-RE] |
| +0x01 | BYTE | **Owner open count**, incremented by `_L_Tbl` when the opener *is* the creating process, so the creator never gets a link record. | `_L_Tbl` #680 (`1C0318A2`) | - | [OBS-RE] |
| +0x02 | 2 bytes | Never written by `_Q_Tbl`; no reader found. Padding before the WORD at +0x04 is the obvious reading and is not established. | - | - | [unverified] |
| +0x04 | WORD | **Queue type**: 0 FIFO, 1 LIFO, 2 PRIORITY. `W_DOSCREATEQUEUE` rejects `> 2` with **336** (0x150). Read by `W_DOSWRITEQUEUE` to choose the insertion rule and by `W_DOSREADQUEUE` to choose the end it reads from. | `_Q_Tbl` #681 | #679, #674 | [OBS-RE] |
| +0x06 | WORD | **Queue id** - the value a caller holds as its `HQUEUE`. Allocated from `_statseg+7` (obj5+0x1E5), pre-incremented, 0 skipped, retried until `_Q_Scan` reports it unused. | `_Q_Tbl` #681 | `_Q_Scan`, `_L_Tbl`, `_L_Find`, `_Q_Delete`, #674, #679 | [OBS-RE] |
| +0x08 | WORD | **Owner PID** - the creating process, from `_statseg+5` (obj5+0x1E3). `W_DOSREADQUEUE` returns **330** (0x14A) to a caller that is not it. | `_Q_Tbl` #681 | #674, `_L_Tbl` | [OBS-RE] |
| +0x0A | WORD | **Element count.** Incremented by `W_DOSWRITEQUEUE`, decremented by `W_DOSREADQUEUE` and `_El_Delete`; saved into object 5's journal cell `_count` (obj5+0x19C) before every mutation. | #679, #674, `_El_Delete` | #674, #679 | [OBS-RE] |
| +0x0C | DWORD far | **Element list head** | `_Q_Tbl` (=0), #679, #674, `_El_Delete` | same | [OBS-RE] |
| +0x10 | DWORD far | **Element list tail** | same | same | [OBS-RE] |
| +0x14 | DWORD far | **Next queue record** - the singly linked system-wide queue list whose head is `_statseg+9` (obj5+0x1E7). | `_Q_Tbl`, `_Q_Delete` | `_Q_Scan`, `_ScanQname`, #674, #679, `C_EXITLISTQUEUE1/2` | [OBS-RE] |
| +0x18 | DWORD | **A 16-bit RAM semaphore inside the record**, addressed `lea ax,[bx+0x18]` and passed to `DosSemWait(hsem, 0)` / `DosSemClear` - the "queue has data" latch. | `_Q_Tbl` (=0), #679 | #679 (`1C03307F`, `1C03324E`, `1C033271`) | [OBS-RE] |
| +0x1C | DWORD | **The reader's registered notification semaphore.** `W_DOSREADQUEUE` stores the caller's handle here on the first registering read and refuses a *different* one with **87**. `W_DOSWRITEQUEUE` posts it only on a write into an **empty** queue, and not when a NoWait=0 reader is blocked: UNI obj3:0x2528 (`[bp-0x16]` count != 0 -> 0x264A, no semaphore call on that path) and 0x256E (`DOSSEMWAIT(queue+0x18, 0)` != 0 -> clear +0x18, skip the notify). | #674 | #679 | [OBS-RE] |
| +0x20 | ASCIIZ | **The queue name**, in the `DosICanonicalize` (#100) form, not the caller's string. `_ScanQname` compares it; `_Q_Delete`/`_FuncInit` re-measure it to compute the free size. | `_Q_Tbl` #681 | `_ScanQname` <- #680 | [OBS-RE] |

#### Record B - the link (opener) record, exactly 10 bytes

Allocated by `_L_Tbl` (<- `W_DOSOPENQUEUE`, #680) - `push byte +0xa; call _FindMem` at `1C031939` - and
freed by `_L_Remove` with the same 0x0A. One record per (process, queue) pair for every opener that is
not the creator.

| off | size | meaning | prov |
|---|---|---|---|
| +0x00 | BYTE | set to 0 at creation; no other writer found | [OBS-RE] `1C031951` |
| +0x01 | BYTE | **open count** for this process on this queue; set to 1, incremented on a repeat open | [OBS-RE] `1C031958`, `1C031924` |
| +0x02 | WORD | **opener PID**, from `_statseg+5` | [OBS-RE] |
| +0x04 | WORD | **queue id** it refers to | [OBS-RE] |
| +0x06 | DWORD far | **next link record** - the system-wide opener list, head at `_statseg+0xD` (obj5+0x1EB) | [OBS-RE] |

#### Record C - the element record, exactly 0x18 = 24 bytes

Allocated by `W_DOSWRITEQUEUE` (#679) into `_e_offset` (obj5+0x1F6) - `push byte +0x18` at `1C033107` -
and freed by `W_DOSREADQUEUE` (#674) and `_El_Delete`, both with 0x18.

| off | size | meaning | prov |
|---|---|---|---|
| +0x00 | BYTE | **element flags**; bit 0x1 read by `W_DOSREADQUEUE` and, with queue flag 0x8, sets the returned status word to 4 | [OBS-RE] |
| +0x01 | BYTE | **priority**, clamped to `<= 0xF` when the queue type is 2 and forced to 0 otherwise; the priority insertion walk compares this byte | [OBS-RE] |
| +0x02 | DWORD | caller-supplied (the request/data pair). Which `DosWriteQueue` argument lands in +0x02 / +0x06 / +0x14 is not established. | [OBS-RE] that they come from parameters; assignment [unverified] |
| +0x06 | DWORD | caller-supplied, as above | same |
| +0x0A | DWORD far | **next element** | [OBS-RE] |
| +0x0E | DWORD far | **previous element** - the element list is doubly linked, which lets `W_DOSREADQUEUE` unlink from either end | [OBS-RE] |
| +0x12 | WORD | **writer PID**, from `_statseg+5` | [OBS-RE] |
| +0x14 | DWORD | caller-supplied, as +0x02 | same |

**Insertion and removal** `[OBS-RE]`. `W_DOSWRITEQUEUE` appends at the **tail** for queue types 0 *and*
1, and does a descending-priority insertion for type 2. **LIFO is a read rule, not an insertion rule:**
`W_DOSREADQUEUE` reads from `queue+0x10` (the tail) when the type is 1 and from `queue+0x0C` (the head)
otherwise. `DosPeekQueue`'s element walk follows +0x0A from the head in all cases, so a LIFO implemented
as push-front would give the same read-all order but a different peek order `[INF]`.

**`_action` journal codes** `[OBS-RE]` (object 5 +0x19A), as placed by the writers: 1 `_Q_Tbl` link-in,
2 `_L_Tbl` link-in, 3 last-element unlink, 4 head-element unlink, 5/6 the other two unlink shapes in
`W_DOSREADQUEUE`, 8 `_L_Remove`, 9/10/11/12 the four `W_DOSWRITEQUEUE` insertion shapes, 13
`_Q_Delete`. What `C_EXITLISTQUEUE1` does with each (its 13-entry jump table at obj3+0x591A) is not
decoded.

### Initialisation - two different moments `[OBS-RE]`

`_DYNAINIT` (SMP obj3+0xF0EA), whole body:

```
DosSubSet(_QSEG1 /*obj5+0x202 -> obj9*/, 1 /*INIT*/, 0x1000)   ; fails -> return 0
DosGetInfoSeg(&gis_sel, &lis_sel)                 ; #8
obj5+0x1F4 = gis_sel        ; _globptr's selector half
obj5+0x1EF = 0x1000         ; _statseg+0x11, current heap size
obj5+0x1F1 = 1              ; _initq
obj5+0x1DE = 1              ; _statseg+0
obj5+0x1E5 = 0              ; next queue id
obj5+0x1E7 = obj5+0x1E9 = 0 ; queue list head
obj5+0x1EB = obj5+0x1ED = 0 ; link list head
return -1
```

`_DYNAINIT` never touches object 10 and never touches obj5+0x1DC. So:
- **Object 9's pool is created once per system**, inside `InitDOSCALL1`'s once-per-system block (object
  5's unlocked +0x14 latch), **without** `\SEM\IPCQUEUE.SEM` held.
- **Object 10's pool is created lazily, by `_FindMem`, under `\SEM\IPCQUEUE.SEM`**, at the first
  allocation that finds object 9 at 64 KB. On a system that never fills object 9, object 10 stays a
  zero-filled segment no `DosSubSet` has seen, and `DosSubAlloc` against it would fail; obj5+0x1DC's
  image value 1 is what routes the first overflow through the pool creation.

### Concurrency `[OBS-RE]`

Everything in both objects is written only while holding `\SEM\IPCQUEUE.SEM` - the system semaphore
`_FuncInit` acquires and `_FuncFree` releases for #674-#681 and both exit lists. `_FindMem` is called only
from `_Q_Tbl`, `_L_Tbl` and `W_DOSWRITEQUEUE`, all inside that bracket. SMP adds nothing: no spinlock, no
`DC1hSpinLock`. Acquire accepts `ERROR_SEM_OWNER_DIED` (105), and `_FuncInit`'s recovery arm then frees a
queue record out of this heap using the journal in object 5 (`_action`, `_que1..3`, `_lnk1..3`,
`_emt1..3`), so the heap and the journal are one mechanism `[INF]`.

**Not established (objects 9/10):** queue record +0x02/+0x03; which `DosWriteQueue` argument occupies
element +0x02 / +0x06 / +0x14 and which `DosCreateQueue` bit reaches queue +0x00 (both need the Pascal
frame decoded and, for the 32-bit entries, the CONFORM16 marshalling); what the exit list does with each
`_action` code; whether growing a segment invalidates an outstanding far pointer (every record is
addressed `selector:offset` and `DosReallocSeg` keeps the selector, so the reading is that it does not
`[INF]`, not traced).

---

## Object 11 - `_SpawnData`, the FSD-daemon thread handoff block

**Header** `[OBS-RE]`: base `0x13060000`, vsize **0x30**, flags `0x1003` - no 0x20, so **INSTANCE, one
copy per process** - and **`mapsize = 0`**, so no image bytes: a 48-byte zero-filled segment, selector
`0x9837`. One symbol in the SMP `.SYM`, `000b:00000000 _SpawnData`, which names the object's start, not a
cell.

**Complete access set** `[OBS-RE]`: five sites, two routines. Selector literal `0x9837` twice, both in
`STARTFSDDAEMONS` (`push word 0x9837` `1C03F473`, `mov cx,0x9837` `1C03F4AF` - the fixup sites
obj3+0xF474/+0xF4B0; the UNI build has the same two literals at `1C03D453`/`1C03D48F`); three
`mov es,[0x1d60]` loads, all obj3 (`F3B3`, `F4BA`, `F59E`); no flat `0x1306xxxx` access. The fixups
targeting object 11 are exactly three: obj6+0x1D60, obj3+0xF474, obj3+0xF4B0. No export name contains
`spawn` (538 names), so `_SpawnData` is a linker symbol and **not an export**; the only holders of
selector `0x9837` are DOSCALL1's own code and obj6+0x1D60.

Ordinals called by its two routines `[INF]` (ordinal-to-name mapping as resolved for this read): #5
`DosExit`, #11 `DosSetPrty`, #34 `DosAllocSeg`, #141 `DosSemClear`, #142 `DosSemWait`, #143 `DosSemSet`,
#145 `DosCreateThread`, #183 `DosFSCtl`.

| off | size / type | meaning | routines | initial value | concurrency | prov |
|---|---|---|---|---|---|---|
| +0x00 | WORD | First word of the **12-byte per-daemon parameter block**; read by `SPAWNEDTHREAD` into `[bp-0xa]` and passed to its closing `DosFSCtl` (#183) beside the copied string. | `STARTFSDDAEMONS` (writes), `SPAWNEDTHREAD` (reads) - no ordinal | zero (loader); overwritten per daemon | see below | [OBS-RE] |
| +0x02 | WORD | **The daemon thread's stack size.** `les bx,[bp-0xdc]` where `[bp-0xdc]` is built as `obj11:0x0002` (`mov ax,2` / `mov cx,0x9837`); `[es:bx]` is pushed to `DosAllocSeg` (#34) and then, with the returned selector, to `DosCreateThread` (#145) as `pbStack = sel:size`. | `STARTFSDDAEMONS` `1C03F4AC..F505` | as above | as below | [OBS-RE] |
| +0x04 | DWORD | **Priority class.** `SPAWNEDTHREAD` loads +0x04/+0x06 as a DWORD and, if non-zero, calls `DosSetPrty` (#11) with scope 2 (thread), class = the low word here, delta = the low word at +0x08, id 0. | `SPAWNEDTHREAD` `1C03F5F9..F60B` | as above | per thread, before the rendezvous is released | [OBS-RE]; scope/class/delta from the Pascal push order |
| +0x08 | DWORD | **Priority delta**, low word, as above. | same | as above | same | [OBS-RE] |
| +0x0C / +0x0E | WORD x2 | **Zeroed by `STARTFSDDAEMONS` immediately before its first `DosFSCtl`** (`bx=0xC`, `[es:bx]=[es:bx+2]=0`); `obj11:0x000C` is then passed to `DosFSCtl` (#183) as a buffer with the literal 0x22 (34) beside it, at `1C03F3E0` and again at `1C03F53D`. 0x0C + 0x22 = 0x2E, so the buffer is the rest of the object. | `STARTFSDDAEMONS` x3 | zero (loader), re-zeroed once per `STARTFSDDAEMONS` | under the once-guard only | [OBS-RE]; the zero-then-call-again-tolerating-122 shape reads as an enumeration cursor `[INF]` - the `DosFSCtl` function code and route are not decoded |
| +0x10..+0x2D | ASCIIZ | **The name the daemon is spawned for.** `SPAWNEDTHREAD` does `repne scasb` from `ES:DI = obj11:0x0010` and `rep movsw` the result into a 46-byte stack buffer `[bp-0x2e]`, then passes that buffer to its closing `DosFSCtl`. `STARTFSDDAEMONS` also passes `obj11:0x0010` as a far pointer (`push word 0x9837 / push word 0x10` at `1C03F473`) to a third `DosFSCtl`, with the literal 4 beside it. What the string is, is not established. | `STARTFSDDAEMONS`, `SPAWNEDTHREAD` | filled by `DosFSCtl` | copied out before the rendezvous is released | [OBS-RE] copy and far pointers; content [unverified] |
| +0x2E / +0x2F | 2 bytes | No access found (all three `mov es,[0x1d60]` blocks read instruction by instruction, plus both `0x9837` literal sites). | - | - | - | [unverified] |

**The handoff mechanism** `[OBS-RE]`. `STARTFSDDAEMONS` (read whole, `1C03F38C..F590`; `SPAWNEDTHREAD`
`1C03F592..F655`) walks a **local** array at `[bp-0xce]` in 12-byte strides
(`add word [bp-0x2],byte +0xc`), and before each spawn does `rep movsw` with `cx=6` - twelve bytes from
that array into obj11+0x00..+0x0B. So object 11 is a **single-slot, serialised handoff**, not per-thread
storage, and two object-6 cells make reusing it safe:
- **`_InitializedAlready` (obj6+0x1262)** - the once-per-process guard; on re-entry `STARTFSDDAEMONS`
  records `_ExitPoint = 1` and returns without touching object 11.
- **`_WaitForThreadSpawned` (obj6+0x1264)** - a 16-bit RAM semaphore: `DosSemSet` (#143) before the first
  spawn and after each, `DosSemWait(-1)` (#142) after each `DosCreateThread`, `DosSemClear` (#141) by
  `SPAWNEDTHREAD` **after** it has copied the 12 bytes and the string onto its own stack and **before** it
  does anything else. The protocol: set -> fill 12 bytes -> spawn -> block until the child has taken a copy
  -> set again -> next daemon. The parent cannot run ahead of a child that has not yet taken its copy.

The 48 bytes hold a 12-byte parameter block, a 4-byte cursor and a ~30-byte name, reused for every daemon
in turn; the block's size is not the daemon's data size.

**Concurrency.** The rendezvous serialises the parent against its child; nothing serialises two parents.
`_InitializedAlready` is an unguarded test-and-set, so two threads of one process entering
`STARTFSDDAEMONS` together both proceed and both drive the same 48 bytes; IBM does not serialise it
`[OBS-RE]`.

**Per process.** Object 11 is INSTANCE, so `DosExecPgm` gives the child a fresh zero-filled 48 bytes
alongside a fresh object 6 whose `_InitializedAlready` is 0 - the daemon start-up is a per-process act,
gated per process, using per-process scratch. Nothing in object 11 crosses a process boundary, and it
needs no cross-process lock `[OBS-RE]`.

**Owning ordinal: #413 `STARTLAZYWRITER`** `[OBS-RE]`. `STARTFSDDAEMONS` and `SPAWNEDTHREAD` are not
exports; export #413 (a call-gate entry to obj3 `0xF380`) is a 12-byte stub that loads DOSCALL1's data selector
and near-calls `STARTFSDDAEMONS`. PM's `START16SYSTEMEXECUTABLES` -> `STARTHPFSLAZY` resolves #413 at run time and
calls it. The APIs they call are #34/#145/#141/#142/#143/#11/#183/#5. *(Corrected 2026-11-06: this line read
"Owning ordinal: none ... reached from DOSCALL1's own init path"; the entry table says otherwise.)*

**What the fields are** `[DOC-IBM]` + `[OBS-RE]`. With the 16-bit `DosFSCtl` prototype (DDK COMBASE
`bsedos16.h`: `pData, USHORT cbData, pcbData, pParms, USHORT cbParms, pcbParms, USHORT usFunCode, PSZ pszRoute,
HFILE hf, USHORT usRouteMethod, ULONG ulReserved` = 34 bytes) every argument is named. +0x00..+0x0B is one
`FSDTHREAD` record (`usFunc`, `usStackSize`, `ulPriorityClass`, `lPriorityLevel`; Toolkit `bsedos.h`).
+0x0C..+0x2F is a `ROUTENAMEBUF` (`hRouteHandle` cursor, then `szRouteName`) filled by
`DosFSCtl(..., usFunCode = 3 FSCTL_GET_NEXT_ROUTE_NAME, pszRoute = NULL, usRouteMethod = 3 FSCTL_FSDNAME)`, which
the kernel answers itself (18 at the end of the list, 122 for a name too long). The name at +0x10 is the FSD
name passed as `pszRoute` to `FSCTL_DAEMON_QUERY` (4), whose answer is a local `FSDDAEMON` (198 bytes,
`usMoreFlag`/`usCallInstance` honoured), and, by each daemon thread, to its own `DosFSCtl(usFunc, no buffers,
FSD-name routed)`, after which the thread ends with `DosExit(EXIT_THREAD, rc)`. Each daemon is therefore a
thread of the process that called #413, living inside the FSD's `FS_FSCTL`.

**Not established (object 11):** the starting ring of a `SPAWNEDTHREAD` thread (the routine ORs RPL bit 0
into the loader's selector for its IOPL code object). *(Corrected 2026-11-06: this paragraph listed the 16-bit
`DosFSCtl` frame, the name at +0x10 and the cursor's function code as not established; the 16-bit prototype in
the DDK COMBASE `bsedos16.h` closes all three, above.)*

---

## The lock-free and single-filler claims, across these objects

- Object 6 has **two** lock-free `xchg` structures (`pThunkStacks` +0x16AC; the thunk-block head
  +0x11C0/+0x11C4), not one `[OBS-RE]`.
- The RAS/trace `PRE*`/`POST*` labels are inside their ordinal's body in both the 16-bit message ordinals
  (#383/#384/#385/#389) and the 32-bit `DOS32SUB*MEM` hooks (#344-#347) `[OBS-RE]`.
- Lock-order links built from caller lists rather than from read call sites remain `[INF]` (object 5's
  "session-manager locks -> IPCQUEUE.SEM" and "switch path -> `savelocksem`").

## See also

- `session-manager.md` - the session manager whose state fills most of objects 5 and 8.
- `video-stack.md` - BVS and the video handlers that use objects 7 and 8.
- `ipc-synchronization.md` - the queue and semaphore APIs behind objects 5, 6, 9 and 10.
- `module-dll.md`, `executable-formats.md` - how a DLL's objects, entry table and imports work.
