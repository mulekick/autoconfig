#!/bin/bash

# set up a freshly installed host in local-debian current condition (git is present)

# current directory
EXEC_PATH="$(pwd)"

if [[ ! -x "$EXEC_PATH/$0" ]]; then
    echo "Please run this script from the install directory."
    exit 1
# script is meant to be run as root
elif [[ "$(id -u)" != "0" ]]; then
    echo "Please run this script using sudo."
    exit 1
fi

##############################################################
#                    INSTALLATION VARIABLES                  #
##############################################################

# avoid confusion with built in shell variables
USER_NAME="$EXEC_PATH/user-name"
USER_GECOS="$EXEC_PATH/user-gecos"
USER_PASSWD="$EXEC_PATH/user-password"
USER_REPOS="$EXEC_PATH/user-repositories"
USER_POSTINSTALL="$EXEC_PATH/user-postinstall"
USER_SHELL="/bin/bash"

# encrypted files storage
GPG_TARBALL="$EXEC_PATH/tarball.tar.gpg"

# prerequisites for installation ...
apt-get update && apt-get install --no-install-recommends -m -y ca-certificates curl gpg

##############################################################
#                       UTILS FUNCTIONS                      #
##############################################################

function red {
    echo -e "\e[31m$1\e[0m"
}
function fill {
    local total_length=60
    local padding=$(((total_length - ${#1}) / 2))
    printf "%*s" $((padding + ${#1})) "$1" >&1
    printf "%*s" $((total_length - padding - ${#1})) "" >&1
}
function announce {
    red "##############################################################"
    red "#$(fill "$1")#"
    red "##############################################################"
}

##############################################################
#                   UPDATE KERNEL VARIABLES                  #
##############################################################

announce "updating kernel variables"

cat << EOF >> /etc/sysctl.d/local.conf
# increase inotify max file watch limit
fs.inotify.max_user_watches=262144
EOF

##############################################################
#                      UPDATE APT SOURCES                    #
##############################################################

announce "updating apt sources"

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

##############################################################
#                       INSTALL PACKAGES                     #
##############################################################

announce "installing default packages"

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
jq docker-ce docker-ce-cli containerd.io docker-buildx-plugin \
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

##############################################################
#                       CONFIGURE SHELL                      #
##############################################################

announce "configuring shell"

# remove nano as an editor alternative
update-alternatives --remove editor /bin/nano

# set vim.basic as an editor alternative
if [[ -x /usr/bin/vim.basic ]]; then update-alternatives --set editor /usr/bin/vim.basic; fi

# editor alternative should already be in auto mode, but anyway
update-alternatives --auto editor

##############################################################
#                        EXTRACT TARBALL                     #
##############################################################

# prompt password
announce "PLEASE ENTER TAR ARCHIVE PASSWORD"
read -r TAR_PASSWD

# decrypt and uncompress user files into current directory
gpg --decrypt --batch --passphrase "$TAR_PASSWD" "$GPG_TARBALL" | tar --strip-components=1 --wildcards -xvf /dev/stdin "tarball/user-*"

##############################################################
#        CREATE USER + SETUP SSH/NETWORK MAPPINGS            #
##############################################################

username=$(cat "$USER_NAME")
USER_HOME="/home/$username"

announce "creating user $username"

# create user (specify shell, disable login)
adduser "$username" --shell "$USER_SHELL" --gecos "$(cat "$USER_GECOS")" --disabled-login

# setup user password
echo "$username:$(cat "$USER_PASSWD")" | chpasswd

# add to sudo group
usermod -a -G sudo "$username"

# decrypt and uncompress config files into user home directory
gpg --decrypt --batch --passphrase "$TAR_PASSWD" "$GPG_TARBALL" | tar -C "$USER_HOME" --strip-components=1 -xvf /dev/stdin "tarball/.ssh" "tarball/.network-mappings"

# setup ownership
chown -R "$username":"$username" "$USER_HOME/.ssh" "$USER_HOME/.network-mappings"

# setup directories permissions
chmod 700 "$USER_HOME/.ssh" "$USER_HOME/.network-mappings"

# setup files permissions (allow shell expansion for wildcards)
chmod 400 "$USER_HOME/.ssh/"*
chmod 644 "$USER_HOME/.ssh/"*.pub
chmod 600 "$USER_HOME/.ssh/authorized_keys" "$USER_HOME/.ssh/known_hosts" "$USER_HOME/.ssh/config"

##############################################################
#                          SETUP SSHD                        #
##############################################################

announce "setting up ssh server"

# decrypt and uncompress config files into server directory
gpg --decrypt --batch --passphrase "$TAR_PASSWD" "$GPG_TARBALL" | tar -C /etc/ssh/sshd_config.d --strip-components=2 -xvf /dev/stdin "tarball/sshd/sshd_overrides.conf"

# decrypt and uncompress login banner into server directory
gpg --decrypt --batch --passphrase "$TAR_PASSWD" "$GPG_TARBALL" | tar -C /etc --strip-components=2 --overwrite -xvf /dev/stdin "tarball/sshd/issue.net"

# setup ownership
chown root:root /etc/ssh/sshd_config.d/sshd_overrides.conf /etc/issue.net

##############################################################
#                      SETUP X.ORG / XRDP                    #
##############################################################

announce "setting up xrdp and xorg"

# add the xrdp user to the ssl-cert group
adduser xrdp ssl-cert

# decrypt and uncompress config files into xrdp directory
gpg --decrypt --batch --passphrase "$TAR_PASSWD" "$GPG_TARBALL" | tar -C /etc/xrdp --strip-components=2 --overwrite -xvf /dev/stdin "tarball/xrdp/xrdp.ini" "tarball/xrdp/sesman.ini"

# setup ownership
chown root:root /etc/xrdp/xrdp.ini /etc/xrdp/sesman.ini

##############################################################
#                     SETUP AUDIO FOR XRDP                   #
##############################################################

announce "building and installing xrdp audio module"

# clone repo
git clone https://github.com/neutrinolabs/pulseaudio-module-xrdp.git "$EXEC_PATH/pulseaudio-module-xrdp"

# cd into repo
cd "$EXEC_PATH/pulseaudio-module-xrdp" || exit 1

# run build scripts
./scripts/install_pulseaudio_sources_apt_wrapper.sh

# move build directory
mv ~/pulseaudio.src "$EXEC_PATH/."

# bootstrap and configure
./bootstrap && ./configure PULSE_DIR="$EXEC_PATH/pulseaudio.src"

# make
make

# install
make install

# cd back into autoconfig directory
cd ..

##############################################################
#                         SETUP DOCKER                       #
##############################################################

announce "configuring docker"

# add user to group
usermod -a -G docker "$username"

# disable docker auto start
systemctl disable docker.service docker.socket containerd.service

# decrypt and uncompress registries credentials into user home directory
gpg --decrypt --batch --passphrase "$TAR_PASSWD" "$GPG_TARBALL" | tar -C "$USER_HOME" --strip-components=1 -xvf /dev/stdin "tarball/.docker"

# setup ownership
chown -R "$username":"$username" "$USER_HOME/.docker"

##############################################################
#                        SETUP SYSTEMD                       #
##############################################################

announce "configuring systemd"

# decrypt and uncompress configuration units into systemd directories
gpg --decrypt --batch --passphrase "$TAR_PASSWD" "$GPG_TARBALL" | tar -C /lib/systemd/system --strip-components=2 -xvf /dev/stdin "tarball/systemd/docker.target"
gpg --decrypt --batch --passphrase "$TAR_PASSWD" "$GPG_TARBALL" | tar -C /etc/systemd/system --strip-components=2 -xvf /dev/stdin "tarball/systemd/network-drives.service"

# setup ownership
chown root:root /lib/systemd/system/docker.target /etc/systemd/system/network-drives.service

# rebuild dependency tree
systemctl daemon-reload

# enable docker configuration unit, create symlinks
systemctl enable docker.target

# set default system target
systemctl set-default multi-user.target

##############################################################
#                        SETUP GIT REPOS                     #
##############################################################

announce "cloning git repositories"

# clone repositories
# shellcheck disable=SC2016
xargs -a "$USER_REPOS" -P 1 -tn 4 runuser -c 'mkdir -pv ~/$1 && \
git clone $0 ~/$1 && \
cd ~/$1 && \
git config user.email $2 && \
git config user.name $3' -P --login "$username"

# decrypt and uncompress confidential data into newly cloned repositories
gpg --decrypt --batch --passphrase "$TAR_PASSWD" "$GPG_TARBALL" | tar -C "$USER_HOME/git" --strip-components=1 --wildcards -xvf /dev/stdin \
"tarball/cloud-control/*" \
"tarball/codebase/*" \
"tarball/fullstackjavascript/*" \
"tarball/helm-charts/*" \
"tarball/megadownload/*" \
"tarball/mulepedia/*" \
"tarball/stream-from-the-shell/*" \
"tarball/stream.generator/*" \
"tarball/watchteevee/*"

# restore tarball source directory
gpg --decrypt --batch --passphrase "$TAR_PASSWD" "$GPG_TARBALL" | tar -C "$USER_HOME/git/autoconfig" -xvf /dev/stdin "tarball"

##############################################################
#                          SETUP $HOME                       #
##############################################################

announce "setting up $USER_HOME"

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
if [[ -f "$USER_HOME/.bashrc" ]]; then echo -e "$extendshell"  >> "$USER_HOME/.bashrc"; fi

# set custom .vimrc
if [[ ! -f "$USER_HOME/.vimrc" ]]; then cp "$USER_HOME/.shell_extend/.vimrc_default" "$USER_HOME/.vimrc"; fi

# setup ownership
chown -R "$username":"$username" "$USER_HOME/.vimrc"

# setup permissions
chmod 600 "$USER_HOME/.vimrc"

##############################################################
#                        SETUP /etc/skel                     #
##############################################################

announce "setting up default user directory"

# install shell_extend for all users
cp -rv "$USER_HOME/.shell_extend" /etc/skel/.

# remove working tree
rm -rf /etc/skel/.shell_extend/.git

# update default .bashrc
if [[ -f /etc/skel/.bashrc ]]; then echo -e "$extendshell"  >> /etc/skel/.bashrc; fi

# set default .vimrc
if [[ ! -f /etc/skel/.vimrc ]]; then cp /etc/skel/.shell_extend/.vimrc_default /etc/skel/.vimrc; fi

# setup permissions
chmod 600 /etc/skel/.vimrc

##############################################################
#                       SETUP MULTIMEDIA                     #
##############################################################

echo -e "installing multimedia tools"

# install gifski
wget -qO "$EXEC_PATH/gifski.deb" "https://github.com/ImageOptim/gifski/releases/download/1.33.0/gifski_1.33.0-1_$ARCH.deb" && dpkg -i "$EXEC_PATH/gifski.deb" || \
echo "gifski: no build available for current architecture, skipping install"

# decrypt and uncompress gifmaker script into user home directory
gpg --decrypt --batch --passphrase "$TAR_PASSWD" "$GPG_TARBALL" | tar -C "$USER_HOME" --strip-components=1 -xvf /dev/stdin "tarball/gifmaker.sh"

# setup gif maker and add alias to .bashrc
# shellcheck disable=SC2016
runuser -c 'echo '\''alias gif=$HOME/gifmaker.sh'\'' >> "$HOME/.bashrc"' -P --login "$username"

# install youtube-dl nightly build
runuser -c 'pipx install "git+https://github.com/ytdl-org/youtube-dl.git" && pipx ensurepath' -P --login "$username"

##############################################################
#                         SETUP NODE.JS                      #
##############################################################

announce "installing node.js"

# setup nvm
runuser -c 'curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash' -P --login "$username"

# install + setup node and npm (load nvm since runuser won't execute .bashrc)
runuser -c '. .nvm/nvm.sh && nvm install --lts --latest-npm' -P --login "$username"

# decrypt and uncompress config file into user home directory
gpg --decrypt --batch --passphrase "$TAR_PASSWD" "$GPG_TARBALL" | tar -C "$USER_HOME" --strip-components=1 -xvf /dev/stdin "tarball/.npmrc"

# setup ownership
chown "$username":"$username" "$USER_HOME/.npmrc"

# setup permissions
chmod 600 "$USER_HOME/.npmrc"

# global modules management 
# shellcheck disable=SC2016
GLOBAL_MODULES_PATH='
# export npm global modules path
export NODE_PATH="$(realpath $NVM_INC/../../lib/node_modules)"'

if [[ -f "$USER_HOME/.bashrc" ]]; then echo -e "$GLOBAL_MODULES_PATH" >> "$USER_HOME/.bashrc"; fi

# install global modules and create symlink to folder 
# shellcheck disable=SC2016
runuser -c '. .nvm/nvm.sh && \
npm install -g degit npm-check-updates js-beautify && \
ln -s $(realpath $NVM_INC/../../lib/node_modules) ~/node.globals' -P --login "$username"

##############################################################
#                        SETUP POSTMAN                       #
##############################################################

announce "installing postman"

# create desktop folder
mkdir "$USER_HOME/Desktop"

# install
wget -qO "$EXEC_PATH/postman-linux-x64.tar.gz" "https://dl.pstmn.io/download/latest/linux64" && tar -C "$USER_HOME/Desktop" -zxvf "$EXEC_PATH/postman-linux-x64.tar.gz"

# setup ownership
chown -R "$username":"$username" "$USER_HOME/Desktop"

##############################################################
#                      INSTALL LINODE CLI                    #
##############################################################

announce "installing linode CLI"

# install linode-cli from the python repositories
runuser -c 'pipx install linode-cli && pipx ensurepath' -P --login "$username"

##############################################################
#                            CLEAN UP                        #
##############################################################

announce "removing installation files"

# uninstall irrelevant packages
# shellcheck disable=SC2086
apt-get purge -y $PURGE && apt-get autoremove -y

# end message
ENDMSG="installation complete.\ndon't forget to complete the following post-installation steps :\n$(cat "$USER_POSTINSTALL")"

# remove local repo
cd .. && rm -rf "$EXEC_PATH"

##############################################################
#                             DONE                           #
##############################################################

echo -e "$ENDMSG"