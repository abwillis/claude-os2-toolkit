# The DASD Device Manager (DMD) contract

What a disk **device manager** (`OS2DASD.DMD`, `BASEDEV=*.DMD`) owes the kernel and the
file systems above it, and how it uses the adapter drivers (`*.ADD`) below it. This is the
interface a replacement DASD manager must meet. The application-visible half (the category 08h/09h
IOCtls, the volume APIs, VPB/DPB, MBR/LVM drive-letter rules) is in `dasd-volume.md`. This doc is
the driver-facing half.

Sources, read 2026-11-04:
- **[DOC-IBM] Storage Device Driver Reference** (IBM DDK `HTML/REF/STORAGE`), *"OS2DASD.DMD -
  Technical Reference"* pages 00455-00481 and *"Extended Device Driver Interface Specification"*
  pages 00482-00504. Cited below as `STORAGE nnnnn`.
- **[DOC-IBM] IBM's OS2DASD source** in the DDK. There are two builds:
  - the 16-bit pre-LVM build, `base/src/dev/dasd/os2dasd/` (1992-96);
  - the mixed 16/32-bit LVM build, `base32/src/basedd/dasd/os2dasd/` (2002, compiled `-DLVM`).

  Cited by file and routine. Unmarked source citations are to the 16-bit build.
- **[DOC-IBM]** `iorb.h` (`base/src/dev/dasd/diskh/`) for the IORB structures.
- **[OBS-RE]** the OS/2 Warp 4.5 14.104a SMP kernel, and `OS2DASD.DMD`/`OS2LVM.DMD` dated
  2001-10-16 (the WSeB pair, read with their matching `.sym`). Kernel addresses are segment:offset in
  that kernel.

---

## 1. What a DMD is [DOC-IBM STORAGE 00455]

A DMD sits between the file systems and the ADDs. It talks to the ADDs only through **IORBs**, so an
ADD never sees partitions or drive letters. IBM lists five jobs for OS2DASD:

1. Implement the kernel/file-system block-driver interfaces, turning requests into IORBs.
2. Scan the ADDs for fixed and removable magnetic devices.
3. Make logical drives from partitioned disks, and report them to the kernel.
4. Provide the IOCtls that disk utilities (FORMAT, CHKDSK, FDISK) use.
5. Pseudo-drive support: several logical drives mapped onto one removable device, such as A: and B:
   on a single diskette drive.

Its two seams:
- **Northbound:** Strategy-1 request packets, the Strategy-2 "Extended Disk Interface", and generic
  IOCtls. All three come from the kernel and the IFSs.
- **Southbound:** IORBs to ADD entry points.

## 2. Device headers [OBS-RE OS2DASD.DMD 2001-10-16; DOC-IBM unpublished notes]

OS2DASD has two headers, chained:

| Header | Attr | Strategy | Name | Caps |
|---|---|---|---|---|
| block | `0x2880` | `DMStrat1` | `" Disk DD"` | `0x00` (pre-LVM / plain build) |
| char | `0xC980` | `DMCharStrat1` | `OS2DASD$` | `0x03` |

- `DriveInit` links the block header to the char header at INIT time (`DiskDDHeader.SDevNext`,
  unpublished notes).
- The char header answers only three commands (`DMCharStrat1`, unpublished notes):
  - INIT (0x00) and INIT-base (0x1B);
  - Shutdown (0x1C), with category 1 unlocking removable-as-fixed units through
    `IOCC_DEVICE_CONTROL`/`IOCM_UNLOCK_MEDIA`.

  Anything else gets `STERR | ERROR_I24_BAD_UNIT`.
- The LVM build also hangs its IDC entry on the char header (`_DM_IDC`), for `OS2LVM.DMD` (section 8).
- **`DEV_LVM` (caps `0x40`, `devhdr.h:63`) is OS2LVM's bit, not OS2DASD's.** The kernel sets its
  `_LVMActive` flag only for a `DEV_LVM` block header followed by a header named `LVM$`
  (`BaseDevInit` 000e:780b) [OBS-RE].

## 3. Strategy-1 commands [DOC-IBM STORAGE 00457, 00462-00465; unpublished notes]

The dispatch table, with IBM's handler names. Commands not listed are `CmdErr`.

