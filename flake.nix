{
  description = "Taylor's NixOS configuration";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  # Keep Autolith's own nixpkgs pin: its SBCL and Lisp package set must match.
  inputs.autolith.url = "github:htayj/autolith";
  inputs.home-manager = {
    url = "github:nix-community/home-manager";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, autolith, home-manager, ... }:
  let
    system = "x86_64-linux";
    pkgs = import nixpkgs { inherit system; config.allowUnfree = true; };
  in {
    nixosConfigurations.nixos = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = { inherit nixpkgs; };
      modules = [
        ./hosts/nixos
      ];
    };
    packages.x86_64-linux.autolith = autolith.packages.x86_64-linux.default;
    packages.x86_64-linux.gitleaks = pkgs.gitleaks;
    packages.x86_64-linux.home-manager = home-manager.packages.${system}.default;
    homeConfigurations.tay = home-manager.lib.homeManagerConfiguration {
      inherit pkgs;
      extraSpecialArgs = { inherit autolith; };
      modules = [ ./home/tay.nix ];
    };
    devShells.${system}.default = pkgs.mkShell {
      packages = [ pkgs.gitleaks pkgs.git ];
    };
    checks.${system} = {
      home = self.homeConfigurations.tay.activationPackage;
      secrets = pkgs.runCommand "source-secret-scan" {
        nativeBuildInputs = [ pkgs.gitleaks ];
      } ''
        gitleaks dir --redact --no-banner --ignore-gitleaks-allow \
          --config ${./.gitleaks.toml} ${./.}
        touch $out
      '';
    };
  };
}
