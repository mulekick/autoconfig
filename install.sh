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
USER_EXTENSIONS=$autoconfig/user-extensions
USER_SHELL=/bin/bash

# encrypted files storage
GPG_TARBALL=$autoconfig/tarball.tar.gpg

# default apt sources are configured at installation, update and upgrade
apt-get update && apt-get upgrade -y

# =============== UPDATE KERNEL VARIABLES ==================
echo -e "updating kernel variables"

echo -e '\n
# increase inotify max file watch limit
fs.inotify.max_user_watches=262144' >> /etc/sysctl.conf

# ================== INSTALL PACKAGES ======================
echo -e "installing default packages"

# install packages (only main dependencies, ignore missing, yes to all prompts)
# shell utilities
# editors
# man pages
# archive management
# policy management
# encryption
# system utilities
# network utilities
# distro + packages management
# shell linter
# docker-relevant packages
# windows network drives mapping
# miscellaneous

apt-get install --no-install-recommends -m -y \
bash-completion tree tmux curl wget dos2unix \
vim vim-common vim-runtime \
man-db \
zip unzip \
policykit-1 \
gnupg2 pgpdump \
procps psmisc sysstat iotop time \
net-tools nmap iftop \
lsb-release apt-rdepends \
shellcheck \
ca-certificates jq \
samba-client samba-common cifs-utils \
cowsay cowsay-off display-dhammapada steghide

# ================= EXTRACT TARBALL ========================
# prompt password
echo -e "=== PLEASE ENTER TAR ARCHIVE PASSWORD ==="
read -r tarpp

# decrypt and uncompress into current directory
gpg --decrypt --batch --passphrase "$tarpp" "$GPG_TARBALL" | tar --strip-components=1 --wildcards -xvf /dev/stdin "tarball/user-*"

# ==== CREATE USER + SETUP SSH/NETWORK MAPPINGS ============
username=$(cat "$USER_NAME")
userhome="/home/$username"

echo -e "creating user $username"

# create user (specify shell, disable login)
adduser "$username" --shell $USER_SHELL --gecos "$(cat "$USER_GECOS")" --disabled-login

# setup user password
echo "$username:$(cat "$USER_PASSWD")" | chpasswd

# add to sudo group
usermod -a -G sudo "$username"

# decrypt and uncompress into user home directory
gpg --decrypt --batch --passphrase "$tarpp" "$GPG_TARBALL" | tar -C "$userhome" --strip-components=1 -xvf /dev/stdin "tarball/.ssh" "tarball/.network-mappings"

# setup ownership
chown -R "$username":"$username" "$userhome/.ssh" "$userhome/.network-mappings"

# setup permissions
chmod 700 "$userhome/.ssh" "$userhome/.network-mappings"

# ===================== SETUP SSHD =========================
echo -e "setting up ssh server"

# setup config overrides
gpg --decrypt --batch --passphrase "$tarpp" "$GPG_TARBALL" | tar -C /etc/ssh/sshd_config.d --strip-components=2 -xvf /dev/stdin "tarball/sshd/sshd_overrides.conf"

# setup login banner
gpg --decrypt --batch --passphrase "$tarpp" "$GPG_TARBALL" | tar -C /etc --strip-components=2 --overwrite -xvf /dev/stdin "tarball/sshd/issue.net"

# setup ownership
chown root:root /etc/ssh/sshd_config.d/sshd_overrides.conf /etc/issue.net

# =================== SETUP GIT REPOS ======================
echo -e "cloning git repositories"

# clone repositories
# shellcheck disable=SC2016
xargs -a "$USER_REPOS" -P 1 -tn 4 runuser -c 'mkdir -pv ~/$1 && \
git clone $0 ~/$1 && \
cd ~/$1 && \
git config user.email $2 && \
git config user.name $3' -P --login "$username"

# decrypt and uncompress into repos
gpg --decrypt --batch --passphrase "$tarpp" "$GPG_TARBALL" | tar -C "$userhome/git" --strip-components=1 --wildcards -xvf /dev/stdin "tarball/codebase/*" "tarball/data-viewer/*" "tarball/megadownload/*" "tarball/node-http-tunnel/*" "tarball/stream-cdn/*"

# restore tarball source directory
gpg --decrypt --batch --passphrase "$tarpp" "$GPG_TARBALL" | tar -C "$userhome/git/autoconfig" -xvf /dev/stdin "tarball"

# ================== SETUP $HOME ===========================
echo -e "setting up $userhome"

