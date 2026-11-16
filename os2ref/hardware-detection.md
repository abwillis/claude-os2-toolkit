# Hardware detection: snoopers, the Resource Manager's trees, and `PREVIOUS.DAT`

How OS/2 (Warp 4 / WSeB 4.5 era, `RESOURCE.SYS` v10.058) finds out what hardware a machine has,
where it records that, how drivers read it back, and how it is carried from one boot to the next.
The kernel side of the Resource Manager (the `RESMGR$` load notifications and the `BASEDEV=`
hand-over) is in `driver-lifecycle.md` section 1.2 and section 3.5; this document starts where that one stops.

*Written 2026-10-21. Sources, in the order used:*
- *[DOC-IBM] the DDK: `base/h/rmbase.h` (all structures and constants), `rmioctl.h`
  (`RM_NODE`, `RM_GETNODE_*`, `RM_ENUMNODES_*`, `RM_COMMAND_*`), `rmcalls.h`,
  `base/src/dev/resource/rmcalls/rmlib.h` (the `CallRM` index table 0-39), the PAS16 sample snooper
  `base/src/snooper/mme/pas16/` (unpublished notes, `readme.txt`), IBM's COM.SYS source
  unpublished notes, and the REF/PDD Resource Manager pages (00321-00331, 00385-00393,
  00538-00541, 00628-00639).*
- *[OBS-RE] read out of the shipped binaries where the DDK has no source: `RESOURCE.SYS`,
  `PCIBUS.SNP`, `ISAPNP.SNP`, `PNP.SYS`, `RESRV.SNP`, `RMINFO.DLL`, `SVDETECT.EXE`, `PNP.DLL`, and the
  SMP 14.104a kernel for the Alt+F1 keys. The write-up listing every routine read is
  unpublished.*
- *[OBS] `RMVIEW.EXE` captures of every view, and the `\OS2\BOOT\PREVIOUS.DAT` the boot wrote, on a
  VirtualBox guest running WSeB 4.50 (retail SMP kernel), 2026-10-21, once on a normal boot and once
  on a boot with `PREVIOUS.DAT` removed. Also `PREVIOUS.DAT` files from a QEMU guest and a UEFI
  desktop machine ( booting OS/2 through a CSM built from SeaBIOS), decoded with an unpublished tool. Every hardware record in the desktop machine's files was carried
  over from the VirtualBox machine the image was installed on, so no snooper output from real
  hardware has been observed.*

The DDK holds no Resource Manager or snooper source beyond the PAS16 sample and the COM.SYS helper,
so most of section 2-section 6 is [OBS-RE].

---

## 1. The model in one screen

1. **`RESOURCE.SYS` builds the skeleton tree itself at its own INIT**, before any snooper runs:
   the physical-device root, the CPU, the planar chipset, the ISA/EISA/MCA bus, an empty PCI bus
   adapter when the machine reports PCI, the logical-device tree, and two **detected** roots,
   `PREVIOUS` and `CURRENT` (section 2) [OBS-RE].
2. **Snoopers are ordinary base device drivers** that the Resource Manager places at the head of
   the kernel's `BASEDEV=` load list (section 3). Each one probes, records what it finds, and fails its INIT
   with `8115h` so the kernel unloads it. `ISAPNP.SNP` is the exception and stays resident [OBS-RE].
3. **What a snooper records is a *detected* node, not an adapter.** `RMCreateDetected` takes a
   `DETECTEDSTRUCT` (an `IDType` and `DeviceID`/`FunctionID`/`CompatibleID`), a resource list and
   optionally an `ADJ_DRIVER_DATA` adjunct naming the driver to use; the node goes under
   `HANDLE_CURRENT_DETECTED`, owned by the snooper's driver node [DOC-IBM `rmbase.h`, REF/PDD].
4. **Real drivers look detected nodes up by ID** (`RMDevIDToHandleList` on `HANDLE_CURRENT_DETECTED`,
   then `RMGetNodeInfo`) and then create their own **adapter and device** nodes. Those are what
   `RMVIEW /P` shows (section 5) [DOC-IBM unpublished notes].
5. **Detected nodes persist through `\OS2\BOOT\PREVIOUS.DAT`**, written at ring 3 by `RMINFO.DLL`
   (section 4). `RESOURCE.SYS` reads it at the next boot into the `PREVIOUS` tree; at **snoop level 0** it
   also copies those entries into `CURRENT` *instead of* running the listed snoopers [OBS-RE].
6. **The kernel reads no Resource Manager table.** Its only traffic with `RESMGR$` is the load
   control in `driver-lifecycle.md` section 1.2 and section 3.5 [OBS-RE].

## 2. The tree `RESOURCE.SYS` builds, and the boot-time order [OBS-RE]

`RESOURCE.SYS`'s INIT builds, in order:
1. The root, `PDEV Physical Device Tree`.
2. `CPU_#` with `386`/`486`/`586`/`686`, or `CPU_0 ???` when the CPU code is outside 1-4.
3. The planar chipset under `Local_Bus`: `PIC_0`/`PIC_1`, `DMA_CTLR_0`/`DMA_CTLR_1`, `TIMER`, `RTC`,
   `VGA`, with their fixed ports.
