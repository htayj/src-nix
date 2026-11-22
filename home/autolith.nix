{ config, lib, pkgs, autolith, ... }:
let
  package = autolith.packages.${pkgs.stdenv.hostPlatform.system}.default;
  source = "${config.home.homeDirectory}/projects/autolith";
  extension = pkgs.stdenv.hostPlatform.extensions.sharedLibrary;
  dev = pkgs.writeShellApplication {
    name = "autolith-dev";
    runtimeInputs = [ pkgs.bash pkgs.coreutils pkgs.git pkgs.gnugrep pkgs.perl pkgs.bubblewrap ];
    text = ''
      if [[ ! -x "${source}/bin/autolith" ]]; then
        echo "Autolith checkout missing: ${source}/bin/autolith" >&2
        exit 1
      fi
      # Use the packaged dependency closure, but load the mutable checkout.
      export AUTOLITH_SBCL="${package.runtime}/bin/sbcl"
      export AUTOLITH_SBCL_SOURCE_ROOT="${package.sbclSource}"
      export AUTOLITH_PROJECT_SETUP="${package.autolithSystem}/.qlot/setup.lisp"
      export COLORLISP_NATIVE_LIBRARY="${package.colorlispNativeLibrary}/lib/libcolorlisp-tree-sitter${extension}"
      export AUTOLITH_FFF_LIBRARY="${package.fffLibrary}/lib/libfff_c${extension}"
      export CL_EXEC_SANDBOX_PROCESS_GROUP_HELPER="${package.sandboxHelper}/libexec/cl-exec-sandbox-process-group"
      export CL_EXEC_SANDBOX_BWRAP="${pkgs.bubblewrap}/bin/bwrap"
      export CL_EXEC_SANDBOX_HELPER="${package.sandboxHelper}/libexec/cl-exec-sandbox-helper"
      # Do not inherit an installed image's ASDF mapping or saved core selection.
      unset AUTOLITH_NIX_SOURCE_ROOT AUTOLITH_ASDF_CACHE AUTOLITH_INSTALLATION_KIND
      unset AUTOLITH_ACTIVE_CORE AUTOLITH_RECOVERY_CORE
      exec "${source}/bin/autolith" --from-source "$@"
    '';
  };
  developmentSkill = pkgs.writeText "autolith-local-development.sexp" ''
    (:autolith-skill
     :version 1
     :name "local-development"
     :description "Develop this local Autolith fork, switch between autolith-dev and the installed Nix version, and promote source changes."
     :instructions "The mutable fork is /home/taylor/projects/autolith; Home Manager configuration is /home/taylor/src. Read each repository's AGENTS.md and Git status before editing. autolith-dev loads the current checkout from source on every launch, including uncommitted edits, using the installed fork's pinned Nix dependencies. It preserves the caller's workspace. Plain autolith runs the GitHub-pinned installed version. Source edits do not automatically reload an already running process. This skill is managed by home/autolith.nix; edit that source rather than this generated file.

    To cut over to development: finish or stop active jobs, record the current conversation identifier and workspace, save a durable handoff in the conversation, then exit normally and launch autolith-dev resume from the same workspace; select the same conversation. Use the command's help to verify explicit conversation selection syntax. Do not start a competing interactive process from a shell tool or kill your own process before recording the handoff. Tell the user when a terminal relaunch is needed. --from-source bypasses the saved startup core, but ordinary private replay and user initialization still apply; --pristine is a separate rescue option that skips them. Do not change credentials, delete state, or claim source edits are running until the replacement process is verified.

    For subsequent source edits, run the fork's relevant checks and relaunch autolith-dev to load them. If SBCL or dependencies change, push the fork changes and refresh the autolith input and Home Manager closure before using this wrapper. To promote a tested revision: push it to the fork's default branch, then in /home/taylor/src run nix flake update autolith --flake path:., scripts/check-secrets, and rbh. Follow repository policy for checks and signed commits. No sudo or NixOS switch is needed. After activation, exit and launch autolith resume from the same workspace to return to the installed version and select the recorded conversation. Validate version/source provenance in the new process; an existing live image is not replaced by rbh.")
  '';
in
{
  home.packages = [ dev ];
  # Autolith confines skill source truenames to its skill roots, so a normal
  # Home Manager symlink into /nix/store cannot be discovered.
  home.activation.autolithDevelopmentSkill = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    run ${pkgs.coreutils}/bin/install -Dm644 ${developmentSkill} \
      "${config.xdg.configHome}/autolith/skills/local-development/SKILL.sexp"
  '';
}
