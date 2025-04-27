# Building Arch Linux from Source with custom flags

First, create a Arch user that is different from root, and set this permission for it on /etc/sudoers:

``` bash
##
## User privilege specification
##
root ALL=(ALL:ALL) ALL
builder ALL=(ALL:ALL) NOPASSWD: ALL
```

This will allow sudo execution without asking for password, which is needed for building all the packages.

Next, configure /etc/makepkg.conf with custom flags(set your own architecture for -march and -mtune variables, or use `native` to select from system (does not work in VMs)):

``` bash
#########################################################################
# ARCHITECTURE, COMPILE FLAGS
#########################################################################
#
CARCH="x86_64"
CHOST="x86_64-pc-linux-gnu"

#-- Compiler and Linker Flags
#CPPFLAGS=""
CFLAGS="-O2 -pipe -march=skylake -mtune=skylake -fno-plt -fexceptions \
        -Wp,-D_FORTIFY_SOURCE=3 -Wformat -Werror=format-security \
        -fstack-clash-protection -fcf-protection \
        -fno-omit-frame-pointer -mno-omit-leaf-frame-pointer"
KCFLAGS="-O2 -pipe -march=skylake -mtune=skylake"
CXXFLAGS="$CFLAGS -Wp,-D_GLIBCXX_ASSERTIONS"
LDFLAGS="-Wl,-O2 -Wl,--sort-common -Wl,--as-needed -Wl,-z,relro -Wl,-z,now \
         -Wl,-z,pack-relative-relocs"
LTOFLAGS="-flto=auto"
#-- Make Flags: change this for DistCC/SMP systems
MAKEFLAGS="-j$(nproc)"
#-- Debugging flags
DEBUG_CFLAGS="-g"
DEBUG_CXXFLAGS="$DEBUG_CFLAGS"
```

These flags will work for most of the arch packages, but some will still force their own flags. For this reason, we *must* make a detour in gcc and cc, to remove their imposed flags, by setting our desired architecture (skylake in my case):

Create this file at /usr/local/bin/cc
```bash
#!/bin/bash

ARGS=()
for arg in "$@"; do
  case "$arg" in
    -march=*|-mtune=*) ;;
    *) ARGS+=("$arg") ;;
  esac
done

exec /usr/bin/cc -O2 -pipe -march=skylake -mtune=skylake "${ARGS[@]}"
```

And this at /usr/local/bin/gcc
```bash
#!/bin/bash

ARGS=()
for arg in "$@"; do
  case "$arg" in
    -march=*|-mtune=*) ;;
    *) ARGS+=("$arg") ;;
  esac
done

exec /usr/bin/gcc -O2 -pipe -march=skylake -mtune=skylake "${ARGS[@]}"
```
Make them both executable! (chmod 777 /usr/local/bin/cc and /usr/local/bin/gcc)

Now, create a chroot environment:

``` bash
mkdir -p ~/archbuild
mkarchroot ~/archbuild/root base-devel
```

Create the packages folder inside ~/archbuild:
``` bash
mkdir packages
```

Now, inside ~/archbuild create the script that will build everything:

``` bash
cd packages

# loop for every package in pacman, and build with chroot
for pkg in $(pacman -Qq); do
    if [ -d "$pkg" ]; then continue; fi
    echo "Cloning and building: $pkg"
    pkgctl repo clone "$pkg" && cd "$pkg" || continue
    makechrootpkg -c -r ~/archbuild -- --skipinteg --noconfirm --nocheck --clean --cleanbuild
    cd ..
done

# For Linux Kernel
mkdir linux
pkgctl repo clone linux
cd linux
makechrootpkg -c -r ~/archbuild -- --skipinteg --noconfirm --nocheck --clean --cleanbuild
```