4. One of `ISA_Bus`, `EISA_Bus` or `MCA_Bus`, chosen from the machine-information bits.
5. `PCI_Bus_0` when the PCI bit (`10h`) is set. This is an empty adapter: `RESOURCE.SYS` itself does
   no configuration-space access.
6. `LDEV Logical Device Tree`, with the classes `DASD`, `CDROM`, `SERIAL`, `PARALLEL`, `TAPE`.
7. The detected roots `PREVIOUS` and `CURRENT`.
8. The snoop level (section 4.1). On an MCA machine, or under a kernel older than `141Fh`, the level is
   forced to 4 (off). At level 4 `RESOURCE.SYS` registers the BIOS ROM adapter itself, because no
   snooper will.

Then, inside the kernel's `BASEDEV=` loop (the 20h/21h hand-over), the snoopers load first:

```
ISAPNP.SNP                         unless level 4
each active line of SNOOP.LST      unless level 0 or 4
PNP.SYS                            unless level 4
then every CONFIG.SYS BASEDEV=, in the kernel's extension order
```

`SNOOP.LST` is the file's real name. As shipped it ends with `PCIBUS.SNP`, after the comment
"Place additional snoopers above this line", so **PCI is probed after every legacy snooper**. That
agrees with the PAS16 readme's "all legacy snoopers, then the PCI snooper, then ISA PnP" [DOC-IBM];
the "ISA PnP last" part is met by `ISAPNP.SNP` isolating cards first and configuring them later
through its resident interface (section 3.2).

**`SNOOP.LST` parsing.** `;` starts a comment to end of line; CR becomes NUL; LF or `1Ah` ends a
line; each remaining non-empty line becomes one list entry in file order, used verbatim as the
file name. **Nothing is trimmed**, so a leading blank becomes part of the name. Each snooper entry
carries the 6-byte tag `"Snoop\0"` where kernel list entries carry their own 6 bytes [OBS-RE].

## 3. What each snooper records [OBS-RE]

### 3.1 `PCIBUS.SNP` - PCI enumeration

- **How it reads PCI.** No direct configuration-space I/O (`CF8h`/`CFCh`) and no PCI BIOS
  `INT 1Ah`. It attaches to `OEMHLP$` (`DevHlp_AttachDD`) and far-calls its IDC entry with a
  generic IOCtl packet, function `0Bh` (`OEMHLP_PCI`): subfunction 0 queries the BIOS (last bus
  number at data `+4`), 3 reads and 4 writes a register (`bus`, `dev*8+fn`, register, size 1/2/4).
  The packet's category byte is 0, where the documented application IOCtl is category 80h; that
  `OEMHLP$` ignores the category on the IDC path is inferred, not read [INF].
- **The walk.** For each bus and device 0-31: read dword 0 (`FFFFFFFF` = absent), then the header
  type at `0Eh`. If bit 7 is set, functions 0-6 are scanned, otherwise only 0. **Function 7 of a
  multifunction device is never scanned** (the function count is returned as 7, not 8).
- **The record**, one detected node per function present:
  - `IDType = 2` (`RM_IDTYPE_PCI`).
  - `DeviceID = FunctionID = CompatibleID = vendor << 16 | device` (so `8086:7111` is `80867111h`).
  - Name `"PCI Device CC-SS-PP"`: base class, sub-class and programming interface from `0Bh`, `0Ah`,
    `09h`. **Hex digits A-F print as K-P** (a nibble above 9 gets `+11h` instead of `+7`), so class
    `0Ch` shows as `0M` and prog-IF `8Ah` as `8K`. This is visible in real captures.
  - **No adjunct**: bus, device and function numbers are recorded nowhere, so a PCI driver must
    still locate its device itself through `OEMHLP$`.
  - Resources, each allocated under `PCIBUS.SNP`'s own driver handle and then attached to the node:
    the IRQ (only when the interrupt pin `3Dh` is non-zero and the line `3Ch` is below 22; recorded
    shared, with the pin), I/O BARs (`base & ~3`, exclusive, 16 address lines), 32-bit memory BARs
    (`base & ~0Fh`, exclusive). BARs are sized by writing `FFFFFFFF` and restoring, **without
    disabling the command register**. **64-bit memory BARs are skipped, both halves**, and the
    expansion-ROM BAR is never probed.
- It creates **no adapter or device nodes**. Its driver node is `"PCIBUS.SNP"`, `"PCI Bus Enumerator
  Driver"`, vendor `"IBM OS/2"`, `DRT_SERVICE`/`DRS_SNOOPER`.

### 3.2 `ISAPNP.SNP` - ISA Plug and Play isolation (resident)

- Character device `ISAPNP$ ` with an IDC entry. Its Resource Manager driver node calls itself
  **`"PNP.SYS"` / `"PnP Device Driver"`**, which is easy to confuse with the separate file
  `PNP.SYS` (section 3.3).
- At INIT it claims the read-data port (first `20Bh`, three ports), the ADDRESS port `279h` and
  WRITE_DATA `A79h`, creates an adapter `"PnP Isolation/Detection Driver"` with a device `PnP_0`, and
  runs the standard ISA PnP protocol: the 32-byte initiation key, reset, wake, serial isolation of
  each card's 72-bit identifier, CSN assignment, then each logical device's resource data. It makes
  up to 8 isolation passes per read-data port and moves the port by 4 once if nothing is found.
  With no cards it releases the isolation ports but stays resident.
