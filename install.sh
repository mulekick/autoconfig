#!/bin/bash

# set up a freshly installed host in local-debian current condition (git is present)

# current directory
autoconfig=$(pwd)

if [[ ! -x "$autoconfig/$0" ]]; then
        echo "Please run this script from the install directory."
        exit 1
fi

# script is meant to be run as root
if [[ "$(id -u)" != "0" ]]; then
        echo "Please run this script using sudo."
        exit 1
fi

# avoid confusion with built in shell variables
USER_NAME=$autoconfig/user-name
USER_GECOS=$autoconfig/user-gecos
USER_PASSWD=$autoconfig/user-password
USER_REPOS=$autoconfig/user-repositories
USER_POSTINSTALL=$autoconfig/user-postinstall
USER_SHELL=/bin/bash

# encrypted files storage
GPG_TARBALL=$autoconfig/tarball.tar.gpg

# prerequisites for installation ...
apt-get update && apt-get install --no-install-recommends -m -y curl gnupg2 ca-certificates

# =============== UPDATE KERNEL VARIABLES ==================
echo -e "updating kernel variables"

echo -e '\n
# increase inotify max file watch limit
fs.inotify.max_user_watches=262144' >> /etc/sysctl.conf

# ================= UPDATE APT SOURCES =====================
echo -e "updating apt sources"

ARCH=$(dpkg --print-architecture)
KEYRINGS="/usr/share/keyrings"
SOURCELISTS="/etc/apt/sources.list.d"

# retrieve third party gpg keys ...
curl -fsSL 'https://download.docker.com/linux/debian/gpg' | gpg --dearmor -o "$KEYRINGS/docker-archive-keyring.gpg"
curl -fsSL 'https://dl.google.com/linux/linux_signing_key.pub' | gpg --dearmor -o "$KEYRINGS/google-archive-keyring.gpg"
curl -fsSL 'https://packages.cloud.google.com/apt/doc/apt-key.gpg' | gpg --dearmor -o "$KEYRINGS/cloud.google.gpg"

# add third party sources ...
echo "deb [arch=$ARCH signed-by=$KEYRINGS/docker-archive-keyring.gpg] https://download.docker.com/linux/debian $(lsb_release -cs) stable" | tee "$SOURCELISTS/docker.list" > /dev/null
echo "deb [arch=$ARCH signed-by=$KEYRINGS/google-archive-keyring.gpg] http://dl.google.com/linux/chrome/deb/ stable main" | tee "$SOURCELISTS/google-chrome.list" > /dev/null
echo "deb [signed-by=$KEYRINGS/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" | tee "$SOURCELISTS/google-cloud-sdk.list" > /dev/null

# update all sources and upgrade ...
apt-get update && apt-get upgrade -y

# ================== INSTALL PACKAGES ======================
echo -e "installing default packages"

# policy management
# system monitoring (most to least relevant)
# network utilities
# encryption
# archive management
# shell utilities
# editors
# man pages
# x11
# xrdp
# multimedia
# google chrome
# google cloud cli
# windows network drives mapping
# docker related packages
# python
# shell linter
# miscellaneous

MINIMAL="policykit-1 \
neofetch procps htop iftop psmisc time iotop sysstat \
iproute2 nmap mtr wget \
pgpdump \
zip unzip \
bash-completion tree tmux dos2unix \
vim vim-common vim-runtime \
man-db \
xorg \
xrdp xorgxrdp \
ffmpeg \
google-chrome-stable \
google-cloud-cli \
samba-client samba-common cifs-utils \
jq docker-ce docker-ce-cli containerd.io \
python3 python3-pip pipx \
shellcheck \
fonts-noto-color-emoji cowsay cowsay-off display-dhammapada steghide"

# x window manager + addons + media player
# xrdp audio module build dependencies
# pulseaudio volume control
RECOMMENDS="xfce4 xfce4-goodies parole \
build-essential dpkg-dev libpulse-dev autoconf libtool debootstrap schroot \
pavucontrol"

# packages to purge post-install ...
PURGE="build-essential dpkg-dev libpulse-dev autoconf libtool debootstrap schroot nano"

