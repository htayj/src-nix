{ pkgs, emacs-config, ... }:
let
  # Keep the new branch pinned in flake.lock; adapt only its host integration.
  source = pkgs.applyPatches {
    name = "taymacs-nixos";
    src = emacs-config;
    patches = [ ./emacs/nixos.patch ];
  };
in
{
  programs.emacs = {
    enable = true;
    package = pkgs.emacs-pgtk;
    extraPackages = epkgs: with epkgs; [
      org erc-hl-nicks treesit-auto markdown-mode rainbow-delimiters colorful-mode
      vertico orderless marginalia consult web-mode corfu sudo-edit magit
      purescript-mode slime nix-mode lsp-mode typst-ts-mode nushell-ts-mode
      paredit modus-themes apheleia expand-region org-transclusion s dash
      vterm ai-code aidermacs evil evil-collection evil-surround undo-tree
      stumpwm-mode
      (treesit-grammars.with-grammars (grammars: with grammars; [
        tree-sitter-bash tree-sitter-c tree-sitter-cpp tree-sitter-css
        tree-sitter-go tree-sitter-html tree-sitter-java tree-sitter-javascript
        tree-sitter-json tree-sitter-lua tree-sitter-nix tree-sitter-nu
        tree-sitter-python tree-sitter-ruby tree-sitter-rust tree-sitter-toml
        tree-sitter-tsx tree-sitter-typescript tree-sitter-typst tree-sitter-yaml
      ]))
    ];
  };

  # Link only the configuration, never the old host's precompiled grammars or
  # Custom output. Emacs can write its history/cache alongside these symlinks.
  home.file = builtins.listToAttrs (map (name: {
    name = ".emacs.d/${name}";
    value.source = "${source}/${name}";
  }) [ "early-init.el" "init.el" "ai.el" "evil.el" ]) // {
    ".emacs.d/mail.el".source = ./emacs/mail.el;
    # Local encryption aliases; adding certified UIDs requires each owner.
    ".gnupg/gpg.conf".text = ''
      group donk@nogroup.group=1F5A5CDCC54EA1745CEE3825212B3C4FDF820C58
      group gronk@nogroup.group=E5BE2168489C61A55AB4AC5A997257BF7C0F99D3
      group bubu@nogroup.group=E6C3BA8819B6B49612F582E05DAB2644C95F5D96
    '';
  };

  home.packages = with pkgs; [
    dejavu_fonts unifont
    ripgrep fd
    sbcl nil
    nodejs typescript-language-server vscode-langservers-extracted
    typst tinymist dprint
  ];
}
