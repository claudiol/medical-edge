#!/bin/bash

# Bootstrap script for Medical-Edge

while ( true )
do    
	oc get namespace xraylab-1    
	if [ $? == 0 ]; then
	  	oc apply -f /home/claudiol/work/blueprints-space/medical-diagnosis-secrets/s3-secret.yaml
	  	oc apply -f /home/claudiol/work/blueprints-space/medical-diagnosis-secrets/db-secret.yaml
		break    
	fi
	sleep 3 
done
#
# This is a temporary Service Account to label nodes for OpenShift Storage
oc create sa ocs-labeler
oc adm policy add-cluster-role-to-user cluster-admin -z  ocs-labeler

#
# bookbag Service Account in the bookbag-xraylab-1
#
oc create sa bookbag
oc adm policy add-cluster-role-to-user cluster-admin -z  ocs-labeler
