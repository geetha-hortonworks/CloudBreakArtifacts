#!/bin/bash

#echo "*********************************Download Configurations"
#git clone https://github.com/vakshorton/CloudBreakArtifacts
#cd CloudBreakArtifacts

export ROOT_PATH=~
echo "*********************************ROOT PATH IS: $ROOT_PATH"

export AMBARI_HOST=$(hostname -f)
echo "*********************************AMABRI HOST IS: $AMBARI_HOST"

export CLUSTER_NAME=$(curl -u admin:admin -X GET http://$AMBARI_HOST:8080/api/v1/clusters |grep cluster_name|grep -Po ': "(.+)'|grep -Po '[a-zA-Z0-9\-_!?.]+')

if [[ -z $CLUSTER_NAME ]]; then
        echo "Could not connect to Ambari Server. Please run the install script on the same host where Ambari Server is installed."
        exit 1
else
       	echo "*********************************CLUSTER NAME IS: $CLUSTER_NAME"
fi

export HADOOP_USER_NAME=hdfs
echo "*********************************HADOOP_USER_NAME set to HDFS"

installUtils () {
	echo "*********************************Installing WGET..."
	yum install -y wget

	echo "*********************************Installing Maven..."
	wget http://repos.fedorapeople.org/repos/dchen/apache-maven/epel-apache-maven.repo -O 	/etc/yum.repos.d/epel-apache-maven.repo
	if [ $(cat /etc/system-release|grep -Po Amazon) == Amazon ]; then
		sed -i s/\$releasever/6/g /etc/yum.repos.d/epel-apache-maven.repo
	fi
	yum install -y apache-maven


	echo "*********************************Installing GIT..."
	yum install -y git

}

waitForAmbari () {
       	# Wait for Ambari
       	LOOPESCAPE="false"
       	until [ "$LOOPESCAPE" == true ]; do
        TASKSTATUS=$(curl -u admin:admin -I -X GET http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME | grep -Po 'OK')
        if [ "$TASKSTATUS" == OK ]; then
                LOOPESCAPE="true"
                TASKSTATUS="READY"
        else
               	AUTHSTATUS=$(curl -u admin:admin -I -X GET http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME | grep HTTP | grep -Po '( [0-9]+)'| grep -Po '([0-9]+)')
               	if [ "$AUTHSTATUS" == 403 ]; then
               	echo "THE AMBARI PASSWORD IS NOT SET TO: admin"
               	echo "RUN COMMAND: ambari-admin-password-reset, SET PASSWORD: admin"
               	exit 403
               	else
                TASKSTATUS="PENDING"
               	fi
       	fi
       	echo "Waiting for Ambari..."
        echo "Ambari Status... " $TASKSTATUS
        sleep 2
       	done
}

serviceExists () {
       	SERVICE=$1
       	SERVICE_STATUS=$(curl -u admin:admin -X GET http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/services/$SERVICE | grep '"status" : ' | grep -Po '([0-9]+)')

       	if [ "$SERVICE_STATUS" == 404 ]; then
       		echo 0
       	else
       		echo 1
       	fi
}

getServiceStatus () {
       	SERVICE=$1
       	SERVICE_STATUS=$(curl -u admin:admin -X GET http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/services/$SERVICE | grep '"state" :' | grep -Po '([A-Z]+)')

       	echo $SERVICE_STATUS
}

waitForService () {
       	# Ensure that Service is not in a transitional state
       	SERVICE=$1
       	SERVICE_STATUS=$(curl -u admin:admin -X GET http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/services/$SERVICE | grep '"state" :' | grep -Po '([A-Z]+)')
       	sleep 2
       	echo "$SERVICE STATUS: $SERVICE_STATUS"
       	LOOPESCAPE="false"
       	if ! [[ "$SERVICE_STATUS" == STARTED || "$SERVICE_STATUS" == INSTALLED ]]; then
        until [ "$LOOPESCAPE" == true ]; do
                SERVICE_STATUS=$(curl -u admin:admin -X GET http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/services/$SERVICE | grep '"state" :' | grep -Po '([A-Z]+)')
            if [[ "$SERVICE_STATUS" == STARTED || "$SERVICE_STATUS" == INSTALLED ]]; then
                LOOPESCAPE="true"
            fi
            echo "*********************************$SERVICE Status: $SERVICE_STATUS"
            sleep 2
        done
       	fi
}

waitForServiceToStart () {
       	# Ensure that Service is not in a transitional state
       	SERVICE=$1
       	SERVICE_STATUS=$(curl -u admin:admin -X GET http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/services/$SERVICE | grep '"state" :' | grep -Po '([A-Z]+)')
       	sleep 2
       	echo "$SERVICE STATUS: $SERVICE_STATUS"
       	LOOPESCAPE="false"
       	if ! [[ "$SERVICE_STATUS" == STARTED ]]; then
        	until [ "$LOOPESCAPE" == true ]; do
                SERVICE_STATUS=$(curl -u admin:admin -X GET http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/services/$SERVICE | grep '"state" :' | grep -Po '([A-Z]+)')
            if [[ "$SERVICE_STATUS" == STARTED ]]; then
                LOOPESCAPE="true"
            fi
            echo "*********************************$SERVICE Status: $SERVICE_STATUS"
            sleep 2
        done
       	fi
}

stopService () {
       	SERVICE=$1
       	SERVICE_STATUS=$(getServiceStatus $SERVICE)
       	echo "*********************************Stopping Service $SERVICE ..."
       	if [ "$SERVICE_STATUS" == STARTED ]; then
        TASKID=$(curl -u admin:admin -H "X-Requested-By:ambari" -i -X PUT -d "{\"RequestInfo\": {\"context\": \"Stop $SERVICE\"}, \"ServiceInfo\": {\"maintenance_state\" : \"OFF\", \"state\": \"INSTALLED\"}}" http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/services/$SERVICE | grep "id" | grep -Po '([0-9]+)')

        echo "*********************************Stop $SERVICE TaskID $TASKID"
        sleep 2
        LOOPESCAPE="false"
        until [ "$LOOPESCAPE" == true ]; do
            TASKSTATUS=$(curl -u admin:admin -X GET http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/requests/$TASKID | grep "request_status" | grep -Po '([A-Z]+)')
            if [ "$TASKSTATUS" == COMPLETED ]; then
                LOOPESCAPE="true"
            fi
            echo "*********************************Stop $SERVICE Task Status $TASKSTATUS"
            sleep 2
        done
        echo "*********************************$SERVICE Service Stopped..."
       	elif [ "$SERVICE_STATUS" == INSTALLED ]; then
       	echo "*********************************$SERVICE Service Stopped..."
       	fi
}

startService (){
       	SERVICE=$1
       	SERVICE_STATUS=$(getServiceStatus $SERVICE)
       	echo "*********************************Starting Service $SERVICE ..."
       	if [ "$SERVICE_STATUS" == INSTALLED ]; then
        TASKID=$(curl -u admin:admin -H "X-Requested-By:ambari" -i -X PUT -d "{\"RequestInfo\": {\"context\": \"Start $SERVICE\"}, \"ServiceInfo\": {\"maintenance_state\" : \"OFF\", \"state\": \"STARTED\"}}" http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/services/$SERVICE | grep "id" | grep -Po '([0-9]+)')

        echo "*********************************Start $SERVICE TaskID $TASKID"
        sleep 2
        LOOPESCAPE="false"
        until [ "$LOOPESCAPE" == true ]; do
            TASKSTATUS=$(curl -u admin:admin -X GET http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/requests/$TASKID | grep "request_status" | grep -Po '([A-Z]+)')
            if [[ "$TASKSTATUS" == COMPLETED || "$TASKSTATUS" == FAILED ]]; then
                LOOPESCAPE="true"
            fi
            echo "*********************************Start $SERVICE Task Status $TASKSTATUS"
            sleep 2
        done
       	elif [ "$SERVICE_STATUS" == STARTED ]; then
       	echo "*********************************$SERVICE Service Started..."
       	fi
}





installNifiService () {
       	echo "*********************************Creating NIFI service..."
       	# Create NIFI service
       	curl -u admin:admin -H "X-Requested-By:ambari" -i -X POST http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/services/NIFI

       	sleep 2
       	echo "*********************************Adding NIFI MASTER component..."
       	# Add NIFI Master component to service
       	curl -u admin:admin -H "X-Requested-By:ambari" -i -X POST http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/services/NIFI/components/NIFI_MASTER
		curl -u admin:admin -H "X-Requested-By:ambari" -i -X POST http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/services/NIFI/components/NIFI_CA
		
       	sleep 2
       	echo "*********************************Creating NIFI configuration..."

       	# Create and apply configuration
		/var/lib/ambari-server/resources/scripts/configs.sh set $AMBARI_HOST $CLUSTER_NAME nifi-ambari-config $ROOT_PATH/CloudBreakArtifacts/hdf-config/nifi-config/nifi-ambari-config.json

		/var/lib/ambari-server/resources/scripts/configs.sh set $AMBARI_HOST $CLUSTER_NAME nifi-ambari-ssl-config $ROOT_PATH/CloudBreakArtifacts/hdf-config/nifi-config/nifi-ambari-ssl-config.json

		/var/lib/ambari-server/resources/scripts/configs.sh set $AMBARI_HOST $CLUSTER_NAME nifi-authorizers-env $ROOT_PATH/CloudBreakArtifacts/hdf-config/nifi-config/nifi-authorizers-env.json

		/var/lib/ambari-server/resources/scripts/configs.sh set $AMBARI_HOST $CLUSTER_NAME nifi-bootstrap-env $ROOT_PATH/CloudBreakArtifacts/hdf-config/nifi-config/nifi-bootstrap-env.json

		/var/lib/ambari-server/resources/scripts/configs.sh set $AMBARI_HOST $CLUSTER_NAME nifi-bootstrap-notification-services-env $ROOT_PATH/CloudBreakArtifacts/hdf-config/nifi-config/nifi-bootstrap-notification-services-env.json

		/var/lib/ambari-server/resources/scripts/configs.sh set $AMBARI_HOST $CLUSTER_NAME nifi-env $ROOT_PATH/CloudBreakArtifacts/hdf-config/nifi-config/nifi-env.json

		/var/lib/ambari-server/resources/scripts/configs.sh set $AMBARI_HOST $CLUSTER_NAME nifi-flow-env $ROOT_PATH/CloudBreakArtifacts/hdf-config/nifi-config/nifi-flow-env.json

		/var/lib/ambari-server/resources/scripts/configs.sh set $AMBARI_HOST $CLUSTER_NAME nifi-login-identity-providers-env $ROOT_PATH/CloudBreakArtifacts/hdf-config/nifi-config/nifi-login-identity-providers-env.json

		/var/lib/ambari-server/resources/scripts/configs.sh set $AMBARI_HOST $CLUSTER_NAME nifi-node-logback-env $ROOT_PATH/CloudBreakArtifacts/hdf-config/nifi-config/nifi-node-logback-env.json

		/var/lib/ambari-server/resources/scripts/configs.sh set $AMBARI_HOST $CLUSTER_NAME nifi-properties $ROOT_PATH/CloudBreakArtifacts/hdf-config/nifi-config/nifi-properties.json

		/var/lib/ambari-server/resources/scripts/configs.sh set $AMBARI_HOST $CLUSTER_NAME nifi-state-management-env $ROOT_PATH/CloudBreakArtifacts/hdf-config/nifi-config/nifi-state-management-env.json
		
		/var/lib/ambari-server/resources/scripts/configs.sh set $AMBARI_HOST $CLUSTER_NAME nifi-jaas-conf $ROOT_PATH/CloudBreakArtifacts/hdf-config/nifi-config/nifi-jaas-conf.json
				
		/var/lib/ambari-server/resources/scripts/configs.sh set $AMBARI_HOST $CLUSTER_NAME nifi-logsearch-conf $ROOT_PATH/CloudBreakArtifacts/hdf-config/nifi-config/nifi-logsearch-conf.json
		
       	echo "*********************************Adding NIFI MASTER role to Host..."
       	# Add NIFI Master role to Ambari Host
       	curl -u admin:admin -H "X-Requested-By:ambari" -i -X POST http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/hosts/$AMBARI_HOST/host_components/NIFI_MASTER

       	echo "*********************************Adding NIFI CA role to Host..."
		# Add NIFI CA role to Ambari Host
       	curl -u admin:admin -H "X-Requested-By:ambari" -i -X POST http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/hosts/$AMBARI_HOST/host_components/NIFI_CA

       	sleep 30
       	echo "************* REMOVING existing param.py file from Nifi scripts*************"
rm -rf /var/lib/ambari-agent/cache/common-services/NIFI/1.0.0/package/scripts/params.py
echo "********************COPYING params.py file from recipes to scripts***********"
cp -f $ROOT_PATH/CloudBreakArtifacts/recipes/params.py    /var/lib/ambari-agent/cache/common-services/NIFI/1.0.0/package/scripts/

       	echo "*********************************Installing NIFI Service"
       	# Install NIFI Service
       	TASKID=$(curl -u admin:admin -H "X-Requested-By:ambari" -i -X PUT -d '{"RequestInfo": {"context" :"Install Nifi"}, "Body": {"ServiceInfo": {"maintenance_state" : "OFF", "state": "INSTALLED"}}}' http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/services/NIFI | grep "id" | grep -Po '([0-9]+)')
		
		sleep 2       	
       	if [ -z $TASKID ]; then
       		until ! [ -z $TASKID ]; do
       			TASKID=$(curl -u admin:admin -H "X-Requested-By:ambari" -i -X PUT -d '{"RequestInfo": {"context" :"Install Nifi"}, "Body": {"ServiceInfo": {"maintenance_state" : "OFF", "state": "INSTALLED"}}}' http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/services/NIFI | grep "id" | grep -Po '([0-9]+)')
       		 	echo "*********************************AMBARI TaskID " $TASKID
       		done
       	fi
       	
       	echo "*********************************AMBARI TaskID " $TASKID
       	sleep 2
       	LOOPESCAPE="false"
       	until [ "$LOOPESCAPE" == true ]; do
               	TASKSTATUS=$(curl -u admin:admin -X GET http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/requests/$TASKID | grep "request_status" | grep -Po '([A-Z]+)')
               	if [ "$TASKSTATUS" == COMPLETED ]; then
                       	LOOPESCAPE="true"
               	fi
               	echo "*********************************Task Status" $TASKSTATUS
               	sleep 2
       	done
}

waitForNifiServlet () {
       	LOOPESCAPE="false"
       	until [ "$LOOPESCAPE" == true ]; do
       		TASKSTATUS=$(curl -u admin:admin -i -X GET http://$AMBARI_HOST:9090/nifi-api/controller | grep -Po 'OK')
       		if [ "$TASKSTATUS" == OK ]; then
               		LOOPESCAPE="true"
       		else
               		TASKSTATUS="PENDING"
       		fi
       		echo "*********************************Waiting for NIFI Servlet..."
       		echo "*********************************NIFI Servlet Status... " $TASKSTATUS
       		sleep 2
       	done
}
# Import NIFI Template
deployTemplateToNifi () {
       	echo "*********************************Importing NIFI Template..."
       	TEMPLATEID=$(curl -v -F template=@"$ROOT_PATH/CloudBreakArtifacts/Nifi/nifi-cdr-cbd.xml" -X POST http://$AMBARI_HOST:9090/nifi-api/process-groups/root/templates/upload | grep -Po '<id>([a-z0-9-]+)' | grep -Po '>([a-z0-9-]+)' | grep -Po '([a-z0-9-]+)')
       	sleep 1

       	echo "*********************************Instantiating NIFI Flow..."
       	# Instantiate NIFI Template
       	curl -u admin:admin -i -H "Content-Type:application/json" -d "{\"templateId\":\"$TEMPLATEID\",\"originX\":100,\"originY\":100}" -X POST http://$AMBARI_HOST:9090/nifi-api/process-groups/root/template-instance
       	sleep 1

       	# Rename NIFI Root Group
		echo "*********************************Renaming Nifi Root Group..."
ROOT_GROUP_REVISION=$(curl -X GET http://$AMBARI_HOST:9090/nifi-api/process-groups/root |grep -Po '\"version\":([0-9]+)'|grep -Po '([0-9]+)')

		sleep 1
		ROOT_GROUP_ID=$(curl -X GET http://$AMBARI_HOST:9090/nifi-api/process-groups/root|grep -Po '("component":{"id":")([0-9a-zA-z\-]+)'| grep -Po '(:"[0-9a-zA-z\-]+)'| grep -Po '([0-9a-zA-z\-]+)')

		PAYLOAD=$(echo "{\"id\":\"$ROOT_GROUP_ID\",\"revision\":{\"version\":$ROOT_GROUP_REVISION},\"component\":{\"id\":\"$ROOT_GROUP_ID\",\"name\":\"Biologics-Demo\"}}")

		sleep 1
		curl -d $PAYLOAD  -H "Content-Type: application/json" -X PUT http://$AMBARI_HOST:9090/nifi-api/process-groups/$ROOT_GROUP_ID
		sleep 1
}
getServiceStatus () {
       	SERVICE=$1
       	SERVICE_STATUS=$(curl -u admin:admin -X GET http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/services/$SERVICE | grep '"state" :' | grep -Po '([A-Z]+)')

       	echo $SERVICE_STATUS
}
# Start NIFI Flow
startNifiFlow () {
    echo "*********************************Starting NIFI Flow..."
	# if [ "$INTVERSION" -gt 24 ]; then
    	# Start NIFI Flow HDF 2.x
    	TARGETS=($(curl -u admin:admin -i -X GET http://$AMBARI_HOST:9090/nifi-api/process-groups/root/processors | grep -Po '\"uri\":\"([a-z0-9-://.]+)' | grep -Po '(?!.*\")([a-z0-9-://.]+)'))
       	length=${#TARGETS[@]}
       	echo $length
       	echo ${TARGETS[0]}

       	for ((i = 0; i < $length; i++))
       	do
       		ID=$(curl -u admin:admin -i -X GET ${TARGETS[i]} |grep -Po '"id":"([a-zA-z0-9\-]+)'|grep -Po ':"([a-zA-z0-9\-]+)'|grep -Po '([a-zA-z0-9\-]+)'|head -1)
       		REVISION=$(curl -u admin:admin -i -X GET ${TARGETS[i]} |grep -Po '\"version\":([0-9]+)'|grep -Po '([0-9]+)')
       		TYPE=$(curl -u admin:admin -i -X GET ${TARGETS[i]} |grep -Po '"type":"([a-zA-Z0-9\-.]+)' |grep -Po ':"([a-zA-Z0-9\-.]+)' |grep -Po '([a-zA-Z0-9\-.]+)' |head -1)
       		echo "Current Processor Path: ${TARGETS[i]}"
       		echo "Current Processor Revision: $REVISION"
       		echo "Current Processor ID: $ID"
       		echo "Current Processor TYPE: $TYPE"

       		if ! [ -z $(echo $TYPE|grep "PutKafka") ] || ! [ -z $(echo $TYPE|grep "PublishKafka") ]; then
       			echo "***************************This is a PutKafka Processor"
       			echo "***************************Updating Kafka Broker Porperty and Activating Processor..."
       			if ! [ -z $(echo $TYPE|grep "PutKafka") ]; then
                    PAYLOAD=$(echo "{\"id\":\"$ID\",\"revision\":{\"version\":$REVISION},\"component\":{\"id\":\"$ID\",\"config\":{\"properties\":{\"Known Brokers\":\"$AMBARI_HOST:6667\"}},\"state\":\"RUNNING\"}}")
                else
                    PAYLOAD=$(echo "{\"id\":\"$ID\",\"revision\":{\"version\":$REVISION},\"component\":{\"id\":\"$ID\",\"config\":{\"properties\":{\"bootstrap.servers\":\"$AMBARI_HOST:6667\"}},\"state\":\"RUNNING\"}}")
                fi
       		else
       			echo "***************************Activating Processor..."
       				PAYLOAD=$(echo "{\"id\":\"$ID\",\"revision\":{\"version\":$REVISION},\"component\":{\"id\":\"$ID\",\"state\":\"RUNNING\"}}")
			fi
       		echo "$PAYLOAD"

       		curl -u admin:admin -i -H "Content-Type:application/json" -d "${PAYLOAD}" -X PUT ${TARGETS[i]}
       	done
	# else
       	# Start NIFI Flow HDF 1.x
		# echo "*********************************Starting NIFI Flow..."
	#	REVISION=$(curl -u admin:admin  -i -X GET http://$AMBARI_HOST:9090/nifi-api/controller/revision |grep -Po '\"version\":([0-9]+)' | grep -Po '([0-9]+)')

	#	TARGETS=($(curl -u admin:admin -i -X GET http://$AMBARI_HOST:9090/nifi-api/controller/process-groups/root/processors | grep -Po '\"uri\":\"([a-z0-9-://.]+)' | grep -Po '(?!.*\")([a-z0-9-://.]+)'))
#length=${#TARGETS[@]}

	#	for ((i = 0; i != length; i++)); do
   #			echo curl -u admin:admin -i -X GET ${TARGETS[i]}
   #			echo "Current Revision: " $REVISION
   	#		curl -u admin:admin -i -H "Content-Type:application/x-www-form-urlencoded" -d "state=RUNNING&version=$REVISION" -X PUT ${TARGETS[i]}
		#   REVISION=$(curl -u admin:admin  -i -X GET http://$AMBARI_HOST:9090/nifi-api/controller/revision |grep -Po '\"version\":([0-9]+)' | grep -Po '([0-9]+)')
	#	done
	# fi
}

# install Solr
installSolr (){


#sudo -u hdfs hadoop fs -mkdir /user/solr
#sudo -u hdfs hadoop fs -chown solr /user/solr

yum -y install lucidworks-hdpsearch

cp /root/telco-cdr-monitoring/solr/* /opt/lucidworks-hdpsearch/solr/server/solr-webapp/webapp/banana/app/dashboards/

#chown -R solr:solr /opt/lucidworks-hdpsearch/solr

 /opt/lucidworks-hdpsearch/solr/bin/solr start -c -z  $AMBARI_HOST:2181

sleep 5

 /opt/lucidworks-hdpsearch/solr/bin/solr create -c cdr  -d data_driven_schema_configs -s 1 -rf 1
 
   }

getNameNodeHost () {
       	NAMENODE_HOST=$(curl -u admin:admin -X GET http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/services/HDFS/components/NAMENODE|grep "host_name"|grep -Po ': "([a-zA-Z0-9\-_!?.]+)'|grep -Po '([a-zA-Z0-9\-_!?.]+)')

       	echo $NAMENODE_HOST
}


getKafkaBroker () {
       	KAFKA_BROKER=$(curl -u admin:admin -X GET http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/services/KAFKA/components/KAFKA_BROKER |grep "host_name"|grep -Po ': "([a-zA-Z0-9\-_!?.]+)'|grep -Po '([a-zA-Z0-9\-_!?.]+)')

       	echo $KAFKA_BROKER
}



getNifiHost () {
       	NIFI_HOST=$(curl -u admin:admin -X GET http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/services/NIFI/components/NIFI_MASTER|grep "host_name"|grep -Po ': "([a-zA-Z0-9\-_!?.]+)'|grep -Po '([a-zA-Z0-9\-_!?.]+)')

       	echo $NIFI_HOST
}

if [ ! -d "/usr/jdk64" ]; then
	echo "*********************************Install and Enable Oracle JDK 8"
	wget http://public-repo-1.hortonworks.com/ARTIFACTS/jdk-8u77-linux-x64.tar.gz
	tar -vxzf jdk-8u77-linux-x64.tar.gz -C /usr
	mv /usr/jdk1.8.0_77 /usr/jdk64
	alternatives --install /usr/bin/java java /usr/jdk64/bin/java 3
	alternatives --install /usr/bin/javac javac /usr/jdk64/bin/javac 3
	alternatives --install /usr/bin/jar jar /usr/jdk64/bin/jar 3
	export JAVA_HOME=/usr/jdk64
	echo "export JAVA_HOME=/usr/jdk64" >> /etc/bashrc
fi


instalHDFManagementPack () {
	wget http://public-repo-1.hortonworks.com/HDF/centos7/3.x/updates/3.0.0.0/tars/hdf_ambari_mp/hdf-ambari-mpack-3.0.0.0-453.tar.gz
ambari-server install-mpack --mpack=hdf-ambari-mpack-3.0.0.0-453.tar.gz --verbose

	sleep 2
	ambari-server restart
	waitForAmbari
	sleep 2
}

getHostByPosition (){
	HOST_POSITION=$1
	HOST_NAME=$(curl -u admin:admin -X GET http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/hosts|grep -Po '"host_name" : "[a-zA-Z0-9_\W]+'|grep -Po ' : "([^"]+)'|grep -Po '[^: "]+'|tail -n +$HOST_POSITION|head -1)
	
	echo $HOST_NAME
}

configureAmbariRepos (){
	tee /etc/yum.repos.d/docker.repo <<-'EOF'
	[HDF-3.0]
	name=HDF-3.0
	baseurl=http://public-repo-1.hortonworks.com/HDF/centos7/3.x/updates/3.0.0.0
	path=/
	enabled=1
	gpgcheck=0
	EOF
	
	curl -u admin:admin -d @$ROOT_PATH/CloudBreakArtifacts/hdf-config/api-payload/repo_update.json -H "X-Requested-By: ambari" -X PUT http://$AMBARI_HOST:8080/api/v1/stacks/HDP/versions/2.6/repository_versions/1
}




echo "*********************************Waiting for cluster install to complete..."
waitForServiceToStart YARN

waitForServiceToStart HDFS

waitForServiceToStart HIVE

waitForServiceToStart ZOOKEEPER


sleep 10

export VERSION=`hdp-select status hadoop-client | sed 's/hadoop-client - \([0-9]\.[0-9]\).*/\1/'`
export INTVERSION=$(echo $VERSION*10 | bc | grep -Po '([0-9][0-9])')
echo "*********************************HDP VERSION IS: $VERSION"

echo "*********************************Stopping Prometheous..."
kill -9 $(netstat -nlp|grep 9090|grep -Po '[0-9]+/[a-zA-Z]+'|grep -Po '[0-9]+')



echo "*********************************Install HDF Management Pack..."
instalHDFManagementPack 
sleep 2


NAMENODE_HOST=$(getNameNodeHost)
export NAMENODE_HOST=$NAMENODE_HOST

ZK_HOST=$AMBARI_HOST
export ZK_HOST=$ZK_HOST
KAFKA_BROKER=$(getKafkaBroker)
export KAFKA_BROKER=$KAFKA_BROKER
# ATLAS_HOST=$(getAtlasHost)

env

echo "export NAMENODE_HOST=$NAMENODE_HOST" >> /etc/bashrc
echo "export ZK_HOST=$ZK_HOST" >> /etc/bashrc
echo "export KAFKA_BROKER=$KAFKA_BROKER" >> /etc/bashrc


echo "export NIFI_HOST=$NIFI_HOST" >> /etc/bashrc

echo "export NAMENODE_HOST=$NAMENODE_HOST" >> ~/.bash_profile
echo "export ZK_HOST=$ZK_HOST" >> ~/.bash_profile
echo "export KAFKA_BROKER=$KAFKA_BROKER" >> ~/.bash_profile


echo "export NIFI_HOST=$NIFI_HOST" >> ~/.bash_profile

. ~/.bash_profile

echo "*********************************Installing Utlities..."
installUtils
#Start Kafka
KAFKA_STATUS=$(getServiceStatus KAFKA)
echo "*********************************Checking KAFKA status..."
if ! [[ $KAFKA_STATUS == STARTED || $KAFKA_STATUS == INSTALLED ]]; then
       	echo "*********************************KAFKA is in a transitional state, waiting..."
       	waitForService KAFKA
       	echo "*********************************KAFKA has entered a ready state..."
fi

if [[ $KAFKA_STATUS == INSTALLED ]]; then
       	startService KAFKA
else
       	echo "*********************************KAFKA Service Started..."
fi
#Configure Kafka
 echo "*********************************Creating Kafka Topics..."
 /usr/hdp/current/kafka-broker/bin/kafka-topics.sh --create --zookeeper $AMBARI_HOST:2181 --replication-factor 1 --partitions 1 --topic cdr
 
 
 #Install Solr
 installSolr 

sleep 2
# Build storm jar from source

echo "*********************************Building CDR Storm Topology"
cd $ROOT_PATH/telco-cdr-monitoring
mvn clean package
# cp -vf /root/target/telco-cdr-monitoring-1.0-SNAPSHOT.jar /home/storm
# Deploy Storm toppology
#mkdir $ROOT_PATH/telco-cdr-monitoring/execdir

#mv $ROOT_PATH/telco-cdr-monitoring/target/telco-cdr-monitoring-1.0-SNAPSHOT.jar  $ROOT_PATH/telco-cdr-monitoring/execdir/

#cp $ROOT_PATH/telco-cdr-monitoring/scripts/start_cdr_producer.sh  /usr/hdf/3.0.0.0-453/nifi/

#chown nifi:nifi $ROOT_PATH/telco-cdr-monitoring/execdir/
#chown nifi:nifi $ROOT_PATH/telco-cdr-monitoring/execdir/*
##chmod 755 $ROOT_PATH/telco-cdr-monitoring/execdir/
#chmod 755 $ROOT_PATH/telco-cdr-monitoring/execdir/*
storm jar $ROOT_PATH/telco-cdr-monitoring/target/telco-cdr-monitoring-1.0-SNAPSHOT.jar com.github.gbraccialli.telco.cdr.storm.Topology $ROOT_PATH/telco-cdr-monitoring/conf/topology.props




sleep 2
# installSchemaRegistryService



sleep 2
installNifiService

sleep 2
NIFI_STATUS=$(getServiceStatus NIFI)
echo "*********************************Checking NIFI status..."
if ! [[ $NIFI_STATUS == STARTED || $NIFI_STATUS == INSTALLED ]]; then
       	echo "*********************************NIFI is in a transitional state, waiting..."
       	waitForService NIFI
       	echo "*********************************NIFI has entered a ready state..."
fi

if [[ $NIFI_STATUS == INSTALLED ]]; then
       	startService NIFI
else
       	echo "*********************************NIFI Service Started..."
fi

echo "***************************************** RUN NIF AS ROOT instead of NIFI... "
#sed -i "s/##run.as=root/run.as=root/"  /usr/hdf/current/nifi/conf/bootstrap.conf
#sed -i "s/run.as=nifi/#run.as=nifi/"  /usr/hdf/current/nifi/conf/bootstrap.conf
waitForNifiServlet

echo "********************************* Copy producer script to Nifi folder"
cp $ROOT_PATH/telco-cdr-monitoring/scripts/start_cdr_producer.sh  /usr/hdf/3.0.0.0-453/nifi/
cp $ROOT_PATH/telco-cdr-monitoring/target/telco-cdr-monitoring-1.0-SNAPSHOT.jar /usr/hdf/3.0.0.0-453/nifi/

echo "*********************************Deploying NIFI Template..."
deployTemplateToNifi

echo "*********************************Starting NIFI Flow ..."
startNifiFlow



#Configure Kafka
# echo "*********************************Creating Kafka Topics..."
# /usr/hdp/current/kafka-broker/bin/kafka-topics.sh --create --zookeeper $AMBARI_HOST:2181 --replication-factor 1 --partitions 1 --topic cdr

HBASE_STATUS=$(getServiceStatus HBASE)
echo "*********************************Checking HBASE status..."
if ! [[ $HBASE_STATUS == STARTED || $HBASE_STATUS == INSTALLED ]]; then
       	echo "*********************************HBASE is in a transitional state, waiting..."
       	waitForService HBASE
       	echo "*********************************HBASE has entered a ready state..."
fi

if [[ $HBASE_STATUS == INSTALLED ]]; then
       	startService HBASE
else
       	echo "*********************************HBASE Service Started..."
fi


STORM_STATUS=$(getServiceStatus STORM)
echo "*********************************Checking STORM status..."
if ! [[ $STORM_STATUS == STARTED || $STORM_STATUS == INSTALLED ]]; then
       	echo "*********************************STORM is in a transitional state, waiting..."
       	waitForService STORM
       	echo "*********************************STORM has entered a ready state..."
fi

echo "*********************************Stoping STORM Service..."
STORM_STATUS=$(getServiceStatus STORM)
if [[ $STORM_STATUS == STARTED ]]; then
       	stopService STORM
else
       	echo "*********************************STORM Service Stopped..."
fi

echo "*********************************Starting STORM Service..."
STORM_STATUS=$(getServiceStatus STORM)
if [[ $STORM_STATUS == INSTALLED ]]; then
       	startService STORM
else
       	echo "*********************************STORM Service Started..."
fi


#export MYSQL_TEMP_PASSWORD=$(grep 'A temporary password' /var/log/mysqld.log |grep -Po ': .+'|grep -Po '[^: ].+')
#mysqladmin -u root --password=$MYSQL_TEMP_PASSWORD password "Password!1"
#export MYSQL_PASSWORD=Password!1

#mysql -u root --password=$MYSQL_PASSWORD --execute="uninstall plugin validate_password"
#mysql -u root --password=$MYSQL_PASSWORD --execute="CREATE DATABASE registry"
#mysql -u root --password=$MYSQL_PASSWORD --execute="CREATE DATABASE streamline"
#mysql -u root --password=$MYSQL_PASSWORD --execute="CREATE DATABASE druid DEFAULT CHARACTER SET utf8"
#mysql -u root --password=$MYSQL_PASSWORD --execute="CREATE DATABASE superset DEFAULT CHARACTER SET utf8"
#mysql -u root --password=$MYSQL_PASSWORD --execute="CREATE USER 'registry'@'%' IDENTIFIED BY 'registry'"
#mysql -u root --password=$MYSQL_PASSWORD --execute="CREATE USER 'streamline'@'%' IDENTIFIED BY 'streamline'"
#mysql -u root --password=$MYSQL_PASSWORD --execute="CREATE USER 'druid'@'%' IDENTIFIED BY 'druid'"
#mysql -u root --password=$MYSQL_PASSWORD --execute="CREATE USER 'superset'@'%' IDENTIFIED BY 'superset'"
#mysql -u root --password=$MYSQL_PASSWORD --execute="GRANT ALL PRIVILEGES ON registry.* TO 'registry'@'%' WITH GRANT OPTION"
#mysql -u root --password=$MYSQL_PASSWORD --execute="GRANT ALL PRIVILEGES ON streamline.* TO 'streamline'@'%' WITH GRANT OPTION"
#mysql -u root --password=$MYSQL_PASSWORD --execute="GRANT ALL PRIVILEGES ON druid.* TO 'druid'@'%' WITH GRANT OPTION"
#mysql -u root --password=$MYSQL_PASSWORD --execute="GRANT ALL PRIVILEGES ON superset.* TO 'superset'@'%' WITH GRANT OPTION"
#mysql -u root --password=$MYSQL_PASSWORD --execute="FLUSH PRIVILEGES"
#mysql -u root --password=$MYSQL_PASSWORD --execute="COMMIT"
