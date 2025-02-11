#!/usr/bin/bash

###################################################
# Copyright (C) IBM Corp. 2021 All Rights Reserved.
# Licensed under the Apache License v2.0
###################################################

logfile=/tmp/user_data.log
echo START `date '+%Y-%m-%d %H:%M:%S'`

#
# Export user data, which is defined with the "UserData" attribute
# in the template
#
%EXPORT_USER_DATA%

#input parameters
storage_ips="${storage_ips}"
cluster_name="${cluster_id}"
numExpectedManagementHosts="${mgmt_count}"
hyperthreading="${hyperthreading}"
cluster_cidr="${cluster_cidr}"
hf_cidr_block="${cluster_cidr}"
spectrum_scale="${spectrum_scale}"
temp_public_key="${temp_public_key}"
windows_worker_node="${windows_worker_node}"
EgoUserName="${EgoUserName}"
EgoPassword="${EgoPassword}"
worker_node_type="${worker_node_type}"