- **Per logical device** it records `IDType = 1` (`RM_IDTYPE_EISA`, which `rmbase.h` documents as
  also covering ISA PnP), `DeviceID` = the logical device's compressed EISA ID, `CompatibleID` from
  the compatible-ID tag, `FunctionID = 0`, the ANSI identifier string as the name (else
  `"PnP adapter, no descriptive text"`), and an `ADJ_DRIVER_DATA` adjunct with the placeholder
  driver name `XXXX.ADD`.
- It arbitrates resources against the Resource Manager, reuses the previous boot's configuration
  (looking devices up in `PREVIOUS`), and reconfigures after an APM resume (it attaches to `APM$`).
- Resident interface: **IOCtl category `91h`** (the same table is reachable through IDC), functions
  `00h` GetISAConfig, `01h` CompleteConfig, `02h` GetNumCards, `03h` GetCardDataSize, `04h`
  GetCardData, `05h` GetCardLdevCount, `06h` GetCardLdevs, `07h` GetLdevConfig, `09h` ActivateLDev,
  `0Bh` GetEscdData.
- Its PnP BIOS / ESCD path has no caller that sets the BIOS entry point; whether it is dead was not
  proven [unverified].

### 3.3 `PNP.SYS` - the ROM BIOS snooper

Despite its module description ("ISA PnP Configurator Device Driver"), `PNP.SYS`'s body is the ROM
scanner. Its driver node is `"BIOS.SNP"` / `"ROM BIOS Snooper"`. It creates adapter `BIOS_ROM`
(memory, planar, 8-bit), scans `C0000h`-`DFFFFh` in 2 KB steps for the option-ROM signature
`55AAh` (size = byte 2 x 512, capped at 64 KB), and records each ROM as a shared memory resource on
that adapter. With nothing found it destroys its driver node. It exits with `8115h`, and runs after
the `SNOOP.LST` snoopers.

### 3.4 `RESRV.SNP` - user-reserved resources

No probing. It reads the arguments of every CONFIG.SYS line naming `RESERVE.SYS` through
`RMGetCommandLine` (`CallRM` 36; this is why the Resource Manager keeps the `DEVICE=` list the kernel
hands it), parses `/IO: /P: /DW: /IRQ: /DMA: /MEM:` with the flags `/EXC /MUL /SHA /GY`, and
allocates each resource under its driver `"RESERVE.SNP"` / `"IBM Reserve Snooper: User Reserved
Resources"` (`DRT_SERVICE` subtype 1) and attaches it to a detected node. **These reservations do
not block drivers**: the Resource Manager waives every snooper-owned resource for a requester that
is not a snooper (section 7.3), so they keep only later snoopers off the hardware. What blocks drivers is
`RESERVE.SYS` itself, an ordinary base driver that reads the same line, allocates the same items
under its own driver node, and stays loaded only if one succeeded (unpublished notes). Its grammar (section 3 there): `/IO:` and `/P:` hex base and length
with any one separator, `/MEM:` a hex paragraph (so below 1 MB) and a 16-bit length, `/IRQ:` and
`/DMA:` decimal; at most one attribute (`/EXC` 1, `/MUL` 2, `/SHA` 4, the undocumented `/GY` 10h)
and one `/DW:` (10 kept, any other value 16) per item, each applying to the item before it; a
malformed line reserves nothing.

### 3.5 The legacy snoopers

`IBMKBD.SNP`, `IBM1FLPY.SNP`, `MOUSE.SNP` and `SERIAL.SNP` were not disassembled; their records are
known from real `PREVIOUS.DAT` files and `RMVIEW` captures [OBS]. Each writes one `RM_IDTYPE_EISA`
detected node with a fixed PnP ID and an `ADJ_DRIVER_DATA` adjunct naming the driver:

| Snooper | Detected node | ID | Driver named | Resources (VirtualBox guest) |
|---|---|---|---|---|
| `IBMKBD.SNP` | "IBM Keyboard Controller" | `PNP0303` | `IBMKBD.SYS` (base) | I/O 60h, 64h shared; IRQ 1 |
| `IBM1FLPY.SNP` | "IBM Floppy Controller" | `PNP0700` | `IBM1FLPY.SYS` (base) | IRQ 6; I/O 3F0h-3F5h, 3F7h; DMA 2; I/O 370h-375h, 377h; all multiplexed |
| `MOUSE.SNP` | "AUX_0 PS/2 Auxiliary Device Controller" | `PNP0F03` | `MOUSE.SYS` (loadable) | IRQ 12 shared; I/O 60h, 64h |
| `SERIAL.SNP` | "Serial Device" | `PNP0500`, compatible `PNP0500` | `COM.SYS` | I/O 3F8h-3FFh (10 address lines); IRQ 4 |

The other shipped snoopers (SCSI, RAID, audio, network, PCMCIA, parallel, infrared) were surveyed
by their strings only; several carry `LEGAxxx` IDs, IBM-assigned pseudo-EISA IDs for legacy devices
without a PnP ID [OBS-RE, strings only].

## 4. Snoop levels and `PREVIOUS.DAT`