# shellcheck disable=SC2016
extendshell='\n
# ------ SET SHELL EXTENSIONS ------\n
if [[ -f $HOME/.shell_extend/.bash_extend ]]; then\n
\t. $HOME/.shell_extend/.bash_extend\n
fi'

# update .bashrc
if [[ -f "$userhome/.bashrc" ]]; then
    echo -e "$extendshell"  >> "$userhome/.bashrc"
fi

# set custom .vimrc
if [[ ! -f "$userhome/.vimrc" ]]; then
    cp "$userhome/.shell_extend/.vimrc_default" "$userhome/.vimrc"
fi

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
if [[ -f /etc/skel/.bashrc ]]; then
    echo -e "$extendshell"  >> /etc/skel/.bashrc
fi

# set default .vimrc
if [[ ! -f /etc/skel/.vimrc ]]; then
    cp /etc/skel/.shell_extend/.vimrc_default /etc/skel/.vimrc
fi

# setup permissions
chmod 600 /etc/skel/.vimrc

# ================== CONFIGURE SHELL ======================== 
echo -e "configuring shell"

# remove nano as an editor alternative
update-alternatives --remove editor /bin/nano

# remove nano, period
apt-get purge -y nano

# set vim.basic as an editor alternative
[[ -x /usr/bin/vim.basic ]] && update-alternatives --set editor /usr/bin/vim.basic

# editor alternative should already be in auto mode, but anyway
update-alternatives --auto editor

# ==================== SETUP DOCKER ========================
echo -e "installing docker"

# retrieve docker gpg key
curl -fsSL 'https://download.docker.com/linux/debian/gpg' | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

# add apt source
echo \
"deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] \
https://download.docker.com/linux/debian $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

# update
apt-get update

# install packages (only main dependencies, ignore missing, yes to all prompts)
# docker packages
apt-get install --no-install-recommends -m -y \
docker-ce docker-ce-cli containerd.io

# add user to group
usermod -a -G docker "$username"

# disable docker auto start
systemctl disable docker.service docker.socket containerd.service

# =================== SETUP SYSTEMD ========================
echo -e "configuring systemd"

# decrypt and uncompress into systemd directories
gpg --decrypt --batch --passphrase "$tarpp" "$GPG_TARBALL" | tar -C /lib/systemd/system --strip-components=2 -xvf /dev/stdin "tarball/systemd/docker.target"
gpg --decrypt --batch --passphrase "$tarpp" "$GPG_TARBALL" | tar -C /etc/systemd/system --strip-components=2 -xvf /dev/stdin "tarball/systemd/data-viewer.service" "tarball/systemd/network-drives.service"

# setup ownership
chown root:root /lib/systemd/system/docker.target /etc/systemd/system/data-viewer.service /etc/systemd/system/network-drives.service

# rebuild dependency tree
systemctl daemon-reload

# enable docker configuration unit, create symlinks
systemctl enable docker.target

# set default system target
systemctl set-default multi-user.target

# =================== SETUP NODE.JS ========================
echo -e "installing node.js"

# setup nvm
runuser -c 'curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.3/install.sh | bash' -P --login "$username"

# install + setup node and npm (load nvm since runuser won't execute .bashrc)
runuser -c '. .nvm/nvm.sh && nvm install --lts --latest-npm' -P --login "$username"

# decrypt and uncompress into user home directory
gpg --decrypt --batch --passphrase "$tarpp" "$GPG_TARBALL" | tar -C "$userhome" --strip-components=1 -xvf /dev/stdin "tarball/.npmrc"

# setup ownership
chown "$username":"$username" "$userhome/.npmrc"

# setup permissions
chmod 600 "$userhome/.npmrc"

# global modules management 
# shellcheck disable=SC2016
GLOBAL_MODULES_PATH='\n
# export npm global modules path\n
export NODE_PATH="$(realpath $NVM_INC/../../lib/node_modules)"'

[[ -f "$userhome/.bashrc" ]] && echo -e "$GLOBAL_MODULES_PATH" >> "$userhome/.bashrc"

# install global modules and create symlink to folder 
# shellcheck disable=SC2016
runuser -c '. .nvm/nvm.sh && \
npm install -g eslint eslint-plugin-html eslint-plugin-node eslint-plugin-import js-beautify degit && \
ln -s $(realpath $NVM_INC/../../lib/node_modules) ~/node.globals' -P --login "$username"

# ===================== MULTIMEDIA =========================
echo -e "setting up multimedia tools"

