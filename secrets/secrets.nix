let
  IanHollow = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIO3PjFNVCaBfwUJIKjQeBoK2kz0VaLdNAQVUb5pJdPPf";
  homeServerVm = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIC4EqEGMCbdAeSwbmcjzSHtpuhUPOAp+IjOjNaGlhC4v";
in
{
  "homelab-vpn-privatekey.age".publicKeys = [
    IanHollow
    homeServerVm
  ];
}