### 4.1 Levels [DOC-IBM enum, OBS-RE behaviour]

`rmbase.h` defines `SNP_NO_RISK` ... `SNP_WARP_RISK` = 0-4, with `SNP_FLG_DEFAULT` and
`SNP_FLG_NEXTBOOT` selecting the permanent or the one-boot value [DOC-IBM]. What `RESOURCE.SYS`
does with them [OBS-RE]:

| Level | `ISAPNP.SNP`, `PNP.SYS` | `SNOOP.LST` | Records from `PREVIOUS.DAT` |
|---|---|---|---|
| 4 | not loaded | not loaded | not loaded; `RESOURCE.SYS` registers the BIOS ROM itself |
| 0 | loaded | **not loaded** | **copied into `CURRENT`** as if detected now, and kept under `PREVIOUS` |
| 1-3 | loaded | loaded | kept under `PREVIOUS` only |

Levels below 3 also relax conflict checking between detections; that was not read in full
[unverified].

**Where the level comes from.** `RESOURCE.SYS` reads the **first word of `PREVIOUS.DAT`**; a missing
file, or one shorter than 3 bytes, means level 3. A `/SL:d` argument overrides it, with the digit
mapped to internal level `(d + 4) mod 5`: `/SL:0` = 4 (off), `/SL:1` = 0, `/SL:2` = 1, `/SL:3` = 2,
`/SL:4` = 3 (full detection). Any other character leaves the file's level in force [OBS-RE].

**The kernel always supplies `/SL:`.** It holds the string `"/SL:N"` in its init data and appends it
to `RESOURCE.SYS`'s command line when it loads that file (`CheckCmdLine`, called from the implicit
base-list load) [OBS-RE, SMP 14.104a]. The Alt+F1 recovery menu overwrites the `N`:

| Key | Digit written | Internal level | Effect |
|---|---|---|---|
| none | `N` | from `PREVIOUS.DAT` | - |
| F5 "Enable full hardware detection" | `4` | 3 | every snooper runs; restored records stay under `PREVIOUS` only |
| F6 "Disable hardware detection" | `0` | 4 | no snoopers |
| F7 (not on the menu) | `2` | 1 | - |
| F8 (not on the menu) | `3` | 2 | - |

After the key the boot continues with the current CONFIG.SYS. The menu text is
`\OS2\BOOT\ALTF1TOP.SCR`. Internal level 0 cannot be chosen from the menu; it comes from the file
(section 4.3).

### 4.2 File format [OBS-RE, confirmed against real files]

```
+0  u16  next-boot level   (SNP_FLG_NEXTBOOT)  - the only word RESOURCE.SYS reads
+2  u16  default level     (SNP_FLG_DEFAULT)
+4  records, each the RM_GETNODE_DATA that RMGetNodeInfo returns (rmioctl.h),
    with every pointer rewritten as an offset from its RM_NODE:
      u32 RMNodeSize                 (5..4096; below 5 ends the file)
      RM_NODE { u32 VersionInfo (C9h), u32 NodeType (4 = driver, 5 = detected),
                u32 DriverHandle, u32 -> DRIVERSTRUCT or DETECTEDSTRUCT, u32 -> RESOURCELIST }
      then the structure, its strings, its adjunct chain, and
      RESOURCELIST { u32 count; RESOURCESTRUCT[count] }   (20 bytes each)
```

The writer emits a driver record just before that driver's **first** detected record, so a driver
that detected nothing is not in the file. On restore a driver node gets `DRF_PREVIOUS` (2) in its
flags and a detected node gets `DS_PREVIOUS_BOOT`; at level 0 a second copy of each detected node,
with the flag clear, goes under `CURRENT`. Both copies hang on the one restored driver node.

### 4.3 Who writes it, and why most machines stay at level 0 [OBS-RE, OBS]

`RESOURCE.SYS` cannot write the file: its `CallRM` slots 37-39 (`RMSetSnoopLevel`,
`RMSaveDetectedData`, `RMDeleteDetectedData`) are null. The writer is **`RMINFO.DLL`** at ring 3. It
builds `?:\OS2\BOOT\PREVIOUS.DAT` from the boot drive (or from the installer's `TARGETPATH`
variable), enumerates the `CURRENT` detected tree, and writes each node's `RMGetNodeInfo` data.

Two callers:
- **`PNP.DLL`**, the Workplace Shell Hardware Manager class DLL, on **every desktop start**: its
  `_DLL_InitTerm` calls `InitializeRM`, which gets the default level, calls
  `RMSaveDetectedData`, and then sets next = default; if the save returns `10h` (fewer than two
  detected nodes, or no drive) it sets level 4 for both.
- `SVDETECT.EXE` ("Save Detect Data Utility"), which does the same; what runs it was not found.

**The consequence.** `RMSaveDetectedData` starts both header words at 0 and overwrites them only
from an existing file. So the first desktop start after a boot without the file writes header
`0, 0`, and from then on every boot runs at **level 0**: the `SNOOP.LST` snoopers (`PCIBUS.SNP`
included) never run again, and the restored detections are re-saved unchanged at every desktop
start. Removing the file, or pressing F5, buys exactly one full-detection boot; the save after it
again writes `0, 0`.

