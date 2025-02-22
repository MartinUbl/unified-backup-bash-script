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
