{
  lib,
  OVMF,
  autovirt,
  patchutils,
  secureBoot ? true,
  msVarsTemplate ? secureBoot,
  tpmSupport ? true,
}:
let
  # AutoVirt EDK2 patch removes VM indicators from OVMF firmware:
  # - Clears VirtualMachine bit in SMBIOS Type 0
  # - Replaces Red Hat PCI vendor IDs with AMD/Intel
  # - Renames VMM-prefixed variables
  # - Overrides ACPI OEM fields
  autovirtPatch =
    let
      candidates = builtins.filter (n: lib.hasPrefix "AMD-edk2-stable" n && lib.hasSuffix ".patch" n) (
        builtins.attrNames (builtins.readDir "${autovirt}/patches/EDK2")
      );
    in
    assert lib.assertMsg (
      candidates != [ ]
    ) "ovmf-stealth: no AMD-edk2-stable*.patch found in autovirt/patches/EDK2";
    "${autovirt}/patches/EDK2/${builtins.head (lib.sort (a: b: a > b) candidates)}";
in
# Apply patches directly to OVMF via overrideAttrs — nixpkgs OVMF uses
# edk2.src (the raw source), so patching edk2 via overrideAttrs is a
# no-op. The AutoVirt patch includes a BaseTools hunk, but BaseTools is
# a separate pre-built derivation symlinked into the OVMF build tree.
# filterdiff strips that hunk so only OvmfPkg/MdeModulePkg/SecurityPkg
# hunks are applied.
(OVMF.override {
  inherit secureBoot msVarsTemplate tpmSupport;
}).overrideAttrs
  (old: {
    pname = "OVMF-stealth";

    nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ patchutils ];

    postPatch = (old.postPatch or "") + ''
      echo "=== OVMF-stealth: applying AutoVirt EDK2 patch (BaseTools excluded) ==="
      filterdiff -x '*/BaseTools/*' ${autovirtPatch} | patch -p1 --no-backup-if-mismatch
      echo "=== OVMF-stealth: AutoVirt patch applied ==="

      # Replace firmware vendor string. The PCD default L"EDK II" lives in
      # MdeModulePkg.dec (not the DSC). sed handles CRLF line endings.
      sed -i 's|L"EDK II"|L"American Megatrends Inc."|g' \
        MdeModulePkg/MdeModulePkg.dec OvmfPkg/OvmfPkgX64.dsc 2>/dev/null || true
      if grep -rq 'L"EDK II"' MdeModulePkg/MdeModulePkg.dec OvmfPkg/OvmfPkgX64.dsc; then
        echo "FATAL: firmware vendor string still contains L\"EDK II\""
        exit 1
      fi

      # BGRT (Boot Graphics Resource Table) is kept -- RDNA 4 (Navi 48) needs
      # the BGRT for a clean UEFI-to-Windows framebuffer handoff. Without it,
      # Windows reinitializes the display engine during ExitBootServices,
      # producing green/red framebuffer corruption on passthrough GPUs.
      # VMAware detects the TianoCore logo CRC (0x110350C5); replace the logo
      # with a blank image to neutralize the CRC without removing BGRT.
      # VMAware CRC 0x110350C5 matches the stock TianoCore logo bitmap.
      # A blank or custom logo in LogoDxe would break the CRC match.

      # AutoVirt's EDK2 patch sets INTEL_Q35_MCH_DEVICE_ID to 0x14D8 (AMD).
      # The matching QEMU patch also sets the MCH to 0x14D8. Both sides
      # agree, so OVMF's Q35 PEI init (TSEG/SMRAM) works: the registers
      # are at fixed Q35 offsets regardless of the advertised device ID.
      # Keep 0x14D8 for a consistent all-AMD PCI topology.
      if ! grep -q 'INTEL_Q35_MCH_DEVICE_ID' OvmfPkg/Include/IndustryStandard/Q35MchIch9.h; then
        echo "FATAL: INTEL_Q35_MCH_DEVICE_ID define not found in Q35MchIch9.h"
        exit 1
      fi

      echo "=== OVMF-stealth postPatch complete ==="
    '';

    meta = (old.meta or { }) // {
      description = "OVMF firmware with AutoVirt hardware emulation patches";
    };
  })
