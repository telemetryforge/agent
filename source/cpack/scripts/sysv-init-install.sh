#!/bin/sh
NAME=""
if [ -f /etc/init.d/fluentdo-agent ]; then
	NAME=fluentdo-agent
elif [ -f /etc/init.d/fluent-bit ]; then
	NAME=fluent-bit
else
	echo "ERROR: No init.d script found"
	exit 1
fi
chmod a+x /etc/init.d/"$NAME"
chkconfig --add "$NAME"