| Cmd | Name | OS2DASD handler | Contract |
|---|---|---|---|
| 01h | Check Media Change | `MediaCheck` | Removable media: asks the ADD for fresh status unless a change is already latched. A latched change blocks further I/O until 11h arrives (00464). |
| 02h | Build BPB | `BuildBPB` | Returns the media BPB (section 5). |
| 04h / 08h / 09h | Read / Write / Write+Verify | `ReadWriteV` | The disk address is the volume's MBR/EBR location + the BPB's HiddenSectors + the packet's RBA (00463). The RBA is volume-relative: sector 0 is the volume's boot sector. |
| 18h / 19h / 1Ah | the same, no caching | `ReadWriteV` | As above, with the EXECUTE_IO cache-suppression bits set (00463). |
| 05h / 06h / 07h / 0Dh / 0Eh | status, flush, open, close | `StatusDevReady` / `StatusComplete` | Done with no action. |
| 0Fh | Removable Media | `RemovableMedia` | Sets BUSY from the unit's ADD `UnitInfo` (00464). |
| 10h | Generic IOCtl | `DriveGenIOCTL` | Categories 08h/09h (section 7). |
| 11h | Reset Media Change | `ResetMedia` | Clears the latch (00464). |
| 12h / 13h | Get / Set Logical Drive Map | `GetLogDriveMap` / `SetLogDriveMap` | Pseudo drives on one removable device. The unit numbers are **1-based**; 0 means no alias (00464). |
| 16h | Get Partitionable Disk Count | `PartFixedDisks` | The number of non-removable drives (00465). |
| 17h | Map Unit Numbers to Physical Drive | `GetUnitMap` | Input: a 0-based fixed-disk number (OS2DASD adds 80h). Output: a ULONG bit map, bit *n* set for each logical unit *n* on that disk (00465). |
| 1Bh | Init (base) | `DriveInit` | section 4. Replaced by `CmdErr` after the first call. |
| 1Dh | Get Driver Capabilities | `GetDriverCaps` | Returns 16:16 pointers to the DCS and the unit's VCS (section 6). |
| 22h | Get Drive Assign | - (`CmdErr`) | Not in the table, so OS2DASD **rejects** it. section 4.2 covers what the kernel does then. |

`DMStrat1` (unpublished notes) checks the unit and dispatches. Requests that need I/O are queued and
turned into IORBs (unpublished notes).

## 4. INIT and how units become drive letters

### 4.1 What INIT returns [DOC-IBM unpublished notes, STORAGE 00460]

The order `DriveInit` follows:

1. Save the DevHlp entry, then call `GetDOSVar(13)` (interrupt level), `VirtToPhys` and `VirtToLin`
   on its data segment, and `RMCreateDriver`.
2. Parse the `BASEDEV=` arguments (`GetInitParms`).
3. `Build_UnitCBs` (section 9), then `Build_VolCBs`, `InitDCS_VCS`, the control-block pool and tracing.
4. Return in the INIT packet:
   - `Unit` = the number of logical units;
   - `BPBArray` = a near-pointer array, one per unit, each pointing at that unit's **media BPB**;
   - `CodeEnd` / `DataEnd`.

**Unit numbering** (`DriveInit`, STORAGE 00460):
- **Units 0 and 1 are always declared**, for A: and B:, whether or not any diskette unit exists. With
  no diskette drive both point at a 1.44 MB template BPB (the no-media case returns exactly 2 units).
  With one diskette drive, B: is a pseudo drive mapped onto it. IBM: *"There is an 'implicit'
  assumption by OS/2 System Initialization, that OS2DASD will be the first block driver loaded."*
- **Units 2-24: logical drives, then removables.** The order:
  1. the primary partition of every fixed disk, disk by disk;
  2. then, disk by disk, every logical drive in that disk's extended-partition chain;
  3. then every remaining removable device.
- **80h-98h: physical drives.** These are internal numbers, one per non-removable disk, used by 17h
  and category 09h. They are not reported as INIT units.
- **Unit numbers are not drive letters.** IBM: *"a block device driver cannot demand that a
  particular set of drive letters be assigned to it"* (00460). section 4.2 shows how a driver can still
  ask for one.

### 4.2 The kernel's side: one DPB per unit, then command 22h [OBS-RE 14.104a SMP]

`BaseDevInit` (000e:780b, block-driver branch) does the following:
1. Records the INIT unit count in the header's name byte 0.
2. For each unit, builds a DPB from a template. The drive number is the running counter `NumIO`,
   so drives are consecutive by default.
