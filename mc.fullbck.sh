#!/bin/bash
#########################################################################
# Backup script for minecraft servers with SCP to another site.		#
# Stops and starts specified minecraft server for 100% backups.		#
# Supports multiple minecraft servers on the same machine		#
#									#
# Author								#
# Pierre Christoffersen, www.nahaz.se					#
# Feel free to redistribute, change or improve, but leave original	#
# authors and contributers in comments.					#
# http://github.com/Nahaz/Minecraft-Backup-Bash-Script			#
#									#
# Exitcodes:								#
# 0=Completed with no errors						#
# 1=Backupd done, server not restarted					#
# 2=Failed								#
# 									#
# Variables used:							#
#									#
# Minecraft-server related:						#
# MINECRAFTDIR=/Dir/to/minecraft/server					#
# MINECRAFTSRV=Name of server.jar used					#
# JXMS=512M #Amount of minimum ram for JVM 				#
# JXMX=3072M #Amount of maximum ram for JVM				#
# GUI=nogui #nogui, don't change, only a var for future purposes	#
# WORLDNAME=Name of minecraft world					#
# SCREEN=Screen name minecraft server is running in			#
#									#
# Server restart/stop timer and message					#
# TIME=60 #Countdown in seconds to shutdown server			#
# MSG="Server restarting in "$TIME" seconds, back in a minute!"		#
# TRIES=3 #Number of tries to start/stop server before giving up	#
#									#
# Temporary directory and remote site for backup			#
# TMPDIR=/dir/to/tmp							#
# BCKSRV=HOSTNAME #Hostname of backupserver				#
# BCKDIR=/dir/on/backupserver/to/store/in				#
#									#
# Don't change these unless you understand what you're doing		#
# LOG=$TMP/mc.$WORLDNAME.fullbck.log					#
# OF=/tmp/$FILE								#
# BUDIR=$MINECRAFTDIR/$WORLDNAME					#
# FILE=$WORLDNAME.$TIMESTAMP.fullbck.tar.gz				#
# TIMESTAMP=$(date +%y%m%d.%T)						#
# LOGSTAMP=$(date +%y%m%d\ %T)						#
#########################################################################

#Minecraft properties
MINECRAFTDIR=
MINECRAFTSRV=
JXMS=
JXMX=
GUI=nogui
WORLDNAME=world
SCREEN=mc
#Restart properties
TIME=30
MSG="Server restarting in "$TIME" seconds, back in a minute!"
TRIES=3
#Backup vars
TMPDIR=
BCKSRV=
BCKDIR=
#no need to change these
TIMESTAMP=$(date +%y%m%d.%T)
LOGSTAMP=$(date +%y%m%d\ %T)
LOG=$TMPDIR/mc.$WORLDNAME.fullbck.log
BUDIR=$MINECRAFTDIR/$WORLDNAME
FILE=$WORLDNAME.$TIMESTAMP.fullbck.tar.gz
OF=$TMPDIR/$FILE

#nifty functions, don't edit anything below

#Check if minecraft server is running, ONLINE == 1 if offline, ONLINE == 2 if running
function srv_check () {
	ONLINE=$(ps aux | grep "java -Xms$JXMS -Xmx$JXMX -jar $MINECRAFTSRV $GUI" | wc -l)
}

