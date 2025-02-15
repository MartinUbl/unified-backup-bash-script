#!/bin/bash

# how often to backup - 0 = whenever the script is run, 1 = every day, 2 = every other day, 7 = once a week
BACKUP_FREQUENCY=0

# where to store the backups; this assumes that the user's public key is in the target server's authorized_keys file
TARGET_SERVER=target.ofmybackup.com
TARGET_USER=backupuser
# backup directory root - all backups will be stored and versioned here
TARGET_DIRECTORY_BASE=/opt/backups/server1

# mysql user and password for backups
MYSQL_USER=backupuser
MYSQL_PASSWORD="backup password"

# directories to backup - space-separated list of directories or empty if not desired
BACKUP_DIRECTORIES="/etc /var/www"

# which databases to backup? "*" = all databases, "?..." = regex format (e.g., "?(^web|mysql)" for all databases staring with web or named "mysql")
#                            or list of databases, (e.g., "web1 web2 mysql test")
BACKUP_MYSQL_DATABASES="*"

# which databases to ignore? default: "information_schema performance_schema"
BACKUP_MYSQL_IGNORE_DATABASES="information_schema performance_schema"

# notification e-mail for errors
NOTIFY_EMAIL="webmaster@localhost"

###########################################################################################
# configuration parameters that should not be changed, unless you know what you are doing #
###########################################################################################

DATE_FORMATTER="%F-%H-%M-%S"

TAR_FLAGS="-czf"

MYSQLDUMP_FLAGS="--single-transaction --quick"

# a list of all possible error e-mail subjects
EMAIL_ERROR_SUBJECTS=("Arcibober się zesrał" "Arcibober uprawiał seks z chomikiem" "Arcibober zjadł zgniłe jajko" "Arcibober zasnął na kiblu")

EMAIL_WARNING_SUBJECTS=("Arcibober upił się i zasnął" "Arcibober trochę posrał się w gacie" "Arcibober ma śmierdzące stopy" "Arcibober polujący na gówno w toalecie")