3. Calls `NewDPB` (000d:4694) for each. `NewDPB` links the DPB and calls `SetDriveLetter` (000d:4829).

`SetDriveLetter` sends Strategy-1 command **22h `CMDGetDriveAssign`** (`devcmd.h:59`) for that unit,
with `rp[+0Dh]` preset to `0xFF`. Then:

- **The driver answers** (status bit 15 clear), with the letter index `L` = `rp[+0Dh]`:
  - `L` > 25: the DPB is freed, and the unit gets no drive at all.
  - letter `L` is free: the unit gets it.
  - letter `L` is taken: the first free letter from A:.
- **The driver rejects 22h**, as OS2DASD does:
  - `_LVMActive` set: the first free letter from `RESERVEDRIVELETTER=`'s start.
  - otherwise: the consecutive letter is kept.

This path serves every block DPB in the system, from `BASEDEV=` and `DEVICE=` alike, and the
run-time rediscover. **A DMD that answers 22h chooses its own letters, per unit.** OS2LVM does
exactly that. The pre-LVM OS2DASD does not, so its letters are its unit order (section 4.1).

### 4.3 Partitions OS2DASD accepts [DOC-IBM STORAGE 00471-00472; unpublished notes]

- **The table:** the MBR or EBR must carry signature `0xAA55`.
- **System-indicator values:** IBM's documented rule (00471) is to accept 01h, 04h, 06h and 07h, and
  *"if the operating system detects any values other than 01h, 04h, 06h, or 07h, it ignores that
  entry"*. The 16-bit `Process_Partition` also accepts:
  - FAT16X (0Eh);
  - the fault-tolerant 87h / C7h, flagged `vf_FTPartition`.
- **Primaries:** the first acceptable entry of the four, in table order, is the disk's primary.
  Entries smaller than 64 sectors are rejected.
- **Extended partitions:** type 05h (00471) is followed through the EBR chain:
  - each EBR holds at most one logical drive plus one 05h link;
  - all four EBR entries are searched, in any order (00472).
- **Rejected:** any other type, including 0Bh/0Ch (FAT32), 35h (LVM), 83h (Linux) and EEh (the GPT
  protective entry), gets no unit. A GPT disk therefore yields no logical drive from OS2DASD.
- **How the EBR chain is walked** (`Setup_Extended_Volumes`, `Build_Next_VolCB`):
  - **Finding the chain.** The first MBR entry of type 05h or 0Fh is the extended partition; the
    16-bit build accepts 0Fh from change `d_267583`.
  - **Each EBR.** Every EBR is read. Its first acceptable volume entry becomes a logical drive, with
    RelativeSectors counted from **this EBR**.
  - **The link.** Its first 05h/0Fh entry is the link to the next EBR, counted from **the extended
    partition's start** (00471).
  - **IBM's special first EBR** (00472: *"possible there will not be a device to be installed"*)
    needs no special code. An EBR with no acceptable entry simply yields no volume, and its link is
    still followed.
  - **Stopping.** The walk stops at an EBR with no link or at a failed read. Nothing in it bounds the
    number of EBRs or detects a cycle, so a cyclic chain would loop at INIT [INF from the code].
    `MAX_PARTITIONS` stops only the *adding*.
  - **Sector size.** `Build_Next_VolCB` sets `BytesPerSector` to 512 for every logical volume.
- **Width:** sector fields are 32-bit. `Process_Partition` flags `vf_TooBig` when `RelativeSectors +
  NumSectors` overflows 32 bits.

### 4.4 Who reads the partition-type byte [DOC-IBM OS2DASD source; OBS-RE HPFS.IFS 14.083; DOC-IBM JFS IFS source]

OS2DASD keeps each volume's system indicator in its VolCB, and only the driver itself reads it:

1. **`Process_Boot` (unpublished notes), building the BPB.**
   - Type 07h with no valid BPB in the boot sector gets a pseudo-BPB: the FAT fields are zeroed,
     `MaxDirEntries` is 512 and the media byte is F8h.
   - Any other type gets a FAT BPB from the size-keyed `DiskTable`.
   - The FAT16 flag (`vf_Big`) is computed only for types other than 07h and FT.
2. **`Is_BPB_Boot`** relaxes its media-byte test for 07h, 87h and C7h.
3. **The fault-tolerance partition table** (unpublished notes).
4. **Destructive-request validation** (unpublished notes). A write to sector 0, or into an 07h partition,
   is first offered to the FSD's `FSD_AccValidate` callout. That callout is registered through
   `DD_SetFSDInfo`.
