# Analysis Blindspot Cookbook (Issue #77 batch 2)

> **SSoT**: blindspot recipes R52-R81 (**BS-*** overlay IDs, not routing PRIMARY). **Not** a third master workflow. Obey ADF R1-R51 + re-agent-workflow + A-T/U-AV first.
> Lab only. Detection+forensics; **no bypass tutorial** for kernel/integrity/injection weaponization.

## 0. Evidence IDs

E-rust-identified, E-golang-identified, E-cpp-rtti, E-objc-msg, E-dotnet-aot, E-string-custom-crypto, E-vmp-protected, E-ollvm-level, E-obfuscation-combo, E-integrity-check, E-proxy-dll, E-process-hollowing, E-apc-inject, E-atom-bombing, E-process-doppelganging, E-exception-chain, E-byovd-advanced, E-edr-callback, E-kernel-protect-tamper, E-uefi-bootkit, E-cloud-cred-theft, E-ole-analysis, E-pdf-malicious, E-wasm-reverse, E-custom-protocol, E-elf-linux, E-llm-hallucination, E-mcp-bootstrap, E-context-pollution, E-anchor-verify

## 1. P0 recipes

### R52 Rust
Trigger: _ZN mangling, core::/std::, panic/unwrap. Action: Rust sigs; panic edges; dynamic if names collapse. Evidence: E-rust-identified. Route: ida/radare2/re.

### R53 Golang
Trigger: runtime.*, go.string.*, newobject. Action: GoReSym-class symbol/type restore; distrust C-like decompile. Evidence: E-golang-identified.

### R56 .NET Native AOT
Trigger: native entry; no classic _CorExeMain/IL path. Action: do not force dnSpy IL workflow; native+AOT tools; managed IL stays dotnet-reverse. Evidence: E-dotnet-aot.

### R57 Custom string crypto
Trigger: high-entropy rdata without standard decoders. Action: entropy -> crypto constants -> dynamic decrypt dump. Evidence: E-string-custom-crypto.

### R58 VMP / virtualizer (tiered)
Trigger: VMP sections, vm_entry, extreme entropy. Action: Tier A qualitative+dynamic + E-vmp-protected; Tier B lab tracer under feasibility gate. MUST NOT claim full static undevirt without Evidence. Evidence: E-vmp-protected.

### R62 Proxy DLL
Trigger: exports overlap system DLL; loads real DLL; odd/missing forwarders. Action: diff exports; Path dropper->proxy->payload (R50). Evidence: E-proxy-dll.

### R78 LLM hallucination
Trigger: API/CFG claims without offset/tool output. Action: R41 grounded bar; else ungrounded. Evidence: E-llm-hallucination.

### R80 Context pollution
Trigger: contradicts confirmed Evidence/timeline; reused rejected hypothesis. Action: re-read timeline+Evidence (R2); drop polluted summary. Evidence: E-context-pollution.

## 2. P1 short rows

| ID | Action | Evidence |
|----|--------|----------|
| R54 C++ RTTI/EH | mark vtables, parse RTTI, xref virtuals | E-cpp-rtti |
| R55 ObjC/Swift | class-dump, objc libs (Darwin) | E-objc-msg |
| R59 OLLVM tier | P0/P1/P2; P2->dynamic; pointer A-T H | E-ollvm-level |
| R60 combo | unflatten then predicates | E-obfuscation-combo |
| R61 integrity | detect self-hash API; lab only | E-integrity-check |
| R63 hollowing | SUSPENDED+unmap+WPM+resume detect | E-process-hollowing |
| R64 APC | QueueUserAPC chain | E-apc-inject |
| R65 AtomBombing | GlobalAddAtom chain | E-atom-bombing |
| R66 doppelganging | TxF transaction chain | E-process-doppelganging |
| R67 SEH+VEH | both + faults | E-exception-chain |
| R68 BYOVD | signed sys + vuln hash DB + IOCTL detect | E-byovd-advanced |
| R69 EDR cb | notify routines | E-edr-callback |
| R70 PG/DSE | detect tamper intent only | E-kernel-protect-tamper |
| R71 UEFI | efi/ESP | E-uefi-bootkit |
| R72 cloud/IMDS | AWS_* / 169.254.169.254 | E-cloud-cred-theft |
| R73 OLE | oleid/olevba/XLM/DDE | E-ole-analysis |
| R74 PDF | /JS /OpenAction /Launch | E-pdf-malicious |
| R75 WASM | wasm2wat imports | E-wasm-reverse |
| R76 C2 proto | magic+handlers lab | E-custom-protocol |
| R77 ELF | LD_PRELOAD/ptrace/proc | E-elf-linux |
| R79 MCP boot | pin path only #76 | E-mcp-bootstrap |
| R81 anchors | P2 idea -> R41/case-review | E-anchor-verify |

## 3. P2 index

OLLVM detail A-T H; IAT/TLS workflow; BYOVD/VBA U-AV; pin #76; decision ADF R1-R51.

## 4. Safety

Authorized lab only. R61/R70/injection = detect+Evidence, no bypass tutorial. Failures still Evidence.

## 5. Checklist add-on

6 language R52-R56; 7 packer tier R58-R60; 8 injection/proxy R62-R67; 9 grounded R78/R80+R41.
