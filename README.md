# Backup script

This is a unified backup script to backup our servers and services.

## Setup

At first, create a user designated for backups on the source server, having a home directory somewhere on a partition with enough space, e.g.:
```
useradd -m -d /opt/arcibober -s /bin/bash arcibober
```

Install the `mailutils` package, or any other package that provides the `mail` command, e.g., `apt install mailutils`

Then, clone the repository and copy `config.template.sh` as `config.sh` and perform the configuration.

Then, create a SSH key on the source server (e.g., `ssh-keygen` as the arcibober user) and copy the public key to authorized hosts on the remote machine (manually or using `ssh-copy-id`).

For MySQL backups, create a user designated for backups (prefer localhost-only access for security reasons) and grant it all required read-only privileges, e.g.:
```
CREATE USER backup@localhost IDENTIFIED BY 'very_secret_backup_password';
GRANT SELECT, SHOW VIEW, TRIGGER, LOCK TABLES ON *.* TO backup@localhost;
```

### Typical setup sequence

A typical setup sequence may consist of the following commands (starting as `root`):

```
mkdir -p /opt/arcibober
useradd -d /opt/arcibober -s /bin/bash arcibober
chown arcibober:arcibober /opt/arcibober
apt install mailutils
su - arcibober
wget https://github.com/MartinUbl/unified-backup-bash-script/raw/refs/heads/main/backup.sh
wget https://github.com/MartinUbl/unified-backup-bash-script/raw/refs/heads/main/config.template.sh
chmod +x backup.sh
ssh-keygen
ssh-copy-id -s remoteuser@remoteserver.example.com
```

## Notes

Everything the Arcibober backs up must be accessible for it. You may use ordinary unix permissions (e.g., read permission, chmod +r), or ACLs.

For example, if you want to back up the `/etc` folder using Arcibober, you may want to run the following set of commands:
```
setfacl -Rdm u:arcibober:rx /etc/
setfacl -Rm u:arcibober:rx /etc/
```

NOTE: the first command sets the defaults, so all files created in future have the same rule applied. The second command manipulates ACLs of currently existing files
