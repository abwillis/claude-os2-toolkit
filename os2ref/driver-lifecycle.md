# OS/2 Driver Lifecycle - load, initialise, register, call, service, shut down

How the OS/2 kernel brings a device driver from a file name to a working device and back down
again: which component loads it and when, what it does to the image, the INIT exchange, how the
device joins the kernel's device list, how a program's request reaches the Strategy routine, how
DevHlp, interrupts, timers and context hooks are dispatched, and what a driver is sent at
shutdown. It is the **lifecycle** companion to `drivers.md`, which holds the **ABIs** (device
header fields, request-packet layouts, Strategy commands, the `FS_*`/`FSH_*` interface); those are
linked, not repeated.

**Build.** Shape and order are read from the **Warp Server for e-Business SMP kernel, revision
14.104a** (retail, with its `.sym`), the last IBM kernel. Several facts were first read in 14.089
and re-checked in 14.104a; where a write-up describes an older build that is said. Addresses are
facts about one build; what carries over is the sequence and the IBM names.

**Provenance.** Tags as defined in `README.md`. RE write-ups behind [OBS-RE] claims are unpublished notes.
IBM pages are cited as `PDD/nnnnn` (*Physical Device Driver Reference*, DDK HTML `REF/PDD`),
`STORAGE/nnnnn` (*Storage Device Driver Reference*) and by DDK/Toolkit file name.

---

## 0. The three contexts, and where each one runs

IBM defines exactly three contexts a physical device driver (PDD) runs in (PDD/00018) [DOC-IBM]:

| context | what runs | on which thread | source |
|---|---|---|---|
| **INIT** | the INIT command of a `DEVICE=` driver | the System Initialization Process's thread, **ring 3 with I/O privilege**; 22 listed `Dos*` calls allowed | PDD/00030, 00031 [DOC-IBM] |
| | the INIT of a `BASEDEV=` driver (and of the loader's implicit base drivers) | ring 0, inside the kernel's own boot code, no ring-3 process yet | section 1.2 [OBS-RE] |
| **Kernel** ("task time") | Strategy for a program's request | **the requesting program's own thread** - *"it will execute as a thread within a process"* | PDD/00018 [DOC-IBM]; section 4 [OBS-RE] |
| | context hooks | the next thread to leave the kernel, or the context-hook daemon | section 6.3 [OBS-RE] |
| **Interrupt** | hardware interrupt handlers, timer handlers | *"the thread of execution does not belong to a process"* | PDD/00018 [DOC-IBM] |

Which DevHlp services each context may call is one IBM table, "DevHlp Services and Device
Contexts" (PDD/00208) [DOC-IBM]; the kernel enforces it per call (section 5).

---

## 1. Boot: who loads drivers, in what order

The whole sequence, in execution order. Each step is expanded below.

| # | step | context | source |
|---|---|---|---|
| 1 | CONFIG.SYS is read and parsed into per-category lists, **before any driver loads** | ring 0 | unpublished notes (`syiInitDataStructures` step 10) [OBS-RE] |
| 2 | the kernel-resident `OEMHLP$` device is initialised, first of all devices | ring 0 | same, `syiInitOS2Components` step 2 [OBS-RE] |
| 3 | `PSD=` drivers are loaded and installed; secondary processors are started | ring 0 | section 7.5 |
| 4 | **the loader's implicit base-driver list** is loaded and initialised | ring 0 | section 1.2 |
| 5 | `BASEDEV=` drivers, reordered by extension, are loaded and initialised | ring 0 | section 1.2 |
| 6 | the boot (mini-)file system is retired; the file-system layer starts; the boot volume is attached | ring 0 | unpublished notes [OBS-RE] |
| 7 | system daemon threads are created (including the context-hook daemon); storage adapter drivers are told "complete init" | ring 0 | unpublished notes, `syiReinitAdds` [OBS-RE] |
| 8 | the **System Initialization Process** starts at ring 3; `DOSCALL1.DLL` is loaded into it | ring 3 | section 1.3 |
| 9 | `DEVICE=` and `IFS=` lines are installed, **interleaved, in CONFIG.SYS order** | ring 3 (INIT), ring 0 (linkage) | section 1.3 |
| 10 | INIT COMPLETE (1Fh) to every driver that asked for it | ring 0, via SICG | section 3.5 |
| 11 | late device init: swapper, `CLOCK$` re-INIT, clock rate | ring 0, via SICG | section 1.3 |
| 12 | DOS emulation starts; **virtual device drivers** load | ring 0, via SICG | section 7.3 |
| 13 | `RUN=`/`CALL=`, `PROTSHELL=`; end of initialisation (init-only DevHlps disabled) | ring 3 -> ring 0 | section 1.3, section 5 |

### 1.1 Before anything is loaded

- **`OEMHLP$` is part of the kernel image.** The kernel's static device chain is `NUL` -> `CON` ->
  `OEMHLP$`, and these are the only headers in the image [OBS-RE] (unpublished notes). `OEMHLP$` is initialised through the same
  base-driver INIT routine as a `BASEDEV=` driver, before the PSDs, and boot stops if it returns no
  end offsets [OBS-RE] (unpublished notes, `syiInitOS2Components`
  step 2).
- **Early module loads read through the boot file system.** Before the PSDs load, the kernel hands
  the loader the boot file system's routine table; it takes it back after the base drivers, then
  retires the boot file system [OBS-RE] (same, steps 4 and 8). So PSDs and every base driver are
  read by the OS2LDR-supplied micro/mini-FSD, never by an installable file system.

### 1.2 Base drivers: the implicit list, then `BASEDEV=`, at ring 0 with no process

IBM: *"During system initialization, base device drivers are preloaded with the operating
system. Installable device drivers are loaded during CONFIG.SYS processing"* (PDD/00030)
[DOC-IBM].

The kernel's base-driver orchestrator runs four steps [OBS-RE] (unpublished notes, 14.089):

1. **Per-process file setup** for the boot process (`syiInitInt13Thread`: 20 handles; despite the
   name it creates no thread in 14.104a) [OBS-RE] (unpublished notes).
2. **The implicit base-driver list** (`InitBaseList`). The kernel calls the OS2LDR helper
   `DosHlpBaseDDList` (a slot of IBM's DosHlp table, DDK `doshlp.inc`) [DOC-IBM] with **`AL` = 1 if
   ABIOS is present, else 0**. It gets back **two** lists: `ES:DI` -> the base *physical* drivers,
   walked here, and `ES:SI` -> the **base virtual device drivers**, which the kernel stores in the
   DOSINITDATA word the `.sym` names **`pszzBaseVDDs`** and hands to DOS-emulation start much later
   (section 7.3) [OBS-RE] (unpublished notes; decompile
   unpublished notes, the store right after the DosHlp call; `ES:SI` as the register is a
   decompile reading). Each PDD name is loaded and initialised in list order, **ahead of every
   `BASEDEV=` line and outside the extension ordering**; entries are a NUL-terminated name plus one
   flag byte, which the walk skips. **An INIT failure here stops the boot** (`SYIAbort`) [OBS-RE].
   The lists held in the loader are `RESOURCE.SYS`, `CLOCK01/02.SYS`, `SCREEN01/02.SYS`,
   `KBDBASE.SYS` (`video-stack.md` section 1.2) [OBS-RE]. IBM names the `01`/`02` pairs as the drivers for
   **Family 1 (AT) and Family 2 (PS/2)** machines (*Using Your DDK*, "Clock Device Driver (Family 1
   and Family 2)", DDK `REF/USEDDK/00038`; `PRINT01` ISA/EISA, `PRINT02` Micro Channel, `INOUT/00397`)
   [DOC-IBM], and the `02` sources are the ABIOS ones (`clock02.asm`, `screen02.asm`). IBM's own
   names for the two `AL` values are **`BASEDD_AT EQU 0`** and **`BASEDD_PS2 EQU 1`** (DDK
   `base/inc/doshlp.inc:201-202`) [DOC-IBM]. The loader's handler confirms the mapping [OBS-RE]
   (read in the Warp 4.5 SMP debug `OS2LDR`, the 14.104a build: `BaseDDList` at loader offset
   `2f3a`, called through the discardable DosHlp selector `0110`, 43 bytes, no hardware access):
   - `AL = 0` (`BASEDD_AT`): `ES:DI` -> the AT list `RESOURCE.SYS`, `CLOCK01.SYS`, `SCREEN01.SYS`,
     `KBDBASE.SYS`;
   - `AL = 1` (`BASEDD_PS2`): `ES:DI` -> the PS/2 list `RESOURCE.SYS`, `CLOCK02.SYS`,
     `SCREEN02.SYS`, `KBDBASE.SYS`, and the handler also sets `CFG_ABIOS_PRESENT` (08h) in the
     loader's configuration flags word and stores `0FFFFh` in a second loader word whose meaning
     was not established;
   - any other `AL`: `DI` is returned unchanged;
   - `ES:SI` -> the same third list whatever `AL` is: `vbios.sys vdma.sys vpic.sys vflpy.sys
     vtimer.sys vlpt.sys vkbd.sys vdsk.sys vcmos.sys vnpx.sys`, plain names, double-NUL
     terminated, matching `doshlp.inc`'s `IPL_DEPENDENT`/`IPL_INDEPEND` split (the flag byte on
     every entry of the two physical lists is `1`, `IPL_DEPENDENT`).
   The lists are static strings in the loader image; nothing fills them at run time.
3. **`OrderBASEDEVs`** reorders the CONFIG.SYS `BASEDEV=` list by file extension, walking the
   kernel's priority string **`.SNP.SYS.BID.VSD.TSD.ADD.I13.FLT.DMD`** (case-insensitive compare of
   the extension); entries with an unknown extension are reported by message [OBS-RE] (unpublished notes). Within one extension,
   CONFIG.SYS order is kept [INF: the relink moves each match in list order].
   **With the Resource Manager present this order is only its input** [OBS-RE] (the 14.104a
   kernel and `RESOURCE.SYS` v10.058; unpublished notes): once, before any `BASEDEV=` loads,
   the kernel sends `RESMGR$` category-80h function **20h** with pointers to its `BASEDEV=` and
   `DEVICE=` lists; the Resource Manager builds its own configuration list from them. If it
   accepts, the kernel **empties its own `BASEDEV=` list** and loads, in order, whatever function
   **21h** returns, one entry per call (each returned handle seeds the next call); an entry that
   carries a kernel list entry reuses it, others get a new one. At its own INIT, before 20h,
   `RESOURCE.SYS` puts snooper drivers at the head of that list (`ISAPNP.SNP`, the entries of
   its `Snoop.lst`, `PNP.SYS`, governed by its `/SL:` option and remembered in its
   `previous.dat`; `hardware-detection.md` section 2, section 4), so they load before every CONFIG.SYS `BASEDEV=`. So with the Resource Manager
   loaded, it decides `BASEDEV=` order and membership; without a device named `RESMGR$` the
   kernel keeps its own list.
4. **`InitBASEDEVs`**: for each entry, load, build the command line, INIT each header; **an INIT
   failure is reported and boot continues** [OBS-RE] (unpublished notes).

A base driver's INIT runs **at ring 0, inside the kernel's boot thread** - there is no ring-3
process yet. The packet is BASEDEVINIT (1Bh), not INIT (0h) (section 2.4). The boot thread's process is nonetheless
the System Initialization Process's: before any PSD or base driver loads, the kernel records the
current PTDA as SYSINIT's (`_SysInitPTDA = _pPTDACur`), and the base drivers then load on that same
thread [OBS-RE] (unpublished notes steps 5
and 8). So during a base driver's INIT the current process is pid 1's [INF from those lines], while
the local InfoSeg has not yet been seeded (the kernel seeds `_Lis2` after `syiInitOS2Components`
returns) [OBS-RE]; what a base driver reads from it then is not established.

### 1.3 The System Initialization Process (SYSINIT)

After the base drivers, the boot thread becomes the page-ager, and a clone of it drops to **ring
3** as the System Initialization Process, which runs `h_syiProcess` [OBS-RE] (unpublished notes
`syiInitProcess`; unpublished notes). Its order, as far as drivers are
concerned [OBS-RE] (unpublished notes; corrects unpublished notes):

1. Open `CON` as handles 0/1/2; add `SET=` variables to the environment.
2. Check the boot file system (fatal if unreadable); `CODEPAGE=`/`COUNTRY=`/`DEVINFO=` setup.
3. **Load `DOSCALL1.DLL`** into this process (`syiGetLoadableEntries`, an ordinary ring-3
   `DosLoadModule`) - **before any `DEVICE=`** [OBS-RE] (unpublished notes). So a `DEVICE=` driver's INIT-time
   `Dos*` calls are DOSCALL1's code running in SYSINIT.
4. Kernel DBCS/country tables; codepage activation; the handle limit raised to 100 for driver
   installation; JIT-debugger registration.
5. **`syiInstallDeviceDrivers`** - every `DEVICE=` and `IFS=` line, **one list, in CONFIG.SYS
   order** (section 2). `DEVICE=` and `IFS=` are not two phases. Before each: the Alt-F2/Alt-F4 boot
   options may display the line or pause for a key that skips it [OBS-RE] (unpublished notes). At the end: a locked-system check, a fatal check that a
   mini-FSD boot found its full IFS, and **SICG function 0**, which rescans the disks and sends
   INIT COMPLETE (section 3.5).
6. FAT auto-check; **late device init** (SICG function 0Eh): start the swapper (`SWAPPATH=`), find
   `CLOCK$` and send it a second INIT (command 0h), set the timer rate from `CLOCKSCALE=` [OBS-RE]
   (unpublished notes). Handle limit back to 20.
7. **DOS emulation and virtual device drivers** (section 7.3).
8. `RUN=`/`CALL=`, `PROTSHELL=`, deferred `RUN=` of PM programs.
9. **End of initialisation** (SICG function 2): the init call gates and init code are freed, the
   parsed CONFIG.SYS is freed, **INIT-only DevHlps are disabled** (section 5), the PSD enters advanced
   interrupt mode; init does not finish before the session manager has initialised [OBS-RE]
   (unpublished notes).

**SICG.** Ring-3 SYSINIT does everything an application could not - linking headers, resizing
driver segments, creating drive parameter blocks, adding file systems - through one private call
gate, the **System-Init Call Gate**, with a packet whose first word is a function number (`0`-`1Bh`).
Ring-0 init code calls the same routines directly. The gate is freed at the end of init [OBS-RE]
(unpublished notes, function table). The function numbers are internal; they are named here only so
the steps can be told apart.

---

## 2. Loading one driver module

### 2.1 The loader, and the load type

Every driver kind is loaded by the ordinary module loader - the worker behind `DosLoadModule` -
with a **load type** that changes how the module is laid out [OBS-RE] (unpublished notes):

| load type | used for | set by |
|---|---|---|
| 2 | device driver: `DEVICE=` (from ring 3), `BASEDEV=` and the implicit list (from ring 0) | a one-shot byte the loader reads and clears |
| 3 | `IFS=` and the boot mini-FSD; the `FSHELPER` pseudo-module is linked for the load so `FSH_*` imports resolve | same |
| 4 | virtual device driver | the VDD loader (section 7.3) |
| 5 | PSD test load (`DosTestPSD`) | a thread flag |

