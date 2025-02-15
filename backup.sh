#!/bin/bash

###############################################################################
# INITIALIZATION															  #
###############################################################################

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
	echo "$1" >&2
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
	WARNINGS+=("$1")
	echo "[WARN] $1" >&2
}

# flush warnings to the console and send an email
flush_warnings() {
	if [ ${#WARNINGS[@]} -gt 0 ]; then
		WARNSTRING=""
		for w in "${WARNINGS[@]}"; do
			echo "[WARN] $w"

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

# spinner for "loading"
spinner() {
	local shs=( - \\ \| / ) pnt=0
	printf '\e7'
	while ! read -rsn1 -t .2 _; do
		printf '%b\e8' "${shs[pnt++%${#shs[@]}]}"
	done
}

startSpinner () {
	tput civis;
	exec {doSpinner}> >(spinner "$@")
}

stopSpinner () {
	echo >&"$doSpinner" && exec {doSpinner}>&-;
	tput cnorm;
}

# MySQL login parameters formatter
mysqlLogin() {
	echo "-u$MYSQL_USER -p$MYSQL_PASSWORD"
}

###############################################################################
# MAIN SCRIPT BODY															  #
###############################################################################

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
	warn "[ERR] Backup directory already exists! Will overwrite contents."
fi

mkdir -p $BUPDIR
if [ ! -d $BUPDIR ]; then
	die_loud "[ERR] Cannot create backup directory (insufficient rights or the disk is full)"
fi

echo "Backup directory: $BUPDIR"
cd $BUPDIR

# back up directories from filesystem

if [ ! -z "$BACKUP_DIRECTORIES" ]; then
	for dir in $BACKUP_DIRECTORIES; do
		if [ -d $dir ]; then
			SAFENAME=$(echo $dir | sed -e s?/?_?g --)
			echo -n "Backing up $dir as $SAFENAME ... "
			startSpinner;
			cd $dir
			tar $TAR_FLAGS $BUPDIR/$SAFENAME.tar.gz *
			cd $BUPDIR
			stopSpinner;
			echo "done"
		else
			warn "[WARN] Directory '$dir' configured for backup does not exist!" >&2
		fi
	done
fi

# back up MySQL databases
if [ ! -z "$BACKUP_MYSQL_DATABASES" ]; then
	DBLIST=""
	if [ "$BACKUP_MYSQL_DATABASES" == "*" ]; then
		DBLIST=$(mysql $(mysqlLogin) -e "SHOW DATABASES"|awk -F " " '{if (NR!=1) print $1}')
		echo "Backing up all databases"
	elif [ "${BACKUP_MYSQL_DATABASES:0:1}" == "?" ]; then
		DBLIST=$(mysql $(mysqlLogin) -e "SHOW DATABASES"|awk -F " " '{if (NR!=1) print $1}'|grep -E "${BACKUP_MYSQL_DATABASES:1}")
		echo "Backing up databases matching regex '${BACKUP_MYSQL_DATABASES:1}'"
	else
		DBLIST="$BACKUP_MYSQL_DATABASES"
		echo "Backing up databases: $DBLIST"
	fi

	# remove ignored databases
	if [ ! -z "$BACKUP_MYSQL_IGNORE_DATABASES" ]; then
		for db in $BACKUP_MYSQL_IGNORE_DATABASES; do
			DBLIST=$(echo $DBLIST|sed -e "s/\b$db\b//g")
		done
	fi

	for db in $DBLIST; do
		echo "Backing up MySQL database $db"
		#mysqldump $(mysqlLogin) $MYSQLDUMP_FLAGS $db > $BUPDIR/$db.sql
	done
fi
