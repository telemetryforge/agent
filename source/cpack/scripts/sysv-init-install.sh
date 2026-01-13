#!/bin/sh
NAME=""
if [ -f /etc/init.d/telemetryforge-agent ]; then
	NAME=telemetryforge-agent
elif [ -f /etc/init.d/fluent-bit ]; then
	NAME=fluent-bit
else
	echo "ERROR: No init.d script found"
	ls -l /etc/init.d/
	exit 1
fi
chmod a+x /etc/init.d/"$NAME"
chkconfig --add "$NAME"
