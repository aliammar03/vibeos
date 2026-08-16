{ pkgs, ... }:
{
  # Bumping this is a Home Manager data-format migration, not a "what
  # version am I on" field. Leave it alone once set.
  home.stateVersion = "26.05";

  # git + delta. Identity (user.name/email) and the gh credential helper
  # already live in ~/.gitconfig (set up outside Nix by `gh auth setup-git`)
  # and take precedence over anything set here for the same keys, so we
  # deliberately don't duplicate them — this only adds delta as the diff/
  # blame/show pager, which ~/.gitconfig doesn't already set.
  programs.git.enable = true;
  programs.delta.enable = true;
  programs.delta.enableGitIntegration = true;

  # zsh: plugins + aliases. `programs.zsh.enable` here manages ~/.zshrc;
  # the system module (configuration.nix) still owns /etc/zshrc and the
  # /etc/shells registration.
  programs.zsh.enable = true;
  programs.zsh.enableCompletion = true;
  programs.zsh.autosuggestion.enable = true;
  programs.zsh.syntaxHighlighting.enable = true;
  # eza's module sets `ll = "eza -l"` by default; override to match what
  # we were using before this migration.
  programs.zsh.shellAliases.ll = "eza -la";

  programs.starship.enable = true;
  programs.starship.enableZshIntegration = true;

  programs.zoxide.enable = true;
  programs.zoxide.enableZshIntegration = true;

  programs.fzf.enable = true;
  programs.fzf.enableZshIntegration = true;

  # Also sets ls/ll/la/lt/lla aliases for zsh via enableZshIntegration.
  programs.eza.enable = true;
  programs.eza.enableZshIntegration = true;

  # Multiplexer available on demand; not auto-started on shell open.
  programs.zellij.enable = true;

  programs.btop.enable = true;
}
