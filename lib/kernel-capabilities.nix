{ lib }:

let
  # Map each kernel-dependent Hyper-V enlightenment to the CONFIG_* options
  # the KVM module requires to advertise it via KVM_CHECK_EXTENSION.
  # Universal features (vapic, relaxed, spinlocks, frequencies, vendor_id) are
  # QEMU/libvirt-level and do not depend on the host kernel -- they are not
  # listed here and always evaluate to true.
  featureRequires = {
    vpindex = [ "KVM_HYPERV" ];
    synic = [ "KVM_HYPERV" ];
    stimer = [ "KVM_HYPERV" ];
    reset = [ "KVM_HYPERV" ];
    ipi = [ "KVM_HYPERV" ];
    tlbflush = [ "KVM_HYPERV" ];
    reenlightenment = [ "KVM_HYPERV" ];
    runtime = [ "KVM_HYPERV" ];
  };

  universalFeatures = [
    "vapic"
    "relaxed"
    "spinlocks"
    "frequencies"
    "vendor_id"
  ];

  allFeatures = universalFeatures ++ builtins.attrNames featureRequires;

  # fromConfigText: parse a kernel .config text and return a capability attrset
  # keyed by feature name. Universal features are always true. Kernel-dependent
  # features are true only if every CONFIG option they require is =y in the
  # config text.
  fromConfigText =
    configText:
    let
      hasConfigOption = opt: builtins.match ".*CONFIG_${opt}=y[ \t]*.*" configText != null;
      kernelDeps = lib.mapAttrs (
        feature: requiredOpts: lib.all hasConfigOption requiredOpts
      ) featureRequires;
    in
    kernelDeps // lib.genAttrs universalFeatures (_: true);

  # fromConfigPath: read a .config file from a path. Returns null if the file
  # does not exist (consumer falls back to setting the attrset by hand or
  # points at a different path). Expects an uncompressed .config; for
  # /proc/config.gz the consumer must gunzip first (the path will not exist
  # at eval time anyway since /proc is not in the Nix store).
  fromConfigPath =
    path: if !(builtins.pathExists path) then null else fromConfigText (builtins.readFile path);

  # Empty capabilities: every feature reported as unsupported. Useful for
  # negative tests in the contract suite.
  emptyCapabilities = lib.genAttrs allFeatures (_: false);
in
{
  inherit
    featureRequires
    universalFeatures
    allFeatures
    fromConfigText
    fromConfigPath
    emptyCapabilities
    ;
}