# install only main dependencies, ignore missing, yes to all prompts
# shellcheck disable=SC2086
apt-get install --no-install-recommends -m -y $MINIMAL

# install with recommends ...
# shellcheck disable=SC2086
apt-get install -m -y $RECOMMENDS

# ================== CONFIGURE SHELL ======================== 
echo -e "configuring shell"

# remove nano as an editor alternative
update-alternatives --remove editor /bin/nano

# set vim.basic as an editor alternative
[[ -x /usr/bin/vim.basic ]] && update-alternatives --set editor /usr/bin/vim.basic

# editor alternative should already be in auto mode, but anyway
update-alternatives --auto editor

# ================= EXTRACT TARBALL ========================
# prompt password
echo -e "=== PLEASE ENTER TAR ARCHIVE PASSWORD ==="
read -r tarpp

# decrypt and uncompress user files into current directory
gpg --decrypt --batch --passphrase "$tarpp" "$GPG_TARBALL" | tar --strip-components=1 --wildcards -xvf /dev/stdin "tarball/user-*"

# ==== CREATE USER + SETUP SSH/NETWORK MAPPINGS ============
username=$(cat "$USER_NAME")
userhome="/home/$username"

echo -e "creating user $username"

# create user (specify shell, disable login)
adduser "$username" --shell "$USER_SHELL" --gecos "$(cat "$USER_GECOS")" --disabled-login

# setup user password
echo "$username:$(cat "$USER_PASSWD")" | chpasswd

# add to sudo group
usermod -a -G sudo "$username"

# decrypt and uncompress config files into user home directory
gpg --decrypt --batch --passphrase "$tarpp" "$GPG_TARBALL" | tar -C "$userhome" --strip-components=1 -xvf /dev/stdin "tarball/.ssh" "tarball/.network-mappings"

# setup ownership
chown -R "$username":"$username" "$userhome/.ssh" "$userhome/.network-mappings"

# setup directories permissions
chmod 700 "$userhome/.ssh" "$userhome/.network-mappings"

# setup files permissions (allow shell expansion for wildcards)
chmod 400 "$userhome/.ssh/"*
chmod 644 "$userhome/.ssh/"*.pub
chmod 600 "$userhome/.ssh/authorized_keys" "$userhome/.ssh/known_hosts" "$userhome/.ssh/config"

# ===================== SETUP SSHD =========================
echo -e "setting up ssh server"

# decrypt and uncompress config files into server directory
gpg --decrypt --batch --passphrase "$tarpp" "$GPG_TARBALL" | tar -C /etc/ssh/sshd_config.d --strip-components=2 -xvf /dev/stdin "tarball/sshd/sshd_overrides.conf"

# decrypt and uncompress login banner into server directory
gpg --decrypt --batch --passphrase "$tarpp" "$GPG_TARBALL" | tar -C /etc --strip-components=2 --overwrite -xvf /dev/stdin "tarball/sshd/issue.net"

# setup ownership
chown root:root /etc/ssh/sshd_config.d/sshd_overrides.conf /etc/issue.net

# ================ SETUP X.ORG / XRDP ======================
echo -e "setting up xrdp and xorg"

# add the xrdp user to the ssl-cert group
adduser xrdp ssl-cert

# decrypt and uncompress config files into xrdp directory
gpg --decrypt --batch --passphrase "$tarpp" "$GPG_TARBALL" | tar -C /etc/xrdp --strip-components=2 --overwrite -xvf /dev/stdin "tarball/xrdp/xrdp.ini" "tarball/xrdp/sesman.ini"

# setup ownership
chown root:root /etc/xrdp/xrdp.ini /etc/xrdp/sesman.ini

# =============== SETUP AUDIO FOR XRDP =====================
echo -e "building and installing xrdp audio module"

# clone repo
git clone https://github.com/neutrinolabs/pulseaudio-module-xrdp.git "$autoconfig/pulseaudio-module-xrdp"

# cd into repo
cd "$autoconfig/pulseaudio-module-xrdp" || exit 1

# run build scripts
./scripts/install_pulseaudio_sources_apt_wrapper.sh

