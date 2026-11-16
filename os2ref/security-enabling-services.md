# Security Enabling Services (SES) - what it is, how to turn it on, and the kernel interface

OS/2's Security Enabling Services are a **hook framework, not a security product**. The kernel can call
registered ring-0 drivers at about forty points (file open/read/write/delete/move, directory and set-info
calls, DevIOCtl, loader open, module lookup, exec, DOS-session creation, the Ctrl+Alt+Del key, SES-API
audit) and can route every 16- and 32-bit DOSCALLS call through a handler; the first driver that answers
non-zero refuses the call. IBM's own SES driver, `SESDD32.SYS`, keeps a security context for every
process; a ring-3 stack (`SESAPI.DLL`, the SES shell and daemons, a logon authority) sits on it. The
policy - who may open what - is supplied by an **Installable Security Subsystem (ISS)**, a third-party
driver. IBM shipped none.

This document has two parts: **Part 1** is for someone enabling SES or installing an ISS; **Part 2** is the
kernel interface an ISS author needs, which IBM never published.

Provenance:
- **[DOC-IBM]** IBM redbook SG24-4668-00, *OS/2 Security Enabling Services: A Developer's Guide* (1996),
  cited by section ("SG24-4668 11.3"). The overview redbook is SG24-4568-00. Both are on the OS/2 Site
  redbook archive, `https://www.os2site.com/sw/info/redbooks/` (`sg244568.zip`, `security-sg244668.zip`). **The guide's Appendix A, the kernel interface, is not
  in it**: IBM states the KPI details were distributed only on request, through a controlled process.
