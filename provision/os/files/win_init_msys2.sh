#!/bin/bash

# exit on any failure
set -e

if [[ -n "${PACKER_DEBUG}" ]]; then
  set -vx
fi

if ! echo $PATH | /bin/grep -q /usr/bin; then
  export PATH=/usr/bin:$PATH
fi

if [ -z "$SSHD_USER" ]; then export SSHD_USER=sshd_server; fi
if [ -z "$SSHD_PASSWORD" ]; then export SSHD_PASSWORD="$(tr -dc 'a-zA-Z0-9' < /dev/urandom | dd count=14 bs=1 2>/dev/null)"; fi

#MSYSTEM=MSYS || MINGW32 || MINGW64
if [ -z "$MSYSTEM" ]; then export MSYSTEM=MINGW32; fi

echo "==> Installing packages"
pacman --noconfirm --noprogressbar --needed -S cygrunsrv openssh mingw-w64-$(uname -m)-editrights python2 mingw-w64-$(uname -m)-python2-pip

echo "==> Configuring packages"
if [ ! -f /usr/bin/python ]; then ln -s /usr/bin/python2 /usr/bin/python; fi

echo "==> Generating SSH keys"
ssh-keygen -A

echo "==> Setting up host's ssh config files"
touch /var/log/lastlog
chmod a+w /etc/ssh/sshd_config

sed -i -e 's/#\?StrictModes \(yes\|no\)/StrictModes no/i' /etc/ssh/sshd_config
sed -i -e 's/#\?PubkeyAuthentication \(yes\|no\)/PubkeyAuthentication yes/i' /etc/ssh/sshd_config
sed -i -e 's/#\?PermitUserEnvironment \(yes\|no\)/PermitUserEnvironment yes/i' /etc/ssh/sshd_config
sed -i -e 's/#\?UseDNS \(yes\|no\)/UseDNS no/i' /etc/ssh/sshd_config
sed -i -e 's/#\?MaxAuthTries \([0-9]*\)/MaxAuthTries 10/i' /etc/ssh/sshd_config
sed -i -e 's/#\?UsePrivilegeSeparation \(.*\)/UsePrivilegeSeparation no/i' /etc/ssh/sshd_config

chmod go-w /etc/ssh/sshd_config

#echo "==> Disabling account password expiration for user $USERNAME"
#echo '' | wmic USERACCOUNT WHERE "Name='$USERNAME'" set PasswordExpires=FALSE

# TODO: sshd privilege separation (e.g. https://gist.github.com/samhocevar/00eec26d9e9988d080ac)

PRIV_USER=sshd_server
PRIV_NAME="Privileged user for sshd"
PRIV_PASSWORD="$(tr -dc 'a-zA-Z0-9' < /dev/urandom | dd count=14 bs=1 2>/dev/null)"
UNPRIV_USER=sshd
UNPRIV_NAME="Privilege separation user for sshd"
EMPTY_DIR=/var/empty

echo "==> Creating privileged user $PRIV_USER"
add="$(if ! net user "${PRIV_USER}" >/dev/null; then echo "//add"; fi)"
if ! net user "${PRIV_USER}" "${PRIV_PASSWORD}" ${add} //fullname:"${PRIV_NAME}" //homedir:"$(cygpath -w ${EMPTY_DIR})" //yes; then
    echo "ERROR: Unable to create Windows user ${PRIV_USER}"
    exit 1
fi

echo "==> Adding $PRIV_USER to admin group"
admingroup="$(mkgroup -l | awk -F: '{if ($2 == "S-1-5-32-544") print $1;}')"
if ! (net localgroup "${admingroup}" | grep -q '^'"${PRIV_USER}"'$'); then
    if ! net localgroup "${admingroup}" "${PRIV_USER}" //add; then
        echo "ERROR: Unable to add user ${PRIV_USER} to group ${admingroup}"
        exit 1
    fi
fi

echo "==> Setting password expiration for ${PRIV_USER}"
passwd -e "${PRIV_USER}"

echo "==> Setting required privileges"
for flag in SeAssignPrimaryTokenPrivilege SeCreateTokenPrivilege SeTcbPrivilege SeDenyRemoteInteractiveLogonRight SeServiceLogonRight; do
    if ! editrights -a "${flag}" -u "${PRIV_USER}"; then
        echo "ERROR: Unable to give ${flag} rights to user ${PRIV_USER}"
        exit 1
    fi
done

echo "==> Creating unprivileged user ${UNPRIV_USER}"
add="$(if ! net user "${UNPRIV_USER}" >/dev/null; then echo "//add"; fi)"
if ! net user "${UNPRIV_USER}" ${add} //fullname:"${UNPRIV_NAME}" //homedir:"$(cygpath -w ${EMPTY_DIR})" //active:no; then
    echo "ERROR: Unable to create Windows user ${UNPRIV_USER}"
    exit 1
fi

echo "==> Updating /etc/passwd"
touch /etc/passwd
for u in "${PRIV_USER}" "${UNPRIV_USER}"; do
    sed -i -e '/^'"${u}"':/d' /etc/passwd
    SED='/^'"${u}"':/s?^\(\([^:]*:\)\{5\}\).*?\1'"${EMPTY_DIR}"':/bin/false?p'
    mkpasswd -l -u "${u}" | sed -e 's/^[^:]*+//' | sed -ne "${SED}" >> /etc/passwd
done

echo "==> Removing old SSH service (if exists)"
cygrunsrv -R sshd || true
echo "==> Stopping processes listening on TCP:22"
(netstat -a -p tcp -n -o | grep LISTENING | awk '/\:22/{print $5}' | xargs kill -f) || true
          
echo "==> Installing SSH service"
cygrunsrv -I sshd -d "MSYS2 sshd" -p /usr/bin/sshd.exe -a "-D -e" -y tcpip --env MSYSTEM=$MSYSTEM -u "${PRIV_USER}" -w "${PRIV_PASSWORD}"

#echo "==> Starting sshd service"
#net start sshd || false

echo "==> Disabling SSH service"
sc config sshd start= disabled

# When running via Run key SSHd can interact with desktop
echo "==> Enabling SSHd to run on startup via registry"
regtool --expand-string set '\HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Run\sshd' "`cygpath -w /autorebase.bat` & `cygpath -w /usr/bin/bash.exe` --login -c \"export MSYSTEM=$MSYSTEM; chown \`whoami\` $EMPTY_DIR && /usr/bin/sshd\""