A type-2 load marks the module **`DEVDRVMOD`** (a type-3 load **`FSDMOD`**, type 4 **`VDDMOD`**)
in its MTE (names from the IBM Debugging Handbook's MTE flag table; values read in the binary)
[OBS-RE] (unpublished notes). These modules get a **kernel reference** of their
own, so the garbage collector never frees them as unreferenced [OBS-RE] (unpublished notes).

**Which `DEVICE=` lines are drivers at all.** Before loading, SYSINIT classifies each `DEVICE=`
file with `DosQueryAppType`: a DOS driver (or a non-OS/2 file) is moved to the DOS-driver list for
the DOS emulator; a 32-bit **VDD** is moved to the VDD list (section 7.3); a 16-bit PDD or a 32-bit
`PHYSDRV` is installed; anything else is reported and skipped [OBS-RE] (unpublished notes
`syiInstallDeviceDrivers`).

### 2.2 Where the image lives

- **IBM's model.** A PDD is a 16:16 module whose first segment is data and second is code. *"These
  two segments are fixed in memory and (by default) will be the only two segments kept in the
  system after device driver initialization"*; other segments are init-only unless marked
  permanent, and a permanent one *"is assumed to be movable and swappable"*. The device header is
  the first item of the first data segment; there is no stack segment - the system provides 8 KB
  (PDD/00019, 00020) [DOC-IBM].
- **The kernel.** Each 16-bit segment of a driver is a **kernel-heap block with a GDT selector**
  (`_ldrAllocSegment` -> `_ldrAllocDD` -> `_SELAllocKHB`). For a `DEVDRVMOD` module, segments 1 and 2
  come from the **resident** heaps (handles 1/2); a later segment comes from heaps 3/4, which are the
  **swappable** heaps, **only if its ring bits mark it IOPL** - IBM's "permanent" segment [OBS-RE]
  (unpublished notes;
  decompile `_ldrExpandSegment`, which gives a type-2 load's segment the GDT flag only for index below 2 or IOPL
  ring bits) - the residency IBM's page describes. **Any other later segment is init-only**: it takes the ordinary
  virtual-memory path, gets an LDT selector, and a writable one is owned by the installing process; after a
  successful INIT the kernel frees every LDT selector the module has (section 2.6) [OBS-RE] (decompiles
  `_ldrAllocSegment`, `_LDRINITSetGDT_DPL0`). The loader overrides the driver's own shared/nonshared bits for a
  type-2 load (it clears them, then marks every code and read-only data segment shared), so only the ring, code/data
  and read-only bits of a driver's segment flags take effect [OBS-RE] (`_ldrExpandSegment`). A GDT
  selector resolves the same in every process, so the driver is global [INF, from GDT + one kernel
  heap].
- **Ring during INIT.** Driver and FSD segments are created at ring 3 and preloaded, so a `DEVICE=`
  INIT running at ring 3 can execute and address them [OBS-RE] (unpublished notes). After INIT they are lowered to ring 0 (section 2.6).
- **A 32-bit (LX) driver's** objects are all allocated resident in the system arena, and **every
  object gets a 16-bit, byte-granular GDT selector** (base = the object's linear address, limit =
  size - 1) whatever its 32-bit (`OBJBIGDEF`) flag: a code object a DPL-0 **conforming** code
  descriptor (so a ring-3 `DEVICE=` INIT can call it), a data object a DPL-3 data descriptor
  [OBS-RE] (unpublished notes). The INIT path takes the header from object
  1 and the code selector from object 2, and requires object 1 writable and object 2 not (section 2.3).
  32-bit code is not run through its object's selector; the driver reaches it by a far jump to the
  kernel's flat code selector (section 7.2). IBM's own shipped 32-bit driver shows the arrangement on the driver
  side [DOC-IBM] (DDK `base32/src/basedd/dasd/os2dasd`: `makefile`'s generated `.def`,
  `dmheader.asm`, `dmthunk.asm`, unpublished notes): the module is linked `PHYSICAL DEVICE` (LX); the
  first data segment is `DDHeader`, holding an ordinary 16:16 header chain; data segments are
  `MIXED1632` and code segments `ALIAS`, so each has a 16-bit view; **the Strategy and IDC entries
  in the header are 16-bit routines** in a 16-bit code segment; the 32-bit code is reached from them
  through `KernThunkStackTo32`/`KernThunkStackTo16`, and the 32-bit side brackets any call back into
  16-bit driver code with `KernSerialize16BitDD`/`KernUnserialize16BitDD`. So such a driver meets
  the kernel through the same 16-bit header ABI as a 16-bit PDD (section 2.3, section 4.3).

### 2.3 The kernel fills in the header before INIT

IBM marks header bytes `+0x12..+0x19` "Reserved" (PDD/00020); the DDK's `devhdr.h` names them
`SDevProtCS`, `SDevProtDS`, `SDevRealCS`, `SDevRealDS` [DOC-IBM]. **The kernel's install code
writes them**, on both the ring-3 `DEVICE=` path and the ring-0 base path, after the module is
loaded and before the first INIT [OBS-RE] (unpublished notes). For every
header in the file's `SDevNext` chain (ending at offset `0xFFFF`):

- `SDevProtCS` <- the selector of the module's **second** segment (code);
- `SDevProtDS` <- the selector of the **first** segment (data, holding the header);
- `SDevRealCS` = `SDevRealDS` <- 0;
- the selector half of `SDevNext` <- the data selector.

These are the fields the kernel later calls through: Strategy is far-called at
`SDevProtCS:SDevStrat`, and `SetIRQ`, `SetTimer`/`TickCount` and `AllocateCtxHook` take the
handler's CS and DS from them [OBS-RE] (section 4.3, section 6).

**The object rule.** "First segment" and "second segment" are the module's objects 1 and 2, and
the install code checks one property of each [OBS-RE] (unpublished notes bytes):

- the module must have at least two objects;
- **object 1 must be writable** - for an LX module the `OBJWRITE` object flag, for an NE module
  the data-segment bit;
- **object 2 must not be**.

Nothing else is tested: not that object 2 is executable, not 16- versus 32-bit, not that the header
chain starts at offset 0 of object 1 (the kernel simply takes `object-1 selector : 0` as the first
header). Because every object of a driver gets a 16-bit selector (section 2.2), `SDevProtCS` and
`SDevProtDS` are 16-bit selectors by construction, so the Strategy and IDC entries the header names
must be 16-bit code in object 2 [INF]. A file that breaks the rule is refused before INIT: a
`DEVICE=` or `BASEDEV=` file gets a message and is unloaded, and a file on the loader's implicit
base list stops the boot [OBS-RE] (same; unpublished notes).

Every LX `PHYSICAL DEVICE` module shipped with Warp 4.5 / WSeB (37 files, including `OS2DASD.DMD`
and `OS2LVM.DMD`) has object 1 = readable, writable, 16:16-aliased data and object 2 = readable,
executable, 16:16-aliased code, with any 32-bit objects after them [OBS-RE, object tables read].
IBM's `OS2DASD` build produces that order from its `.def` (`DDHeader` and the `MIXED1632` data
segments first, the `ALIAS` code segments after) and `dmsegs.asm` (`DGROUP = DDHeader, CONST, _BSS,
_DATA`; `StaticGroup = Code, _TEXT, RMCode`) [DOC-IBM] (DDK `base32/src/basedd/dasd/os2dasd`). An
IFS is not under this rule: its entry points are resolved by name (section 7.2).

### 2.4 The INIT exchange

| | `DEVICE=` | `BASEDEV=` / implicit list |
|---|---|---|
| command | **0h INIT** (PDD/00103-00107) | **1Bh BASEDEVINIT** (PDD/00179-00182) |
| packet length | 23 (`0x17`) | **25** (`0x19`); byte `+0x18` = `InitSysiData`, written as `0x48` (below) |
| who calls Strategy | SYSINIT's own ring-3 code, **directly** (`call far` to the header's Strategy, ES:BX -> packet) | the kernel's ordinary Strategy-call routine (section 4.3), at ring 0 |
| DevHlp pointer in the packet | a far pointer through a **DPL-3 call gate** to the DevHlp router | the router's **direct** ring-0 address |
| command line (`Pointer_2`) | the file name as written, then the arguments | built from the `BASEDEV=` line |
| first drive number (`Data_2`) | next free drive | next free drive |

[DOC-IBM] for the commands and fields; [OBS-RE] for the two routes and pointers
(unpublished notes, gate `0x1510`).

For a 32-bit (LX) driver the INIT is the same exchange: the kernel calls the header's 16-bit
Strategy entry through object 2's selector (section 2.3), and the driver thunks into its own 32-bit code
if it wants to (section 2.2) [OBS-RE + INF]. A ring-3 `DEVICE=` INIT reaches object 2 because its code
descriptor is DPL-0 conforming until the end of INIT (section 2.6) [OBS-RE]
(unpublished notes).

**The two extra bytes.** The PDD Reference's 1Bh request block stops at `Data_2` (23 bytes), but
the DDK's `devsym.inc` gives the INIT packet two lengths: `LENInit` (10 data bytes, "non-resident
drivers") and `LENInitRes = LENInit + 2` ("resident drivers"), the latter adding
**`InitSysiData equ byte ptr PktData+11` - "SysInit's DOSALIAS selector", "for resident drivers
only"** [DOC-IBM] (DDK `base/inc/devsym.inc`; `PktHeadSize` 13, so `PktData+11` = `+0x18` and
13 + 12 = 25). So the 25-byte base form is IBM's resident-driver INIT packet, and `+0x18` is that
field; the kernel writes `0x48` there [OBS-RE]. Every occurrence of the name `InitSysiData` in the
DDK is a definition - no shipped driver source uses it [DOC-IBM, by search].

IBM's 1Bh page gives per-case init arguments for a base driver - printer buffer sizes for a
parallel-port driver, a code-page count for the STDIN device, a disk/machine configuration table
for a block or ADD-strategy driver, and the command line for any other (PDD/00182) [DOC-IBM].
What the kernel puts at `+0x12` (`InitArgs`, a far pointer) [OBS-RE] (unpublished notes SMP):

- **Which case.** A block device always gets case 3. A character device whose level is exactly 3
  (`attr & 0380h == 0180h`) runs case 1 if capability bit 2 is set, then case 3 if capability
  bit 3 is set; then any character device with attribute bit 0 (STDIN) runs case 2. The last one
  to run sets the pointer; if none runs, case 4. The routines that ran earlier keep their side
  effects.
- **Case 4** points at the first character of the command line itself, not at an offset word as
  the PDD page's table suggests. IBM's `IBMKBD.SYS` reads it that way (unpublished notes) [DOC-IBM].
- **Case 1** points at three printer buffer-size words (`PRINTMONBUFSIZE=`, 134 each by default)
  followed by the command line inline (`prtinit.inc` `PRT_Parm_List`) [DOC-IBM].
- **Case 3** points at a five-word list: an obsolete cache list (all zero), the disk configuration
  chain (13-byte packed entries, one per BIOS drive), the 16 real-mode IRQ vectors as found at
  boot, the command line's offset, and the machine configuration table. Every offset in it shares
  the pointer's selector (`dskinit.h`) [DOC-IBM].
- **The command line** is the file name as written on the `BASEDEV=` line, then its arguments with
  their delimiter.

**What the driver returns** (PDD/00106) [DOC-IBM]: `Data_1` = number of units (block devices; 0
for character), `Pointer_1` = **end-of-code and end-of-data offsets**, `Pointer_2` = BPB array
(block devices), status `0100h`. Failure: status `810Ch`, or **`8115h`** - the kernel treats status
code `15h` as a **quiet** failure and shows no message [OBS-RE] (unpublished notes).

**When the kernel counts an INIT as successful** [OBS-RE]: status error bit clear, **and** the
end offsets not both 0, **and** for a `DEVICE=` block device a non-zero unit count
(unpublished notes). On the base path, either end offset being 0 counts as failure
(`BaseDevInit`, unpublished notes).

**INIT-time services.** A `DEVICE=` driver may call 22 `Dos*` functions - `DosOpen`, `DosRead`,
`DosWrite`, `DosDevIOCtl`, `DosGetMessage`, `DosPutMessage`, `DosSMRegisterDD`, ... - and must not
call `DosExit` (PDD/00031) [DOC-IBM]; they run as DOSCALL1 code in SYSINIT (section 1.3). A base driver,
at ring 0 with no process, has only DevHlp [INF from section 1.2].

### 2.5 Several devices in one file

One file can hold a chain of headers, and IBM states the rules per header: a driver "can fail
initialization on a subset of the headers", "the system initialization process remembers the last
nonzero size code and data segment offsets", a device that fails "will not receive any future
request packets", and the driver "remains loaded" if at least one header passes (PDD/00106 for 0h,
PDD/00182 for 1Bh) [DOC-IBM]. The kernel honours these on the `DEVICE=` path only.

**`DEVICE=`.** Each header gets its own INIT in chain order. A header is named and linked into the
system chain **only after its own INIT succeeded**, and only a successful INIT's end offsets are
kept for the shrink; **the module is kept if at least one header succeeded** [OBS-RE]
(unpublished notes, `syiInitializeDeviceDriver`; unpublished notes, 14.089). A failed header is simply never linked, which is
how it receives no further packets.

**`BASEDEV=`** [OBS-RE] (unpublished notes bytes):
- **Keep or free is decided by the last header alone.** After each header's INIT the kernel stores
  the two end-offset words its INIT routine returns, unconditionally, and after the loop keeps the
  file only if both are non-zero. That routine returns the driver's end offsets on success, **0:0 on
  a failure it reports**, and - for a quiet failure (status code `15h`) - the end offsets **as the
  driver left them**. So a file whose last header fails noisily is freed even if earlier headers
  passed; a file whose last header passes is kept whatever the others returned; and the shrink
  (section 2.6) uses the last header's offsets, not the last non-zero ones.
- **A kept file is linked whole.** The link walks the file's own `SDevNext` chain to `0xFFFF` and
  splices all of it after `OEMHLP$`, with no per-header test.
- **Nothing marks a failed header.** The failure path writes nothing to the header. The
  character-device name table is later built by walking the whole chain and adding every header with
  the character bit, testing nothing else, and the Strategy-call routine reads no per-header state
  either. So a failed **character** header in a kept file is named, openable and callable like any
  other: **the driver must refuse requests to it itself** [OBS-RE for the routines read; INF that a
  request actually arrives - not observed]. A failed **block** header gets no unit count and no
  drive from the kernel, so no drive letter reaches it [OBS-RE].
- A driver that relies on IBM's sentence therefore needs both: fail with zero end offsets, and keep
  its own per-header "initialised" flag that its Strategy routine checks [INF from the above].

**Implicit base list.** Any header's failure stops the boot, a quiet `15h` failure included
[OBS-RE] (section 1.2; unpublished notes).

### 2.6 After INIT: shrink, lower the privilege

On success the kernel **resizes the first code and data segments to the returned end offsets**: a
non-zero end `e` reallocates the segment to `e+1` bytes (the offset of the last byte kept); an end
of 0 leaves that segment alone; a failed reallocation panics [OBS-RE] (unpublished notes). It then **lowers every GDT selector of the module to DPL 0**
(`_LDRINITSetGDT_DPL0`) and frees any LDT selector the module had [OBS-RE] (same; and the
module-load notes in unpublished notes). An IFS gets the DPL change alone
(section 7.2). Memory a driver allocated with `DevHlp_VMAlloc` during INIT had ring-3 access for the INIT,
which is removed at the end of driver initialisation [OBS-RE] (unpublished notes).

**The segment IOPL flag is a keep marker, not a ring** [DOC-IBM PDD/00019, 00028; OBS-RE
unpublished notes]. For a physical device driver `_ldrExpandSegment` gives a GDT selector to
the first two segments and to any later segment whose flags carry the IOPL bit ((flags & 0C00h) == 0800h); for driver
and IFS segments it then forces the descriptor's ring field to 3 (`or 0C40h` / `and 0FDDFh`), so the IOPL bit does not
survive as a ring-2 segment. `_ldrAllocDD` puts data segments 1-2 and code segments 1-2 in resident heaps and later
kept segments in swappable ones; a later segment without the flag gets ordinary LDT memory and is freed after INIT
(`_LDRINITSetGDT_DPL0`, called from `sicgf5` after a kept `DEVICE=` INIT and from `sicgf8` for an IFS, masks each GDT
access byte with 9Bh - DPL 0, and the conforming/expand-down bit cleared - and frees the LDT selectors). The
`BASEDEV=` path was not traced to that call.

### 2.7 Failure handling

