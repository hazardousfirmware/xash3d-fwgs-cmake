#!/bin/bash

# Script to compile half-life game for linux

# Dependencies:
# - wget
# - git
# - cmake
# - make or ninja
# - gcc / g++
# - bsdtar
# - cabextract
# - bash

# Build libraries + dev packages:
# - SDL2
# - ALSA (sound)
# - stdc++
# - libm, libc
# - OpenGL
# - libvorbis
# - libvorbisfile
# - libopus
# - libopusfile
# - freetype2
# - bzip2
# - curl
# - ffmpeg
# - libmpg123


set -e

work_dir="/tmp/hlbuild"

# Number of cores to compile with
cores=$(lscpu | grep -m 1 'CPU(s):' | awk '{print $2}')


mkdir -p "${work_dir}"
cd "${work_dir}"

assets_url="https://archive.org/download/half-life-1-anthology/HALF_LIFE_1_ANTHOLOGY.ISO"
assets_file_hash="75340841bb1ca30eed8a52d4a0dc18febb8a10c83835fb88c4f6213f0e3dac6b"
assets_file="HALF_LIFE_1_ANTHOLOGY.ISO"

# Download game ISO
echo "Downloading game ISO ..."
if [[ ! -f "${assets_file}" ]]; then
    wget "${assets_url}" -O "${assets_file}"
else
    if ! echo "${assets_file_hash}  ${assets_file}" | sha256sum -c ; then
        # Corrupt file, delete and redownload
        rm "${assets_file}"
        wget "${assets_url}" -O "${assets_file}"
    fi
fi

# Mount ISO
rm -rf CD CAB 2>/dev/null || true
mkdir -p CD CAB

echo "Extracting files ..."
cabfiles=( "1:bshift.ico" "2:halflife_blue_shift.gcf" "4:halflife.gcf" "7:opposing_force.gcf" "9:team_fortress_classic.gcf" )

for kv in "${cabfiles[@]}"; do
    cab="hl${kv%%:*}.cab"
    output_file="${kv##*:}"

    echo "    exctracting: $cab ..."
    [[ -f "$cab" ]] || bsdtar -xpf ${assets_file} -C CD/ "$cab"
    [[ -f "CAB/${output_file}" ]] || cabextract -d CAB "CD/$cab"
done

