# Building Arch Linux from Source with custom flags

First, create an Arch user that is different from root, and set this permission for it on /etc/sudoers:

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

Create two files like this at /usr/local/bin/cc and /usr/local/bin/gcc, but for gcc change the exec call to gcc. Create them both inside and outside of chroot:

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

Now, create this for every python-config you have (which python-config) at /usr/local/bin/ both inside and outside of chroot. This is just for the python related package `libnewt`:
``` bash
#!/bin/bash

if [[ "$1" == "--cflags" ]]; then
    # Call the real python-config, but strip -march and -mtune
    /usr/bin/python3.13-config --cflags | sed -E 's/-march=[^[:space:]]+//g' | sed -E 's/-mtune=[^[:space:]]+//g'
else
    /usr/bin/python3.13-config "$@"
fi
```

Make them all executable! (chmod 777 *)

Next, set your `.gitconfig` to ignore ssh calls and use HTTP/HTTPS instead:
``` bash
[http]
        version = HTTP/1.1
        postBuffer = 524288000
        sslVerify = false
        lowSpeedLimit = 0
        lowSpeedTime = 999999
        sslBackend = openssl
        curloptResolve = git.savannah.gnu.org:443:209.51.188.168
[url "https://gitlab.archlinux.org/"]
        insteadOf = git@gitlab.archlinux.org:
[url "https://git.savannah.gnu.org/"]
        insteadOf = git@git.savannah.gnu.org:
[url "http://git.savannah.gnu.org/"]
        insteadOf = https://git.savannah.gnu.org/
```

Now, create a chroot environment:

``` bash
mkdir -p ~/archbuild
mkarchroot ~/archbuild/root base-devel
```

Create the packages folder inside ~/archbuild:
``` bash
mkdir packages
```

Now, inside ~/archbuild create the script that will build everything.
Invoke this script by passing the name of the file containing all packages that you want to build. 
If you want to build all current system packages, first run:
`pacman -Qq > packages.txt`

If you want to build only the essentials(base, base-devel, linux and linux-firmware), pass as argument the file included in this repository called base_base-devel.txt.
Otherwise, pass packages.txt.

Script to make all packages:
``` bash
cd packages

# loop for every package in pacman, and build with chroot
for pkg in $(cat $1); do
    if [ -d "$pkg" ]; then continue; fi
    echo "Cloning and building: $pkg"
    pkgctl repo clone "$pkg" && cd "$pkg" || continue

    if [ "$pkg" = "texinfo" ]; then # patch for texinfo package
      sed -i -e 's|./configure --prefix=/usr|./configure --prefix=/usr -C CFLAGS="-march=skylake -mtune=skylake" PERL_EXT_CFLAGS="-march=skylake -mtune=skylake"|g' PKGBUILD
    fi

    makechrootpkg -c -r ~/archbuild -- --skipinteg --noconfirm --nocheck --clean --cleanbuild > build.log
    cd ..
done
```

Now, for the Arch ISO, copy default releng profile:
```bash
cp -r /usr/share/archiso/configs/releng ~/archbuild/archiso
```

Copy all .zst files from each package to `archbuild/archiso/releng/airootfs/packages/`. \
Copy a list of all your built packages names to `/home/builder/archbuild/archiso/releng/`, and name the file `packages.x86_64`.
Don't forget to add syslinux to the list, even if you didn't build it, since it will be needed when creating the ISO.
Any package that you add that you didn't build will be downloaded through pacman.

Create your custom repository:
```bash
repo-add custompkgs.db.tar.zst *.pkg.tar.zst
```

Create your custom repo on pacman.conf. Place this ABOVE everything else, to make sure it gets chosen before any other remote repo:
```bash
[custompkgs]
SigLevel = Never
Server = file:///home/builder/archbuild/archiso/releng/airootfs/packages/
```

To generate the ISO, run inside releng:
```bash
mkarchiso -v . > iso.log
```

# Important
When installing the ISO, make sure to copy the pacman.conf to /etc/pacman.conf, otherwise it will create a new chroot with default settings, without your pacman.conf. Make sure it is not overriden.
Also, always check twice if your packages are really being chosen over remote. You can do so by using `pacman -Qi package` and checking stuff like packaging date, and Packager. If you didn't set a Packager name for you, it should be saying "Unknown Packager".