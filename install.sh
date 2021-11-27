#!/bin/bash

# set up a freshly installed host in local-debian current condition (git is present)

# script is meant to be run as root
if [ "$(id -u)" != "0" ]; then
        echo "Please run this script using sudo."
        exit 1
fi

# avoid confusion with built in shell variables
USER_NAME=$(pwd)/tarball/user-name
USER_GECOS=$(pwd)/tarball/user-gecos
USER_PASSWD=$(pwd)/tarball/user-password
USER_SHELL=/bin/bash

# encrypted files storage
GPG_TARBALL=$(pwd)/tarball.tar.gpg

# default apt sources are configured at installation, update and upgrade
apt-get update && apt-get upgrade

# ================== INSTALL PACKAGES ======================
echo -e "installing default packages"

# install packages (only main dependencies, ignore missing, yes to all prompts, progress indicator
# shell utilities
# editors
# man pages
# archive management
# encryption
# system utilities
# network utilities
# distro + packages management
# shell linter
# docker-relevant packages
# miscellaneous

apt-get install --no-install-recommends -m -y --show-progress \
bash-completion tree tmux curl wget \
vim vim-common vim-runtime \
man-db \
unzip \
gnupg2 pgpdump \
procps psmisc sysstat iotop time \
net-tools nmap iftop \
lsb_release apt-rdepends \
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

# ================== SETUP $HOME ===========================
echo -e "setting up $userhome"

# shellcheck disable=SC2016
extendshell='\n
# ------ SET SHELL EXTENSIONS ------\n
if [[ -f $HOME/.shell_extend/.bash_extend ]]; then\n
\t. $HOME/.shell_extend/.bash_extend\n
fi'

# clone github repo 
runuser -c 'git clone git@github.com:mulekick/.shell_extend.git' -P --login "$username"

# update .bashrc
if [[ -f "$userhome/.bashrc" ]]; then
    echo -e "$extendshell"  >> "$userhome/.bashrc"
fi

# set custom .vimrc
if [[ ! -f "$userhome/.vimrc" ]]; then
    cp "$userhome/.shell_extend/.vimrc_default" "$userhome/.vimrc"
fi

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

# set vim.basic as an editor alternative
[[ -x /usr/bin/vim.basic ]] && update-alternatives --set editor /usr/bin/vim.basic

# editor alternative should already be in auto mode, but anyway
update-alternatives --auto editor

# ==================== SETUP DOCKER ========================
echo -e "installing docker"

# retrieve docker gpg key
curl -fsSL 'https://download.docker.com/linux/debian/gpg' | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

# add apt source
echo \
"deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] \
https://download.docker.com/linux/debian $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

# update
apt-get update

# install docker packages
apt-get --no-install-recommends -m -y --show-progress docker-ce docker-ce-cli containerd.io

# =================== SETUP SYSTEMD ========================
echo -e "configuring systemd"

# decrypt and uncompress into current directory
gpg --decrypt --batch --passphrase "$tarpp" "$GPG_TARBALL" | tar --strip-components=1 -xvf /dev/stdin "tarball/docker.target"

# copy docker configuration unit
cp -v "$(pwd)/docker.target" /lib/systemd/system/.

# rebuild dependency tree
systemctl daemon-reload

# enable docker configuration unit, create symlinks
systemctl enable docker.target

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

[[ -f "$userhome/.bashrc" ]] && echo -e "$GLOBAL_MODULES_PATH"  >> "$userhome/.bashrc"

echo -e "installation complete."
