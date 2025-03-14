#!/bin/bash

###############################################################################
# INITIALIZATION															  #
###############################################################################

# check if the script is run with an argument
if [ ! -z "$1" ]; then
	if [ "$1" == "--autoupdate" ]; then
		echo "Performing autoupdate of Arcibober"
		echo "> Downloading the latest version"
		wget -nv -q https://github.com/MartinUbl/unified-backup-bash-script/raw/refs/heads/main/backup.sh -O .backup.new.sh >/dev/null
		echo "> Checking the downloaded file"
		chmod +x .backup.new.sh
		if [ $(wc -l < .backup.new.sh) -lt 10 ]; then
			echo "Downloaded file is too short, aborting"
			exit 1
		fi
		mv .backup.new.sh backup.sh
		echo "Update complete!"
		exit 0
	else
		echo "Unknown argument: $1"
		echo "Supported parameters:"
		echo "  --autoupdate - update the script automatically"
		exit 2
	fi
fi

# check the presence of the configuration file
if [ ! -f "config.sh" ]; then
	echo "[ERR] No config file found!"
	exit 3
fi

# load config
source config.sh

###############################################################################
# FUNCTIONS AND HELPERS														  #
###############################################################################

WARNINGS=()

# terminate script with an error code and send an email
die_loud() {
	TIMESTAMP=$(date +"%Y-%m-%d %H:%M:%S")
	echo -e "$TIMESTAMP [\e[31mERR\e[0m]$1" >&2
	if [ ! -z "$NOTIFY_EMAIL" ]; then
		SUBJECT=${EMAIL_ERROR_SUBJECTS[$RANDOM % ${#EMAIL_ERROR_SUBJECTS[@]}]}

		# build WARNSTRING as a list of warnings all prefixed by [WARN] and separated by newlines
		WARNSTRING=""
		for w in "${WARNINGS[@]}"; do
			if [ -z "$WARNSTRING" ]; then
				WARNSTRING="[WARN] $w"
			else
				WARNSTRING="$WARNSTRING\n[WARN] $w"
			fi
		done

		echo -e "[ERR] $1\n$WARNSTRING" | mail -s "[!] $SUBJECT" $NOTIFY_EMAIL
	fi
	exit 1
}

# add a warning to the list of warnings
warn() {
	TIMESTAMP=$(date +"%Y-%m-%d %H:%M:%S")
	WARNINGS+=("$1")
	echo -e "$TIMESTAMP [\e[33mWARN\e[0m] $1" >&2
}

info() {
	TIMESTAMP=$(date +"%Y-%m-%d %H:%M:%S")
	echo -e "$TIMESTAMP [\e[32mINFO\e[0m] $1"
}

# flush warnings to the console and send an email
flush_warnings() {
	if [ ${#WARNINGS[@]} -gt 0 ]; then
		WARNSTRING=""
		for w in "${WARNINGS[@]}"; do
			echo -e "[\e[33mWARN\e[0m] $w"

			if [ -z "$WARNSTRING" ]; then
				WARNSTRING="[WARN] $w"
			else
				WARNSTRING="$WARNSTRING\n[WARN] $w"
			fi
		done

		if [ ! -z "$NOTIFY_EMAIL" ]; then
			SUBJECT=${EMAIL_ERROR_SUBJECTS[$RANDOM % ${#EMAIL_ERROR_SUBJECTS[@]}]}
			echo -e "$WARNSTRING" | mail -s "[!] $SUBJECT" $NOTIFY_EMAIL
		fi
	fi
}

# MySQL login parameters formatter
mysqlLogin() {
	echo "-u$MYSQL_USER -p$MYSQL_PASSWORD"
}

###############################################################################
# MAIN SCRIPT BODY															  #
###############################################################################

# if the target server is set, but there are some .tar.gz files in the current directory, warn the user
if [ ! -z "$TARGET_SERVER" ]; then
	if [ $(ls -1 *.tar.gz 2>/dev/null|wc -l) -gt 0 ]; then
		warn "There are some .tar.gz files in the current directory, which will be uploaded to the target server; make sure they are not needed locally and remove them"
	fi
fi

CURDATE=$(date +"$DATE_FORMATTER")
TODAY=$(($(date +%s -d $(date +%Y%m%d))/86400))

if [ -f ".state" ]; then
	LASTDAY=$(cat .state)
	DUE=$(($LASTDAY+$BACKUP_FREQUENCY))
	if [ $DUE -gt $TODAY ]; then
		echo "Backup not yet due"
		exit 0
	fi	
fi

echo $TODAY > .state

HOME=$(pwd)
BUPDIR=$HOME/$CURDATE

if [ -d $BUPDIR ]; then
	warn "Backup directory already exists! Will overwrite contents."
fi

mkdir -p $BUPDIR
if [ ! -d $BUPDIR ]; then
	die_loud "Cannot create backup directory (insufficient rights or the disk is full)"
fi

cd $BUPDIR

# back up directories from filesystem

if [ ! -z "$BACKUP_DIRECTORIES" ]; then
	for dir in $BACKUP_DIRECTORIES; do
		if [ -d $dir ]; then
			SAFENAME=$(echo $dir | sed -e s?/?_?g --)
			info "Backing up $dir as $SAFENAME"
			cd $dir
			tar $TAR_FLAGS $BUPDIR/$SAFENAME.tar.gz *
			cd $BUPDIR
			info "Backup of $dir complete"
		else
			warn "Directory '$dir' configured for backup does not exist!" >&2
		fi
	done
else
	info "No directories were requested to be backed up"
fi

# back up MySQL databases
if [ ! -z "$BACKUP_MYSQL_DATABASES" ]; then
	DBLIST=""
	if [ "$BACKUP_MYSQL_DATABASES" == "*" ]; then
		DBLIST=$(mysql $(mysqlLogin) -e "SHOW DATABASES"|awk -F " " '{if (NR!=1) print $1}')
		info "Backing up all databases"
	elif [ "${BACKUP_MYSQL_DATABASES:0:1}" == "?" ]; then
		DBLIST=$(mysql $(mysqlLogin) -e "SHOW DATABASES"|awk -F " " '{if (NR!=1) print $1}'|grep -E "${BACKUP_MYSQL_DATABASES:1}")
		info "Backing up databases matching regex '${BACKUP_MYSQL_DATABASES:1}'"
	else
		DBLIST="$BACKUP_MYSQL_DATABASES"
		info "Backing up databases: $DBLIST"
	fi

	# remove ignored databases
	if [ ! -z "$BACKUP_MYSQL_IGNORE_DATABASES" ]; then
		for db in $BACKUP_MYSQL_IGNORE_DATABASES; do
			DBLIST=$(echo $DBLIST|sed -e "s/\b$db\b//g")
		done
	fi

	for db in $DBLIST; do
		info "Backing up MySQL database $db"
		mysqldump $(mysqlLogin) $MYSQLDUMP_FLAGS $db | gzip -c > $BUPDIR/$db.sql.gz
	done
else
	info "No MySQL databases were requested to be backed up"
fi

# back up Docker containers
if [ ! -z "$BACKUP_DOCKER_CONTAINERS" ]; then
	if [ "$BACKUP_DOCKER_CONTAINERS" == "*" ]; then
		CONTAINERS=$(docker ps -q)
	else
		CONTAINERS=$BACKUP_DOCKER_CONTAINERS
	fi

	for container in $CONTAINERS; do
		info "Backing up Docker container $container"
		docker export $container | gzip -c > $BUPDIR/$container.tar.gz
	done
else
	info "No Docker containers were requested to be backed up"
fi

# compress the whole backup directory
cd $HOME
tar $TAR_FLAGS $CURDATE.tar.gz $CURDATE
if [ $? -ne 0 ]; then
	die_loud "Cannot compress the backup directory"
fi

rm -rf $CURDATE

# check if the backup was created and is not empty
if [ ! -s $CURDATE.tar.gz ]; then
	die_loud "Backup creation failed or the backup is empty"
fi

# check if the target server is known and add it to known_hosts if not
if [ -z "$(ssh-keygen -F $TARGET_SERVER)" ]; then
  	ssh-keyscan -H $TARGET_SERVER >> ~/.ssh/known_hosts
fi

# attempt to establish connection to the target server - probe the connection
info "Probing SSH connection to the target server"

ssh $SSH_FLAGS -o ConnectTimeout=5 $TARGET_USER@$TARGET_SERVER "ls" >/dev/null
if [ $? -ne 0 ]; then
	die_loud "Cannot establish SSH connection to the target server"
fi

# upload the backup to the target server
if [ ! -z "$TARGET_SERVER" ]; then
	info "Uploading backup to $TARGET_SERVER"

	SSH_COMMAND="ssh $SSH_FLAGS $TARGET_USER@$TARGET_SERVER"
	SCP_COMMAND="scp $SCP_FLAGS"

	info "Creating the target directory on the remote server"

	# create the target directory base on the remote server if not exists
	$SSH_COMMAND "mkdir -p $TARGET_DIRECTORY_BASE"
	if [ $? -ne 0 ]; then
		die_loud "Cannot create the target directory on the remote server"
	fi

	info "Querying the available space on the remote server"

	# check if there is enough space on the remote server to upload the backup
	SPACE_QR=$($SSH_COMMAND "df -P $TARGET_DIRECTORY_BASE")
	SPACE=$(echo "$SPACE_QR" | tail -n 1 | awk '{print $4}')
	if [ $SPACE -lt $(stat -c %s $CURDATE.tar.gz) ]; then
		die_loud "Not enough space on the remote server to upload the backup"
	fi

	info "Uploading the backup to the remote server"

	$SCP_COMMAND $CURDATE.tar.gz $TARGET_USER@$TARGET_SERVER:$TARGET_DIRECTORY_BASE
	if [ $? -ne 0 ]; then
		die_loud "Cannot upload the backup to the remote server"
	fi

	info "Calculating MD5 hashes of the uploaded backup"

	# calculate MD5 hash of local backup and compare it to remote backup MD5 hash
	MD5_LOCAL=$(md5sum $CURDATE.tar.gz | awk '{print $1}')
	MD5_REMOTE_QR=$($SSH_COMMAND "md5sum $TARGET_DIRECTORY_BASE/$CURDATE.tar.gz")
	MD5_REMOTE=$(echo $MD5_REMOTE_QR | awk '{print $1}')

	if [ "$MD5_LOCAL" != "$MD5_REMOTE" ]; then
		warn "MD5 hash of the uploaded backup does not match the local backup!"
	else
		info "MD5 hashes match, removing local copy"
		rm $CURDATE.tar.gz
		if [ $? -ne 0 ]; then
			warn "Cannot remove the local backup"
		fi
	fi

	info "Cleaning up old backups on $TARGET_SERVER"

	BACKUP_LIST=$($SSH_COMMAND "ls -1 -t $TARGET_DIRECTORY_BASE")
	if [ $(echo "$BACKUP_LIST" | wc -l) -gt $KEEP_BACKUPS ]; then
		OLD_BACKUPS=$(echo "$BACKUP_LIST" | tail -n +$(($KEEP_BACKUPS+1)))
		for backup in $OLD_BACKUPS; do
			$SSH_COMMAND "rm $TARGET_DIRECTORY_BASE/$backup"
		done
	fi


	if [ $? -ne 0 ]; then
		warn "Cannot clean up old backups on the remote server"
	fi
else
	warn "No target server specified, backup will not be uploaded and will be kept only locally"
fi

info "Backup complete"
flush_warnings
exit 0
