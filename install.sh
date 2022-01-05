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
USER_SHELL=/bin/bash

# encrypted files storage
GPG_TARBALL=$autoconfig/tarball.tar.gpg

# default apt sources are configured at installation, update and upgrade
apt-get update && apt-get upgrade

# ================== INSTALL PACKAGES ======================
echo -e "installing default packages"

# install packages (only main dependencies, ignore missing, yes to all prompts, progress indicator
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
# miscellaneous

apt-get install --no-install-recommends -m -y --show-progress \
bash-completion tree tmux curl wget dos2unix \
vim vim-common vim-runtime \
man-db \
unzip \
policykit-1 \
gnupg2 pgpdump \
procps psmisc sysstat iotop time \
net-tools nmap iftop \
lsb-release apt-rdepends \
shellcheck \
ca-certificates jq \
cowsay cowsay-off display-dhammapada steghide

# ================= EXTRACT TARBALL ========================
# prompt password
echo -e "=== PLEASE ENTER TAR ARCHIVE PASSWORD ==="
read -r tarpp

# decrypt and uncompress into current directory
gpg --decrypt --batch --passphrase "$tarpp" "$GPG_TARBALL" | tar --strip-components=1 --wildcards -xvf /dev/stdin "tarball/user-*"

# =============== CREATE USER + SETUP SSH ==================
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
gpg --decrypt --batch --passphrase "$tarpp" "$GPG_TARBALL" | tar -C "$userhome" --strip-components=1 -xvf /dev/stdin "tarball/.ssh"

# setup ownership
chown -R "$username":"$username" "$userhome/.ssh"

# setup permissions
chmod 700 "$userhome/.ssh"

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
gpg --decrypt --batch --passphrase "$tarpp" "$GPG_TARBALL" | tar -C "$userhome/git" --strip-components=1 --wildcards -xvf /dev/stdin "tarball/codebase/*" "tarball/data-viewer/*" "tarball/megadownload/*" "tarball/node-http-tunnel/*"

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

# install docker packages
apt-get install --no-install-recommends -m -y --show-progress docker-ce docker-ce-cli containerd.io

# add user to group
usermod -a -G docker "$username"

# disable docker auto start
systemctl disable docker.service docker.socket containerd.service

# =================== SETUP SYSTEMD ========================
echo -e "configuring systemd"

# decrypt and uncompress into systemd directory
gpg --decrypt --batch --passphrase "$tarpp" "$GPG_TARBALL" | tar -C /lib/systemd/system --strip-components=1 -xvf /dev/stdin "tarball/docker.target"

# setup ownership
chown root:root /lib/systemd/system/docker.target

# rebuild dependency tree
systemctl daemon-reload

# enable docker configuration unit, create symlinks
systemctl enable docker.target

# set default system target
systemctl set-default multi-user.target

# =================== SETUP NODE.JS ========================
echo -e "installing node.js"

# setup nvm
runuser -c 'curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.0/install.sh | bash' -P --login "$username"

# install + setup node and npm (load nvm since runuser won't execute .bashrc)
runuser -c '. .nvm/nvm.sh && nvm install --lts --latest-npm' -P --login "$username"

# global modules management 
# shellcheck disable=SC2016
GLOBAL_MODULES_PATH='\n
# export npm global modules path\n
export NODE_PATH=\"$NVM_INC/../../lib/node_modules\"'

[[ -f "$userhome/.bashrc" ]] && echo -e "$GLOBAL_MODULES_PATH" >> "$userhome/.bashrc"

# install global modules and create symlink to folder 
# shellcheck disable=SC2016
runuser -c '. .nvm/nvm.sh && \
npm install -g ascii-table chalk eslint eslint-plugin-html js-beautify && \
ln -s $(realpath $NVM_INC/../../lib/node_modules) ~/node.globals' -P --login "$username"

# ===================== MULTIMEDIA =========================
echo -e "setting up multimedia tools"

# install ffmpeg
apt-get install --no-install-recommends -m -y --show-progress ffmpeg

# setup megadownload and add alias to .bashrc
# shellcheck disable=SC2016
runuser -c '. .nvm/nvm.sh && \
cd git/megadownload && \
npm install && \
echo '\''alias mdl=$HOME/git/megadownload/megadownload.js'\'' >> "$HOME/.bashrc"' -P --login "$username"

# ==================== DATA-VIEWER =========================
echo -e "setting up data viewer service"

# start docker
systemctl isolate rundocker.target 

# run install script
# shellcheck disable=SC2016
runuser -c 'cd ~/git/data-viewer && 
. data-viewer-install.sh' -P --login "$username"

# stop docker
systemctl isolate multi-user.target 

# decrypt and uncompress into systemd directory
gpg --decrypt --batch --passphrase "$tarpp" "$GPG_TARBALL" | tar -C /etc/systemd/system --strip-components=1 -xvf /dev/stdin "tarball/data-viewer.service"

# setup ownership
chown root:root /etc/systemd/system/data-viewer.service

# rebuild dependency tree
systemctl daemon-reload

# ====================== CLEANUP ===========================
echo -e "removing installation files"

# remove local repo
cd .. && rm -rf "$autoconfig"

# ======================== DONE ============================
echo -e "installation complete."