# install packages (only main dependencies, ignore missing, yes to all prompts)
# ffmpeg
apt-get install --no-install-recommends -m -y \
ffmpeg

# setup megadownload and add alias to .bashrc
# shellcheck disable=SC2016
runuser -c '. .nvm/nvm.sh && \
cd git/megadownload && \
npm install && \
echo '\''alias mdl=$HOME/git/megadownload/megadownload.js'\'' >> "$HOME/.bashrc"' -P --login "$username"

# install gifski
wget -qO "$autoconfig/gifski.deb" "https://github.com/ImageOptim/gifski/releases/download/1.8.1/gifski_1.8.1_$(dpkg --print-architecture).deb" && dpkg -i "$autoconfig/gifski.deb" || \
echo "gifski: no build available for current architecture, skipping install"

# decrypt and uncompress into user home directory
gpg --decrypt --batch --passphrase "$tarpp" "$GPG_TARBALL" | tar -C "$userhome" --strip-components=1 -xvf /dev/stdin "tarball/gifmaker.sh"

# setup gif maker and add alias to .bashrc
# shellcheck disable=SC2016
runuser -c 'echo '\''alias gif=$HOME/gifmaker.sh'\'' >> "$HOME/.bashrc"' -P --login "$username"

# ==================== DATA-VIEWER =========================
echo -e "setting up data viewer service"

# start docker
systemctl isolate rundocker.target 

# run install script
# shellcheck disable=SC2016
runuser -c 'cd ~/git/data-viewer && \
. data-viewer-install.sh' -P --login "$username"

# stop docker
systemctl isolate multi-user.target

# ================ SETUP X.ORG / XRDP ======================
echo -e "setting up xrdp and xorg"

# install packages (only main dependencies, ignore missing, yes to all prompts, progress indicator)
# x
# xfce
# xrdp
apt-get install --no-install-recommends -m -y \
xorg dbus-x11 x11-xserver-utils \
xfce4 xfce4-goodies \
xrdp xorgxrdp

# add the xrdp user to the ssl-cert group
adduser xrdp ssl-cert

# setup custom config
gpg --decrypt --batch --passphrase "$tarpp" "$GPG_TARBALL" | tar -C /etc/xrdp --strip-components=2 --overwrite -xvf /dev/stdin "tarball/xrdp/xrdp.ini" "tarball/xrdp/sesman.ini"

# setup ownership
chown root:root /etc/xrdp/xrdp.ini /etc/xrdp/sesman.ini

# =============== SETUP AUDIO FOR XRDP =====================
echo -e "building and installing xrdp audio module"

# install packages (yes to all prompts)
# module build dependencies
# pulseaudio volume control
apt-get install -y \
build-essential dpkg-dev libpulse-dev autoconf libtool debootstrap schroot \
pavucontrol

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

# uninstall build dependencies
apt-get purge -y build-essential dpkg-dev libpulse-dev autoconf libtool debootstrap schroot

# cleanup
apt-get autoremove -y

# =================== SETUP CHROME =========================
echo -e "installing google chrome"

# retrieve google gpg key
curl -fsSL 'https://dl.google.com/linux/linux_signing_key.pub' | gpg --dearmor -o /usr/share/keyrings/google-archive-keyring.gpg

# add apt source
echo \
"deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/google-archive-keyring.gpg] \
http://dl.google.com/linux/chrome/deb/ stable main" | tee /etc/apt/sources.list.d/google-chrome.list > /dev/null

# update
apt-get update

# install packages (only main dependencies, ignore missing, yes to all prompts)
# chrome
apt-get install --no-install-recommends -m -y \
google-chrome-stable

# ================== SETUP POSTMAN =========================
echo -e "installing postman"

# create desktop folder
mkdir "$userhome/Desktop"

# install
wget -qO "$autoconfig/postman-linux-x64.tar.gz" "https://dl.pstmn.io/download/latest/linux64" && tar -C "$userhome/Desktop" -zxvf "$autoconfig/postman-linux-x64.tar.gz"

# setup ownership
chown -R "$username":"$username" "$userhome/Desktop"

# ====================== CLEANUP ===========================
echo -e "removing installation files"

# end message
endmsg="installation complete.\ndon't forget to install the following extensions if using as a vscode remote:\n$(cat "$USER_EXTENSIONS")"

# remove local repo
cd .. && rm -rf "$autoconfig"

# ======================== DONE ============================
echo -e "$endmsg"