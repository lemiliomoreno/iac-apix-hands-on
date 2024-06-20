#!/bin/bash

# Set your variables
access_key_id=""
secret_access_key=""
default_region="us-west-2"
cluster_name=""

# Export the initial credentials and region
export AWS_ACCESS_KEY_ID=$access_key_id
export AWS_SECRET_ACCESS_KEY=$secret_access_key
export AWS_DEFAULT_REGION=$default_region

# Update kubeconfig for EKS
aws eks update-kubeconfig --region $default_region --name $cluster_name
