# `programs.filmcraft` for NixOS and home-manager.
#
# The option set is shared; `kind` selects only the behaviour the target module system can express:
# home-manager writes the settings overlay and the palette variable per user, NixOS installs the
# package and the MIME default for the whole system. NixOS cannot write per-user files, so it never
# writes `settings`.
#
# The overlay is `settings.override.json` beside `preferences.json`
# (`crates/engine/src/autosave.rs`), merged over the saved preferences at start-up. FilmCraft never
# writes it, so the declarative values survive a normal save. Unlike most of the suite, FilmCraft
# keeps its preferences in the data directory (`~/.local/share/filmcraft`), not the config
# directory, so that is where this module writes the overlay.
{ kind }:
{
  config,
  lib,
  pkgs,
  # The package of this flake; `flake.nix` passes it through `_module.args`, so importing the
  # module directly needs no overlay.
  filmcraftPackage ? pkgs.filmcraft,
  ...
}:

let
  inherit (lib)
    mkEnableOption
    mkIf
    mkOption
    types
    ;

  cfg = config.programs.filmcraft;

  jsonFormat = pkgs.formats.json { };

  # The same list as `packaging/linux/ai.storyteller.filmcraft.desktop` (`MimeType=`).
  mimeTypes = [
    "application/x-filmcraft"
    "video/mp4"
    "video/x-m4v"
    "video/quicktime"
    "video/x-matroska"
    "video/webm"
    "video/vnd.avi"
    "video/x-msvideo"
    "application/mxf"
    "video/mp2t"
    "video/mpeg"
    "video/3gpp"
  ];

  desktopFile = "ai.storyteller.filmcraft.desktop";

  # The per-user data directory: `$XDG_DATA_HOME/filmcraft` on Linux.
  settingsDir = "${config.xdg.dataHome}/filmcraft";

  associations = lib.genAttrs mimeTypes (_: [ desktopFile ]);
in
{
  options.programs.filmcraft = {
    enable = mkEnableOption "FilmCraft";

    package = mkOption {
      type = types.package;
      default = filmcraftPackage;
      defaultText = lib.literalMD "the `filmcraft` package of this flake";
      description = "The FilmCraft package to install.";
    };

    setAsDefault = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Open FilmCraft projects and video files with FilmCraft by default (the MIME types of
        `packaging/linux/ai.storyteller.filmcraft.desktop`).
      '';
    };

    settings = mkOption {
      type = jsonFormat.type;
      default = { };
      description = ''
        Free-form preferences merged over the app's settings. Home-manager writes them to
        `~/.local/share/filmcraft/settings.override.json`; NixOS ignores them, because it cannot
        write per-user files.
      '';
    };

    paletteFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = ''
        Optional shared palette file, exported as `CRAFT_PALETTE_FILE` by home-manager.
      '';
    };
  };

  config = lib.mkMerge [
    (mkIf cfg.enable (
      if kind == "nixos" then
        {
          environment.systemPackages = [ cfg.package ];
          xdg.mime.defaultApplications = mkIf cfg.setAsDefault associations;
        }
      else
        {
          home.packages = [ cfg.package ];
          home.sessionVariables = mkIf (cfg.paletteFile != null) {
            CRAFT_PALETTE_FILE = toString cfg.paletteFile;
          };
          home.file."${settingsDir}/settings.override.json" = mkIf (cfg.settings != { }) {
            source = jsonFormat.generate "filmcraft-settings.override.json" cfg.settings;
          };
          xdg.mimeApps = mkIf cfg.setAsDefault {
            enable = true;
            defaultApplications = associations;
            # Associated even when another application stays the default.
            associations.added = associations;
          };
        }
    ))
  ];
}
