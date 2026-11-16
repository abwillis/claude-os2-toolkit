# The error-log service: `LOG.SYS`, `LOGDAEM`, the `Log*` and `DosLog*` calls

How an OS/2 Warp 4.5 program's or driver's error-log entry reaches the system error log file, and what each call
answers. Tags as `README.md` defines them. Field-level detail is in unpublished notes.

## 1. The pieces

- **Two CONFIG.SYS lines activate the service**: `DEVICE=\OS2\LOG.SYS` and `RUN=\OS2\SYSTEM\LOGDAEM.EXE`, in either
  order [DOC-IBM cmdref21.txt `LOG.SYS`, `RUN`; Problem Determination guide, SYSLOG's message "To activate logging
  enter DEVICE=\OS2\LOG.SYS and RUN=\OS2\SYSTEM\LOGDAEM.EXE in config.sys and reboot"].
- **`LOG.SYS`** (device `LOG$`) keeps an in-memory buffer (`/E:4`-`64` KB, default 8 KB) [DOC-IBM]; requests are
  category 0Ch IOCtls; it registers with the kernel (`DevHlp_LogEntry` service 80h) only when LOGDAEM asks (IOCtl
  4Dh), not at INIT [OBS-RE].
- **`LOGDAEM.EXE`** keeps a read (IOCtl 60h) always pending, so each entry leaves LOG.SYS's buffer at once and goes on
  through LFAPI to the file's writer [OBS-RE].
- **The file's writer is `ERLOGGER.EXE`**, started by `SMSTART.EXE` (`RUN=\OS2\SMSTART.EXE`) by its bare name - found
  through `DosExecPgm`'s own search, the current directory then `PATH` [OBS-RE; DOC-IBM cp1.txt DosExecPgm]. It opens
  `\OS2\SYSTEM\RAS\LOG0001.DAT` on the boot drive and serves `\PIPE\LFPIPE` [OBS-RE]. SMSTART reports a start that
  fails in `\OS2\SMSTERR.DAT` [OBS].
- **The status word** is the GIS's `SIS_SysLog` (+0x48, `DosQueryRASInfo` index `SIS_SYS_LOG` 2): `LF_LOGENABLE` 1,
  `LF_LOGAVAILABLE` 2 [DOC-IBM Debugging Handbook]; 3 once LOGDAEM has registered LOG.SYS [OBS].

## 2. The paths in

| Caller | Call | Route |
|---|---|---|
| a 32-bit program | `LogOpen` / `LogAddEntries` / `LogGetEntries` / `LogSetState` / `LogSetName` / `LogQueryState` / `LogClose` (DOSCALLS 430-436) | DOSCALL1: an ordinary handle on `LOG$` and category 0Ch IOCtls 44h, 60h, 40h/42h, 45h, 61h [OBS-RE] |
| a 16-bit program | `DosLogEntry` (193) | the kernel: LOG.SYS's IDC entry, service 83h [OBS-RE] |
| a driver | `DevHlp_LogEntry` (3Bh) service 1 or 90h | the kernel: LOG.SYS's IDC entry, the service in CX [OBS-RE] |
| a 16-bit program | `DosLogRegister` / `DosLogRead` (195/196) | DOSCALL1: IOCtl 4Bh, then the named pipe `\PIPE\LOGDATA\JGRENBLF` [OBS-RE] |

## 3. What a caller sees [OBS, Warp 4.5 WSeB 14.104a SMP, 2026-10-30]

- **The entry reaches the file**: an entry from each of `LogAddEntries`, `DevHlp_LogEntry` 90h and `DosLogEntry`
  appears in `LOG0001.DAT` as a DET4 record.
- **The writer comes up after the programs STARTUP.CMD starts**: `LogOpenFile` (LFAPI) answers 524 until
  `\PIPE\LFPIPE` exists - 0.6 to 1.2 s after STARTUP.CMD's programs start; the Toolkit's own `errlog1.exe` sample, run
  first, gets 524. An entry added before then is not written [INF].
- **`LogReadEntry(READ_LAST_RECORD)`** with no filter, straight after appends, answered 0 with the file's older first
  record, not the newest. Why is not read.
- **LOG.SYS has no function 40h/42h, 45h or 61h**: `LogSetState`, `LogSetName` and `LogQueryState` answer 22.
- **`LogGetEntries`** with a 256-byte buffer: 520, the buffer size needed (8192 by default) in its first doubleword.
- **`DevHlp_LogEntry` 90h** returns AX 0100h (LOG.SYS's device status, done) with CARRY SET: the kernel's exit sets
  carry for any AX but 0 [OBS-RE dh_LogEntry `cmp ax,1; cmc`; OBS].
- **`DosLogRegister`** with a semaphore name: 518 after 60 s (the shipped LOGDAEM never answers its request);
  without one: 0 at once, an ID of FFFFh giving FFFEh. **`DosLogRead`** on the handle a failed register leaves: 526.
- **192 `DosLogMode` and 194 `DosGetLogBuffer`** do nothing and answer the caller's own DI (1458 for one OpenWatcom
  caller): the kernel entry has no worker and returns DI as `pre_sci` left it [OBS-RE every kernel build; OBS].
  IBM documents them by name only.