Observed on the VirtualBox guest [OBS]:
- On the normal boot the file's header was `0, 0`; `RMVIEW /DC` and `/DP` were identical apart
  from their title; each detected node appeared twice in `/DA` (under `PREVIOUS` and `CURRENT`);
  and the snooper driver nodes showed a blank flag (`DRF_PREVIOUS`, which `RMVIEW` has no word
  for), while live drivers showed `STATIC`.
- After removing the file and rebooting: `/DP` was empty, `/DC` was byte-identical to the normal
  boot's, the snooper drivers showed `STATIC`, and `RESERVE.SNP` (from `SNOOP.LST`) appeared in
  `/DA`. The newly written file had header `0, 0` and differed from the old one only in the five
  snooper driver records' flags (0 live, 2 restored); every detected record and resource was the
  same.

**The lock-in carries hardware between machines.** An image installed on one machine and booted on
another keeps reporting the first machine's detections at level 0. The UEFI desktop machine's files
held only the VirtualBox install machine's records: its i440FX PCI functions, a PS/2 mouse
(`PNP0F03`) that machine does not have, and COM1 as `PNP0500` where its ACPI reports `PNP0501`
[OBS].

**A known failure.** On a QEMU guest and on the desktop machine, the file grows by one `MOUSE.SNP`
driver-and-detected pair (`AUX_0`, `PNP0F03`) on every boot, until the Resource Manager's 64 KB heap
fills and `RESOURCE.SYS` traps [OBS]. Each new pair carries a live (flags 0) driver node created
during the `DEVICE=` phase. On the desktop machine it appeared even on a boot with the snooper list disabled,
on hardware with no PS/2 controller, so it is a fixed claim rather than a detection [INF]. Which
component creates it was not established [unverified]. The VirtualBox guest's file does not grow.

## 5. How the tables are read

