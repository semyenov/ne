{
  description = "A modern NixOS configuration with flake-parts";

  inputs = {
    # Nixpkgs - using NixOS 25.05
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";

    # Nixpkgs unstable for bleeding edge packages
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";

    # Home Manager for user environment management
    home-manager = {
      url = "github:nix-community/home-manager/release-25.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Flake-parts for modular flake organization
    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };

    # Hardware configuration for various devices
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";

    # Declarative disk partitioning
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs@{ self, nixpkgs, flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [ "x86_64-linux" "aarch64-darwin" ];
      
      perSystem = { config, self', pkgs, system, ... }: {
        # Development shell
        devShells.default = pkgs.mkShell {
          packages = with pkgs; [
            git
            nixpkgs-fmt
            statix
            deadnix
            nil
            nixd
          ];
          
          shellHook = ''
            echo "NixOS Development Shell"
            echo "Available commands:"
            echo "  nixos-rebuild switch --flake .#nixos"
            echo "  nix flake update"
            echo "  nix flake check"
          '';
        };
        
        # Formatter
        formatter = pkgs.nixpkgs-fmt;
        
        # Custom packages (only for Linux)
        packages = if system == "x86_64-linux" then {
          cursor-appimage = pkgs.callPackage ./packages/cursor-appimage.nix { };
          yandex-music = pkgs.callPackage ./packages/yandex-music.nix { };
        } else { };
      };
      
      flake = {
        # NixOS configurations
        nixosConfigurations = {
          nixos = nixpkgs.lib.nixosSystem {
            system = "x86_64-linux";
            specialArgs = { inherit inputs; };
            
            modules = [
              # Hardware configuration
              ./hosts/default/hardware-configuration.nix
              
              # Main system configuration
              ./hosts/default/configuration.nix
              
              # Apply overlays
              { nixpkgs.overlays = [ self.overlays.default self.overlays.unstable-packages ]; }
              
              # Home Manager as NixOS module
              inputs.home-manager.nixosModules.home-manager
              {
                home-manager.useGlobalPkgs = true;
                home-manager.useUserPackages = true;
                home-manager.extraSpecialArgs = { inherit inputs; };
                home-manager.backupFileExtension = "backup";
                
                # User configurations
                home-manager.users.semyenov = import ./home/users/semyenov.nix;
              }
            ];
          };
        };
        
        # Overlays for package modifications
        overlays = {
          default = import ./overlays/default.nix;
          
          # Add unstable packages overlay
          unstable-packages = final: prev: {
            unstable = import inputs.nixpkgs-unstable {
              system = prev.system;
              config.allowUnfree = true;
            };
          };
        };
        
        # NixOS modules that can be imported by other flakes
        nixosModules = {
          # example-module = ./modules/example.nix;
        };
        
        # Templates for creating new NixOS configurations
        templates = {
          default = {
            path = ./.;
            description = "A modern NixOS configuration template";
          };
        };
      };
    };
}