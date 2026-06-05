{
  description = "VM hardware emulation stack for NixOS — QEMU, OVMF, ACPI, SMBIOS, timing";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    git-hooks = {
      url = "github:cachix/git-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    std = {
      url = "github:Daaboulex/nix-packaging-standard?ref=v2.5.0";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.git-hooks.follows = "git-hooks";
    };

    autovirt = {
      url = "github:Scrut1ny/AutoVirt";
      flake = false;
    };
    better-timing = {
      url = "github:SamuelTulach/BetterTiming";
      flake = false;
    };
  };

  outputs =
    inputs@{ flake-parts, self, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [ "x86_64-linux" ];

      imports = [ inputs.std.flakeModules.base ];

      flake.overlays.default = final: _prev: {
        qemu-stealth = self.packages.${final.stdenv.hostPlatform.system}.default;
        ovmf-stealth = self.packages.${final.stdenv.hostPlatform.system}.ovmf-stealth;
        acpi-ssdt-stealth = self.packages.${final.stdenv.hostPlatform.system}.acpi-ssdt-stealth;
        smbios-extract = self.packages.${final.stdenv.hostPlatform.system}.smbios-extract;
        smbios-stealth-tables = self.packages.${final.stdenv.hostPlatform.system}.smbios-stealth-tables;
      };

      flake.nixosModules.default = import ./module.nix;

      flake.lib = import ./lib.nix { inherit (inputs.nixpkgs) lib; };

      perSystem =
        { pkgs, ... }:
        {
          packages.default = pkgs.callPackage ./qemu/package.nix { inherit (inputs) autovirt; };
          packages.ovmf-stealth = pkgs.callPackage ./ovmf/package.nix { };
          packages.acpi-ssdt-stealth = pkgs.callPackage ./acpi/package.nix { };
          packages.smbios-extract = pkgs.callPackage ./smbios/package.nix { };
          packages.smbios-stealth-tables = pkgs.callPackage ./smbios/tables-package.nix { };

          checks.module-eval-nixos = inputs.std.lib.nixosModuleCheck {
            inherit (inputs) nixpkgs;
            inherit (pkgs.stdenv.hostPlatform) system;
            overlays = [ self.overlays.default ];
            module = ./module.nix;
            config.myModules.vfio.stealth.enable = true;
          };

          checks.boot-smoke = pkgs.testers.runNixOSTest {
            name = "qemu-stealth-boot-smoke";
            globalTimeout = 600;
            nodes.machine =
              { lib, ... }:
              {
                virtualisation.qemu.package = lib.mkForce self.packages.${pkgs.stdenv.hostPlatform.system}.default;
                virtualisation.useEFIBoot = true;
                # Disable Secure Boot for CI: the NixOS test kernel is unsigned,
                # so OVMF with msVarsTemplate (MS keys enrolled + SB enforced)
                # rejects it. The stealth patches are still fully present.
                virtualisation.efi.OVMF =
                  lib.mkForce
                    (self.packages.${pkgs.stdenv.hostPlatform.system}.ovmf-stealth.override {
                      secureBoot = false;
                    }).fd;
              };
            testScript = ''
              machine.wait_for_unit("multi-user.target", timeout=300)
            '';
          };
        };
    };
}