| what failed | `DEVICE=` | `BASEDEV=` | implicit base list | `IFS=` |
|---|---|---|---|---|
| file not found / bad format / no memory | message, continue | message, continue (a two-diskette boot first asks for the next diskette) | fatal | message, continue |
| INIT failed | every header failed: module unloaded (`_LDRFreeModule`), message unless quiet | the **last** header failed: module unloaded, message unless quiet (section 2.5) | any header: **fatal**, quiet or not | module unloaded, message |
| the boot volume's IFS on a mini-FSD boot | - | - | - | **fatal** |

[OBS-RE] (unpublished notes, `syiInstallFileSysDriver`,
`syiLoadDeviceFileSysDriver`; unpublished notes). This refines the 14.089
reading that every `IFS=` failure is fatal (unpublished notes): only
the case where the boot volume would be left without a file system is.

---

## 3. Registration: how a device joins the system

### 3.1 The device chain

The kernel's device list is a singly linked chain of device headers through `SDevNext`, starting
at the resident `NUL` header. Where a new header goes depends on how it was loaded [OBS-RE]
(unpublished notes):

| driver | position | granularity |
|---|---|---|
| implicit base list, `BASEDEV=` | **immediately after `OEMHLP$`** | the whole file chain at once, after the last header's INIT; a later file goes in front of an earlier one |
| `DEVICE=` character device | **immediately after `CON`** | one header at a time, after its INIT succeeded |
| `DEVICE=` block device | **at the end of the chain** | one header at a time |

The link's selector half is taken from the header's own `SDevProtDS` (section 2.3).

### 3.2 Character devices: the name table

`DosOpen` does not walk the chain; it looks names up in a separate **character-device name table**
keyed by (class, name). At the end of base-driver loading the kernel walks the chain and enters
every character header; a `DEVICE=` character header is entered - **replacing** an existing entry
of the same name - once its INIT succeeds [OBS-RE] (unpublished notes, `sicgf11`). **Order:** the table is kept in order of entry - a new
name is appended after every existing entry (first fit over free space, and the only free space is
the tail until an entry is removed), and a replacement overwrites the existing entry where it
stands. At the base-driver pass a second header with an already-entered name is not entered, so the
earlier header in the chain keeps the name. Only file-system attach and detach (class 2) remove
entries, and a hole they leave can be refilled by a later entry out of order [OBS-RE]
(unpublished notes). The kernel also remembers the STDIN, STDOUT and CLOCK
devices of the base drivers (`ConInpDev`, `ConOutDev`, `BClock`) from their attribute bits
[OBS-RE] (unpublished notes).

### 3.3 Replacing a character device: DEINSTALL (14h)

IBM: *"the attribute field and name in its header are used to determine if the new device driver
is attempting to replace a driver already installed. If so, the previously installed device driver
is requested by the operating system to DEINSTALL the indicated device. If the installed device
driver refuses the DEINSTALL command, the new device driver is not allowed to initialize"*; a
driver that honours it releases its memory, IRQs, hooks and timers (PDD/00032, 00164-00167)
[DOC-IBM].

The kernel, **before** the new `DEVICE=` character header's INIT [OBS-RE]
(unpublished notes):
- searches the chain **after `CON`** for a header with the **identical attribute word** and the
  same 8-byte name; none -> the new header proceeds;
- found -> sends it **DEINSTALL (14h)**, a 13-byte packet; an error status -> the new header is not
  initialised (a message is shown); success -> the old header is unlinked;
- a new character header with the `NUL` attribute bit is always refused.

So `NUL` and `CON` themselves are never sent DEINSTALL; a `DEVICE=` driver named `CON` takes the
name only through the name table (section 3.2) [OBS-RE].

### 3.4 Block devices and drive letters

A block driver's INIT returns a unit count and a BPB per unit (PDD/00106) [DOC-IBM]. For each unit
the kernel takes the next free drive letter and builds a **drive parameter block**; it refuses a
driver whose units would run past `Z:`, and grows its sector buffers if a unit's sector size
exceeds the largest seen so far [OBS-RE] (unpublished notes). Base block
drivers get the same treatment in ring-0 code, and their unit count is written into the header's
name field (IBM: "Name or Units", PDD/00025) [OBS-RE] (unpublished notes).
`RESERVEDRIVELETTER=` sets where the `DEVICE=` drive letters start; a reserved letter already in
use is reported and ignored [OBS-RE] (unpublished notes step 2). Drive
letters of storage handled by adapter drivers come from the storage stack's device manager, which
is itself a base block driver (section 7.1).

**The kernel asks each unit for its letter** [OBS-RE] (14.104a; unpublished notes). Building a
unit's drive parameter block (`NewDPB`) calls `SetDriveLetter` (`000d:4829`), which sends the
driver Strategy-1 command **22h**, IBM's `CMDGetDriveAssign` (DDK `base/h/devcmd.h:59`) [DOC-IBM]:
a 12h-byte packet, unit = the DPB's unit, byte `+0Dh` = `FFh` on entry. The answer decides the
letter:
- a letter `0`-`25` (A-Z): used if free, otherwise the first free letter from `A:`;
- a value above 25: the DPB is freed and the unit gets **no drive** (how a hidden volume stays
  hidden);
- an error status (what every ordinary driver returns, not implementing 22h): the unit keeps the
  next consecutive letter - **unless LVM is active**, in which case it takes the first free
  letter from the `RESERVEDRIVELETTER=` start.

"LVM active" is a kernel flag (`_LVMActive`) set in `BaseDevInit` when a base block header has
capability bit `40h` (`DEV_LVM`, DDK `devhdr.h:63`) [DOC-IBM] **and** the dword at offset `28h` of
its header segment is `"LVM$"` - i.e. a block header at 0 followed by a character header named
`LVM$` at `1Eh` [OBS-RE]. The same `NewDPB` path serves `DEVICE=` block drivers (`sicgf7`) and the
run-time rediscover (section 7.1).

**Removable or fixed** [OBS-RE] (14.104a `SetDPBRemovFlag` `000d:47e0`; unpublished notes): before 22h, `NewDPB` sends command **0Fh** (13 bytes, the
unit); a status without the error bit and with the busy bit (200h) marks the DPB non-removable,
IBM's "busy = non-removable" convention (PDD/00146) [DOC-IBM]. A non-removable DPB is never sent
media check.

**The physical-disk table** [OBS-RE] (`BuildPhysDiskTable` `000e:672c`, `InitDeviceMgr`;
unpublished notes): built once, after the last `DEVICE=` line (SICG function 0),
and never rebuilt: command **16h** (`CMDPartfixeddisks`, 12h bytes) to every block header from
`CON` on; each driver's count adds that many entries, each naming the header and the disk's index
within the driver. Under the LVM pair the DASD manager answers 0 and the LVM manager the real count.

**`DosPhysicalDisk`** (DOSCALLS 287; 16-bit 129) works on that table [DOC-IBM cp1.txt; OBS-RE
`w_PhysicalDisk` `000d:76be`, `DevReturnHandle` `000d:78d3`, `DevReleaseHandle` `000d:79f7`]:
- function 1 (count): the data length must be 2 and the pointer non-null, the parameters null with
  length 0, else 87;
- function 2 (handle for disk `"N:"`): data length 2, parameter length 3 or 4, the string decimal
  digits with no leading zero, then `:` and NUL; N from 1 to the count, else 87; a disk another
  handle holds answers 5. The handle is an SFT entry marked as a physical disk (open mode `2090h`,
  not inherited) naming the table entry, whose in-use word holds the opener's pid;
- function 3 (release): parameter length 2, data null and 0; a handle that is not a physical-disk
  one answers 6, another process's 5, a locked disk 33;
- any other function: 1.

**Disk IOCtls without a file system** [OBS-RE] (`w_DevIOCtl` `000b:0e30`, `swioc_calldriver`
`000b:15ed`; 14.104a):
- Category 9 only on a physical-disk handle; any other handle answers 6, a character device's
  included. Functions 00h/01h (lock, unlock) and 6Ah (rediscover) are the kernel's own; the rest
  go to the table entry's driver as generic IOCtl 10h with the disk's index as the unit. Another
  category on a physical-disk handle answers 6.
- Category 8 with handle -1: a parameter maximum of exactly 1 answers 15. Functions 20h, 46h, 5Dh,
  66h-69h, 43h (command byte 1, else 87) and 63h (command byte 0, else 87) go to the driver of the
  drive named in parameter byte 1 (0 = A:), with that drive's DPB unit and SFN `FFFFh`; a remote
  drive answers 50. 40h, 4Fh and 6Fh first query 63h themselves; 6Ah has its own handler; any
  other function is an invalid handle.
- Category 8 on a direct-access (DASD) handle goes through the file system that mounted the volume
  (`FSD_OpenCreate` makes such handles; unpublished notes).

### 3.5 Commands the kernel sends unprompted

| command | when | to whom | source |
|---|---|---|---|
| 1Bh BASEDEVINIT | boot, once per header | base drivers | section 2.4 |
| 0h INIT | boot, once per header; **and a second time to `CLOCK$`** during late init | `DEVICE=` drivers; `CLOCK$` | section 2.4; unpublished notes [OBS-RE] |
| 14h DEINSTALL | before a same-named character driver's INIT | the earlier driver | section 3.3 |
| 22h GET DRIVE ASSIGN (`CMDGetDriveAssign`) | each time a block unit's DPB is built: base and `DEVICE=` INIT, and run-time rediscover | the block driver owning the unit | section 3.4 |
| **1Fh INIT COMPLETE** | **once, after the last `DEVICE=`/`IFS=` line, before any VDD loads** | every header in the chain with function level 3 **and** capability bit 4 - base and `DEVICE=` alike | PDD/00194-00197 [DOC-IBM]; unpublished notes [OBS-RE] |
| 0Dh/0Eh OPEN/CLOSE | every open, dup, inherit and close of a handle | character devices with attribute bit 11 | section 4.2 |
| 1Ch SHUTDOWN | `DosShutdown` | level-2, and level-3 with capability bit 0 - among the **character** headers the walk reaches (section 8) | section 8 |
| IORB `IOCC_CONFIGURATION`/`IOCM_COMPLETE_INIT` | end of ring-0 init, before SYSINIT | every registered adapter driver | section 7.1 |

IBM's 1Fh text: *"all physical device drivers have been loaded and initialized. Virtual device
drivers have not been loaded ... The device driver can now establish links to other physical device
drivers"* (PDD/00197) [DOC-IBM] - matching where the kernel sends it.

**Resource Manager notifications.** Each base driver load is bracketed by notifications to the
Resource Manager, and SYSINIT forwards the same for `DEVICE=` drivers through SICG [OBS-RE]
(unpublished notes). The kernel delivers them as
a generic IOCtl of category 80h [OBS-RE: `h_RMNotifyWork` builds a 25-byte packet, command 10h,
category 80h]. On the base path the function codes are `40h` before the load, `42h` after a
successful INIT and `41h` after a failed one (after the module is freed) [OBS-RE]
(unpublished notes). IBM documents only functions `01h`-`03h` of category 80h
(`FUNC_RM_GET_NODEINFO`, `_ENUM_NODES`, `_ENUM_DRIVERS`: DDK `base/h/rmioctl.h`; PDD/02359)
[DOC-IBM]. What the kernel sends and what `RESOURCE.SYS` does with it [OBS-RE] (unpublished notes):
- **Target:** the kernel finds the device **by name**, `RESMGR$`, on the chain from `CON` -
  `RESOURCE.SYS`'s only header (character, attribute `8180h`). If none matches, the call does
  nothing and the kernel carries on (and keeps its own `BASEDEV=` list, section 1.2).
- **The packet:** a static 19h-byte generic IOCtl, command 10h, category 80h, function in `AL`;
  parameter = the caller's `ES:DI`, data = the caller's `DS:SI`.
