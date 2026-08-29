# Read-only diagnostic kernel module, built standalone and scp'd to the device
# for one-off insmod testing. See sheng_mdss_test.c.
{
  stdenv,
  lib,
  shengKernel,
}:

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