#Kill minecraft server, but post $MSG to server $TIME before shutdown and warn 5 seconds before shutdown. If "stop" don't work, kill $PID.
function kill_mc() {
	screen -S $SCREEN -p 0 -X stuff "`printf "say $MSG\r"`"; sleep $TIME
	screen -S $SCREEN -p 0 -X stuff "`printf "say Going down in 10 seconds! Saving world...\r"`"
	screen -S $SCREEN -p 0 -X stuff "`printf "save-all\r"`"; sleep 5
	screen -S $SCREEN -p 0 -X stuff "`printf "stop\r"`"; sleep 5
	srv_check
	if [ $ONLINE == 1 ]; then
		echo $LOGSTAMP": Minecraft server shutdown successfully">> $LOG
	else
		echo $LOGSTAMP": Minecraft server did NOT shutdown, will try with force">> $LOG
		local PID=$(ps -e | grep "java -Xms$JXMS -Xmx$JXMX -jar $MINECRAFTSRV $GUI" | grep -v grep | awk '{print $1;}')
		local STOP=$TRIES
		while [[ $STOP -gt 0 && $ONLINE == 2 ]]; do
			echo $LOGSTAMP": Try #"$STOP" of stopping minecraft server">> $LOG
			kill $PID
			srv_check
			STOP=$(($STOP-1))
		done
		if [ $STOP == 0 ]; then
			echo $LOGSTAMP": Could not kill minecraft server, exiting">> $LOG
			exit 2
		else
			echo $LOSTAMP": Killed minecraft server after "$STOP" number of tries, proceeding with full backup">> $LOG
		fi
	fi
}
#Start minecraft server with $PARAMS
function start_mc() {
	function java_start() {
		screen -S $SCREEN -p 0 -X stuff "`printf "cd $MINECRAFTDIR\r"`"; sleep 1
		screen -S $SCREEN -p 0 -X stuff "`printf "java -Xms$JXMS -Xmx$JXMX -jar $MINECRAFTSRV $GUI\r"`"; sleep 3
	}
	local PARAMS="screen -dmS $SCREEN java -Xms$JXMS -Xmx$JXMX -jar $MINECRAFTSRV $GUI"
	java_start
	srv_check
	if [ $ONLINE == 2 ]; then
		echo $LOGSTAMP": Server started successfully with "$PARAMS>> $LOG
	else
		echo $LOGSTAMP": Server did not start, trying again.">> $LOG
		local START=0
		local SCREXIST=$(ps aux | grep "SCREEN -dmS $SCREEN" | wc -l)
		while [[ $START -lt 3 && $ONLINE == 1 ]]; do
			echo $LOGSTAMP": Try #"$START" of starting minecraft server">> $LOG
			SCREXIST=$(ps aux | grep "SCREEN -dmS $SCREEN" | wc -l)
			if [ $SCREXIST == 1 ]; then
				echo $LOGSTAMP": Screen session not found, starting screen with -dmS "$SCREEN>> $LOG
				screen -dmS $SCREEN; sleep 1
				java_start
			else
				java_start
			fi
			srv_check
			START=$(($START+1))
		done
		if [ $START == 3 ]; then
			echo $LOGSTAMP": Server did not start after "$START" number of tries, exiting">> $LOG
			exit 1
		else
			echo $LOGSTAMP": Server started after "$START" number of tries with "$PARAMS>> $LOG
			echo $LOGSTAMP": Backup complete">> $LOG
			exit 0
		fi
	fi
}
function run_backup() {
#Backup dir, output to $LOG
tar -czf $OF $BUDIR
if [ $? == 0 ]; then
	echo $LOGSTAMP": TAR of "$BUDIR" to "$OF" was successful">> $LOG
elif [ $? == 1 ]; then
	echo $LOGSTAMP": TAR of "$BUDIR" to "$OF" was successful, but backup is not 100% of "$BUDIR", most likely because it was changed during reading">> $LOG
else
	echo $LOGSTAMP": TAR of "$BUDIR" to "$OF" was NOT successful, reason: "$?" FATAL ERROR">> $LOG
fi
#SCP backup to $BCKSRV, output to $LOG
scp $OF $BCKSRV:$BCKDIR
if [ $? == 0 ]; then
	echo $LOGSTAMP": SCP of "$OF" to "$BCKSRV" was successful">> $LOG
else
	echo $LOGSTAMP": SCP of "$OF" to "$BCKSRV" was NOT successful, reason: "$?":Some error ocurred">> $LOG
fi

echo $LOGSTAMP": Proceeding to start server...">> $LOG
start_mc
}

#Is minecraft server running? yes - stop then continue, no - continue
echo $LOGSTAMP": Beginning full backup of "$BUDIR>> $LOG
srv_check
if [ $ONLINE == 2 ]; then
	kill_mc
	if [ $ONLINE == 1 ]; then
		run_backup
	fi
else
	run_backup
fi
