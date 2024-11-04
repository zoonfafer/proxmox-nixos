{
  lib,
  python3,
  pkgs, 
  pkgsCross,
  stdenv, 
  fetchgit,
  ... 
}:

stdenv.mkDerivation rec {
  pname = "pve-edk2-firmware";
  version = "4.2023.08-4";

  src = fetchgit {
    url = "https://github.com/zoonfafer/${pname}.git";
    rev = "a4fd06bb39a9cb1ce357bf933b9b4df6feb5b45a";
    sha256 = "sha256-snd4JOD8QpSRvYD3/qy1URKh3YVRxJ0V/GlgWfB0u2k=";
    fetchSubmodules = true;
  };

  buildInputs = [ ];

  hardeningDisable = [ "format" "fortify" "trivialautovarinit" ];

  nativeBuildInputs = with pkgs; [
    dpkg fakeroot qemu
    bc dosfstools acpica-tools mtools nasm libuuid
    qemu-utils libisoburn python3
  ] ++ (lib.optional (stdenv.hostPlatform.system != "aarch64-linux") pkgsCross.aarch64-multiplatform.stdenv.cc)
    ++ (lib.optional (stdenv.hostPlatform.system != "x86_64-linux") pkgsCross.gnu64.stdenv.cc)
    ++ (lib.optional (stdenv.hostPlatform.system != "riscv64-linux") pkgsCross.riscv64.stdenv.cc);

  depsBuildBuild = [ stdenv.cc ];

  postPatch = 
    let
      pythonPath = python3.pkgs.makePythonPath (with python3.pkgs; [ pexpect ]);
    in
    ''
      patchShebangs .
      substituteInPlace ./debian/rules \
        --replace-warn /bin/bash ${pkgs.bash}/bin/bash
      substituteInPlace ./Makefile ./debian/rules \
        --replace-warn /usr/share/dpkg ${pkgs.dpkg}/share/dpkg
      substituteInPlace ./debian/rules \
        --replace-warn 'PYTHONPATH=$(CURDIR)/debian/python' 'PYTHONPATH=$(CURDIR)/debian/python:${pythonPath}'

      # Skip dh calls because we don't need debhelper
      substituteInPlace ./debian/rules \
        --replace-warn 'dh $@' ': dh $@'

      # Patch cross compiler paths
      substituteInPlace ./debian/rules ./**/CMakeLists.txt \
        --replace-warn 'aarch64-linux-gnu-' '${pkgsCross.aarch64-multiplatform.stdenv.cc.targetPrefix}'
      substituteInPlace ./debian/rules ./**/CMakeLists.txt \
        --replace-warn 'riscv64-linux-gnu-' '${pkgsCross.riscv64.stdenv.cc.targetPrefix}'
      sed -i '/^EDK2_TOOLCHAIN *=/a export $(EDK2_TOOLCHAIN)_BIN=${pkgsCross.gnu64.stdenv.cc.targetPrefix}' ./debian/rules
    '';

  buildPhase = 
    let
      mainVersion = builtins.head (lib.splitString "-" version);
    in
    ''
      make ${pname}_${mainVersion}.orig.tar.gz
      pushd ${pname}-${mainVersion}
      dpkg-source -b .
      make -f debian/rules override_dh_auto_build
    '';

  installPhase = ''
    # Copy files as mentioned in *.install files
    for f in ./debian/*.install; do
      while IFS= read -r line; do
        read -ra paths <<< "$line"
        dest="$out/''${paths[-1]}"
        mkdir -p "$dest"
        for src in "''${paths[@]::''${#paths[@]}-1}"; do
          cp $src "$dest"
        done
      done < "$f"
    done

    # Create symlinks as mentioned in *.links files
    for f in ./debian/*.links; do
      while IFS= read -r line; do
        read -ra paths <<< "$line"
        dest="$out/''${paths[-1]}"
        for src in "''${paths[@]::''${#paths[@]}-1}"; do
          ln -s "$out/$src" "$dest"
        done
      done < "$f"
    done
  '';

  passthru.updateScript = [
    ../update.py
    pname
    "--url"
    src.url
  ];

  meta = {
    description = "edk2 based UEFI firmware modules for virtual machines";
    homepage = "git://git.proxmox.com/git/${pname}.git";
    maintainers = with lib.maintainers; [ ];
  };
 }