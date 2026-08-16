{ pkgs, ... }:
{
  # Split out because it's long and self-contained: the fastfetch config and
  # login greeting (`vibe`).
  imports = [ ./modules/landing.nix ];

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
  programs.eza.git = true; # show per-file git status in listings
  programs.eza.icons = "auto"; # filetype icons — needs the Nerd Font

  # Multiplexer available on demand; not auto-started on shell open.
  programs.zellij.enable = true;

  programs.btop.enable = true;

  # Moved here from environment.systemPackages so the catppuccin module
  # can theme it — it only themes home-manager-managed programs.
  programs.bat.enable = true;

  # ── Look and feel ────────────────────────────────────────────────────
  # One switch themes every supported program we have installed: bat,
  # btop, delta, eza, fzf, starship, zellij, zsh-syntax-highlighting.
  # Module is registered in configuration.nix (home-manager.sharedModules).
  catppuccin.enable = true;
  catppuccin.flavor = "mocha";
  catppuccin.accent = "mauve";

  # Custom two-line framed prompt. Catppuccin's starship module supplies
  # the `catppuccin_mocha` palette (so the colour names below resolve) and
  # sets `format` with mkDefault, which this overrides.
  #
  # Everything you type starts at the same column regardless of how long
  # the path or branch name is, because the input line is its own row.
  programs.starship.settings = {
    add_newline = true;

    format =
      "[╭─](surface2)"
      + "$directory$git_branch$git_status$nix_shell$cmd_duration"
      + "$line_break"
      + "[╰─](surface2)$character";

    directory = {
      format = "[ $path]($style)[$read_only]($read_only_style) ";
      style = "bold mauve";
      truncation_length = 4;
      truncation_symbol = "…/";
      truncate_to_repo = true;
      read_only = " ";
      read_only_style = "red";
    };

    git_branch = {
      format = "[$symbol$branch]($style) ";
      symbol = " ";
      style = "bold pink";
    };

    # `\${count}` is escaped so Nix passes the literal ${count} through to
    # starship, which does its own substitution.
    git_status = {
      format = "([$all_status$ahead_behind]($style) )";
      style = "bold peach";
      ahead = "⇡\${count}";
      behind = "⇣\${count}";
      diverged = "⇕⇡\${ahead_count}⇣\${behind_count}";
      modified = "!\${count}";
      staged = "+\${count}";
      untracked = "?\${count}";
      deleted = "✘\${count}";
      renamed = "»\${count}";
      conflicted = "=\${count}";
      stashed = "≡";
    };

    # Shows when you're inside a `nix develop` / `nix-shell`.
    nix_shell = {
      format = "[$symbol$state]($style) ";
      symbol = " ";
      style = "bold blue";
    };

    # Only appears for commands slower than 2s.
    cmd_duration = {
      format = "[ $duration]($style) ";
      style = "yellow";
      min_time = 2000;
    };

    character = {
      success_symbol = "[❯](bold green)";
      error_symbol = "[❯](bold red)";
      vimcmd_symbol = "[❮](bold green)";
    };

    # Single-user WSL box — no value in showing who/where on every prompt.
    username.disabled = true;
    hostname.disabled = true;
  };
}