# permissions are fucked as a result of ISO9660 r/o
chmod 0644 CAB/* CD/*

# Get hlextract tool
echo "Get/build hlextract tool ..."

[[ -d hllib ]] || git clone 'https://github.com/RavuAlHemio/hllib.git'
cd hllib

if [[ ! -f build/hlextract ]]; then
    cmake -B build .
    cmake --build build -- -j ${cores}
fi

cd ..


# Extract gcf files
echo "Extract GCF files"

rm -rf game 2>/dev/null || true

mkdir -p game

# HL original game
[[ -d game/valve ]] || ./hllib/build/hlextract -p CAB/halflife.gcf -d game/ -e root/valve -e root/reslists

# Blue shift
[[ -d gamne/bshift ]] || ./hllib/build/hlextract -p CAB/halflife_blue_shift.gcf -d game/ -e root/bshift -e root/reslists

# Opposing Force
[[ -d game/gearbox ]] || ./hllib/build/hlextract -p CAB/opposing_force.gcf -d game/ -e root/gearbox -e root/reslists

# Team fortress
[[ -d game/tfc ]] || ./hllib/build/hlextract -p CAB/team_fortress_classic.gcf -d game/ -e root/tfc -e root/reslists

# Copy icons
cp CAB/bshift.ico game/bshift/game.ico

# Remove EXE/DLL/SO etc files
for ext in exe dll so gbx icd sys; do
    find game/ -iname "*.${ext}" -delete
done

gamedirs=( "hlfixed:valve" "opforfixed:gearbox" "bshift:bshift" )
# Clone the game SDK repos
for kv in "${gamedirs[@]}"; do
    branch=${kv%%:*}
    dir=${kv##*:}

    echo "building ${branch} ..."
    [[ -d "${branch}" ]] || git clone -b "${branch}" 'https://github.com/FWGS/hlsdk-portable.git' "${branch}"

    if [[ ! -f "${branch}/build/cl_dll/client_amd64.so" ]] || [[ ! -f "${branch}/build/dlls/${branch%*fixed}_amd64.so" ]]; then
        cmake -B "$branch/build" "$branch" -DXASH_AMD64=1 -DXASH_LINUX=1 -D64BIT=on -DUSE_VGUI=off
        cmake --build "$branch/build" -- -j ${cores}
    fi

    echo "Copying DLLs for game dir: ${dir} ..."
    cp "${branch}/build/cl_dll/client_amd64.so" "game/${dir}/cl_dlls/"
    cp "${branch}/build/dlls/${branch%*fixed}_amd64.so" "game/${dir}/dlls/"
done

# TODO: compile team fortress classic (SDK)


# Compile main game
[[ -d "xash3d-fwgs" ]] || git clone 'git@github.com:hazardousfirmware/xash3d-fwgs-cmake.git' --recursive "xash3d-fwgs"
cmake -B "xash3d-fwgs/build" "xash3d-fwgs" -DENABLE_FFMPEG=1 -DMAINUI_FONT_SCALE=1
cmake --build "xash3d-fwgs/build" -- -j ${cores}

echo "Copying game engine files ..."
cp xash3d-fwgs/build/*.so game/
cp xash3d-fwgs/build/xash3d game/
cp xash3d-fwgs/build/xashded game/


echo ""

# download menu fonts and graphics
echo "Downloading menu fonts and graphics ..."
[[ -d "xash-extras" ]] || git clone "https://github.com/FWGS/xash-extras.git"
cp -r "xash-extras/gfx" "game/valve/"

echo ""

# Generate desktop file templates
echo "Generate desktop file templates and install script ..."

# valve game
cat > "game/hl.sh" << EOF
#!/bin/bash

cd %INSTALL_DIR%
export LD_LIBRARY_PATH=%INSTALL_DIR%

./xash3d

EOF
chmod +x game/hl.sh

cat > "game/xash3d-hl.desktop" << EOF
[Desktop Entry]
Name=XASH3D - Half-Life
Exec=%INSTALL_DIR%/hl.sh
Icon=%INSTALL_DIR%/valve/game.ico
Type=Application
Comment=Half-Life for Linux
Categories=Game;ActionGame;
Path=%INSTALL_DIR%/
Terminal=true
StartupNotify=false

# Replace %INSTALL_DIR% with actual installation directory

EOF

# bshift game
cat > "game/bshift.sh" << EOF
#!/bin/bash

cd %INSTALL_DIR%
export LD_LIBRARY_PATH=%INSTALL_DIR%

./xash3d -game bshift

EOF
chmod +x game/bshift.sh

cat > "game/xash3d-bshift.desktop" << EOF
[Desktop Entry]
Name=XASH3D - Half-Life: Blue Shift
Exec=%INSTALL_DIR%/bshift.sh
Icon=%INSTALL_DIR%/bshift/game.ico
Type=Application
Comment=Half-Life: Blue Shift for Linux
Categories=Game;ActionGame;
Path=%INSTALL_DIR%/
Terminal=true
StartupNotify=false

# Replace %INSTALL_DIR% with actual installation directory

EOF

# opposing force game
cat > "game/opfor.sh" << EOF
#!/bin/bash

cd %INSTALL_DIR%
export LD_LIBRARY_PATH=%INSTALL_DIR%

./xash3d -game gearbox

EOF
chmod +x game/opfor.sh

cat > "game/xash3d-opfor.desktop" << EOF
[Desktop Entry]
Name=XASH3D - Half-Life: Opposing Force
Exec=%INSTALL_DIR%/opfor.sh
Icon=%INSTALL_DIR%/gearbox/game.ico
Type=Application
Comment=Half-Life: Opposing Force for Linux
Categories=Game;ActionGame;
Path=%INSTALL_DIR%/
Terminal=true
StartupNotify=false

# Replace %INSTALL_DIR% with actual installation directory

EOF

cp "$0" "game/compile-game.sh"

# Generate installation script
cat > "game/install.sh" << EOF
#!/bin/bash

# Script to install half-life on linux

# In order to run the game the following libraries are needed
## SDL2 GL dl m ffmpeg vorbis vorbisfile opus opusfile libmpg123 libbzip2 llibcurl 

# This install script will install desktop shortcut to current extract directory.

set -e

dir="\$(dirname \$(realpath \$0))"

# Install as non-root (extract and play only)
echo "Installing shortcut for \$dir"

sed -i -e "/^#/! s|%INSTALL_DIR%|\${dir}|g" xash3d-hl.desktop xash3d-bshift.desktop xash3d-opfor.desktop
sed -i -e "/^#/! s|%INSTALL_DIR%|\${dir}|g" hl.sh bshift.sh opfor.sh

mkdir -p "\$HOME/.local/share/applications/"

cp xash3d-hl.desktop xash3d-bshift.desktop xash3d-opfor.desktop "\$HOME/.local/share/applications/"

EOF

chmod +x "game/install.sh"

echo "DONE!"