# move build directory
mv ~/pulseaudio.src "$autoconfig/."

# bootstrap and configure
./bootstrap && ./configure PULSE_DIR="$autoconfig/pulseaudio.src"

# make
make

# install
make install

# cd back into autoconfig directory
cd ..

# ==================== SETUP DOCKER ========================
echo -e "installing docker"

# add user to group
usermod -a -G docker "$username"

# disable docker auto start
systemctl disable docker.service docker.socket containerd.service

# decrypt and uncompress registries credentials into user home directory
gpg --decrypt --batch --passphrase "$tarpp" "$GPG_TARBALL" | tar -C "$userhome" --strip-components=1 -xvf /dev/stdin "tarball/.docker"

# setup ownership
chown -R "$username":"$username" "$userhome/.docker"

# =================== SETUP SYSTEMD ========================
echo -e "configuring systemd"

# decrypt and uncompress configuration units into systemd directories
gpg --decrypt --batch --passphrase "$tarpp" "$GPG_TARBALL" | tar -C /lib/systemd/system --strip-components=2 -xvf /dev/stdin "tarball/systemd/docker.target"
gpg --decrypt --batch --passphrase "$tarpp" "$GPG_TARBALL" | tar -C /etc/systemd/system --strip-components=2 -xvf /dev/stdin "tarball/systemd/network-drives.service"

# setup ownership
chown root:root /lib/systemd/system/docker.target /etc/systemd/system/network-drives.service

# rebuild dependency tree
systemctl daemon-reload

# enable docker configuration unit, create symlinks
systemctl enable docker.target

# set default system target
systemctl set-default multi-user.target

# =================== SETUP GIT REPOS ======================
echo -e "cloning git repositories"

# clone repositories
# shellcheck disable=SC2016
xargs -a "$USER_REPOS" -P 1 -tn 4 runuser -c 'mkdir -pv ~/$1 && \
git clone $0 ~/$1 && \
cd ~/$1 && \
git config user.email $2 && \
git config user.name $3' -P --login "$username"

# decrypt and uncompress confidential data into newly cloned repositories
gpg --decrypt --batch --passphrase "$tarpp" "$GPG_TARBALL" | tar -C "$userhome" --strip-components=1 --wildcards -xvf /dev/stdin \
"tarball/.backup_and_sync/*"

gpg --decrypt --batch --passphrase "$tarpp" "$GPG_TARBALL" | tar -C "$userhome/git" --strip-components=1 --wildcards -xvf /dev/stdin \
"tarball/codebase/*" \
"tarball/fullstackjavascript/*" \
"tarball/megadownload/*" \
"tarball/mulepedia/*" \
"tarball/node-http-tunnel/*" \
"tarball/stream-from-the-shell/*" \
"tarball/stream.generator/*" \
"tarball/watchteevee/*"

# restore tarball source directory
gpg --decrypt --batch --passphrase "$tarpp" "$GPG_TARBALL" | tar -C "$userhome/git/autoconfig" -xvf /dev/stdin "tarball"

# ================== SETUP $HOME ===========================
echo -e "setting up $userhome"

# shellcheck disable=SC2016
extendshell='
# ------ GLOBAL SHELL EXTENSIONS ------

# enable pipx autocompletion
eval "$(register-python-argcomplete pipx)"

# enable custom shell utilities
if [[ -f $HOME/.shell_extend/.bash_extend ]]; then
\t. $HOME/.shell_extend/.bash_extend
fi

# -------------------------------------
'

# update .bashrc
[[ -f "$userhome/.bashrc" ]] && echo -e "$extendshell"  >> "$userhome/.bashrc"

# set custom .vimrc
[[ ! -f "$userhome/.vimrc" ]] && cp "$userhome/.shell_extend/.vimrc_default" "$userhome/.vimrc"

# setup ownership
chown -R "$username":"$username" "$userhome/.vimrc"

# setup permissions
chmod 600 "$userhome/.vimrc"

# ================= SETUP /etc/skel ========================
echo -e "setting up default user directory"

# install shell_extend for all users
cp -rv "$userhome/.shell_extend" /etc/skel/.

