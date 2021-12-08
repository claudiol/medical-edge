#!/bin/bash


# Function log
# Arguments:
#   $1 are for the options for echo
#   $2 is for the message
#   \033[0K\r - Trailing escape sequence to leave output on the same line
function log {
    if [ -z "$2" ]; then
        echo -e "\033[0K\r\033[1;36m$1\033[0m"
    else
        echo -e $1 "\033[0K\r\033[1;36m$2\033[0m"
    fi
}

# Bootstrap script for Medical-Edge
ADMIN=$(oc whoami | awk '{print $1}')
if [ "$ADMIN" != "admin" ] || [ "$ADMIN" != "system:admin" ]; then
    log "You must be kubeadmin to run this script"
fi

#
# Loop until namespace xraylab-1 is created.
#
while ( true )
do
    log -n "Checking that the namespace [ xraylab-1 ] exists ..."
    oc get namespace xraylab-1 > /dev/null 2>&1
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
    log -n "Creating s3 and database secrets for xraylab-1 ... "
    helm template secrets secrets/ -f ~/values-secret.yaml -f values-global.yaml > /tmp/s3-db-secrets.yaml
    if [ $? == 0 ]; then
	oc apply -f /tmp/s3-db-secrets.yaml > /dev/null 2>&1
	rm /tmp/s3-db-secrets.yaml
	echo "done"
	break
    else
	echo "FAIL. Helm chart failed to render."
	exit
    fi
done	

#
# This is a temporary Service Account to label nodes for OpenShift Storage
#
log -n "Creating ocs-node-labeler Service Account ... " 
#oc create sa ocs-labeler > /dev/null 2>&1
#if [ $? == 0 ]; then
#    echo "done"
#else
#    echo "Already exists"
#fi

oc label node -l node-role.kubernetes.io/worker= cluster.ocs.openshift.io/openshift-storage= > /dev/null 2>&1
if [ $? == 0 ]; then
    echo "done"
fi

#log -n "Adding cluster role for ocs-node-labeler Service Account ... " 
#oc adm policy add-cluster-role-to-user cluster-admin -z  ocs-node-labeler
#if [ $? == 0 ]; then
#    echo "done"
#fi

#
# bookbag Service Account in the bookbag-xraylab-1
#
log -n "Creating bookbag Service Account ... "
oc create sa bookbag
if [ $? == 0 ]; then
    echo "done"
fi

log -n "Adding cluster role for bookbag Service Account ... "
oc adm policy add-cluster-role-to-user cluster-admin -z bookbag
if [ $? == 0 ]; then
    echo "done"
fi

#
# Check for the Grafana Service Account to be created
#
while ( true )
do  
    log -n "Waiting for the grafana Service Account ... "
    oc get sa grafana-serviceaccount -n xraylab-1 > /dev/null 2>&1
    if [ $? == 0 ]; then
	echo "done"
	break
    fi
done

log -n "Adding cluster role to grafana-serviceaccount ... "
oc adm policy add-cluster-role-to-user cluster-monitoring-view -z grafana-serviceaccount -n xraylab-1 > /dev/null 2>&1
if [ $? == 0 ]; then
    echo "done"
fi

log -n "Retrieving grafana service account secret ... "
# Make sure we are in xraylab-1
oc project xraylab-1 > /dev/null 2>&1
SATOKEN=$(oc get secret $(oc get secret | grep grafana-serviceaccount-token | tail -1 | awk '{print $1}') -o json | jq '.data.token')
#
#  Still not sure how we will be able to apply this token to the grafana/prometheus-datasource.yaml manifest
#  One idea is to add the token to the ~/values-secret.yaml, run helm template and then oc apply the manifest.
# For now we will sed ... ugh
sed -i "s/BEARER-TOKEN/$SATOKEN/g" charts/datacenter/xraylab/grafana/templates/xraylab-grafana-prometheus-datasource.yaml
if [ $? == 0 ]; then
    echo "done"
else
    log "Error in trying to replace BEARER-TOKEN"
fi

#
# Apply prometheus Manifest
#
log -n "Generating grafana templates manifests ... "
helm template charts/datacenter/xraylab/grafana -f values-global.yaml > /tmp/grafana.yaml
if [ $? == 0 ]; then
    echo "Done"
fi

log -n "Applying  grafana  manifests ... "
oc apply -f /tmp/grafana.yaml
if [ $? == 0 ]; then
    echo "Done"
    rm -r /tmp/grafana.yaml
fi

POD=""
while ( true )
do
    log -n "Make sure that rook-ceph-tools pod is running ... "
    POD=$(oc get pods -n openshift-storage | grep rook-ceph-tools | grep Running | awk '{print $1}')
    if [ -z $POD ]; then
	continue;
    else
	echo "Done"
	break;
    fi
done

while ( true )
do
    log -n "Creating S3 user account ... "
    oc exec -n openshift-storage $POD -- radosgw-admin user create --uid="xraylab-1" --display-name="xraylab-1 user" > /dev/null 2>&1
    if [ $? != 0 ]; then
	continue
    fi
    echo "done."
    #
    # Create the S3 user
    #
    RESPONSE=$(oc exec -n openshift-storage $POD -- radosgw-admin user create --uid="xraylab-1" --display-name="xraylab-1 user")

    #echo $RESPONSE
    #
    # Parse the response using the jq tool
    #
    USER=$(echo -n $RESPONSE | jq -j '.keys[0].user')
    S3_ACCESS_KEY=$(echo -n $RESPONSE | jq -j '.keys[0].access_key' | base64 -w 0 )
    S3_SECRET_KEY=$(echo -n $RESPONSE | jq -j '.keys[0].secret_key' | base64 -w 0 )

    echo $S3_ACCESS_KEY
    if [ ! -z $S3_ACCESS_KEY ] && [ ! -x $S3_SECRET_KEY ]; then
	cat <<EOF > /tmp/s3-secret-bck.yaml
apiVersion: v1	  
data:	    
  AWS_ACCESS_KEY_ID: $S3_ACCESS_KEY
  AWS_SECRET_ACCESS_KEY: $S3_SECRET_KEY
kind: Secret
metadata:
  name: s3-secret-bck
  namespace: xraylab-1
type: Opaque
EOF

	log -n "Applying s3 secret ... "
	oc apply -f /tmp/s3-secret-bck.yaml
	if [ $? == 0 ]; then
	    log "Done\r"
	    break
	else
	    log "Something went wrong applying s3-secret manifest"
	fi
    fi
done

