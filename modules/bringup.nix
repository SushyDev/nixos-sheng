# Host policy, not a driver -- deliberately not imported by ./default.nix.
# What `nix build .#nixos` needs to produce an image you can get into.
#
# NOT SECURE: the root password is "password" and tty1 autologins as root.
{
  self,
  lib,
  pkgs,
  ...
}:

{
  sheng.rootfs.etcNixosSource = self;

  networking.hostName = lib.mkDefault "sheng";
  networking.networkmanager.enable = true;
  services.openssh.enable = true;

  # nssmdns6 off: the responder registers IPv4 only, and the missing AAAA
  # costs a resolver timeout per lookup.
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    publish = {
      enable = true;
      addresses = true;
      workstation = true;
    };
  };

  hardware.bluetooth.enable = lib.mkDefault true;

  environment.systemPackages = with pkgs; [
    vim
    curl
    wget
    htop
    git
    busybox # for devmem
  ];

  users.users.root.hashedPassword = "$6$e/k7.7lhroPMA6hy$ysO.xH9hAm5y0NCdKQs4AAT0MQFy0kP7F6XpVIryRAN1wNHReXXHx21zdonHiXwKuynriN9UA.OQDhhz67atj/";
  users.mutableUsers = true;

  # Set here, not as a runtime drop-in, which systemd applies first.
  services.getty.autologinUser = "root";

  system.stateVersion = lib.mkDefault "26.11";
}
