#####################################
#
# Copyright 2017-2018 NXP
#
#####################################

#!/bin/bash

echo 'V' > /dev/watchdog

export version=`cat /usr/local/edgescale/conf/edgescale-version`

push_publicip() {
	# Get public IP
	publicip=`curl -k https://checkip.amazonaws.com`

	token=$(cat /data/.edgescale.cred)
	url="$ES_API_URI/devices/positions"
	# Create curl body
	body='{"ip": "'$publicip'", "device_name": "'$ES_DEVICEID'"}'

	curl -X POST -H "Content-Type: application/json; verson=$version" -H "access-token: $token" $url -d "$body"
}

cd /usr/local/edgescale/bin/
mkdir -p /data

# trust the self-signed certificates before the first API call
update-ca-certificates

./env.sh

# install mosquitto
[ -e /etc/init.d/mosquitto ]||(apt install -y mosquitto && /etc/init.d/mosquitto start)

start-stop-daemon --start --startas /usr/local/edgescale/bin/es-watchdog --name es-watchdog -m --pidfile /var/run/es-watchdog.pid -b
start-stop-daemon --start --startas /bin/tee-supplicant --name tee-supplicant -m --pidfile /var/run/tee-supplicant.pid -b
./cert-agent

. /data/config.env
for env in $(set | grep ^ES)
do
	export ${env}
done

if [ ! -d /backup ];then
    mkdir /backup
    backupPartition=($(ls /dev/mmcblk*p3))
    if [ -n "${backupPartition[0]}" ]; then
        mount ${backupPartition[0]} /backup
    fi
fi

if [ -z $ES_OEM_TRUST_CA ] ; then
		rm -rf /usr/local/share/ca-certificates/es-oem-trust.crt
else
		echo -n $ES_OEM_TRUST_CA | base64 -d > /usr/local/share/ca-certificates/es-oem-trust.crt
fi
update-ca-certificates

if [ $? -eq 0 ];then
    # report public IP Address to cloud
    push_publicip

    # starting kubelet
    ./k8s.sh

    # check OTA status
    ./ota-statuscheck &

    # check MMC blocks health status
    ./mmc-check.sh &

    # starting mq-agent
    start-stop-daemon --start --startas /usr/local/edgescale/bin/mq-agent --name mq-agent -m --pidfile /var/run/mq-agent.pid -b
fi
