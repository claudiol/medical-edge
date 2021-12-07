#!/bin/bash


# Function log
# Arguments:
#   $1 are for the options for echo
#   $2 is for the message
#   \033[0K\r - Trailing escape sequence to leave output on the same line
function log {
    if [ -z "$2" ]; then
        echo -e "\033[1;36m$1\033[0m\033[0K\r"
    else
        echo -e $1 "\033[1;36m$2\033[0m\033[0K\r"
    fi
}

# Bootstrap script for Medical-Edge
ADMIN=$(oc whoami | awk '{print $1}')
if [ "$ADMIN" != "admin" ] || [ "$ADMIN" != "kubeadmin" ]; then
    log "You must be kubeadmin to run this script"
    exit
fi

#
# Loop until namespace xraylab-1 is created.
#
while ( true )
do
    log -n "Checking that the namespace [ xraylab-1 ] exists ..."
    oc get namespace xraylab-1    
    if [ $? == 0 ]; then
	log "done"
	break
    fi
done

#
# Generate the secrets manifest for S3 and database
#
while ( true )
do
    log -n "Creating s3 and database secrets for xraylab-1 ..."
    helm template secrets secrets/ -f ~/xray-values-secret.yaml -f values-global.yaml > /tmp/s3-db-secrets.yaml
    if [ $? == 0 ]; then
	oc apply -f /tmp/s3-db-secret.yaml
	rm /tmp/s3-db-secret.yaml
	echo "done"
	break
    fi
done	

#
# This is a temporary Service Account to label nodes for OpenShift Storage
#
log -n "Creating ocs-node-labeler Service Account ..." 
oc create sa ocs-labeler
if [ $? == 0 ]; then
    log "done"
fi

log -n "Adding cluster role for ocs-node-labeler Service Account ..." 
oc adm policy add-cluster-role-to-user cluster-admin -z  ocs-labeler
if [ $? == 0 ]; then
    log "done"
fi

#
# bookbag Service Account in the bookbag-xraylab-1
#
log -n "Creating bookbag Service Account ..."
oc create sa bookbag
if [ $? == 0 ]; then
    log "done"
fi

log -n "Adding cluster role for bookbag Service Account ..."
oc adm policy add-cluster-role-to-user cluster-admin -z  ocs-labeler
if [ $? == 0 ]; then
    log "done"
fi

#
# Grafana
#
log -n "Creating grafana Service Account ..."
oc create sa grafana-serviceaccount
if [ $? == 0 ]; then
    log "done"
fi
log -n "Adding cluster role to grafana-serviceaccount ..."
oc adm policy add-cluster-role-to-user cluster-monitoring-view -z grafana-serviceaccount -n xraylab-1
if [ $? == 0 ]; then
    log "done"
fi