- **[OBS-RE]** Reverse-engineering of the shipped binaries: `OS2KRNL` 14.104a SMP retail (addresses below
  are that build's), cross-checked for function set and constants against the UNI and SMP Astrict/Hstrict
  debug kernels of the same release; `SESDD32.SYS` ("@#IBM:14.085#@"), `SESAPI.DLL`, `SESDMON.EXE`,
  `PSSDMON.EXE`, `KBDBASE.SYS`, `MOUSE.SYS` ("@#IBM:10.058#@") from a Warp Server for e-business 4.5
  install; the two third-party ISS drivers named in section 1.6.
- **[OBS]** Measured on Warp Server for e-business 4.5, kernel 14.104a SMP retail, in a virtual machine,
  with small probe programs calling the APIs named and printing their return codes.
- **[DOC]** The Security/2 0.4.5 readme (Hobbes, `pub/os2/util/multiuser/Security2_0-4-5.zip`); the AVP
  3.0 monitor readme (Hobbes, `pub/os2/util/virus/AVP_3-0b128.zip`).

---

## Part 1 - Using SES

### 1.1 What ships, and what it does on its own

A WSeB install carries `\OS2\SESDD32.SYS` and `\OS2\SECURITY\` with three directories [OBS]:

| Directory | Files | Role |
|---|---|---|
| `SES\` | `SESAPI.DLL`, `SESRES.DLL`, `SECUTIL.DLL`, `SESSTART.EXE`, `SESDMON.EXE`, `SESSHELL.EXE`, `PSSDMON.EXE` | the API, the daemon and its launcher, the replacement PROTSHELL, the protected-shell daemon |
| `SLA\` | `PDFSLA.EXE` | the default System Logon Authority |
| `SESDB\` | `SECURE.SYS`, `SESDB.DLL`, `SLDAPI.DLL`, `CLDAPI.DLL`, `PVDAPI.DLL` | the authority list, and the system-logon, client-logon and password-validation driver DLLs |

None of it is active until CONFIG.SYS says so. Enabled with no ISS, SES gives **a logon shell that admits
a guest with no password, and enforces nothing** [OBS] (section 1.3).

### 1.2 Enabling it

SG24-4668 14.2.1 [DOC-IBM] gives the CONFIG.SYS block, to be placed first in the file: `BASEDEV=SESDD32.SYS`
(and the ISS's own `BASEDEV=`), `CALL=` of `SESSTART.EXE` with `SESDMON.EXE` as its argument (the first
`CALL=`), `PROTSHELL=` set to `SESSHELL.EXE`, `SET RUNWORKPLACE=` set to `PSSDMON.EXE`, and the variables
`SESDBPATH`, `AUTOGUEST`, `GUESTNAME`, `TRUSTEDPATH`, `USERSHELL`, `RESTARTUSERSHELL`, `BACKGROUNDBITMAP`.
The 2001 binaries read exactly those variable names [OBS-RE] (strings in `SESSHELL.EXE`, `PSSDMON.EXE`,
`SESDMON.EXE`).

**The trap: the redbook's block does not boot.** It leaves `\OS2\SECURITY\SES` off `LIBPATH`. The system
stops at PROTSHELL with *"cannot find the file SESAPI specified in the PROTSHELL statement"* [OBS]. Add the
directory to `LIBPATH` (and `PATH`). The tell: the block was copied from the book, and the boot dies at the
shell, not at a driver.

`SECURE.SYS` (SG24-4668 14.2.2 [DOC-IBM]) lists the programs that hold SES authority, one per line:
program path, `/SCA='tag'`, then role flags (`/SLA`, `/UIA`, `/PSS`, `/SES`, `/ACA`, `/APA`, `/CLA`,
`/RLA`, `/SPA`), and `/START` for a program SES starts itself after PM is up.
Cooperating programs share a tag to act as one authority. The shipped file registers `SESDMON` (`/SES`),
`PDFSLA` (`/SLA /UIA /START`) and `PSSDMON` (`/PSS`) [OBS].

### 1.3 Logon, guest and lock, as they actually behave

Measured with no ISS loaded [OBS]:

- **`AUTOGUEST=YES` does not log a guest on.** The Workplace Shell starts at once, but
  `SESQuerySubjectInfo(-1, ...)` (the current user) returns 35526 `SES_NO_CURRENT_USER`. The desktop
  runs with no user.
- **`AUTOGUEST=NO`** shows the logo bitmap and waits. **One Enter logs on the `GUESTNAME` user** (subject
  handle 1) - no password - and only then is the shell started. After logon, `SESSHELL` itself and the
  shell carry handle 1 in all six subject slots and the local-PM-user flag (status `00100000h`).
- **STARTUP.CMD runs before logon, either way.** Anything it starts - a network daemon, an ssh server -
  and every process those spawn have an empty security context (status 0, all handles 0). **Remote
  sessions never pass through SES logon.** The tell: an ssh session works on a machine whose console
  is still at the logon bitmap.
- **Lock** is the event `SES_EVENT_LOCK` (code 20h), which SG24-4668 13.8.4 [DOC-IBM] says any process
  may start. `SESStartEvent` with that code returns 0 once the console is showing the bitmap, and the
  user stays logged on. **Locking does not stop programs starting**: `DosExecPgm` succeeds during the
  lock, locally and remotely. Enter unlocks the guest, again with no password.
- The authorities report the status their `SECURE.SYS` line grants (`SESQueryContextStatus`; flag values
  in SG24-4668 B.20 [DOC-IBM]): `PDFSLA` `04070408h` (authority 4, SLA + UIA + the three
  effective-handle flags), `PSSDMON` `02074000h` (authority 2, PSS + the same three). `SESQueryAuthorityID`
  maps tags `ses`/`pss`/`sla` to 1/2/4 and an unknown tag to 35524 `SES_ID_NOT_FOUND`, as B.9-B.10 say.

**A documentation error to know about:** SG24-4668 B.4 shows `SUBJECTINFO` twice and the two disagree. Its
field table puts each name/token **length before the pointer**; its C declaration puts the **pointer first**.
The C declaration is the one `SESAPI.DLL` uses [OBS]: a query through it returns the subject name.

### 1.4 What a refusal looks like to a program

Measured with an access-control ISS (Security/2) refusing a user [OBS]:

- **Every refusal is rc 5, `ERROR_ACCESS_DENIED`** - for `DosOpen` (read, write, create), `DosDelete`,
  `DosMove`, `DosCreateDir`, `DosDeleteDir`, `DosSetPathInfo`, `DosFindFirst`, `DosExecPgm` and
  `DosLoadModule`. `DosFindFirst` too returns 5, not a not-found code.
- **A refused call has no side effects**: nothing created, deleted or renamed, no time stamp changed.
- **`DosQueryPathInfo` cannot be refused**: there is no hook for it (Part 2, section 2.4).
- **`DosExecPgm`'s failing-name buffer tells you where the refusal happened.** Refused at loader-open
  (the ISS denies reading the EXE): rc 5 **and the buffer holds the EXE's name**. Refused at the exec
  callout (reading allowed, execution denied): rc 5 **and the buffer is empty**. `DosLoadModule` refused at
  loader-open also names the module.

### 1.5 Inhibiting all process creation: `SESControlProcessCreation`

SG24-4668 B.1 [DOC-IBM]: action 1 inhibits creation of new processes system-wide, 0 releases it; the
caller needs system-logon or remote-logon authority, else 35517 `SES_INVALID_AUTHORITY`.

- **No program WSeB ships calls it** [OBS-RE]: nothing on the system imports `SESAPI` ordinal 50, and the
  name occurs nowhere else. Locking (section 1.3) does not use it. On a stock install it is never engaged.
- From an ordinary process, actions 1, 2 and 0 all return **35517** - the authority check precedes the
  parameter check [OBS].
- From a program given `/SLA` in `SECURE.SYS` [OBS]: action 1 returns 0; then **`DosExecPgm` returns 5**
  (empty failing-name buffer) and **an OS/2 `DosStartSession` returns 5** - including for the inhibiting
  program itself, which gets no exemption - while **a DOS session still starts** (rc 0). Action 2 returns
  35367 `SES_INVALID_PARAMETER`; action 0 releases, and everything starts again.

So it is a lever for a third-party logon authority (for instance, nothing runs until someone has logged
on), and it does not cover DOS sessions.

### 1.6 Installable Security Subsystems that exist

| Product | Driver | Registers as | Hooks | Notes |
|---|---|---|---|---|
| Security/2 0.4.5 (freeware) | `SSES.SYS` + `ssesctl.exe` | ISS | open/delete/move/find/directory/set-info **pre** hooks, loader open, module lookup, exec and exec-post, DOS-session create, both callgates | per-user ACLs; works beside IBM's SES [OBS] |
| Kaspersky AVP 3.0 monitor | `SEC32.SYS` | ISS | open, open-post, close | on-access virus scanner |

[OBS-RE] for the registrations and tables. Security/2 installs unattended
(`install.exe -i -d <dir>`; `-n` leaves CONFIG.SYS alone and writes the lines it wants to its `etc`
directory) [DOC] [OBS]. It puts its own `SESMGR.DLL` first on `LIBPATH` [OBS]. Its installer says `root` has
no password; its readme says the password is `root` [OBS] [DOC].

**Two ISS drivers cannot be loaded together.** Both products use the same registration kind, and the kernel
accepts one registration per kind; the second halts the system during boot with *"internal processing
error at ... 000f:6df8"* on 14.104a [OBS] (Part 2, section 2.1). Security/2's readme warns that it does not
work alongside the AVP monitor [DOC]; this is why. IBM's own `SESDD32.SYS` uses a different kind and
coexisted with Security/2 [OBS]; with the AVP monitor it should too, by the same rule [INF].

### 1.7 SES and the mouse driver

SG24-4668 11 [DOC-IBM] lists `MOUSE.SYS` and the keyboard drivers among the components modified for SES.
`SESDD32.SYS` attaches to `MOUSE$` and `KBD$` at boot and registers an activity counter with each.

**`MOUSE.SYS` 10.058, as shipped with WSeB, cannot take that registration**: with SES enabled, the first
mouse event stops the system with TRAP 000D in module `MOUSE` (`CS:EIP 0C10:00003847` on the observed
system) [OBS]. The cause [OBS-RE]: the driver's IDC entry pushes registers and locals and then far-calls
its dispatcher, and the registration handler reads the counter's selector and offset at stack offsets
that assume no such wrapper. It stores the caller's DI and SI instead, and the next mouse event
increments through that pointer. The trap screen shows exactly those values: DS holds `SESDD32`'s DI, and
ESI holds its SI with its return address above it. A VirtualBox mouse driver also traps with SES enabled
[OBS]; why was not analysed. The keyboard driver reads the arguments correctly and boots.

The tell: SES works over a remote session or keyboard-only, and the machine dies the moment the mouse
moves. Use SES without a mouse, or find an SES-built `MOUSE.SYS`; none was identified.

---

## Part 2 - The kernel interface (what SG24-4668 Appendix A withheld)

Everything here is [OBS-RE] on `OS2KRNL` 14.104a SMP retail unless tagged otherwise. Symbol names are the
kernel's own debug symbols. SG24-4668 11.1-11.3 [DOC-IBM] describes the design in words: an ISS driver calls
a new DevHlp, `DevHlp_Security`, with `DHSEC_GETEXPORT` to fetch the kernel's security helpers and
`DHSEC_SETIMPORT` to register its callouts.

### 2.1 `DevHlp_Security` is DevHlp 44h, keyed by a magic number

- DevHlp code **44h** (68) is `dh_Sec`, context flags 07h (init, task **and interrupt** time). It far-calls
  the flat routine `g_SecDevRoute`, passing the caller's registers through. (`devhlp.inc` gives this code
  no name; a DevHlp table read from the kernel's RAS copy instead of the live dispatch table will show it
  as unused - read the live one.)
- **DL=44h, EAX = a 32-bit function code, ECX = a flat parameter pointer**; the result comes back in EAX.

| EAX | Function |
|---|---|
| `48A78DF8h` | **GETEXPORT**: copies the export structure (section 2.5) to `*ECX`; the caller's first two words are major and sub-version; sub-version 0 gets 2Ch bytes, any other 3Ch |
| `73AE3627h` (bit 31 ignored) | **SETIMPORT, ISS kind** (section 2.2) |
| masked: `((EAX << 1) OR 43FDA93Ch) = 6BFFED7Ch` | **SETIMPORT, second kind** (the kernel's flag symbol says `PDF`); IBM's `SESDD32.SYS` uses `34B9A63Eh` |
| masked: `((EAX << 1) OR 43FDA93Ch) = FFFDBBBEh` | **SETIMPORT, third kind** (`AV` in the symbol); no user found |
| `5E4D7692h` | stores the **address** of the kernel's current-PTDA cell at `*ECX` |
| `33528882h` | returns 1 if the loader semaphore is held, else 0 (ignores its arguments) |
| `650EA11Eh` | trusted-path query (section 2.7) |
| `2518E571h` | audit fan-out (section 2.8) |

**Every failure halts the system**: an unrecognised EAX, a second registration of a kind already
registered, or a registration the kernel rejects. There is no error return. [INF] The masked codes look
like deliberate obscuring of the registration values.

### 2.2 Registration (SETIMPORT) and the hook list

The caller passes a table whose first word is the major version (must be 1) and second the sub-version.
Sub-version 0 means a **104h-byte** table; any other means **10Ch** (adding two large-file slots). The kernel
copies it into its own heap behind a link word, pushes it on the **front** of a list, and sets a global
"security active" flag. So **the most recently registered driver's callouts run first** - an ISS loaded
after `SESDD32.SYS` is consulted before it.

**Walker rules**, for every event slot: a slot of 0 is skipped; each driver's routine is called in turn;
**the first non-zero return stops the walk and becomes the API's return code**, and the kernel abandons the
operation (the guide's "the worker routine does not continue" [DOC-IBM]). The "pre" hooks are skipped while a
per-thread flag says a hook is already running, so a driver's own file-system helpers do not re-enter the
hooks. When nothing is registered, every call site tests the global flag and skips the hook - SES costs
nothing until a driver registers.

### 2.3 The import table, offset by offset

Offsets are into the **caller's** table. Each entry is a flat 32-bit routine address unless noted.

| Off | Callout | Off | Callout |
|---|---|---|---|
| +00 | version (word major = 1, word sub) | +4C | NewSize (sub-version 0 tables) |
| +04 | OpenPre | +50 | QueryFileInfo |
| +08 | OpenPost | +54 | MakeDir |
| +0C | ReadPre | +58 | ChangeDir |
| +10 | ReadPost | +5C | RemoveDir |
| +14 | WritePre | +60 | FindNext |
| +18 | WritePost | +64 | FindFirst (old-style 3.x find) |
| +1C | Close | +68 | FindClose |
| +20 | ChgFilePtr (sub-version 0 tables) | +6C | FindFirst/FindNext (3.x) |
| +24 | DeletePre | +70 | FindClose (3.x) |
| +28 | DeletePost | +74 | ExecPost |
| +2C | MovePre | +78 | CreateVDM |
| +30 | MovePost | +7C | CreateVDMPost |
| +34 | LoaderOpen | +80 | SetDateTime |
| +38 | GetModule (module lookup by name) | +84 | SetFileInfo |
| +3C | Exec | +88 | SetFileMode |
| +40 | FindFirst | +8C | SetPathInfo |
| +44 | **16-bit callgate handler**, a 16:16 address (section 2.6) | +90 | DevIoctl |
| +48 | **32-bit callgate handler** (section 2.6) | +94 | TrustedPathControl (section 2.7) |
| | | +98..+100 | 27 audit callouts (section 2.8) |
| | | +104 / +108 | ChgFilePtr / NewSize (sub-version non-zero tables; these **replace** +20 / +4C) |

[INF] +104/+108 are the large-file forms. Argument lists of the individual callouts were not established
and IBM publishes none; read them from the call site before relying on one. The three importers known
(`SESDD32.SYS`, Security/2, AVP) each fill a coherent subset of this map, which is the cross-check.

### 2.4 What has no hook

`DosQueryPathInfo` has no slot (measured refusal-proof, section 1.4). Of the calls that only query, just
QueryFileInfo (by handle) and the find family are hooked. `SESDD32.SYS` itself fills only Exec, ExecPost,
CreateVDM and CreateVDMPost: **IBM's SES watches process creation only**; file access control is entirely
the ISS's.

### 2.5 The export structure (GETEXPORT)

| Off | Content |
|---|---|
| +00 | version words, overwritten with the caller's |
| +04..+24 | the nine file-system helpers SG24-4668 11.2.1 [DOC-IBM] names: Read, Write, Open, Close, QFileSize, ChgFilePtr, SFFromSFN, FindNext, PathFromSFN (in this order) |
| +28 | the DOS-kernel service dispatch table: 87 flat pointers an ISS may overwrite to hook a DOS-session service (the guide's `apDemSvc`, 11.1.3 [DOC-IBM]) |
| +2C..+38 | ReadL, WriteL, QFileSizeL, ChgFilePtrL (only when the sub-version is non-zero) |

**There are no security-context helpers in the kernel** (the guide's `SecHlpQuerySubjectInfo` and the
rest): no export slot and no kernel symbol. [INF] They belong to `SESDD32.SYS`, which owns that state.

### 2.6 Callgate routers

- **32-bit:** each 32-bit DOSCALLS entry stub pushes its kernel routine and an internal API code and calls a
  small router that, unhooked, just jumps to the routine. Registering +48 rewrites the router into a jump to
  the ISS handler, which receives the code and the routine's address and must call the routine itself to
  let the call proceed (SG24-4668 11.1.2 [DOC-IBM] describes this contract). The codes were not mapped to
  ordinals.
- **16-bit:** registering +44 flips one instruction in the common 16-bit dispatcher so that every 16-bit
  call it handles detours through the handler.
- **The SMP gap.** SMP kernels have a second 16-bit dispatcher, used by 31 16-bit APIs - among them
  `DosChgFilePtr`, the internal read/write entries `DosIRead`/`DosIWrite`, `DosGetPID`/`DosGetPPID`/`DosGetPrty`,
  `DosGetInfoSeg`, `DosPortAccess`, `DosCliAccess`, the 16-bit semaphore calls, `DosGetCp`, `DosError`,
  `DosDevConfig`. It has the same detour code, but **nothing ever enables it**: a 16-bit callgate handler
  never sees those 31 calls on an SMP kernel. Uniprocessor kernels have no second dispatcher. File reads,
  writes and seeks still reach the per-event hooks. Not measured (no usable debug kernel was available);
  [OBS-RE] only. Security/2's readme reports that kernel 14.062 traps when a 16-bit handler is registered
  and 14.086 does not [DOC]; not checked.

### 2.7 Trusted path

`KBDBASE.SYS` calls `DevHlp_Security` with `650EA11Eh` from its keyboard interrupt handling. At the
Ctrl+Alt+Del site, a non-zero answer suppresses the reboot event; a latch makes it one query per key press.
The kernel asks each registered driver's +94 routine with no arguments and reduces the answer to 0 or 1.
[INF] A second keyboard call site is the other trusted-path sequence the guide names
(Ctrl+Alt+NumLock+NumLock); not decoded.

### 2.8 Audit

`2518E571h` takes a record whose code selects one of the 27 audit slots and calls that slot in **every**
registered driver - it does not stop on a non-zero return. The only caller found is `SESDD32.SYS`, auditing
its own API. The code-to-API mapping was not established.

### 2.9 Ring 3 to SESDD32

`SESAPI.DLL` does not use DosDevIOCtl. Every export calls one common stub that far-calls through a call gate
`SESDD32.SYS` provides at run time, passing a class (E5h context/control, 3 events, 64h approval/trust), a
function number and a parameter pointer. `SESControlProcessCreation` is class E5h function 8Dh.

`SESStartEvent` (SG24-4668 F.6 [DOC-IBM], which names the events but gives no values) takes a 128h-byte
structure: event code, status, then a 120h-byte data union. Codes [OBS-RE], read from the SES daemon's
dispatcher:

| Code | Event | Basis |
|---|---|---|
| 04h | LOGON | handler named in the binary |
| 08h | LOGOFF | [INF] |
| 10h | SHUTDOWN | [INF] |
| 20h | LOCK | **[OBS]** (section 1.3) |
| 40h | UNLOCK | handler named |
| 80h | CHANGE_PASSWORD | handler named |
| 100h / 200h | CREATE_PROFILE / DELETE_PROFILE | one handler; order from the guide [INF] |
| 400h | IA (identification and authentication) | handler named |

The per-authority variants of an event are the base code with a high bit set: `08000000h` query,
`10000000h` client logon authority, `20000000h` user identification authority, `40000000h` system logon
authority - sent in the order of the guide's event flows (13.8.3-13.8.5 [DOC-IBM]).

---

## Where the searches came up empty

- **IBM's KPI documentation** (SG24-4668 Appendix A): withheld by IBM; not in the redbook, the DDK or the
  Toolkit headers. No `DevHlp_Security`, import or export structure is defined in any IBM header.
- **A driver using the third registration kind**: none found among the known ISS products.
- **An SES-modified `MOUSE.SYS`**: not identified.
- **Debug-kernel confirmation** of the callgate behaviour: the WSeB debug kernels tried could not be used
  with PM running, so section 2.6 rests on static reading alone.