- **Load notifications.** Base drivers: `40h` before the load, `41h` after a failure (after the
  module is freed), `42h` after the keep test once the headers are linked. `DEVICE=` drivers get
  the same three as **`60h`/`61h`/`62h`**, from ring 3 through SICG function 1Ah. The parameter is
  the driver's file name from its CONFIG.SYS entry; the data pointer is null. `RESOURCE.SYS`
  keeps one global driver state: `40h`/`60h` set a bit nothing tests; **`41h`/`61h` do nothing -
  nothing is recorded or released, so a failed driver must free what it claimed**; `42h`/`62h`
  clear the state if the driver registered itself with the Resource Manager during its load,
  otherwise create a placeholder driver node named by that file name ("Non-Resource manager
  aware [base] device driver", vendor "Unknown Vendor", version 1.1). Inferred, not observed: a
  Resource-Manager-aware driver that fails leaves the "registered" bit set, so the next unaware
  driver gets no node.
- **`20h`/`21h`:** the `BASEDEV=` hand-over in section 1.2.
- The kernel sends no other category-80h functions. `RESOURCE.SYS`'s dispatch also accepts `00h`
  (returns its ring-3 call gate) and `04h` (copies its whole heap to the data pointer, with no
  length or access check), and **refuses the documented `03h` `FUNC_RM_ENUM_DRIVERS` with
  `8103h`**.

---

### 3.6 Inter-driver calls: `AttachDD` [OBS-RE]

A driver finds another's entry with `DevHlp_AttachDD` (2Ah): DS:BX the 8-character name, DS:DI a
12-byte table (PDD/00231 [DOC-IBM]). The kernel's routine (SMP 14.104a `h_dh_AttachDD`) walks the
device chain from `CON`, discarding `CON`'s own compare, so neither `NUL` nor `CON` can be found. It
matches the name only. On a match it copies six header words into the table: **+08h, +16h, +18h,
+08h, +12h, +14h** (the IDC offset, `SDevRealCS`, `SDevRealDS`, the IDC offset again, `SDevProtCS`,
`SDevProtDS`) and clears the carry. **It tests neither the IDC attribute bit (14) nor a zero IDC
offset**, so the book's "carry set ... No IDC Entry Point" does not happen: a header without an IDC
entry is attached with zero words. The real-mode words matter: the Resource Manager publishes its
two entries in them (`hardware-detection.md` section 7.1). unpublished notes

A caller far-calls the table's protected-mode entry (word 4 : word 3); the callee's own convention
says what it takes. `OEMHLP$`'s IDC entry **is its Strategy routine**: the kernel copies one
OS2LDR boot-block word into both header words, and the protected-mode code and real-mode words get
its DOSHLP code selector, so the table is `{24DCh, 0100h, 0100h, 24DCh, 0100h, 0108h}` on the SMP
14.104a build. A caller passes ES:BX a request packet, IBM's own drivers a generic IOCtl
(unpublished notes), and the callee loads its own DS. unpublished notes

## 4. Task time: from a program's call to the Strategy routine

### 4.1 Name resolution

`DosOpen` decides "device or file" **before** canonicalising the name and before any file system
is asked, so a device name wins over a like-named file - IBM: *"DosOpen checks for a device name
before checking for a file name"* [DOC-IBM]. A registered name matches as the **last component of
any path** (`NUL`, `C:NUL`, `\DEV\NUL`, `C:\ANYDIR\NUL`), case-insensitively, with trailing blanks
and dots stripped; `NUL.TXT` is a file. `\DEV\` is required only for pseudo-character devices
attached with `DosFSAttach`. `PRN` is looked up as `LPT1`. A DOS-session process uses DOS's rules
(8 characters, extension dropped) [OBS-RE] (unpublished notes).
IBM's list of reserved names (`CLOCK$`, `COM1`-`COM4`, `CON`, `KBD$`, `LPT1`-`LPT3`, `MOUSE$`,
`NUL`, `POINTER$`, `PRN`, `SCREEN$`) names devices the base drivers *support*; most exist only when
their driver is loaded (same, section 4) [DOC-IBM] + [OBS-RE].

### 4.2 Open and close

The kernel sends **OPEN (0Dh)** and **CLOSE (0Eh)** only to a character device whose attribute word
has **bit 11** set. The 17-byte packet carries the handle's system file number and, on CLOSE, a
"last reference" flag; OPEN is sent for every open, every `DosDupHandle` and every handle inherited
at `DosExecPgm`, CLOSE for every close [OBS-RE] (unpublished notes; packet layout
from the DDK `devsym.inc` [DOC-IBM]).

### 4.3 The Strategy call (`DevIOCall`)

Open/close, read/write and IOCtl each have their own kernel front end and end in the same routine,
which runs **on the requesting thread** with no thread or address-space switch [OBS-RE]
(unpublished notes):

1. Save every register and the caller's fault-recovery state.
2. For **commands 3, 4, 8, 9, 0Ch, 18h, 19h, 1Ah** (IOCtl input, read, write, write-verify, IOCtl
   output, and the three no-cache variants) replace the packet's transfer address with a **physical**
   address, and put the virtual one back afterwards.
3. For 10h (generic IOCtl) set the length byte from the driver's function level: 25 below level 2,
   29 at level 2, and above level 2 29 only with capability bit 0 (unpublished notes).
4. Release the big kernel lock; **take the single lock for all 16-bit driver code** (section 6.5).
5. **Far-call `SDevProtCS:SDevStrat` with DS:SI = the device header and ES:BX = the packet.** So on
   entry DS is the driver's first data segment (where the header lives) - the part of the Strategy
   ABI that IBM's Strategy page (PDD/00100) does not state.
6. Release the driver lock. **If the status word's Done bit (0100h) is clear**, loop: under the
   scheduler spinlock re-test Done, then `DevWait` = **ProcBlock on the packet's address**, no
   timeout, not interruptible; the spinlock is handed to the sleep so a `DevDone` on another CPU
   between the test and the sleep is not lost.
7. Re-take the big kernel lock if step 4 released it.

**Completion.** The driver finishes later - typically in its interrupt handler - with **`DevDone`**,
which *"sets the done bit ... and issues the DevHlp_ProcRun for threads that are blocked in the kernel
waiting for the request packet"* (PDD/00235) [DOC-IBM]; in the kernel it sets `0100h` in the status
and wakes every thread blocked on the packet address [OBS-RE] (unpublished notes). Request packets come from a kernel pool, so they stay valid after Strategy
returns [OBS-RE] (unpublished notes: allocate / dispatch / free around the call).

**The caller's buffers.** IOCtl parameter and data pointers are the caller's own 16:16 addresses
(*"virtual addresses"*, PDD/00152) [DOC-IBM]; they resolve because the caller's process is current
during Strategy [INF from step 5's no-switch]. To use them later - at interrupt time - a driver
locks and translates them (`Lock`/`VMLock`, `VirtToPhys`) or maps them globally
(`VMProcessToGlobal`) [DOC-IBM]. Read/write transfer addresses already arrive physical (step 2;
PDD/00121 *"a locked 32-bit physical address"*) [DOC-IBM] + [OBS-RE].

### 4.3a Character READ and WRITE (`DosRead`/`DosWrite` on a device handle)

[OBS-RE] 14.104a SMP (unpublished notes; ), with [OBS] measurements on 14.104a
SMP under VirtualBox (2026-10-27, a test character driver logging every request):
- **Route.** 16-bit: `DOS_Read`/`DOS_Write` -> `ReadDev`/`WriteDev` -> `DevRWRaw` -> `DevIOCall2` -> Strategy. 32-bit:
  `DOS32IREAD` -> `FS32IREAD` -> `w_Big32IO` -> for a character device `f_w_BigOper16`, which calls the same 16-bit worker
  per piece. `ReadDev`/`WriteDev` divert first: the null device sends no request; console input (read) and console output
  (write) return 116 to DOSCALL1, which serves them through KBD/VIO.
- **No request for a zero count** (`DevRWRaw` tests the count before anything else): rc 0, count 0.
- **The pieces.** A transfer is cut at the end of the caller's 64 KB tile; a tile-aligned piece is F000h (then 1000h); a
  buffer at or above 1FFF0000h goes FFFFh at a time. [OBS]: a 70000-byte read at tile offset 8264 went as two requests,
  57272 and 12728; a tile-aligned one as F000h, 1000h and the rest.
- **The lock.** Each piece is locked, never copied, and sent as **one request per physically contiguous run** in one packet
  reused (never a scatter list). A driver at function level 3 with capability bit 1 (`DEV_16MB`) gets runs anywhere;
  any other gets one contiguous run below 16 MB, the kernel moving pages to make it (the lock fails if it cannot).
- **A buffer the lock cannot take, or seems unable to take.** [OBS] 14.104a SMP under VirtualBox, 32-bit `DosRead` and
  `DosWrite` on a test character driver that logs every request and keeps up to 512 written bytes:
  - **The trap:** treating any page the caller cannot read or write as an error. A reserved, never-committed page is
    *lent*, not refused.
  - READ into a committed read-only page: rc 5, `*pcbActual` 1, no request, no exception. [OBS-RE] the 1 is the lock's
    page-list entry count (its failure exit sets it to 1), not a byte count, and the rc is the lock's own.
  - The lock asks for write access only on the READ direction [OBS-RE] (the 16-bit lock helper adds the write flag only
    for a read), so **a WRITE from a read-only page succeeds**: rc 0, count 100.
  - **A WRITE whose buffer runs into a reserved, uncommitted page of the caller's own object succeeds:** 8192 bytes with
    the second page reserved gave rc 0, count 8192, no exception. 512 bytes starting 256 below the page boundary went as
    **one** request of 512, and the driver received 00h for every byte from the reserved page. Afterwards `DosQueryMem`
    still reports that page uncommitted (flags 3: read and write, no `PAG_COMMIT`).
  - The lock covers the whole 64 KB tile [OBS-RE], but uncommitted pages elsewhere in the tile do not fail it: a 100-byte
    READ and a 100-byte WRITE from a committed page in an otherwise uncommitted tile both gave rc 0, count 100.
  - Before any of this, DOSCALL1's `DOS32READ`/`DOS32WRITE` touch the buffer's first byte when the count is not 0
    [OBS-RE] (unpublished notes), so an unmapped *first* byte faults in the caller before the kernel runs.
  - **How to verify:** `DosQueryMem` the page after the call - `PAG_COMMIT` is still clear - and read back what the
    driver kept.
  - **The tell:** an implementation that answers a device write with an address error (487) or an access error for a
    buffer whose later pages are merely reserved is wrong; real OS/2 transfers zeros.
  - **Not measured:** a READ across a reserved page (on the 8 KB attempt the test driver's own READ loop trapped, so no
    answer was captured), a page in no object, and the 16-bit calls.
- **The packet**: Len 2Ch, command 04h (READ), 08h (WRITE) or **09h when DosSetVerify is on**, XferAddr the run's
  physical start, the count, the SFN (`sfi_selfsfn`).
- **Counts.** Each request's returned count advances the position; **a short count without error ends the call, rc 0**,
  and `*pcbActual` is the total.
- **Errors.** Code 11h (character I/O interrupted): rc 95, no hard error. Any other code: a character-device hard error
  (FAIL / RETRY / IGNORE allowed); with no hard-error daemon the answer is FAIL. The rc is ErrMap24 for 00h-14h (00h-0Ch -> 19-31, 0Dh -> 107, 0Eh -> 31, 0Fh -> 34, 10h -> 163, 12h -> 165, 13h -> 87, 14h -> 99) and **the code itself
  for 15h-FFh** (`GenErrCode` skips both tables; [OBS]: 15h gave 21). Bit 14 (driver-defined) is not honoured on
  READ/WRITE. **The count so far is returned with the error** ([OBS]: half transferred, then 0Bh: rc 30, count 50; a
  failure on the second piece of 70000: rc 30, count the first piece's).
- **Not measured:** WRITE with a code of 15h or more (the path is shared with READ).

### 4.4 Status word -> return code

After the call [OBS-RE] (unpublished notes): error bit (8000h) clear ->
success (Done is not re-tested); set -> for a **user-defined IOCtl category** (bit 7) the API returns
`FF00h | code`; else with status bit 14 (driver-defined error) `FE00h | code`; else the code is
mapped through a kernel table - `00h`-`0Ch` -> `ERROR_WRITE_PROTECT` (19) ... `ERROR_GEN_FAILURE`
(31), `0Dh` -> 107, `10h` -> 163, `11h` -> 95 `ERROR_INTERRUPT`, `12h` -> 165, `13h` -> 87. The status
error field is one byte (DDK `OS2EQU.INC` `STECODE Equ 00FFh`) [DOC-IBM]. Open/close add a
hard-error retry step for character devices (unpublished notes).

### 4.5 Generic IOCtl specifics

The kernel calls the driver for a generic IOCtl only if the category is user-defined (bit 7) or the
function has bit 6 set; other categories are answered by an in-kernel table first. Before the
driver runs it stores the caller's maximum lengths through `pcbParmLen`/`pcbDataLen`, and nothing
updates them afterwards [OBS-RE] (unpublished notes).

---

## 5. DevHlp: entry, dispatch, context check

- **Entry.** A driver loads the function code into **`DL`** and far-calls the DevHlp address it was
  given at INIT (PDD/00041; DDK `devhlp.inc`) [DOC-IBM]. `DEVICE=` drivers received a far pointer
  through a DPL-3 call gate, base drivers the router's direct address; both reach the same router,
  `h_DeviceHelpDM` [OBS-RE] (section 2.4; unpublished notes).
- **Fast path and bounds.** `EOI` (31h) has an inline fast path when the kernel itself drives the
  8259; `DL >= 84h` panics [OBS-RE] (unpublished notes, 14.089).
- **The table.** `DevhlpFuncDisp`: one 3-byte record per function code `00h`-`83h` - handler offset
  and a flags byte. Unimplemented codes point at a panic [OBS-RE] (unpublished notes).
- **The context check** - the kernel's form of IBM's table (PDD/00208) [OBS-RE] (unpublished notes):

  | flag | the call is legal when | IBM column |
  |---|---|---|
  | 01h | at task time and **not** inside the kernel - a ring-3 `DEVICE=` INIT calling through the gate | INIT |
  | 02h | at task time inside the kernel (Strategy, or IDC called from it); 01h also satisfies this test | Kernel |
  | 04h | at interrupt time | Interrupt |
  | 08h | ABIOS service: redirected to an "ABIOS not present" stub at end of init if there is no ABIOS | - |
  | 10h | MP-safe at task time: called directly; otherwise the router drops the driver lock and takes the big kernel lock around the call | - |

  A ring-0 base-driver INIT runs inside the kernel, so for the router it is task time (02h), not
  INIT (01h) [INF from the test order].
- **The book and the kernel differ on six services.** IBM's table (PDD/00208) lists 78 of the 132 ordinals; on 72 its
  Kernel/Interrupt/INIT columns match the kernel's 02h/04h/01h bits. On five the 14.104a kernel allows more contexts
  than the book gives: `ProcBlock` (04h) also INIT; `SetTimer` (1Dh) also interrupt time; `AttachDD` (2Ah) also
  interrupt time; `AllocGDTSelector` (2Dh) also kernel task time; `RegisterDeviceClass` (43h) also kernel task time.
  The sixth, `ROMCritSection` (26h), is listed by the book ("Note 1" in its Kernel column) but is one of the kernel's
  unimplemented records: flags `07h`, its handler the panic [DOC-IBM PDD/00208 compared with the `DevhlpFuncDisp`
  flags bytes and handlers, OBS-RE]. A driver that relies on the book stays inside both for the five; one that calls a
  service in a context only the kernel allows works on that kernel; one that calls `ROMCritSection` stops the system.
- **What a violation does.** A call whose context bit is clear **panics the system** - it does not
  return an error [OBS-RE] (unpublished notes).
- **INIT-only services after INIT.** At end of initialisation every record whose flags are exactly
  01h or 09h is re-pointed at the panic, so **an INIT-only DevHlp called after boot is fatal**
  [OBS-RE] (same).
- **Kernel exit.** A call through the INIT path (not inside the kernel) is bracketed like a system
  call: the router enters the kernel, and on the way out runs pending kernel-exit work (context
  hooks, rescheduling) [OBS-RE] (same, flag 01h).

- **GetDOSVar (24h) returns the address of a kernel variable**, not a value: `AX:BX` -> the cell, which the driver
  reads itself (PDD/00245) [DOC-IBM]. The kernel's routine [OBS-RE] (unpublished notes, 14.104a SMP):
  indexes 0, 3 and 15h and above set carry; 1 the GIS selector, 2 the LIS selector:offset, 4-6 the dump, reboot and
  MSATS vectors, 7/8 the yield flags and 13 the interrupt level (in a second kernel data segment, so their `AX`
  differs), 11 the code-page buffer, 14 a device class table chosen by `CX` = 1 (disk) or 2 (mouse), 15 the DMQS
  selector, 16/17 the APM code segment and length (the APM BIOS is set up first if driver initialisation is still in
  progress), 18 the SMP-active flag, 19 the PSD flags (refreshed from the PSD's own word on each call), 20 the processor
  count; 9, 10, 12 and 17 work although IBM's page does not list them. Two special cases: **index 1 asked by the clock
  driver** (its CS equals `CLOCK$`'s `SDevProtCS`) returns the GIS's **read-write** alias instead - the one driver
  allowed to write the GIS; and **index 18 on a uniprocessor system** (the flag not 1) returns with carry set.

- **The physical-memory services, where the pages leave the answer open.** Measured on OS/2 Warp 4.5 WSeB, kernel 14.089 UNI (a
  VirtualBox VM, 2026-10-26: a 16-bit character driver calling each service from a generic IOCtl at task time, the
  results read back by a 32-bit program) [OBS]: a second `FreePhys` (19h) of the same address, a second `Unlock` (14h)
  of the same handle and a second `FreeGDTSelector` (53h) of the same selector each return with carry set; a second
  `VMFree` (58h) of the same block sets carry with EAX 87; `AllocGDTSelector` (2Dh) with CX 0 answers 488;
  `VMSetMem` (66h) decommitting a range that is already decommitted answers **5** (PDD/00308 says only that the range
  "must be entirely precommitted"); `GetDescInfo` (5Dh) of a GDT selector `PhysToGDTSelector` (2Eh) made, after the
  driver has read through it, answers access byte **93h** - present, ring 0, writable data, accessed; `VMLock` (55h)
  and `LinToPageList` (5Eh) of one 4 KB block give one PageList entry; `VerifyAccess` (27h), `PhysToUVirt` (17h) types
  1 and 2, `VMProcessToGlobal` (59h) and `UnPhysToVirt` (32h) on valid arguments clear the carry.
- **`VerifyAccess` (27h) is the kernel's user-buffer probe** [OBS-RE] (unpublished notes, 14.104a
  SMP): a selector at or below 7, an offset plus length past 64 KB (so CX 0, meaning 64 KB, is valid only at offset 0),
  a descriptor that is not present or is neither data nor readable code, a DPL below the selector's RPL, or a byte of
  the range that cannot be read - or, for DH 1, written back unchanged - fails it. The DevHlp then returns to the driver
  with **carry set and every register kept**, having queued `XCPT_ACCESS_VIOLATION` {`XCPT_UNKNOWN_ACCESS`,
  `XCPT_DATA_UNKNOWN`} for the calling thread; the exception is delivered when that thread returns to ring 3, through
  its own handler chain. "The process is terminated" (PDD/00299) is that exception's default action, not something the
  DevHlp does.
- **Interrupts off across a DevHlp call** [DOC-IBM PDD/00203, 00048]: a DevHlp preserves the caller's interrupt flag,
  except the ones the reference names as enabling interrupts - `ProcBlock`, `Yield`, `TCYield`, `AllocReqPacket`,
  `FreeReqPacket`, `SemRequest`, `SemHandle`, `MonWrite`, `MonFlush`; `EOI` does not change it. IBM gives no time limit
  for running with interrupts off, only "as briefly as possible" and a yield about every 3 ms. IBM's own drivers read
  the flag with `PUSHF` (the UHCI driver's `pushf; pop; test 200h`) and restore it with `POPF` (the DDK's
  `pushf ... popf` macros), so a driver's view of IF includes what `PUSHF` shows.
- **`VMSetMem` (66h)** [OBS-RE] (unpublished notes): 87 for no flag, a bit above 2, two bits, or an
  unaligned address or size; 5 unless the range lies in a `VMAlloc` object made reserve-only, not shared, at its
  primary mapping; 32798 past the object's end.
- **What IBM's own drivers do beyond the pages** [SRC-IBM / OBS-RE]: the mouse device-dependent driver calls
  `VerifyAccess` while a `PhysToVirt` pointer is still in use (DDK `mouse/ioget.asm`, `MouGetPtrShape`), which PDD/00260
  says no driver may do; it calls `VMAlloc` with flags 82h, setting a bit the page calls reserved; and `VMAlloc`'s memory
  is not zeroed (unpublished notes). The pointer draw driver `POINTDD.SYS` (10.056)
  imports nothing and makes no DevHlp call at INIT; its `PhysToVirt` calls name only B8000h, B0000h and A0000h, and its
  text-mode draw is enabled by a flag set after reading the VGA graphics controller (port 3CFh) (unpublished notes).

- **`DynamicAPI` (6Ch) makes a driver routine callable as a system call** [DOC-IBM PDD "DynamicAPI"]: `AX:BX` the
  worker (16:16 when DH bit 1 is set, else linear), `CX` the parameter count (words for a 16-bit gate, DH bit 0; dwords
  otherwise), at most 16 words or 8 dwords; carry clear and `DI` the gate selector. The kernel has **16 fixed slots**,
  claimed and never released [OBS-RE] (unpublished notes). A call through the gate reaches
  the slot's stub (`push si; mov si,n; jmp dynam_sci`), which enters the kernel as a system call does, then picks the
  `SCIReturn<n>` that pops the parameter bytes and far-returns into the worker, so the worker runs inside a system-call
  frame and its return goes back through the SCI exit [OBS-RE] (unpublished notes). The
  32-bit successor is KEE's `KernDynamicAPI`, which copies a template stub per call instead of using the slots [OBS-RE]
  (unpublished notes). IBM's `OS2CDROM.DMD` calls it at INIT.

- **Registers on failure: three DevHlps the reference does not describe** [OBS-RE] (14.104a SMP kernel, the
  handlers' bytes; unpublished notes). A host or emulator that answers every failure with "carry set, AX = error"
  gets these three wrong, and a driver that reads the register after the call sees the difference.
  - **`PhysToUVirt` (17h)** returns with **ES = 53h** on every failure and on a release (type 2): the DevHlp
    handler loads ES with 53h before calling the worker, and the worker loads the new selector into ES only on a
    successful map. A driver that releases the selector it holds in ES gets 53h back, never the freed selector.
  - **`ABIOSGetParms` (29h)** on a machine without ABIOS sets carry and returns **AX unchanged** (the caller's LID):
    the handler sets AX = 3 inside a `pusha`/`popa` frame, so the error code is lost and only carry reports the
    failure. The other ABIOS DevHlps (34h-38h) do return AX = 3 there.
  - **`AllocateCtxHook` (63h)** sets carry with **no error code** on both failure paths (EBX not -1, and the hook
    allocation failing): EAX is the allocator's out-pointer stack slot, unwritten in the first case. Community
    references list 87 here; the shipped kernel does not load it.

  The tell: a hosted driver that works on real OS/2 and misbehaves only after a failed call - typically a pop of a
  segment register it expected unchanged, or an error path that tests AX. Verify by disassembling the handler named
  in the kernel's DevHlp table for the code and following it to its `ret`.

The DevHlp catalogue itself is in `kernel-services.md`; the lifecycle calls in `drivers.md`.

---

## 6. Interrupt time, timers, context hooks, blocking

### 6.1 Hardware interrupts

- **Registering** (`SetIRQ`, PDD/00289) [DOC-IBM]: the kernel takes the handler's CS and DS from the
  device header (`SDevProtCS`/`SDevProtDS`), refuses a reserved IRQ (the cascade, IRQ 2), allows
  sharing only if the IRQ is shareable on the hardware and every holder asked for sharing, puts the
  new handler at the **head** of the IRQ's chain and unmasks the IRQ. **There is no four-handler
  limit** in 14.104a [OBS-RE] (unpublished notes). `UnSetIRQ`
  unlinks the first record with the caller's DS and frees it later from a context hook, so another
  CPU may still be walking it; it masks the IRQ when the chain empties [OBS-RE] (same).
- **Dispatch** [OBS-RE] (unpublished notes, router steps 1-12):
  1. A spurious IRQ 7/15 (ISR bit clear) is dropped (a spurious slave IRQ also EOIs the cascade).
  2. On the outermost interrupt, with SMP running, take the external-interrupt lock and, if the
     16-bit driver lock is held by a thread running on another CPU, **hold that CPU** for the
     duration (section 6.5).
  3. Switch to the per-CPU interrupt stack (and to a 16-bit stack tile for 16-bit handlers).
  4. Walk the chain: **interrupts are enabled only for a shared IRQ** (an exclusive handler runs
     with IF = 0), **DS = the driver's data selector**, far call. **Carry clear = claimed -> stop**;
     carry set -> next handler.
  5. **Claimed: the kernel sends no EOI** - the driver must call `DevHlp_EOI` (PDD/00237)
     [DOC-IBM]. If the claiming driver is the CLOCK device, the time fields of the global
     information segment are copied to the user-visible copy.
  6. **Unclaimed:** on a shareable (or DOS-session) IRQ the kernel counts it and **masks the IRQ
     after more than 10 unclaimed in a row**, and sends the EOI; otherwise it just sends the EOI. A
     claim resets the count.
  7. On the way out to ring 3 or V86 with work pending, run kernel-exit processing - context hooks
     among it (section 6.3).
- **Interrupt stack.** `RegisterStackUsage` (PDD/00049) [DOC-IBM] sizes the interrupt stack; the
  kernel refuses a total above `3800h` bytes with 262 [OBS-RE] (unpublished notes).
- **The registers and results in detail** [OBS-RE] (14.104a SMP; unpublished notes):
  - `SetIRQ` saves and restores every register (`pusha`/`popa`): on a refusal **AX is not loaded** (the book's "AX =
    error code" is not what the kernel does) and only the flags change. DH above 1 is refused (bit 3 is the kernel's
    own entry's). Refusal order: IRQ >= the IRQ count; other flag bits; the reserved IRQ; then the consent rule - on an
    empty chain an exclusive handler always passes and a shared one needs the IRQ's "shareable" flag (04h); on an
    owned IRQ only a shared request, on a shareable IRQ, whose owners registered shared (01h), passes; then the
    record's allocation. Every successful `SetIRQ` unmasks the IRQ.
  - `UnSetIRQ` gives carry for an IRQ past the count, a reserved IRQ, no record with the caller's header DS, or a
    record already queued for freeing; it masks an emptied IRQ only when no PSD handler is attached.
  - **The handler's registers at the call**: DS the driver's data selector; ES the kernel's flat data selector (not
    the driver's); AX carries nothing. The kernel saves every register (PDD/00035 [DOC-IBM]).
  - **The unclaimed count** is a byte per IRQ, incremented only on a shareable (04h) or DOS-session (10h) IRQ; the IRQ
    is masked on the 11th unclaimed interrupt in a row, and the EOI is always sent after. **Only a claim resets it**:
    neither `SetIRQ` nor an unmask does, so a re-unmasked IRQ is masked again by its next unclaimed interrupt.
  - **`DevHlp_EOI`** (31h) has a fast path ahead of the DevHlp context check: interrupts off, the 8259 EOI(s), the
    caller's flags back, **carry clear and AX kept** (drivers rely on the carry surviving it: UHCI's `CLC();
    DevHelp_EOI(irq);` [DOC-IBM] DDK `usb/UHCI/uhcirq.c`).
  - **`SetIRQMask`** (77h: AL the IRQ, AH 1 mask / 0 unmask) and **`GetIRQMask`** (78h: AL; EAX 1 masked, 0 unmasked)
    exist in 14.104a's DevHlp table (flags 17h) though PDD/00208 does not list them; IBM's SMP mouse driver uses
    `SetIRQMask` in place of 8259 port writes [DOC-IBM] (DDK `mouse/move.asm`).
  - **`RegisterStackUsage`'s arithmetic**: one system-wide budget (the packet's IRQ is never read): cost = cNest x
    cbStackEOI + max(cbStackCLI, cbStackSTI, cbStackEOI); a handler that enables interrupts adds its cost to the total
    (base 2000h), refused above 3800h; one that does not counts only if it exceeds the largest such cost so far,
    refused if the total plus it is above 3800h; a refusal is carry with AX = 262.
  - Measured [OBS] (14.104a SMP under VirtualBox, 2026-10-27): IRQ 5 free; a shared `SetIRQ` as its first handler is
    refused, so the shareable flag is clear on that line. Who sets the shareable flag, and on which IRQs, is not
    established (the loader's IRQ initialisation; not read).

### 6.2 Timers

`SetTimer` (PDD/00291) and `TickCount` (PDD/00295) [DOC-IBM] register into one **32-entry** table
keyed by (handler offset, driver DS) [OBS-RE] (unpublished notes). The
table is walked by `Tick_Handler`, which the kernel runs from **`DevHlp_SchedClock`** - the call
the clock driver makes on its timer interrupt - once at least 31 ms have accumulated after the EOI
[OBS-RE] (unpublished notes). Each due handler is
far-called **with interrupts enabled, DS = the driver's DS**, on whichever CPU took the clock
interrupt; its return is ignored; a nested clock interrupt does not re-enter the walk [OBS-RE]
(unpublished notes). A handler registered with count `n` is first called after `n+1` walks, then
every `n`. **A count of 0** sets the countdown to 0, which the walk's decrement wraps to `FFFFh`,
so the handler is called on every **65 536th** walk, first time included - IBM's *"0 means FFFFH+1
ticks"* (PDD/00295) [DOC-IBM] + [OBS-RE] (unpublished notes: call when the countdown is 1, else decrement). The
"ticks" IBM counts are these walks, not hardware timer interrupts [INF, from section 6.2's 31 ms
threshold]. `TickCount` can register a **new** handler only from task time inside the kernel; at
interrupt time it can only change an existing one [OBS-RE] (unpublished notes).

### 6.2a The high-resolution timer: `RegisterTmrDD`, the loader's counters, `DosTmrQueryTime`

**The trap.** `TIMER0.SYS` - the `TIMER0$` high-resolution timer driver, `BASEDEV=TIMER0.SYS` on a stock install - looks
like the driver that calls DevHlp `RegisterTmrDD` (61h) and so makes `DosTmrQueryFreq` and `DosTmrQueryTime` work. A
test for their 535 (`ERROR_TMR_NO_DEVICE`, `bseerr.h` [DOC-IBM]) then boots without it. That boot answers 0: TIMER0 is
not the caller, and removing it does not produce 535.

Measurements below marked [OBS] were taken on Warp Server for e-Business 4.50, kernel revision 14.089 (`ver /r`),
`PSD=OS2APIC.PSD`, in a VirtualBox VM, with three probes: a 16-bit `DEVICE=` driver calling 61h at its INIT; a
`BASEDEV=` driver sampling ports 20h, 21h, 40h and 43h at its ring-0 INIT and handing the samples to a program by a
private generic IOCtl; and 32-bit programs calling the two APIs. [OBS-RE] claims are from the 14.104a SMP kernel, the
WSeB `OS2LDR` (43008 bytes) and `CLOCK01.SYS` 10.058 (unpublished notes).

**Who registers.**
- **The clock driver**, `CLOCK01.SYS` (`CLOCK02.SYS` on Micro Channel), in its first INIT (`RTINIT`), which runs from
  the kernel's implicit base-driver list ahead of every `BASEDEV=` (section 1.2): `CX:DI` = its `PTTimer0` routine, `DL`
  = `DevHlp_RegisterTmrDD` [DOC-IBM DDK `base/src/dev/clock/clock01/clock01.asm` RTINIT; PDD reference
  "RegisterTmrDD"]. The shipped `CLOCK01.SYS` matches the source there [OBS-RE].
- **Not `TIMER0.SYS`**: it makes no 61h call and never reads or writes the timer cells [DOC-IBM DDK
  `base/src/dev/mme/timer0/`; OBS-RE `TIMER0.SYS`]. A byte scan of an install's drivers and DLLs finds the 61h call only
  in `CLOCK01.SYS` and `CLOCK02.SYS` [OBS-RE] (bound: a driver that loads `DL` some other way is not excluded).
- `PTTimer0` is the profiler's entry - function 0 takes timer 0 from VTIMER, 1 gives it back (DDK
  `base/src/dev/clock/ptt0.asm`) [DOC-IBM]. The kernel stores `CX:DI`; in 14.104a no code reads the stored pointer
  [OBS-RE] (an absolute-operand scan; a reach through a computed address is not excluded).

**What the loader answers.** The kernel passes the call to the loader's DOSHLP `RegisterTmrDD` (slot
`DosHlpRegisterTmrDD`, DDK `base/inc/doshlp.inc` [DOC-IBM]) and returns its registers to the driver [OBS-RE]. OS2LDR's
routine ignores its input and answers [OBS-RE]:
- `DI:BX` -> the rollover cell, two ULONGs: +0 the current rollover count, +4 the next (DDK
  `base/src/dev/clock/clockdd.asm`, `qwTmrRollover` [DOC-IBM]);
- `DI:CX` -> `qwTmr`, the 64-bit count;
- `EAX` = 1193167, the 8254's input frequency (`doshlp.inc` `TIMER_FREQ_HI`/`TIMER_FREQ_LO` = 1234CFh [DOC-IBM]).

Measured from a `DEVICE=` driver's INIT: carry clear, DI non-zero, BX 0C9Ch, CX 0CA4h, EAX 1193167; read at task time,
both rollover halves hold 10000h [OBS]. A non-zero DI makes the kernel keep both pointers and the frequency and set its
timer-status bit [OBS-RE]. The DOSHLP routine is init code, discarded at the end of initialisation, and 61h is an
INIT-only DevHlp (PDD reference "RegisterTmrDD") disabled with the others then (section 5) [OBS-RE].

**Who advances the count: the clock driver, not DOSHLP.** DOSHLP has no IRQ0 code [OBS-RE]. `CLOCK01` [DOC-IBM
`clock01.asm`; OBS-RE]:
- in RTINIT, after registering, writes current = next = 10000h into the rollover cell;
- in its second INIT (`RTINIT2`, the command-0 INIT the kernel sends `CLOCK$` after the loadable drivers are in,
  section 1.3) programs 8254 counter 0 to mode 2 with count 0 (10000h, about 18.2 Hz) and hooks IRQ0, exclusive;
- on each IRQ0 (`PTInt`): add = current; current = next; `qwTmr += add`, saturating at 7FFFFFFF:FFFFFFFFh.

The system tick is a different interrupt (the RTC on IRQ 8). So `qwTmr` is 0 until RTINIT2 and a whole number of
10000h periods after it [INF from the above]; measured, it advanced 23 periods over a 23-period interval [OBS].

**The gate.** `DosTmrQueryFreq` and `DosTmrQueryTime` test the timer-status bit first and answer 535, writing nothing,
when it is clear; only a `RegisterTmrDD` whose DOSHLP answer had DI non-zero sets it [OBS-RE]. The clock driver is
always in the base list and IBM's OS2LDR always answers DI non-zero, so with IBM's loader no CONFIG.SYS reaches 535
[INF]. Measured with `BASEDEV=TIMER0.SYS` removed: `DosTmrQueryFreq` answers 0 with 1193167, `DosTmrQueryTime` advances
at that rate, and `DosOpen` of `TIMER0$` answers 110 [OBS]. `DosTmrQueryFreq` copies the EAX the registration returned
[OBS-RE].

**What `DosTmrQueryTime` computes.** The kernel calls the PSD's `PSD_QUERY_SYSTEM_TIMER` (packet `PSD_QRYTMR`, the
DevCon SMP book's `PSD.H` [DOC-IBM]); `OS2APIC.PSD` exports no timer function, so the kernel's default calls DOSHLP's
32-bit query routine [OBS-RE]. That routine [OBS-RE OS2LDR; port and command values DDK `base/inc/timer.inc` and
`base/src/dev/mouse/hw.inc`, DOC-IBM]:
1. interrupts off; reads the master 8259's ISR (OCW3 0Bh) and IRR (OCW3 0Ah) at port 20h and ORs them;
2. latches counter 0 (`out 43h,0`), reads the count low then high from 40h, reads port 20h again (the IRR);
3. live part = (10000h - count) mod 10000h - the fixed reload RTINIT2 programs, not the rollover cell;
4. IRQ0's bit clear in both reads: `qwTmr` + live part. Set before the latch: `qwTmr` + live part + the current
   rollover (the period PTInt has not added yet). Set only after the latch: `qwTmr` + the current rollover;
5. a signed overflow saturates.

**When the count is not monotonic.**
- **`TIMER0$` in use.** On its first client (an open of `TIMER0$`, or its IDC registration) TIMER0 takes IRQ0 from the
  clock driver through `CLOCK$`'s IDC and programs counter 0 for a 1 ms period; on its last client it gives IRQ0 back
  (DDK `mme/timer0/clockidc.c`, `timerset.c` [DOC-IBM]). Meanwhile PTInt does not run and `qwTmr` stops. Measured with
  `TIMER0$` open, five calls about 128 ms apart: 057EFC07h, 057EFB91h, 057FFF2Dh, 057EFB58h, 057EFFA9h - the frozen
  count, plus a live part within one 1 ms period, plus once a pending IRQ0's 10000h. After the close the next value,
  057E002Ah, was below all of them, and the count then advanced normally [OBS].
- **Before RTINIT2.** Between the clock driver's two INITs `qwTmr` is 0, counter 0 runs in mode 2 with reload 10000h,
  and IRQ0 is masked [OBS-RE; OBS]. A `BASEDEV=` probe reading the 8259 and counter 0 in the query routine's order at
  its ring-0 INIT found [OBS]: IMR F9h (IRQ0 masked), ISR 0, counter 0 status 34h; IRR bit 0 **clear** at the INIT's
  first samples and **set** from counter 0's first terminal count on, staying set across later wraps - a masked,
  unacknowledged IRQ0 does latch. The same probe built as a `.DMD` (the last `BASEDEV=` class), alone and in one boot
  with the first: the bit is clear again when each base INIT begins, even after an earlier driver's INIT left it set.
  At nine INIT entries in seven boots the count was 5.6-51.6 ms past the last wrap. So the routine's answer at a base
  INIT is (10000h - count) mod 10000h until counter 0's next terminal count, then that plus 10000h: a 54.9 ms sawtooth
  that never advances. After boot (IMR F8h) the bit reads clear in every sample.
- **Not established:** what clears the latched IRQ0 between base driver INITs, and whether it happens per INIT. A
  counter reload cannot (an 8259 drops a latched IRR bit only on acknowledge or re-initialisation) [INF]. To settle it:
  read the kernel's `BASEDEV=` INIT path for 8259 writes (an OCW3 poll, an ICW, an unmask and acknowledge), or set a
  kernel-debugger I/O breakpoint on ports 20h/21h during the base load. Bound on all of the window's [OBS]: VirtualBox's
  emulated 8259 and 8254, one kernel revision.

**How to verify.** `grep -n DevHlp_RegisterTmrDD` over the DDK's `base/src/dev/clock/` (two hits, `clock01` and
`clock02`) and `base/src/dev/mme/timer0/` (none); disassemble the loader's DOSHLP table entry at
`DosHlpRegisterTmrDD`; for behaviour, a `DEVICE=` driver that calls 61h at INIT and prints DI, BX, CX, EAX, and a
program that calls `DosTmrQueryTime` with and without `TIMER0$` open.

**The tell.** A 535 test whose recipe removes `TIMER0.SYS` and still gets 0; a high-resolution time that stalls or
steps backwards while a `TIMER0$` client is active; an emulated `RegisterTmrDD` that returns the caller's own registers,
so the clock driver takes its `PTTimer0` offset for a selector.

### 6.3 Context hooks

IBM: `AllocateCtxHook`/`ArmCtxHook` let interrupt-time code request task-time work; arming is legal
at interrupt time and the hook runs once on *"the next available task-time thread"*, with EAX = the
armed value and EBX = -1 (PDD/00226, 00230) [DOC-IBM]. The kernel [OBS-RE]
(unpublished notes):
- a DevHlp hook is always **global**; its handler's CS and DS come from the device header;
- arming sets a global "hooks pending" bit; **arming an already-armed hook succeeds** and replaces
  the data (IBM says it is an error) - `ArmCtxHook` with ECX != -1 returns 87; `AllocateCtxHook`
  with EBX != -1 sets carry without loading 87;
- **who runs them:** (a) **any thread of any process** leaving the kernel - system-call return,
  interrupt return to ring 3/V86, the DevHlp INIT path - runs all pending global hooks in its kernel
  exit, except the INT 13 thread; (b) the **context-hook daemon** thread, which sleeps until hooks
  are pending (the Debugging Handbook's *"\*ctxh Default Global Context Hook dispatching thread"*
  [DOC-IBM]). A hook is disarmed before it is called (so it may re-arm itself), is called with
  interrupts enabled **under the 16-bit driver lock**, with DS = the driver's DS and ES = 0.

### 6.4 Blocking and waking

`ProcBlock(id, timeout, interruptible)` blocks the current thread on a 32-bit id; callers re-check
their condition because wakeups can be spurious (PDD/00262) [DOC-IBM]. `ProcRun(id)` wakes
**every** thread blocked on that id and returns the count; nothing is latched if none is waiting
(PDD/00263) [DOC-IBM] + [OBS-RE] (unpublished notes). While asleep, the
thread gives up the big kernel lock and the 16-bit driver lock and re-takes them on resumption
[OBS-RE] (same; unpublished notes). Result mapping: woken -> carry clear; timeout ->
carry and zero set; interrupted -> carry set, zero clear (PDD/00262) [DOC-IBM] + [OBS-RE].

**A fourth result: PM event posted (`AL = 5`).** PDD/00262 documents only "`AL` = awake code,
non-zero if unusual wakeup" [DOC-IBM]. The DDK's `proc.inc` names four codes - `PBR_NA 0`,
`PBR_TE 1`, `PBR_IN 3`, `PBR_PM 5` - beside `PM_EVENT_POSTED EQU 3000`, which `bsedos.h` glosses
*"PM Shared Event Posted"* next to `DC_SEM_PM` *"PM Shared Event Semaphore"* [DOC-IBM]. The kernel's
sleep primitive returns 3000 and `ProcBlock` reports it as `AL = 5`, carry set, zero clear - the
same flags as "interrupted" [OBS-RE]. Its only source is the post of a PM shared event semaphore:
`DosPMWaitEventSem`, `DosPMRequestMutexSem`, `DosPMWaitMuxWaitSem` (each taking that semaphore as
its first argument) and an undocumented `DOS32PM16SEMCHK` (which leaves the arm set for a following
16-bit semaphore wait) record the calling thread in the semaphore and mark it; `DosPMPostEventSem`
or DevHlp `PMPostEventSem` (70h) then latches a wake flag in that thread, one-shot, and wakes it if
it is blocked - **on whatever id it is blocked on**. If the thread is not asleep when the post
comes, the flag stays latched and its next sleep ends with 3000 at once, even a non-interruptible
one; the mark is cleared when any sleep
returns [OBS-RE] (unpublished notes; one writer in the whole image). So a
driver sees `AL = 5` only when the thread that entered it was armed this way and the PM semaphore
is posted before or during the block [INF]; it is an unusual wakeup like any other: re-test the
condition. IBM's own consumer is the kernel's 16-bit semaphore wait, which turns `AL = 5` back into
3000; no driver in the DDK's shipped source tests for it - they test carry/zero or the C wrapper's
`WAIT_TIMED_OUT` (8001h) / `WAIT_INTERRUPTED` (8003h) (searched: the DDK's shipped driver source,
for `PBR_*`, `PM_EVENT_POSTED` and `AL` tests after `ProcBlock`). The C `DevHelp_ProcBlock` in the
DDK's `dhcalls.lib` zeroes `AH` and returns 0 when carry is clear, else `AX | 8000h` - so **8005h**
for this case, a value `dhcalls.h` does not name and which equals neither constant [OBS-RE]
(`dhcalls.lib`, modules `dhcall6a` and `dhret`, `DHRET_10`).

### 6.5 SMP serialisation

The PDD Reference says nothing about SMP. The kernel has **one global lock for all 16-bit driver
code** (`_R0SubSysSpinLock`), held across every Strategy call, every context-hook callback and KEE's
`KernSerialize16BitDD` bracket - so **at most one CPU is in 16-bit driver code** at a time. An
interrupt handler runs under the external-interrupt lock with the CPU of the driver-lock holder held
by IPI, so a driver's interrupt handler never overlaps its own task-time code on another CPU. No
per-device lock exists [OBS-RE] (unpublished notes).

---

## 7. Other driver kinds

### 7.1 Storage: adapter drivers (ADD), device managers (DMD), filters

- **IBM's model.** An `.ADD` is a PDD that, at INIT, registers a direct-call entry point with
  `DevHlp_RegisterDeviceClass` (PDD/00275; STORAGE/00034); device managers (`OS2DASD.DMD`,
  `OS2SCSI.DMD`) and filters call that entry with a far pointer to an **IORB**
  (STORAGE/00020) - not through the request-packet path. Every registered ADD must answer
  `IOCC_CONFIGURATION`; `IOCM_COMPLETE_INIT` tells it that it may stop relying on INT 13h BIOS
  support, which it must keep until then (STORAGE/00024) [DOC-IBM].
- **The device class tables** [DOC-IBM STORAGE/00034-00035; OBS-RE unpublished notes]:
  `RegisterDeviceClass` (43h) appends `{entry offset, entry selector, flags, name}` (22 bytes; at
  most 15 name characters kept) to the class's table: class 1 (disk) holds 32, class 2 (mouse) 3.
  It answers `AX` = the new count, which is the handle (entry `h-1`), or `AX` 8 with carry for a
  class out of range or a full table. Nothing removes an entry and duplicates are not checked.
  `GetDOSVar` 14 with `CX` = the class gives the table, `{count, max, entries[]}`; a device manager
  walks it to find the ADDs.
- **The kernel's part** [OBS-RE] (unpublished notes):
  after the base drivers and before SYSINIT starts, the kernel itself sends each registered ADD an
  IORB `IOCC_CONFIGURATION`/`IOCM_COMPLETE_INIT`. A block or ADD-strategy base driver's INIT is
  preceded by the disk-table preparation of IBM's 1Bh "case 3" (section 2.4). The load order -
  `.ADD` before `.I13`, `.FLT`, `.DMD` - is the extension table (section 1.2). `.BID/.VSD/.TSD` are
  the pre-2.0 LADDR model, kept in the ordering only (`drivers.md`).
- **Drive letters of ADD-served units** [DOC-IBM] (DDK `OS2DASD` source, 16-bit
  unpublished notes and 32-bit unpublished notes;
  `dmheader.asm`): the ADDs report units, not drive letters. `OS2DASD.DMD`'s first header is a
  **block** device header (`" Disk DD"`), and at its BASEDEVINIT it builds a unit control block
  per adapter unit (allocating each with an `IOCM_ALLOCATE_UNIT` IORB), then returns
  `Data_1` = **number of logical drives** - removable disks plus partitions, plus 1 "pseudo drive"
  when drive A's volume is flagged multiplexed, or plus 2 when there is no removable disk or none at
  `A:`/`B:` - and a BPB array in that order (`A:`, `B:`, then the volumes from the first fixed one
  on). With no media it
  returns 2 units. The kernel then gives those units consecutive drive letters exactly as for any
  base block driver (section 3.4).
- **The volume order, which is the DOS drive-letter order** [DOC-IBM] (DDK `OS2DASD`, 16-bit
  unpublished notes):
  1. **One primary partition per fixed disk, disk by disk** (80h, 81h, ...). On each disk it is
     the **first** of the four partition-table entries, in table order, whose type is recognised
     (FAT up to 16M, 16-32M, over 32M, FAT16X, IFS, active or inactive fault-tolerant); the
     active flag is not consulted. A table without the AA55h signature, or a recognised entry of
     under 64 sectors, gives the disk no primary volume.
  2. **Then the extended partition's logical volumes, across all fixed disks**, disk by disk. If
     drive 80h has no primary partition it is not searched for extended volumes; every later
     disk is searched whether it had a primary or not (`Setup_Partition_VolCBs` header comment).
  3. **Partitioned removable media** ("pseudo-fixed") come after the fixed disks and are processed
     "linear": each disk's extended volumes immediately after its own primary, with the number of
     reserved volumes per disk set by the `/MP` option (at least one).
- **The LVM build: `OS2DASD.DMD` and `OS2LVM.DMD` are a pair** [OBS-RE] (read in the 2001-10-16
  `OS2DASD.DMD` and `OS2LVM.DMD` with same-dated `.sym` files, against 14.104a; unpublished notes):
  - **`OS2DASD.DMD`** is the DDK's 32-bit build compiled for LVM: its INIT returns **0** units and
    no BPB array ("allowing OS2LVM to report the logical drives", source comment), and it reports
    0 fixed disks to command 16h. It never checks for `OS2LVM`; without it there are no drive
    letters at all, `A:`/`B:` included, since the pseudo-floppies are handed over too.
  - **`OS2LVM.DMD`**, at its own 1Bh INIT, calls `DevHlp_AttachDD("OS2DASD$")`, then `OS2DASD`'s IDC
    entry with function 1 (`DMIDC_GET_INTERFACE`), receiving the `DASD_INTERFACE` (DDK `dmidc.h`):
    `OS2DASD`'s Strategy-1/2/3 entries and iterators over physical disks and partitions. If either
    step fails it returns `8115h` and does not load - the pair's only check. So `OS2DASD.DMD` must
    precede it; both are `.DMD`, one extension tier, and within a tier `BASEDEV=` order appears to
    follow CONFIG.SYS [INF].
  - It returns its own volumes as units (`Unit` = N, a 26-entry BPB pointer array). **Units are
    `OS2LVM`'s slots, not letters.** Before returning it assigns letters itself: each volume's
    preferred letter from the on-disk tables below first, fixed volumes winning ties, then the
    lowest free letter. The kernel then asks each unit with command 22h (section 3.4), and `OS2LVM`
    answers with the assigned letter, or `BFh` (above 25) for a hidden volume. It answers command
    16h with `OS2DASD`'s disk count, so it owns every physical disk the kernel sees.
  - This matches a firsthand account: `OS2LVM.DMD` uses the letters LVM records on disk and
    otherwise the ordinary DOS mapping above [OBS-USER, firsthand long-term use of real OS/2 LVM
    systems by one user]. The on-disk record is IBM's **Drive Letter Assignment table**: one sector per
  partition table, signature `424D5202h`/`44464D50h`, CRC'd, holding a `DLA_Entry` per
  partition-table entry with the volume's `Drive_Letter` [DOC-IBM] (IBM's LVM engine source as
  released under the GPL and carried by osFree, `include/os3/lvmtk/lvm_data.h:32-103`). The engine
  distinguishes a volume's `Drive_Letter_Preference` (what it wants), `Current_Drive_Letter`
  (what it has; differs when the preference is taken by another volume) and
  `Initial_Drive_Letter` (what the operating system assigned at boot) (`lvm_intr.h:229-233`), and
  after a change asks `OS2DASD`/`OS2LVM` to rediscover with IOCtl category 9 function 6Ah
  (`OS2/lvm/diskio.h:53`, `engine.c:4825-4854`).
- **Volumes at run time: two kernel intercepts in `w_DevIOCtl`, no DevHlp** [OBS-RE] (unpublished notes):
  - **Rediscover**, category 9 function 6Ah on a physical-disk handle (`h_w_DynamicRediscover`):
    the kernel forwards it to the driver; `OS2LVM` deletes the volumes listed for extension, passes
    the request on to `OS2DASD` (which re-reads the partition tables), rebuilds, reassigns letters
    and writes the number of new units into the data packet. The kernel then builds a DPB - and so
    asks command 22h - for each unit 2-25 without one, until that count is used up. Errors: 87,
    13 (count of 25 or more), 110.
  - **Delete**, category 8 function 6Ah, handle -1, parameter `{0, drive}` (`h_w_DynamicDelete`;
    the LVM engine's own call, `OS2/lvm/volume.c:1238`): a drive below `C:` is refused with 87;
    the kernel locks the spindle, unmounts, forwards to the driver (`OS2LVM` clears the slot),
    unlocks, and with LVM active frees the drive's DPB and letter and wakes path-change
    notification. Removable-media eject reaches the same code.
- **Not covered here:** the DMD<->file-system path (Strategy-2 request lists).

### 7.2 Installable file systems (`IFS=`)

[OBS-RE] (unpublished notes)
- Loaded as type 3 in the same `DEVICE=`/`IFS=` walk (section 1.3), with `FSHELPER` imports resolved
  against the kernel's pseudo-module.
- The `FS_*` exports are resolved by name into a template (an inconsistent set is refused).
- **Check** before INIT: the `FS_NAME` must not already be installed (183), `FS_ATTRIBUTE` may use
  only bits 0-5 and 28-31 (263), `FSA_UNC` needs `FS_VERIFYUNCNAME`, `FSA_LOCK` needs `FS_FILELOCKS`.
- **`FS_INIT`** is called from ring 3 in SYSINIT, like a `DEVICE=` INIT (IBM's prototype:
  `FS_INIT(PSZ szParm, ULONG pDevHlp, PULONG pMiniFSD)`, DDK `fsd.h` [DOC-IBM]); on 0 the file
  system is **added** (at most 254), then its selectors are lowered to DPL 0.
  - **`szParm` is the line's text after the file name, the separating blank included**, or a null
    pointer when nothing follows the name: `IFS=C:\X\MINFS.IFS /TEST:1` hands FS_INIT ` /TEST:1`
    [OBS] (an NE test IFS logging its `szParm`, OS/2 Warp 4.5 WSeB, kernel 14.104a SMP,
    2026-10-31). `pMiniFSD` is null on a normal boot [OBS-RE] (unpublished notes).
  - A 16-bit routine an LX IFS exports from a 16-bit object is reached as that object's 16:16
    even when the linker marked the entry 32-bit (OpenWatcom's MIXED1632 does): such an IFS
    installs and its FS_INIT runs [OBS] (same machine).
- **The calling context of every other `FS_*` call:** the calling thread, ring 0, `SS` the per-thread
  task area (1530h) whose top holds the current process's PTDA - an FSD that saves `SS` reads the
  calling process's fields through it later, e.g. the code page at `SS:FFB0h` (DOSCALLS 487,
  `PTDA_CODEPAGE_TAG`), which HPFS does [OBS-RE] (unpublished notes); an
  FS_FSCTL from a test program read the word there equal to DosQueryCp's first entry [OBS] (same
  machine).
- **The `FSH_*` helpers differ from IBM's reference in places** [OBS-RE] (unpublished notes): `FSH_GETPRIORITY` answers 0FFFFh, not 1111h, and only with `PRIORITY_DISK_IO` and a
  foreground-boosted thread; `FSH_CHECKEANAME`'s bad level is 124, not 87; `FSH_WILDMATCH` answers
  8000h or 0FFFFh as well as 257 on a miss and turns a leading 05h into E5h in both strings;
  `FSH_UPPERCASE` also turns `/` into `\`; `FSH_QSYSINFO` decodes only the low byte of `index - 1`;
  `FSH_SEGALLOC` accepts flag bit 2 and refuses ring 1 with 87, ring 2 with 5; `FSH_REGISTERPERFCTRS`
  does not check its flags; with no hard-error daemon `FSH_CRITERROR` writes the raw template to the
  screen, pauses for Enter in screen group 0 and answers 4 (ACK allowed) or 3, killing nothing.
- **Mini-FSD boot:** if the new IFS has the boot mini-FSD's name it is its full version - its
  `FS_INIT` runs, the mini-FSD is terminated and unloaded, and the IFS takes the mini-FSD's slot;
  any failure there is fatal (section 2.7).
- **Shutdown:** `FS_SHUTDOWN(SD_BEGIN/SD_COMPLETE)` (section 8). The `FSH_*` surface: `drivers.md`.

**The entry-point list.** The kernel looks up 59 names, in a fixed order that is also the slot
order of the file system's control block, in classes [OBS-RE] (unpublished notes, the list read out of the 14.104a image; class rules
unpublished notes):

| class | names | rule |
|---|---|---|
| 0 | `FS_ATTRIBUTE`, `FS_NAME` and the 36 other base `FS_*` entries (`FS_ATTACH` ... `FS_WRITE`, `FS_COMMIT`, `FS_FSCTL`, `FS_FLUSHBUF`, `FS_SHUTDOWN`) | mandatory |
| 1 | `FS_OPENPAGEFILE`, `FS_ALLOCATEPAGESPACE`, `FS_DOPAGEIO` | all or none |
| 2 | `FS_SDCHGFILEPTR`, `FS_SDFSINFO`, `FS_SDREAD`, `FS_SDWRITE` | all or none |
| 3 | `FS_VERIFYUNCNAME` | optional here; required by `FSA_UNC` (the check above) |
| 4 | `FS_CANCELLOCKREQUEST`, `FS_FILELOCKS` | all or none |
| 5 | `FS_MPSAFEFLAGS2` | optional |
| 6 | `FS32_ATTRIBUTE`, `FS32_READ`, `FS32_WRITE`, `FS32_CHGFILEPTRL`, `FS32_READFILEATCACHE`, `FS32_RETURNFILECACHE` | optional, each; resolved as **flat 0:32** addresses |
| 7 | `FS_NEWSIZEL`, `FS_FILELOCKSL`, `FS_CANCELLOCKREQUESTL`, `FS_CHGFILEPTRL` | optional, each |

An absent optional entry leaves its slot 0 [OBS-RE]. `FS32_CHGFILEPTR` is not on the list, so an
IFS that exports it (IBM's JFS does) has it ignored by this kernel [OBS-RE].

**A 32-bit IFS is the 16-bit interface plus the class-6 entries.** It still exports every
class-0 `FS_*` entry as a 16:16 far routine; the kernel calls those through its locking stub, which
reads `FS_MPSAFEFLAGS2` on every call (bit `01h`: run without the big kernel lock; bit `40h`:
without the ring-0 subsystem lock; bits `10h`/`20h` the same per function on the read/write/seek
fast path) [OBS-RE] (unpublished notes, `h_fscMPStub2`, `fscAdd`). The `FS32_*` entries
are called directly as flat near calls with flat pointers: `FS32_READ`/`FS32_WRITE` from the
kernel's 32-bit file read/write workers, `FS32_READFILEATCACHE`/`FS32_RETURNFILECACHE` from KEE's
`KernReadFileAtCache`/`KernReturnFileCache`, which test the slot for 0 first [OBS-RE] (same trace
section 3). Which condition sends a read to `FS32_READ` rather than `FS_READ` is not established (section 9).

**How the 16-bit entries reach 32-bit code** - IBM's JFS IFS source (GPL, 2000) as carried by
osFree, `filesys/jfs/src/jfs/ifs/thunk.asm`, `makefile` (the `.def`), and
`filesys/jfs/src/jfs/common/include/thunk.inc` [DOC-IBM]:
- The module is linked as a `LIBRARY` (shipped `JFS.IFS` and `UDF.IFS` are LX `DLL`-typed: object
  1 = 32-bit code, object 2 = 16-bit code, then 32-bit and 16-bit data) [DOC-IBM] + [OBS-RE, object
  tables read]. It exports `FS_ATTRIBUTE`, `FS_NAME` and `FS_MPSAFEFLAGS2` from a 16-bit data
  segment, `FS32_ATTRIBUTE` from 32-bit read-only data, each `FS_xxx` as a 16-bit routine
  `fs_xxx16`, and the `FS32_*` entries as the 32-bit bodies themselves.
- Each `fs_xxx16` is a far pascal routine in a `USE16` code segment: it saves registers, loads
  `DS`/`ES` with the flat data selector, far-jumps to a label in its `USE32` code segment through
  the kernel's flat code selector, calls **`KernThunkStackTo32`**, converts each 16:16 pointer
  argument to a flat address, calls the 32-bit `FS32_xxx` body, calls **`KernThunkStackTo16`**,
  far-jumps back to the 16-bit segment and returns with the pascal `retf n`.
- **`FS_INIT` makes no KEE call and no thunk.** It runs at ring 3 in SYSINIT, loads the flat data
  selector with RPL 3, records the DevHlp entry, calls 32-bit `DosQuerySysInfo` and DevHlp
  `VirtToLin`, and defers *"stuff that can't be done at ring 3, but needs to be done at ring 0
  before thunking or calling 32-bit C code"* to a routine run on the first `FS_MOUNT` or `FS_FSCTL`.
- JFS sets `FS_MPSAFEFLAGS2` to `41h`, commented *"01h = don't get r0 spinlock; 40h = don't acquire
  subsys spinlock; FS_MPSAFEFLAGS2 is an array of 64 bits"* (`dd 41h, 0`). Calls back into a 16-bit
  device driver's Strategy-2 entry are bracketed with `KernSerialize16BitDD`/`KernUnserialize16BitDD`
  (unpublished notes).

**What it takes from KEE** [OBS-RE, import fixups of the shipped files]: `JFS.IFS` imports KEE
ordinals 10-13 (spinlocks), 20-23 and 25-27 (mutexes), 30/31 (`KernBlock`/`KernWakeup`), 40-43
(`KernThunkStackTo16/To32`, `KernSerialize16BitDD`/`KernUnserialize16BitDD`), 50/51
(`KernCopyIn/Out`), 60-64 (`KernVMAlloc/Free/Lock/Unlock`, `KernLinToPageList`) and 121/122
(Unicode conversion); `UDF.IFS` imports 20, 21, 25-27, 40-43, 50, 51, 60, 61 and 120-122. The thunk
pair (40/41) is what every 16-bit entry needs; the rest is what each file system's own code uses
[INF from the entry shape above]. Ordinal names: unpublished notes section E.3.

### 7.3 Virtual device drivers

[OBS-RE] (unpublished notes
`VDMMINIT`, `LOADVDDS`; unpublished notes)
- `DEVICE=` lines whose file is a 32-bit VDD are set aside during driver installation (section 2.1).
- After all PDDs (and after INIT COMPLETE), SYSINIT starts DOS emulation through SICG; the kernel's
  DOS-emulation initialisation loads first a **base VDD list**, then the `DEVICE=` VDDs, each with
  `_LDRLoadVDD` (load type 4, kernel reference, file closed) and then its init entry with the
  argument string.
- Init returning 0 = failure: **a base VDD's failure aborts DOS-emulation start**; a `DEVICE=`
  VDD's is only reported. A failure of the video-BIOS post-init a VDD may return unloads every VDD.
- With `PROTECTONLY=YES` DOS emulation is not started: DOS drivers are reported as not loadable
  and no VDD is loaded. If DOS-emulation start fails, the system marks itself protect-mode-only.
- VDDs import only `MVDM`, `KEE` and other VDDs (unpublished notes).
- **The base VDD list comes from the loader**, through the same `DosHlpBaseDDList` call that
  returns the base PDD list (section 1.2): its second pointer is stored in `pszzBaseVDDs` at boot, and
  `g_MVDMINIT` converts that word to a linear address and passes it as `VDMMINIT`'s
  `pszzBaseVDDs` argument [OBS-RE] (unpublished notes; decompiles
  unpublished notes). The
  loader's third list (`vbios.sys`, `vdma.sys`, `vpic.sys`, `vflpy.sys`, `vtimer.sys`, `vlpt.sys`,
  `vkbd.sys`, `vdsk.sys`, `vcmos.sys`, `vnpx.sys`; `video-stack.md` section 1.2) [OBS-RE] is the same ten
  drivers IBM lists as "all the base virtual device drivers included with OS/2" (VDD Reference,
  DDK `REF/VDD/00043`) [DOC-IBM]; IBM: *"Base virtual device drivers are loaded first, followed by
  installable virtual device drivers"* (`REF/VDD/00015`) [DOC-IBM]. One list serves both machine
  families (it is not paired like the PDD lists) [OBS-RE, `video-stack.md` section 1.2].

### 7.4 KEE (32-bit kernel extensions)

IBM's DDK header `bsekee.h` (base32 DDK) declares the **Kernel Execution Environment**: flat 32-bit
`APIENTRY` `Kern*` services - spinlocks, mutexes, `KernBlock`/`KernWakeup`, context hooks,
`KernThunkStackTo16/To32`, `KernSerialize16BitDD`/`KernUnserialize16BitDD` [DOC-IBM]. The kernel
exports them through a pseudo-module named `KEE` [OBS-RE] (unpublished notes). At task time `KernSerialize16BitDD` takes the same 16-bit driver lock as a
Strategy call (section 6.5; at interrupt time it does nothing, below) [OBS-RE] (unpublished notes). A 32-bit `PHYSDRV` file goes through
the same `DEVICE=` install path as a 16-bit PDD (section 2.1) [OBS-RE]. IBM's shipped 32-bit `OS2DASD`
keeps a 16:16 header with 16-bit Strategy/IDC entries and thunks into its 32-bit code (section 2.2)
[DOC-IBM].

**Context rules: IBM publishes none, and the kernel checks none.** `bsekee.h` marks only
individual flags as init-time-only (`VMDHIA_USER`, `VMDHA_USEHIGHMEM` of `KernVMAlloc`) [DOC-IBM];
there is no per-service table like PDD/00208. In the kernel, a KEE call is a direct flat call into
the service - it does not pass through the DevHlp router, so the router's context flags and panic
(section 5) never apply - and no KEE entry point refuses or panics on its calling context [OBS-RE]
(unpublished notes, every `Kern*` entry of 14.104a read for a
context test). Three services adapt to the context instead [OBS-RE] (same):

| service | at task time | at interrupt time | during initialisation |
|---|---|---|---|
| `KernSerialize16BitDD` / `KernUnserialize16BitDD` | take / release the 16-bit driver lock (section 6.5) | **do nothing** | do nothing until the kernel's SMP state is up |
| `KernThunkStackTo32` / `KernThunkStackTo16` | switch the task's stack | switch on a per-nesting-level save area | - |
| `KernVMAlloc` / `KernVMFree` | ordinary allocation | - | the init-time path, as `DevHlp_VMAlloc` uses then (section 2.6) |

Everything else runs unconditionally: `KernBlock` and the mutex requests go straight to the
kernel's sleep primitive with no interrupt-time test, and `KernVMLock`/`KernVMUnlock` straight to
the same workers as the DevHlp calls [OBS-RE]. What a block at interrupt time then does is not
established (section 9). **The context is the caller's to know**: KEE exports the kernel's own interrupt
nesting level as a data item, `_KernInterruptLevel` (ordinal 92; -1 at task time) [OBS-RE]
(unpublished notes section E.3; unpublished notes), and a later `bsekee.h`
carried with IBM's ACPI toolkit declares it (`KernInterruptLevel`) with `_KernSISData`,
`_KernLISData`, `_KernTKSSBase` and `_KernKEEVersion` [DOC] (osFree, `include/os3/acpitk/bsekee.h`,
an "Additions" block not in the DDK's copy; the file is (c) IBM 1998 but that block is not dated).

**What IBM's own code does** - IBM source, so [DOC-IBM]:
- *"On OS/2 the KernVMUnlock() call is not allowed during interrupt time"*; JFS defers the unlock
  to thread time (IBM's JFS IFS source as carried by osFree, unpublished notes).
- At interrupt time - JFS's Strategy-2 completion callback (unpublished notes) and its
  I/O-done paths (unpublished notes, *"called by thread or interrupt handler"*) - JFS calls
  `KernThunkStackTo32`/`To16`, `KernAcquireSpinLock`/`KernReleaseSpinLock` and `KernWakeup`.
- `KernBlock` is called only on paths its comments mark *"called by thread"* (unpublished notes).
- `OS2DASD` brackets every call into a 16-bit adapter driver with `KernSerialize16BitDD()` -
  *"OK to call even if already serialized"* - and `KernThunkStackTo16`, and calls its
  trace services only on a flat stack: *"If it isn't KernPerfSysTrace and/or KernRASSysTrace will
  trap"* (DDK unpublished notes).

So the practical rule, by analogy with the DevHlp table and IBM's usage: spinlocks, `KernWakeup`,
`KernArmHook`, the thunks and the serialisation bracket are interrupt-safe; `KernBlock`, the mutex
requests and the VM lock/unlock/alloc/free calls are task-time only [INF].

**What the services do, beyond their signatures** (unpublished notes; measured on a 14.104a SMP install
by a 32-bit LX physical device driver calling KEE from task-time generic IOCtls) [OBS-RE] [OBS]:
- **The stack thunks move EBP with ESP.** `KernThunkStackTo32` adds the 16-bit stack's base to both ESP and EBP and
  loads the flat stack selector; `KernThunkStackTo16` subtracts it from both. A frame pointer set on the 16-bit stack
  stays valid across the thunk (OS2DASD reads `[ebp+4]` right after To32). EAX and EDX come back changed.
- **A mutex's word 0 is its exclusive owner's `TaskNumber` DWORD**, whose high word is 1 under the per-thread low
  word, plus 10000h per nested request: after one nested `KernTryRequestExclusiveMutex` the high half reads 2. A
  shared holder adds 10000h with the low half 0; +4 counts waiting readers, +6 waiting writers.
- **`KernBlock` is a single-wakeup sleep**, so a DevHlp `ProcRun` on the same id does not find it; `KernWakeup` always
  looks for single-wakeup sleepers. With `WAKEUP_ONE`, the count pointer receives the woken thread's TCB address, not
  1; without it, the count.
- **`KernCopyIn`/`KernCopyOut` on a bad address** answer 115 to the driver; the program's call that reached the driver
  (`DosDevIOCtl`) then answers 87, and no exception reaches the program.
- With no tracing active `KernRASSysTrace` answers -1 and `KernPerfSysTrace` 0. `KernVMUnlock` of an unlocked handle
  answers 6; `KernVMFree` of a freed block 87. `KernAllocSpinLock` writes 0FFh to the lock DWORD; acquiring sets its
  byte +3 to 0FFh.
- **Loader:** an import of an empty KEE (or MVDM, FSHELPER) slot resolves; a `DEVICE=` driver that imports FSHELPER is
  not loaded.
- **The file calls (100-104)** `[OBS-RE]` `[OBS]` (unpublished notes). `KernLockFile`
  answers 6 for any device - a `DosOpen`'d `\DEV\CON` and a program's handle 0 both measured - and for a handle not
  open, and leaves a file's SFT entry busy; the handle it returns is accepted by the other four only while the entry
  is busy (else 6, `KernTestFileCache` FALSE). `KernReadFileAt` depends on the file system's kind: a 32-bit FSD gets
  the full QWORD offset (bit 63 answers 131) and the count asked for; a 16-bit FSD, the built-in FAT among them, gets
  only the low DWORD (bit 31 answers 131) and is read **to the end of the file whatever count was asked** - 14 bytes
  for 4 at offset 2 of a 16-byte FAT file, written into the caller's buffer. Either way the shared file pointer is left
  after the data.

**The base-driver INIT-time file calls, DevHlp 7Fh-82h** `[DOC-IBM]` `[OBS-RE]` `[OBS]` (DDK `dhcalls.h`; unpublished notes). OpenFile, CloseFile, ReadFile and ReadFileAt take ES:DI pointing to a FILEIOINFO
whose Length word is the size of its Data part (8, 2, 8, 0Ch); any other Length is carry with AX 18h. There is no
handle: one file is open at a time. OpenFile searches the boot volume for the name, then `\OS2\` + the name, then
`\OS2\BOOT\` + the name, and reports only the low WORD of the size (a 70000-byte file reads as 4464). Success and
failure are the carry flag; AX beside it is not a code (a missing file's AX is 7Fh, a good CloseFile's 80h - the
function number). With no mini-FSD (a FAT boot volume), ReadFile and ReadFileAt stop the system when no file is open,
for a count over 64 KB, or into a buffer at or above 1 MB.

### 7.5 Platform Specific Drivers (`PSD=`)

[OBS-RE] (unpublished notes) + [DOC-IBM] (the
SMP programming addendum, cited there)
- Loaded through the module loader during ring-0 init, **before** any base driver; the parameter
  string is copied for the PSD; the mandatory exports are `PSD_INSTALL`, `PSD_DEINSTALL`,
  `PSD_INIT`; **the first PSD whose `PSD_INSTALL` succeeds is used**.
- **No PSD:** the kernel runs uniprocessor on its own 8259/timer defaults (contradicting the
  addendum's "OS/2 requires a PSD"). With one: `PSD_INIT` (failure fatal), processor count, then
  each secondary processor is started.
- At end of init: advanced interrupt mode is entered if the PSD supports it, and init-only PSD
  functions are disabled.
- Calling convention and the full function list: unpublished notes; the `.PSD` files: `drivers.md`.

---

## 8. Shutdown: what drivers receive

`DosShutdown(0)` [OBS-RE] (unpublished notes, 14.104a W4; mode 0 and 1 also measured
on WSeB 14.089 [OBS]):

1. The shutdown state is set and in-flight built-in-file-system calls are drained.
2. The file-system lock takes effect; every installable file system's entry points are replaced by
   blocking stubs (read, write, seek and FS-info keep filters that let the shutdown and swapper
   threads through).
3. **SHUTDOWN (1Ch), function 0 (start)** to every header that is **level 2**, or **level 3 with
   capability bit 0** - IBM's rule (PDD/00184-00187) [DOC-IBM] - **among the headers the walk
   reaches, which are character headers only** (below).
4. **`FS_SHUTDOWN(SD_BEGIN)`** to every file system; every open file is committed; buffers flushed;
   FAT dirty bits cleared; **`FS_SHUTDOWN(SD_COMPLETE)`**.
5. **SHUTDOWN (1Ch), function 1 (end)** to the same drivers.

IBM: *"Each device driver receives this packet twice for each device header"*, and swapping is off
before the call, so the handling code must be resident or locked (PDD/00187) [DOC-IBM]. After the
lock, ordinary file-system calls block for ever; **`DosDevIOCtl` on a device handle opened before
the shutdown still reaches its driver** [OBS-RE] + [OBS] (unpublished notes). Mode 1 only
flushes buffers; drivers are not called [OBS-RE] + [OBS]. No driver is unloaded or sent DEINSTALL
at shutdown [INF: nothing in the sequence does so].

**What the walk visits.** `NotifyDevs` does **not** follow `SDevNext`. It enumerates records with
`GetNextDev` (a wrapper on the kernel's record-pool search, `Rmp_FindN`), keeps a record only if
its byte `+9` has bit 0 set, and follows the record's far pointer at `+0` to the header it then
tests and sends 1Ch to [OBS-RE] (decompiles unpublished notes in four held kernel builds:
`pmmerge/ghidra/out/os2krnl{d_smp_astrict,b_smp_hstrict,b_uni_hstrict,d_uni_astrict}/decompiled_16/`;
14.104a's `GetNextDev` calls `h_Rmp_FindN`, unpublished notes). The DevHlp
save/restore broadcast (`w_DDSaveRestore`, command 20h) uses the same walk. That record shape is
the **character-device name table's** - `+0` header pointer, `+9` class, class 1 = an entry made
from a device header (section 3.2; unpublished notes) [OBS-RE] -
and the bytes confirm the pool: `GetNextDev` passes the name table's own handle, the one the
table's creator allocates and every name-table lookup uses, with a zero key length (match any
record) [OBS-RE] (14.104a `GetNextDev`, `CharDevTabInit`; unpublished notes). So the walk visits the **class-1 entries of that table**:
pseudo-character devices attached to a file system (class 2) are skipped. Consequences [OBS-RE]: a
**block** header is never sent SHUTDOWN through itself, since none is ever entered; a character
header replaced by a same-named `DEVICE=` driver (section 3.3) is not visited; nor is a base character
header whose name was already entered from an earlier header in the chain (section 3.2), nor one whose name
the table refuses. IBM's own storage manager is consistent with the first: `OS2DASD`, a block
driver, carries a second, character header that also *"allows the driver to handle the Shutdown
command for cleanup operations"* (DDK `dmheader.asm`) [DOC-IBM].

**Order.** Both phases are the same forward walk of the table in its **storage order** (the
function code is the only difference) [OBS-RE]. That order is the order of entry, barring a hole
left by a file-system detach (section 3.2; section 9), so drivers
receive SHUTDOWN, start and end alike, in this order [INF: composed from the [OBS-RE] steps in section 3.1
and section 3.2]: `NUL`, `CON`, `OEMHLP$`; then the character headers of the base drivers, **the
last-loaded file first**, each file's headers in the file's own order; then the `DEVICE=`
character drivers in CONFIG.SYS processing order - except that a `DEVICE=` header that replaced a
same-named one is visited **at the replaced one's position**. Each header in that sequence is
then sent the command only if its level and capability qualify (step 3). There is no reverse
pass, and no ordering by driver kind or name. IBM documents no order (PDD/00184-00187) [DOC-IBM].

**Swapping.** IBM's 1Ch page says swapping is turned off before drivers get the command
(PDD/00187) [DOC-IBM]. The shutdown sequence read contains no such step, and the file-system gates
installed in step 2 let a thread whose `TCBfSwapping` is set **through**, so swapper I/O continues
after the lock [OBS-RE] (unpublished notes). Whether paging is
stopped elsewhere is not established (section 9).

---

## 9. Not established

Each item names what would settle it, and what has already been searched without an answer, so the
search is not repeated. (The BASEDEVINIT packet length and `+0x18`, the source of the base VDD
list, and `TickCount`'s count of 0 were answered from held material and moved into section 2.4, section 7.3 and
section 6.2; which list `DosHlpBaseDDList` returns for each `AL` into section 1.2.)

1. **Whether a request really reaches a failed character header of a kept base file**, and whether
   `DevHlp_AttachDD` finds one. The bytes show it stays linked, named and unmarked (section 2.5); that a
   packet then arrives is inference. Settle: boot a two-header base driver that fails one header,
   open its name and walk the chain in the kernel debugger; read `DevHlp_AttachDD`'s lookup.
   *Searched:* `InitBASEDEVs`, `InitBaseList`, `BaseDevInit`, `SetPMCharDevEntries`,
   `AddRecFromDevHdr`, `DevIOCall` (14.104a bytes, unpublished notes).
2. **The remaining KEE and 32-bit-IFS edges** (section 7.2, section 7.4). The object rule, KEE's lack of
   context checks and the IFS entry-point classes are answered there; open are: what a `KernBlock`
   (or other sleeping KEE call) at interrupt time actually does, since nothing refuses it; whether a
   ring-3 `DEVICE=` INIT or `FS_INIT` can call a KEE entry at all (IBM's JFS makes no KEE call there and
   defers its ring-0 set-up, but says nothing about KEE); and what sends a read or write down an IFS's
   `FS32_READ`/`FS32_WRITE` rather than its 16-bit entry. Settle: read `_TKSleep`'s path when
   entered on an interrupt stack and the page protection of the kernel's 32-bit code object at
   SYSINIT time, or measure both with a test driver under the kernel debugger; read the callers of
   `w_Big32IO`'s read/write arm for the test that selects it. *Searched:* DDK `bsekee.h` (flag-level
   notes only); every `Kern*` decompile of 14.104a for context reads and panics
   (unpublished notes); IBM's JFS and `OS2DASD` sources; `READ_WORKER`,
   `w_Big32IO` (thin decompile).
3. **Whether a hole in the character-device name table ever reorders the shutdown walk** (section 3.2, section 8).
   The pool and the placement rule are read (section 8): entry order, except that a later entry can fill
   a hole left by a file-system attach failure or detach. Whether any such removal happens before or
   during `DEVICE=` processing - the only time a class-1 entry is added - is not established; nor,
   from the bytes alone, which headers the level test admits on a given system. Settle: a
   kernel-debugger breakpoint on the Strategy call with command `1Ch` during `DosShutdown(0)` on a
   real system, logging each header in turn. *Searched:* `GetNextDev`, `NotifyDevs`, `Rmp_FindN`,
   `Rmp_Add`/`Rmp_Srch`/`Rmp_Link`, `AddCharDevEntry`, `RemCharDevEntry` and its callers (14.104a
   bytes, unpublished notes "The shutdown walk, read in the bytes").
4. *(Answered: the meaning of `ProcBlock`'s `AL = 5` / the sleep result 3000 - PM event posted -
   and what the C wrapper returns for it are now in section 6.4.)*
5. **Whether paging is stopped before SHUTDOWN**, as PDD/00187 states - the bytes read show the
   swapper let through the file-system gates (section 8). Settle: read the swapper's own shutdown test,
   `DisableFSDs` past `000c:29de` and the flush helpers' bodies, or measure. (`000c:287a` is the
   start of `NotifyDevs`, not an unread step of `w_Shutdown`; section 8.)
   *Searched:* unpublished notes, the 1Ch pages.
6. **The edges of the LVM drive-letter path** (section 3.4, section 7.1; the mechanism is established). Open:
   whether a hidden volume's unit uses up one of the rediscover count's new units (inferred from
   the code; a live rediscover with a hidden volume would settle it); the names of the `OS2LVM`
   volume flags that order its letter passes; who calls the kernel's removable-media rediscover
   (no static caller; a kernel-debugger breakpoint would settle it); same-extension `BASEDEV=`
   order and units 0/1 = `A:`/`B:`, both inferred. Read in 14.104a SMP only; the uniprocessor
   kernel was not compared. *Searched/read:* unpublished notes.
7. **The Resource Manager's remaining edges** (section 1.2, section 3.5; the kernel interface is established).
   The snoop levels and the `SNOOP.LST`/`PREVIOUS.DAT` formats are now established
   (`hardware-detection.md` section 2, section 4), and so are the snooper entries' 6 bytes at offset 4 (the tag
   `"Snoop\0"`). Open: the 6 bytes at offset 4 of the kernel's own configuration entries; whether a failed Resource-Manager-aware driver really
   suppresses the next unaware driver's node (a live `RMVIEW` comparison would settle it). Read in
   14.104a SMP only. *Read:* unpublished notes.

---

## See also

- `drivers.md` - the device header, request packets, Strategy commands, DevHlp lifecycle calls,
  BASEDEV extensions, PSDs, the `FS_*`/`FSH_*` interfaces.
- `boot-sequence.md` - the boot stages this document's section 1 sits inside.
- `kernel-services.md` - the DevHlp catalogue.
- `device-monitors-and-debug.md` - device monitors, which hook character drivers.
- `display-driver-install.md`, `video-stack.md` - the video drivers' own install and the loader's
  implicit driver lists.
- `config-and-environment.md` - how CONFIG.SYS is parsed into the lists section 1 consumes.
- `dasd-volume.md` - block devices, DPBs and VPBs.