**By drivers** [DOC-IBM unpublished notes, IBM's COM.SYS]:
1. Skip detection on systems too old to have snoopers (COM.SYS tests the OS version).
2. `RMConvertID(&id, "PNP0500", RM_CONVERT_TO_ID)`.
3. `RMDevIDToHandleList(RM_IDTYPE_EISA, id, ..., SEARCH_ID_DEVICEID, HANDLE_CURRENT_DETECTED, list)`,
   then again with `SEARCH_ID_COMPATIBLEID`.
4. `RMGetNodeInfo` on each handle, and walk its resource list for I/O and IRQ.
5. A trial `RMAllocResource` / `RMDeallocResource` to check nobody else claimed it.
6. Create the driver's own adapter, device and logical-device nodes.

A PCI driver would search with `RM_IDTYPE_PCI` and `vendor << 16 | device`, and still has to find
its bus/device/function itself (section 3.1) [INF]. On the VirtualBox guest the drivers' adapters match the
snooper records: `KBD_0` reuses `IBMKBD.SNP`'s ports and IRQ, `AUX_0` reuses `MOUSE.SNP`'s name but
claims IRQ 12 exclusive where the detection said shared, `FLOPPY_0` claims the primary controller
only, and the IDE driver splits the PIIX bus-master BAR that `PCIBUS.SNP` recorded as one 16-port
range into two of 8. PCI functions no driver claims (display, network, USB there) exist only as
`CURRENT` detected nodes [OBS].

**By `ISAPNP.SNP`**, which looks devices up in `PREVIOUS` to restore their configuration (section 3.2).

**By `RMVIEW.EXE`**, through `RMINFO.DLL` [OBS-RE]. `RMVIEW` imports only `RMEnumNodes`,
`RMGetNodeInfo` and `RMConvertID`. `RMINFO.DLL` opens `RESMGR$` and uses category-80h function `00h`
(fetch the ring-3 call gate for its `RMCreate*`/`RMAlloc*` exports), `01h` (`RMGetNodeInfo`) and
`02h` (`RMEnumNodes`, drivers included, so `RESOURCE.SYS`'s refusal of the documented `03h` never
shows). `RMVIEW` has **no option to read a file**: `/DP` enumerates the `PREVIOUS` tree that
`RESOURCE.SYS` built from the file at boot. Its views: `/P` physical (adapters and devices only, no
detected nodes), `/P1` with the planar chipset, `/D` drivers, `/DA` drivers including snoopers, `/D1`,
`/DC` current detected, `/DP` previous detected, `/L` logical, `/R` raw, `/IRQ /IO /IOA /DMA /MEM`
claimed resources (`/SO` sorts by owner), `/HW` the hardware tree.

## 6. Not established

1. ~~That `OEMHLP$` ignores the category byte on its IDC path (section 3.1).~~ Settled [OBS-RE]: the IDC
   entry is the Strategy routine and its IOCtl arm tests no category; only the EISA and PCI arms
   read the byte, to skip their buffer checks when it is 0 (unpublished notes). Shipped drivers use both: category 0 (`IBM1S506`, `CMD640X`, IBM's USB host drivers,
   `PCIBUS.SNP`) and 80h (the Adaptec, BusLogic, I2O and DPT drivers, Veit Kannegieser's
   `PCIBUS.SNP`) (section 15 there).
2. Whether `ISAPNP.SNP`'s PnP BIOS / ESCD path is dead (section 3.2).
3. The conflict rules of levels 1-3 (section 4.1).
4. The fields of an ISA PnP detected node beyond those listed (vendor ID, serial number); a capture
   on hardware with ISA PnP cards would settle it.
5. What creates the live `MOUSE.SNP` driver node that makes `PREVIOUS.DAT` grow (section 4.3). A breakpoint
   on `RESOURCE.SYS`'s `RMCreateDriver` on a level-0 boot would settle it.
6. What the snoopers record on real hardware. No capture exists: it needs a full-detection boot
   (F5, or the file removed) with the shipped `SNOOP.LST`. On a machine booted through a
   compatibility BIOS, such a capture also reflects that BIOS. `PCIBUS.SNP` scans as many buses as
   the BIOS's PCI services report through `OEMHLP$` (subfunction 0). The IDs and class codes it reads
   are the devices' own, but the BAR addresses and interrupt lines are as the firmware and the
   compatibility BIOS left them. `PNP.SYS` finds whatever option ROMs that BIOS shadows at
   `C0000h`-`DFFFFh` [INF]. From the code, `PCIBUS.SNP` would give
   every device with a 64-bit memory BAR no memory resource, and would reach buses behind PCI
   bridges only if `OEMHLP$` reports them [INF].
7. ~~Which PnP IDs each shipped driver searches for.~~ Read [OBS-RE] (unpublished notes, Warp 4.5, eCS 2.0, ArcaOS 5.0): `COM.SYS` searches `CURRENT`
   for EISA `PNP0500`, by `DeviceID` then by `CompatibleID`; `IBM1S506.ADD` for `PNP0600`; the
   Crystal audio drivers by vendor only; `ICHCSND.SYS` by a PCI ID; others search the physical tree
   by key (`"SERIAL*"`, `"PCMCIA*"`, `"PCI_Bus_0"`, `"DSKT_*"`). The original question: ACPI firmware commonly reports a PS/2 mouse as
   `PNP0F13` and a 16550 UART as `PNP0501`, where the snoopers record `PNP0F03` and `PNP0500`
   [INF]; whether a driver given the ACPI ID would find its device depends on that.

## 7. The Resource Manager's interfaces [OBS-RE unless tagged]

unpublished notes (conflicts, `RMDestroyDriver`, IOCtls,
search rules, entries, `RMCALLS.LIB`), unpublished notes. `RESOURCE.SYS` 10.058.

### 7.1 How a driver and a program reach it

- **The header** (`"RESMGR$ "`, attribute `8180h`, capabilities `DEV_ADAPTER_DD`): `_RMInit` writes
  its ring-0 entry `_RSMR0Entry` into +08h, its own code selector into +16h (`SDevRealCS`), and into
  +18h (`SDevRealDS`) a ring-3 call gate it makes with `DevHlp_DynamicAPI` onto `_RSMR3Entry`, three
  parameter words. `AttachDD` copies those words (`driver-lifecycle.md` section 3.6).
- **`RMCALLS.LIB`** [DOC-IBM PDD/00324-00328; OBS-RE the library objects]: the driver declares
  `Device_Help`, `RMFlags`, `RM_Help0`, `RM_Help3`. `RMCreateDriver`'s first call attaches
  `RESMGR$ ` and sets `RM_Help0 = table[+2]:table[+6]`, `RM_Help3 = table[+4]:0000`,
  `RMFlags |= 5`; a failed attach sets `RMFlags |= 2`, after which the older services return 0 with
  handle `-1` and the newer ones 15h. `CallRM` tests its own CS's privilege bits: at ring 3 it pushes
  `{index, far pointer to the caller's arguments}` and far-calls `RM_Help3`; at ring 0 it pushes
  the index and far-calls `RM_Help0`, whose body unwinds the wrapper's frames and returns straight to
  the driver.
  - The "caller's arguments" pointer is `[bp+6]`, the first argument, in every service wrapper but
    `RMADDToHDEVICE` (16), which passes `[bp+0Ah]`, its second argument [OBS-RE the base DDK's
    `rmcalls.lib`, module unpublished notes, 2026-10-30]. The ring-0 path never reads the pointer, so a
    ring-0 driver sees no difference; a ring-3 caller of 16 hands the service `ADDHandle` where
    `phDevice` belongs. `RMINFO.DLL` does not export 16.
- **Function indices 0-39** (`rmlib.h` [DOC-IBM]): 1 `RMGetVersion` .. 36 `RMGetCommandLine`; 0 and
  37-39 are null in `_RMFunctionTable` (`RMSetSnoopLevel`, `RMSaveDetectedData`,
  `RMDeleteDetectedData` are `RMINFO.DLL`'s own), 28h and above answer 14h. 10, 11, 24, 25, 26
  answer 0 and do nothing in `RESOURCE.SYS`, and the library returns 14h without calling.
- **Programs** reach it only through `RMINFO.DLL`, the one ring-3 module that opens `RESMGR$`: its
  init takes the gate from IOCtl 80h/00h, its 15 service exports far-call the gate as `CallRM` does,
  and `RMEnumNodes`/`RMGetNodeInfo` use IOCtls 02h/01h. `RMVIEW`, `SVDETECT`, `PNP.DLL`,
  `INSTALL.EXE`, `MMSNIFF.DLL` use `RMINFO.DLL`'s exports; one third-party program (`PCI.EXE`)
  issues 01h and 02h directly.
- **Every service and IOCtl first calls `_RMEntry`**: it refuses (13h, `RMRC_IRQ_ENTRY_ILLEGAL`)
  unless the interrupt level is `FFFF:FFFF` (task or INIT time), then takes one global lock,
  `ProcBlock`ing while it is held.

### 7.2 The IOCtls (category 80h)

Status is preset `0100h`; an arm changes it only to `810Ch` or `8103h`. **00h** the gate's far
pointer (no parameter, 4 data bytes). **01h** node information: parameter `{handle, Linaddr}` (8
bytes); `RMNodeSize` written once 4 data bytes verify, `810Ch` when the node does not fit. **02h**
enumeration: command 0 physical, 1 logical, 3 previous, 4 current - a pre-order walk from the root
at depth 0; 2 every driver in creation order at depth 0, each followed by every node it owns at
depth 1; `NumEntries` written, then `810Ch` when the entries do not fit. **03h** (documented) and
**04h** (a copy of the private heap; no caller in Warp 4.5, eCS or ArcaOS) - 03h answers `8103h`.

**Node information layout** (01h and `RMGetNodeInfo`): `RMNodeSize`; `RM_NODE` {`VersionInfo`
C9h, `NodeType`, `DriverHandle` (a driver node's own handle, any other node's owning driver),
pointer to the structure at +18h, pointer to the resource list}; the structure; its strings in field
order; its adjuncts; last `RESOURCELIST` (an adapter's, device's or detected node's assigned
resources, a driver's unassigned ones, none for an LDEV, a sysname or a resource). For `CallRM` 28
the pointers are 16:16 into the caller's buffer; for IOCtl 01h they are rebased to the flat
`Linaddr` the parameter carries. A driver structure's `DrvrCallback` is copied as stored.

### 7.3 Resources: the conflict decision

- Limits: only IRQ 0-15, DMA 0-7 and timer 0-2 have headers, so anything above conflicts; memory
  below `C0000h` always conflicts; an I/O resource needs `IOAddressLines` 10 or 16, a 10-line base
  in `100h-3FFh` (else 0Eh).
- Compared against: I/O the whole chain, overlap tested under the decode mask of the smaller
  address-line count, the requester's own driver's resources skipped; memory the whole chain; IRQ,
  DMA and timer the level's chain, with no same-driver exemption.
- Per overlapping resource: waived when it sits on a previous-boot detected node, or its owner is a
  snooper (`DRT_SERVICE` subtype 1 or 2) and the requester is not; otherwise it conflicts unless
  neither side is EXCLUSIVE, a SHARED request meets a SHARED holder and a MULTIPLEXED one a
  MULTIPLEXED holder (RECONFIGURE and GRANT_YIELD ignored). At snoop level 0-2 a live snooper's
  request is further limited against what was detected last boot; at the default level 3 and at 4
  it is not.

### 7.4 The other services, where the book is silent

- **`RMDestroyDriver`** tears down everything the driver made: its unassigned resources, and the
  whole subtree of every node it owns, whoever owns the descendants, with their resources; LDEVs
  aliasing a destroyed node keep existing with no device.
- **Searches** (`RMKeyToHandleList`, `RMAdjToHandleList`, `RMResToHandleList`,
  `RMDevIDToHandleList`): `cHandles` counts every match, the first `cMaxHandles` are stored, the
  return is 0; `cMaxHandles` 0 gives 0Eh. Keys compare through `_RMCpyKey` (upper-cased, cut at the
  first blank, 16 characters, blank-padded), 16 characters or a trailing-`*` prefix, over the start
  node's subtree. Adjuncts match on type and on the data over the shorter length, from an adapter or
  device. `RMResToHandleList` runs the conflict test with no requester and returns each conflicting
  holder's node. `RMDevIDToHandleList` requires `IDType` equal and every flagged field equal, over
  the start's subtree and its following siblings.
- **`RMGetCommandLine`**: the `Index`-th (0-based) line of the `BASEDEV=` (0) or `DEVICE=` (1) list
  whose name after its last `\` matches in its first 16 characters, case folded; the arguments
  verbatim, length without the NUL, 11h with the needed length when short, 10h with no such line.
- **`RMParseScsiInquiry`**: the key from inquiry byte 0 (`DISK_#` .. `COMM_#`, else `UNKNOWN_#`),
  six blanks, vendor (8 bytes), a blank, product (16), a blank, revision (4).
- **`RMHandleToType`** answers 4 with type 0 for an invalid handle and for a driver handle;
  **`RMHandleToParent`** gives a resource's node (or its driver), and a root's own pseudo-handle;
  **`RMUpdateAdjunct`** takes a 0-based index and a new length no larger than the old;
  **`RMModifyNodeFlags`** replaces the node's flags word; **`RMCreateLDev`** places an LDEV under
  its class's node.
- **`RMGetVersion`** stores bytes (2 and 1) into the two words.
- IBM's own defects: `RMAdjToHandleList` stores past `cMaxHandles`; `RMGetCommandLine` writes its NUL
  one byte past a buffer of exactly the length; `RMParseScsiInquiry` releases the global lock without
  taking it.

## 8. Later releases: eCS 2.0 and ArcaOS 5.0 [OBS-RE]

unpublished notes. ArcaOS 5.0 ships Warp 4.5's `SNOOP.LST` and
snoopers unchanged, then installs Veit Kannegieser's `PCIBUS.SNP` over IBM's; eCS 2.0 trims
`SNOOP.LST` to `RESRV`, `IBMKBD`, `IBM1FLPY`, `PARALLEL`, `MOUSE`, `SERIAL` and the same rewritten
`PCIBUS`. That `PCIBUS.SNP` keeps IBM's record (`RM_IDTYPE_PCI`, `vendor << 16 | device` in all
three IDs) and adds an `ADJ_PCI_DEVFUNC` adjunct (`bus << 8 | devfn`), the subsystem vendor as
`VendorID` (unless it reads 0, 3030h, 8000h or FFFFh), and in the physical tree a device per
PCI-to-PCI bridge with a `PCI_Bus_<n>` adapter under it. It reads PCI through `OEMHLP$` function 0Bh
with category 80h.

**The IRQ range.** [OBS-RE] IBM `RESOURCE.SYS` (10.058 and 10.070, the latter also the eCS 2.0
and ArcaOS 5.0 base install) can allocate only IRQ 0-15: it builds a resource-class header per
IRQ level, and a level without one conflicts. The eCS and ArcaOS ACPI packages install a patched
build (10.041 / 10.042, described by the package as "Patched RESOURCE.SYS 2011.12.22") whose
only code change is one immediate in `_RMInit`: 20h IRQ headers per PIC node instead of 8, so
IRQ 0-31 under `PIC_0` and 32-63 under `PIC_1`; 64 and up still conflict. DMA (0-7), timer
(0-2), 32-bit memory, `ADJ_PCI_DEVFUNC` and the absence of MSI are unchanged. The ArcaOS build
also names its previous-boot file `PREVIOUS.ACP` instead of `PREVIOUS.DAT`; [INF] since
`RMINFO` still writes `PREVIOUS.DAT`, that file is never found and the Resource Manager runs at
snoop level 3 each boot unless `/SL:` is given. [OBS-RE] PCI IRQs reach the Resource Manager
from configuration register 3Ch, which `PCIBUS.SNP` reads through `OEMHLP$` function 0Bh.
[INF, from strings only] ArcaOS's `ACPI.PSD` answers `OEMHLP$` category 80h function 0Bh itself
and sets 3Ch from the ACPI `_PRT` routing; its upper bound is unestablished. [DOC-IBM] The SMP
kernel's platform-specific driver interface already allowed more than 16 levels:
`PSDHLP_SET_IRQ` registers a handler "at any given IRQ level between IRQ 0-IRQ 1F" (IBM, *OS/2
Warp SMP Additions*, 1997-03-12, page PSDHLP_SET_IRQ).

## 9. `OEMHLP$` functions 03h, 05h, 06h and 0Dh

Category 80h, no parameter packet (PDD/02156, 02188, 02199) [DOC-IBM]; function names in the Toolkit's `bsedev.h`
(`OEMHLP_GETVIDEOFONTS` 3, `OEMHLP_GETROMBIOSINFO` 5, `OEMHLP_GETMISCVIDEOINFO` 6) and the DDK's `oemhlp.h`
(`OEMHLP_MACHINE_ID` 13, "return machine ID byte"; the PDD reference documents no 0Dh).

- **03h** (PDD/02154-02165): an 18h-byte data packet of six real-mode `segment:offset` pointers, in this order: 8x14,
  8x8, 8x8 upper half, 9x14, 8x16, 9x16 (PDD/02163) - INT 10h AX=1130h's sets; the caller converts them. The kernel's arm
  copies at most 12 words and stops at the first word of the caller's area that is already FFFFh [OBS-RE]
  (unpublished notes).
- **05h** (PDD/02186-02195): four words - model, submodel, BIOS revision, BIOS/ABIOS flags (bit 0 ABIOS present); the
  high bytes of model and submodel are 0. From INT 15h C0h's table; on its failure the model is the byte at F000:FFFE
  and the rest 0 [OBS-RE] (same, section 6).
- **06h** (PDD/02197-02203): one byte, byte 2Dh of the INT 10h 1B00h state buffer, 0 if unsupported.
- **0Dh**: one word, the INT 15h AX=2310h byte when model:submodel is FCh:01h, else 0 [OBS-RE] (same, section 6).

On OS/2 Warp 4.5 WSeB, kernel 14.089 UNI, in a VirtualBox VM (2026-10-26, a 32-bit program's `DosDevIOCtl` to `OEMHLP$`) [OBS]: 03h's six
pointers are all non-zero real-mode addresses; 05h answers FCh, 01h, 1, 0; 06h answers 21h (attribute bit 5 blink, bit
0 all modes on all displays); 0Dh answers 0 - on an FCh:01h machine, so the 2310h byte there is 0.

## See also

- `driver-lifecycle.md` section 1.2 (the `BASEDEV=` hand-over to the Resource Manager) and section 3.5 (the
  load notifications).
- `drivers.md` - the BASEDEV extension order and the device-driver ABI.
- `boot-sequence.md` - where the base-driver load sits in the boot.