5. **The Resource Manager's `VolIFSType`** (`InitRMInfo`).

VolCBs that OS2DASD creates without a table entry are given 07h, *"Needed for Is_BPB_Boot()"*
(unpublished notes).

The file systems above do not read it:
- **HPFS.IFS** recognises a volume only by `"HPFS    "` at boot-sector offset 36h (`HPFSDISK`,
  [OBS-RE]).
- **IBM's JFS IFS** recognises a volume by `Boot_System_ID` = `"JFS     "` (`FS32_MOUNT`).

### 4.5 What the kernel sends a block driver, and when [OBS-RE 14.104a SMP]

| When | Command | Kernel routine |
|---|---|---|
| base INIT | 1Bh | `BaseDevInit` |
| each DPB built | 0Fh (removable? BUSY = fixed) | `SetDPBRemovFlag` 000d:47e0 |
| each DPB built | 22h | `SetDriveLetter` 000d:4829 |
| once, the physical-disk table | 16h | `BuildPhysDiskTable` |
| volume identification (mount) | 1Dh, then cat 08h fn 63h, then 04h for sector 0, then 02h | `GenhVPB` 000e:1014, `ReadBoot`, `BuildBPB` |
| before I/O on a removable DPB | 01h | `ProbeChange` |
| uncertain-media reset | 11h | `ResetMedia` |
| every transfer | 04h / 08h / 09h | `DoVolIO` |

So 1Dh is sent per volume at identification time, not at INIT. After it, the IFSs are polled with
FS_MOUNT.

**Strategy-2 is used only when `VolChars.MaxSGList` is at least 10h.** `GenhVPB` records Strategy-2
(and Strategy-3 when `GDC_DD_STRAT3` is set) in the DPB, and passes the DCS/VCS to the FS_MOUNT poll
as `vpi_pDCS`/`vpi_pVCS`, only when 1Dh succeeded **and** `MaxSGList` is at least 10h. Otherwise both
pointers are 0:0.

This matters for two reasons:
- **STORAGE 00493 says `MaxSGList` is 0 when the adapter has no scatter/gather. OS2DASD does not
  follow that page:** it reports the adapter's `MaxHWSGList`, or `-1` (FFFFh) when the adapter reports
  0 (`InitDCS_VCS`). A literal 0 would switch Strategy-2 off for the volume.
- **IBM's JFS IFS dereferences `vpi_pDCS` without testing it** and takes `Strategy2` from it (and
  `Strategy3` when the bit is set). A volume whose driver fails this gate cannot be mounted by JFS.
  JFS also requires `VPB_ABOVE16M_ALLOWED` in `vpi_flags`, and otherwise posts a critical error.

**`vpi_flags` comes from the 8/63h answer, not from the DCS** (`GenhVPB` 000e:1139-1151; the
vpfsi is built on the stack in IBM's field order, `vpi_flags` at `[bp-0Eh]`):
- **Device Attributes bit 2 (04h)** sets `vpi_flags` 01h, `VPB_ABOVE16M_ALLOWED`. PDD/01821 calls
  that bit *"Greater than 16MB Support ... physical addresses greater than 16MB"*.
- **Bit 4 (10h)** sets `vpi_flags` 04h. OS2DASD calls that attribute bit `DP_DEVICEATTR_FLOPPY_FMT`.

OS2DASD sets bit 2 when the unit's ADD reported `AF_16M` (unpublished notes, via `UCF_16M`).

**OS2DASD's FAT16 flag (`fBigFat`) never reaches the kernel.** It only sizes the FAT of a BPB the
driver synthesises when the boot sector has no valid BPB (unpublished notes). A FAT volume with a valid
boot sector gets its BPB from that sector whatever the partition type.

**But the kernel's own FAT reads the partition entry itself, from the disk** [OBS-RE 14.104a SMP
retail OS2KRNL, read 2026-11-07 by disassembly; the decompiles of `Check_if_FAT_Check` are empty in
every tree]. The paragraph above is true of the driver's flag and says nothing about the on-disk
entry, and section 4.4's "the file systems above do not read it" holds only for the IFSs. In `GenhVPB`
(000e:1014), when the FS_MOUNT poll (`FSMountVolume`, 000e:159e) leaves the volume unclaimed and the
boot sector is not blank (`[bp-0F1h]`), it calls an unnamed local check at 000e:1418 before mounting
FAT; a carry from it skips the FAT mount:
1. **Removable?** It asks the driver (`0x7f:0x1402`, AX 2008h: category 08h function 20h, the
   removable-media query; that it reaches the driver as command 0Fh is [INF], from a driver-side
   trace showing 0Fh immediately before the read below). The check is skipped, and FAT
   accepted, when the answer is not 1 (fixed), or when `vpi_flags` (`[bp-0Eh]`) has 04h (section 4.5:
   Device Attributes bit 4).
