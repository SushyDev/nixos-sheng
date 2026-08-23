# Read-only diagnostic kernel module, built against the exact sheng
# kernel's headers/config -- see sheng_mdss_test.c for what it does and
# why. Not part of the system closure; built standalone and scp'd to
# the device for one-off insmod testing during U-Boot driver bring-up.
{ stdenv, lib, shengKernel }:

stdenv.mkDerivation {
  pname = "sheng-mdss-test-module";
  version = "0.1.0";

  src = ./.;

  makeFlags = [
    "KDIR=${shengKernel.dev}/lib/modules/${shengKernel.modDirVersion}/build"
  ];

  installPhase = ''
    runHook preInstall
    mkdir -p $out
    cp sheng_mdss_test.ko $out/
    cp sheng_dsi_lab.ko $out/
    runHook postInstall
  '';

  meta = {
    description = "Read-only MDSS_GDSC register dump module for the sheng kernel";
    platforms = [ "aarch64-linux" ];
  };
}