# remove working tree
rm -rf /etc/skel/.shell_extend/.git

# update default .bashrc
[[ -f /etc/skel/.bashrc ]] && echo -e "$extendshell"  >> /etc/skel/.bashrc

# set default .vimrc
[[ ! -f /etc/skel/.vimrc ]] && cp /etc/skel/.shell_extend/.vimrc_default /etc/skel/.vimrc

# setup permissions
chmod 600 /etc/skel/.vimrc

# ===================== MULTIMEDIA =========================
echo -e "installing multimedia tools"

# install gifski
wget -qO "$autoconfig/gifski.deb" "https://github.com/ImageOptim/gifski/releases/download/1.13.0/gifski_1.13.0-1_$ARCH.deb" && dpkg -i "$autoconfig/gifski.deb" || \
echo "gifski: no build available for current architecture, skipping install"

# decrypt and uncompress gifmaker script into user home directory
gpg --decrypt --batch --passphrase "$tarpp" "$GPG_TARBALL" | tar -C "$userhome" --strip-components=1 -xvf /dev/stdin "tarball/gifmaker.sh"

# setup gif maker and add alias to .bashrc
# shellcheck disable=SC2016
runuser -c 'echo '\''alias gif=$HOME/gifmaker.sh'\'' >> "$HOME/.bashrc"' -P --login "$username"

# install youtube-dl nightly build
runuser -c 'pipx install "git+https://github.com/ytdl-org/youtube-dl.git" && pipx ensurepath' -P --login "$username"

# =================== SETUP NODE.JS ========================
echo -e "installing node.js"

# setup nvm
runuser -c 'curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.5/install.sh | bash' -P --login "$username"

# install + setup node and npm (load nvm since runuser won't execute .bashrc)
runuser -c '. .nvm/nvm.sh && nvm install --lts --latest-npm' -P --login "$username"

# decrypt and uncompress config file into user home directory
gpg --decrypt --batch --passphrase "$tarpp" "$GPG_TARBALL" | tar -C "$userhome" --strip-components=1 -xvf /dev/stdin "tarball/.npmrc"

# setup ownership
chown "$username":"$username" "$userhome/.npmrc"

# setup permissions
chmod 600 "$userhome/.npmrc"

# global modules management 
# shellcheck disable=SC2016
GLOBAL_MODULES_PATH='
# export npm global modules path
export NODE_PATH="$(realpath $NVM_INC/../../lib/node_modules)"'

[[ -f "$userhome/.bashrc" ]] && echo -e "$GLOBAL_MODULES_PATH" >> "$userhome/.bashrc"

# install global modules and create symlink to folder 
# shellcheck disable=SC2016
runuser -c '. .nvm/nvm.sh && \
npm install -g eslint eslint-plugin-html eslint-plugin-node eslint-plugin-import js-beautify degit npm-check-updates && \
ln -s $(realpath $NVM_INC/../../lib/node_modules) ~/node.globals' -P --login "$username"

# ================== SETUP POSTMAN =========================
echo -e "installing postman"

# create desktop folder
mkdir "$userhome/Desktop"

# install
wget -qO "$autoconfig/postman-linux-x64.tar.gz" "https://dl.pstmn.io/download/latest/linux64" && tar -C "$userhome/Desktop" -zxvf "$autoconfig/postman-linux-x64.tar.gz"

# setup ownership
chown -R "$username":"$username" "$userhome/Desktop"

# ================== INSTALL LINODE CLI =========================
echo -e "installing linode CLI"

# install linode-cli from the python repositories
runuser -c 'pipx install linode-cli && pipx ensurepath' -P --login "$username"

# ====================== CLEANUP ===========================
echo -e "removing installation files"

# uninstall irrelevant packages
# shellcheck disable=SC2086
apt-get purge -y $PURGE && apt-get autoremove -y

# end message
endmsg="installation complete.\ndon't forget to complete the following post-installation steps :\n$(cat "$USER_POSTINSTALL")"

# remove local repo
cd .. && rm -rf "$autoconfig"

# ======================== DONE ============================
echo -e "$endmsg"