2. **The partition-table sector.** It issues category 08h function 64h (Read Track) for cylinder 0,
   head 0, sector 1, one 512-byte sector. A DMD resolves that CHS relative to the volume's own
   partition table: the MBR for a primary partition, the EBR for a logical drive. Any error from it
   skips FAT (16h and 32h return the call's carry, the rest set it).
3. **`Check_if_FAT_Check` (000e:14e3) on each of the four entries at 1BEh**: `SysIndicator AND EFh`
   (the hidden bit removed) must be 01h, 04h, 06h or 0Eh, **and** `RelativeSectors` must equal the
   boot sector's HiddenSectors (offset 1Ch, saved at `[bp-0F6h]` in `GenhVPB` 000e:11f3-11fc). The
   first match sets a kernel byte (`[3CABh]`, not traced) and FAT is mounted.

So on a fixed disk a FAT volume mounts only when the sector at its own C0/H0/S1 holds a FAT-type
entry pointing at it. A volume whose partition-table sector is something else (a protective or
foreign table) is not mounted as FAT, whatever its boot sector says, and its driver gives no error.
Measured the same day: one FAT16 image (media F8h, extended BPB "FAT16") at sector 26624 mounted
from an MBR type-06h entry and was refused under a protective-MBR table, with the driver's answers
identical apart from that sector.

## 5. The BPB [DOC-IBM STORAGE 00461, 00475]

- **What it is:** a structure shared between the block driver and the FAT file system. HPFS gets a
  **pseudo BPB** built by the driver.
- **When it is built:** for each logical drive, the BPB is read when its VolCB is created. If the
  media has no valid BPB, OS2DASD **builds one from the partition size**, using a size-keyed table.
  That BPB is given to the kernel and never written to the media.
- **Two copies:**
  - a **media BPB**: what is in the drive now; Build BPB (02h) changes it;
  - a **device BPB**: the device's maximum; only 08h/43h Set Device Parameters changes it.

  The two are identical for fixed disks.
- **HiddenSectors:** for a primary partition, the distance from the MBR; for a logical drive, the
  distance from **its own EBR** (00475). An extended volume behaves as a little fixed disk, with its
  EBR as the MBR. Category 08h CHS I/O is mapped inside the extended volume, where C0/H0/S1 is the EBR
  (00476). Category 09h is whole-disk (00477).

## 6. Get Driver Capabilities and the DCS/VCS [DOC-IBM STORAGE 00490-00493; unpublished notes]

Command 1Dh returns two 16:16 pointers, at packet +10h and +14h, after 3 reserved bytes. **A driver
that does not answer 1Dh gets Strategy-1 only:** the kernel and FSDs then *"assume the physical device
driver supports only standard OS/2 requests"* (00490).

**DCS, the Driver Capabilities Structure.** One per driver; the kernel and FSDs must not modify it.

| Field | Contents |
|---|---|
| reserved | WORD 0 |
| `DD_VerMajor` / `DD_VerMinor` | 01h / 01h |
| `DD_Capabilities` | bit 3 mirroring, bit 4 duplexing, bit 5 **does not block in Strategy-2** (HPFS386 requires it) |
| entry points | 16:16 `DD_Strategy2`, `DD_SetFSDInfo`, `DD_ChgPriority`, `DD_SetRestPos`, `DD_GetBoundary`; 0:0 = not provided |

**The DCS grew after the reference page was written** [DOC-IBM DDK `base/h/strat2.h` `DriverCaps`
and `GDC_DD_*`; the same in `base32/.../common/include/strat2.h`]:

- **Two capability bits the page does not list:** `GDC_DD_16M` 0x40 (">16M memory supported") and
  `GDC_DD_STRAT3` 0x80 ("strat-3 entry point", change tag `@189811`).
- **A seventh entry point:** `Strategy3`, at DCS +1Ch.
- **A different name at +0Ch:** the header calls that slot `EndofInt`, where the page calls it
  `DD_SetFSDInfo`. OS2DASD stores `DD_SetFSDInfo` there (`InitDCS_VCS`).

The LVM-era build supplies Strategy-3 (unpublished notes, 32-bit). Its consumers include JFS: IBM's JFS
IFS source (GPL, held by osfree) takes `Strategy3` from the DCS that the kernel leaves in
`vpi_pDCS`, but only when `GDC_DD_STRAT3` is set. Otherwise it uses `Strategy2`.

OS2DASD (16-bit) sets the capabilities `GDC_DD_Mirror | GDC_DD_Duplex | GDC_DD_No_Block |
GDC_DD_16M`, and fills Strategy2 = `DMStrat2`, SetFSDInfo = `DD_SetFSDInfo` and ChgPriority.

**VCS, the Volume Characteristics Structure.** One per volume, advisory:
- `VolDescriptor`, with bits for removable, read-only, RAM-like seek, outboard cache, adapter
  scatter/gather, and ReadPrefetch;
- AvgSeekTime and AvgLatency, `FFFFh` when unknown;
- TrackMin/MaxBlocks and HeadsPerCylinder, 1 when unknown;
- `VolCylinderCount` (the sector count when unknown);
- `VolMedianBlock`;
- `MaxSGList`, 0 when the adapter does not do scatter/gather.

## 7. Strategy-2 (the Extended Disk Interface) [DOC-IBM STORAGE 00458, 00483-00504; unpublished notes]

The FSD learns `DD_Strategy2` from 1Dh and is handed it at FS_MOUNT (00494). The interface:
- is entered with **ES:BX = a global pointer to a Request List**;
- may be called **at task time or at interrupt time**, so only physical and global addresses
  appear in it (00485);
- takes buffers that are guaranteed locked;
- must never block if the DCS sets the does-not-block bit (00485).

**The Request List header** is 20 bytes:

| Field | Contents |
|---|---|
| `ReqListCount` | number of requests |
| reserved | |
| `LstNotifyAddress` | 16:16; called with ES:BX = the list, CF = an unrecoverable error |
| `LstRequestControl` | bit 1 single request, bit 2 sequential, bit 3 terminate on error, bit 4 notify on error, bit 5 notify on completion |
| Block Device Unit | one unit for the whole list |
| `LstStatus` | low nibble: 0 none queued, 1 queueing, 2 all queued, 4 all done; high nibble: error class |
| DD-reserved | |

**The requests** follow it. Each is an EXECUTE CHAIN entry whose prefix byte sits where a standard
packet keeps its command, so both kinds can share one queue (00487). Only READ, WRITE and READ
PREFETCH are defined (00494), with scatter/gather descriptors.

`DD_SetFSDInfo` stores the FSD's `FSD_EndofInt` and `FSD_AccValidate` callouts (unpublished notes).

## 8. Generic IOCtls a DMD answers [DOC-IBM STORAGE 00459; OBS-RE 14.104a SMP for the kernel's routing]

| Category | Functions (STORAGE 00459) |
|---|---|
| 08h, logical drive | 22h alias letter, 40h lock/unlock/eject, 43h set params, 44h write track, 45h format/verify, 5Dh diskette controller, 60h media switches, 63h get params, 64h read track, 65h verify track, 66h lock status |
| 09h, physical disk | 44h write track, 63h get params, 64h read track, 65h verify track |

What the kernel does before the driver sees them (`sw_DevIOCtl` 000b:1418) [OBS-RE]:
- **08h/00h and 08h/01h (lock/unlock drive) never reach the driver.** The kernel runs `LockDrive` /
  `UnlockDrive` itself.
- 08h/03h and 08h/21h become Strategy-1 13h and 12h.
- Most other functions arrive as command 10h.
- On an IFS-mounted volume, a DASD handle's other category 08h functions go to the FSD's
  `FS_IOCTL` first.
- 09h/6Ah (rediscover) and 08h/6Ah (delete) are intercepted in `w_DevIOCtl`, forwarded, and then
  the kernel makes or frees DPBs itself. This is the LVM path.

## 9. The southbound side: finding ADDs and talking IORB [DOC-IBM unpublished notes; `iorb.h`; STORAGE 00020]

**Finding units at INIT** (`Build_UnitCBs`):

1. `DevHlp_GetDOSVar(DHGETDOSV_DEVICECLASSTABLE, 1)` gives the class-1 (ADD) table of the entry
   points that ADDs registered with `RegisterDeviceClass`.
2. For each ADD: `IOCC_CONFIGURATION` / `IOCM_GET_DEVICE_TABLE`, which returns adapters and their
   `UnitInfo`s.
3. For each unit whose type is `UIB_TYPE_DISK` (or optical, when treated as fixed) and that is
   neither `UF_NODASD_SUPT` nor `UF_DEFECTIVE`: `IOCC_UNIT_CONTROL` / `IOCM_ALLOCATE_UNIT`. If the
   unit names a `FilterADDHandle`, this goes to the filter's entry point instead of the ADD's. On
   success a UnitCB records:
   - the `UnitInfo`;
   - the entry point (the filter's when filtered);
   - `MaxHWSGList`;
   - the adapter flags `AF_HW_SCATGAT`, `AF_16M`, `AF_CHS_ADDRESSING`;
   - the drive number: 80h + n for fixed disks, or the removable index.
4. At INIT every IORB is issued `IORB_ASYNC_POST`, and the DMD spins on `IORB_DONE`.

**Calling an ADD** (STORAGE 00020): a far call, `VOID (FAR *ADDEntryPoint)(PIORB)`. Completion is
the IORB's `NotifyAddress`. The IORB codes OS2DASD issues (grep of its source):
- configuration, unit control and geometry;
- EXECUTE_IO: read, write, write-verify, read-verify, prefetch;
- format, unit status, device control (lock, unlock, media sense, change line);
- adapter passthru.

**The 32-bit ceiling southbound:** `IORB_EXECUTEIO.RBA` is a `ULONG` (`iorb.h:505`), and
`BlockCount` is a `USHORT`. A DMD can therefore address at most 2^32 blocks of a unit through
standard IORBs: 2 TiB at 512-byte blocks.

**The same ceiling holds northbound, so it is the interface's and not one driver's:**
- The Strategy-1 read/write packet's start sector is 32-bit.
- The Strategy-2 request entry `PB_Read_Write` has `ULONG Start_Block` and `ULONG Block_Count`
  (DDK `base/h/strat2.h`). Strategy-3 takes the same `Req_List_Header` request lists, in flat form.
- The BPB's HiddenSectors and BigTotalSectors are 32-bit.

A volume relative to its own start can therefore hold at most 2^32 sectors. How far into the disk it
may start is the DMD's business: the ADD sees a 32-bit RBA.

## 10. The LVM build [DOC-IBM `base32/.../os2dasd` `#ifdef LVM`; OBS-RE OS2DASD/OS2LVM 2001-10-16]

The OS2DASD that ships with LVM-era OS/2 (WSeB, Convenience Packs, eComStation):
- **reports 0 units and a NULL BPB array** at INIT (unpublished notes LVM build: *"Return 0 drives,
  allowing OS2LVM to report the logical drives"*), and 0 for 16h;
- hands its physical disks and partitions to `OS2LVM.DMD` through the IDC on `OS2DASD$`
  (`DMIDC_GET_INTERFACE`, `dmidc.h`);
- adds a Strategy-3 for OS2LVM.

OS2LVM then:
- reports the volumes as units;
- answers 22h with each volume's DLA-table letter (`dasd-volume.md`).

So on LVM systems letters are chosen by the driver through 22h, and on pre-LVM systems by unit order.
OS2DASD does not check for OS2LVM; without it, no fixed-disk letters appear.

---

## Open in this doc

- **Strategy-2 detail** (the request formats and the scatter/gather descriptor, STORAGE 00495-00504)
  is summarised here, not transcribed.
- **The run-time rediscover** (09h/6Ah) is described from the LVM side only.
- ~~Whether the kernel sends 1Dh at boot or only at mount, and in what order relative to 22h, was
  not traced.~~ Answered 2026-11-04 in section 4.5: 1Dh is sent at volume identification, after INIT's
  0Fh/22h.
- ~~Where the kernel's `VPB_ABOVE16M_ALLOWED` comes from.~~ Answered 2026-11-04 in section 4.5: 8/63h
  Device Attributes bit 2, not `GDC_DD_16M`.
- **The no-media 2-unit INIT**, and the A:/B: units when the machine has no diskette controller, were
  read from source, not observed.
