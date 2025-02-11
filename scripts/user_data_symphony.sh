#!/bin/bash

###################################################
# Copyright (C) IBM Corp. 2021 All Rights Reserved.
# Licensed under the Apache License v2.0
###################################################

set -x
##################################################################
#args
#total number of management_node hosts
# export numExpectedManagementHosts=3
#host can be primary, secondary, management_node or not set for compute
export egoHostRole=${egoHostRole}

#password should be 8 to 15 characters
export adminPswd=Admin
export guestPswd=Guest

#Host Factory
export VPC_APIKEY_VALUE=${vpcAPIKeyValue}

export hf_maxNum=${hf_maxNum}
export hf_ncores=${hf_ncores}
export hf_memInMB=${hf_memInMB}
export hf_profile=${hf_profile}

#Gen2 UIDS
#Only used in primary
export imageID=${imageID}
export subnetID=${subnetID}
export vpcID=${vpcID}
export securityGroupID=${securityGroupID}
export sshkey_ID=${sshkey_ID}
export regionName=${regionName}
export zoneName=${zoneName}
export resourceGroupID=${resourceGroupID}
#prefix should be 10 characters or fewer
export hostPrefix=${hostPrefix}


#required ports for firewall
#GUI: 8443
#EGO: 17870, 27820(SSL only)
#SOAM: 17874-17875, 21000-21010
#

#common =================
export enableSSL=N
#cluster ID should be 39 characters alphanumeric no spaces, supports -_.
# export clusterID=SunilSymphony731ClusterPOC
export clusterID=${cluster_name}
export domainName='.ibm.com'

#nfs
export nfsHostIP=$storage_ips

#vpn
export CLUSTER_CIDR=$cluster_cidr
##################################################################

#internal
export CLUSTERADMIN=egoadmin
export EGO_TOP=/opt/ibm/spectrumcomputing
export SHARED_TOP=/data
export SHARED_TOP_CLUSTERID=${SHARED_TOP}/${clusterID}
export SHARED_TOP_SYM=${SHARED_TOP_CLUSTERID}/sym731
export HOSTS_FILES=${SHARED_TOP_CLUSTERID}/hosts
export LOCK_FILE=${SHARED_TOP_CLUSTERID}/lock
#ensure DONE file does not exist before starting
export DONE_FILE=${SHARED_TOP_CLUSTERID}/done
export SHARED_HOSTS_FILE=${SHARED_TOP_CLUSTERID}/sharedhosts
export HOST_NAME=`hostname`
export export HOST_IP=$(hostname -I)
export DELAY=15
export STARTUP_DELAY=1
export ENTITLEMENT_FILE=$EGO_TOP/kernel/conf/sym_adv_entitlement.dat
export EGO_HOSTS_FILE=${SHARED_TOP_SYM}/kernel/conf/hosts
export SHARED_EGO_CONF_FILE=${SHARED_TOP_SYM}/kernel/conf/ego.conf
export IBM_CLOUD_PROVIDER_SCRIPTS=hostfactory/1.1/providerplugins/ibmcloudgen2/samplepostprovision/sym
export IBM_CLOUD_PROVIDER_PP_SCRIPT=${EGO_TOP}/${IBM_CLOUD_PROVIDER_SCRIPTS}/post_installgen2.sh
export IBM_CLOUD_PROVIDER_SHARED_PP_SCRIPT=${SHARED_TOP_SYM}/${IBM_CLOUD_PROVIDER_SCRIPTS}/post_installgen2.sh
export IBM_CLOUD_PROVIDER_WORK=work/providers/ibmcloudgen2inst
export LOCAL_HOST_IPV4="127.0.0.1   localhost localhost.localdomain localhost4 localhost4.localdomain4"
export LOCAL_HOST_IPV6="::1         localhost localhost.localdomain localhost6 localhost6.localdomain6"

##################################################################

function scale_update_worker_hostname
{
    if [ ${spectrum_scale} == true ]; then
        TMP_HOST_NAME=$(grep -F "${HOST_IP}" ${SHARED_HOSTS_FILE} | awk '{ print $3 }')
        if [ -n "${TMP_HOST_NAME}" ]; then
            export HOST_NAME=${TMP_HOST_NAME}
            hostnamectl set-hostname ${HOST_NAME}
        fi
    fi
}

function scale_create_shared_hosts_file
{
    if [ ${spectrum_scale} == true ]; then
        python3 -c "import ipaddress; print('\n'.join([str(ip) +  ' ${hostPrefix}-' + str(ip).replace('.', '-') + '${domainName}' + ' ${hostPrefix}-' + str(ip).replace('.', '-') for ip in ipaddress.IPv4Network('${hf_cidr_block}')]))" >> ${SHARED_HOSTS_FILE}
    fi
}

function scale_append_hosts_file
{
    if [ ${spectrum_scale} == true ]; then
        cat ${SHARED_HOSTS_FILE} >> /etc/hosts
    fi
}

function scale_disable_hf
{
    if [ ${spectrum_scale} == true ]; then
        [ -f ${EGO_TOP}/eservice/esc/conf/services/hostfactory.xml ] && sed -i -e "s|AUTOMATIC|MANUAL|g" ${EGO_TOP}/eservice/esc/conf/services/hostfactory.xml
    fi
}

function config_hyperthreading
{
    if ! $hyperthreading; then
    for vcpu in `cat /sys/devices/system/cpu/cpu*/topology/thread_siblings_list | cut -s -d- -f2 | cut -d- -f2 | uniq`; do
        echo 0 > /sys/devices/system/cpu/cpu$vcpu/online
    done
    fi
}

function mount_nfs
{
    mkdir $SHARED_TOP
    chmod 1777 $SHARED_TOP
    echo "${nfsHostIP}:${SHARED_TOP}      ${SHARED_TOP}      nfs rw,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,_netdev 0 0" >> /etc/fstab
    mount $SHARED_TOP
}

function mount_nfs_readonly
{
    mkdir $SHARED_TOP
    chmod 1777 $SHARED_TOP
    echo "${nfsHostIP}:${SHARED_TOP}      ${SHARED_TOP}      nfs ro,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,_netdev 0 0" >> /etc/fstab
    mount $SHARED_TOP
}

function wait_for_nfs
{
    MAX_LOOP=100
    for (( i=1; i <= $MAX_LOOP; ++i ))
    do
        if grep -qs "$SHARED_TOP " /proc/mounts; then
            echo "NFS Found"
            break;
        fi
        echo "Waiting for mount point $SHARED_TOP to be created $I/$MAX_LOOP"
        sleep ${DELAY}
        mount $SHARED_TOP
    done
    if [ ! 'mountpoint -q $SHARED_TOP' ]; then
        echo "ERROR: Mount point $SHARED_TOP does not exist, cluster deployment timed-out."
        exit 1
    fi
}

function wait_for_primary_host
{
    # wait for primary to be installed
    MAX_LOOP=100
    if [ ! -f ${DONE_FILE} ]; then
        for (( i=1; i <= $MAX_LOOP; ++i ))
        do
            if [ -f ${DONE_FILE} ]; then
                break;
            fi
            echo "Waiting lock file ${DONE_FILE} to be created $I/$MAX_LOOP"
            sleep ${DELAY}
        done
        if [ ! -f ${DONE_FILE} ]; then
            echo "ERROR: Lock file ${DONE_FILE} does not exist, cluster deployment timed-out."
            exit 1
        fi
    fi
}

function clean_shared
{
    rm -rf ${SHARED_TOP_CLUSTERID}
    mkdir -p ${SHARED_TOP_SYM} ${HOSTS_FILES} && chown -R ${CLUSTERADMIN} ${SHARED_TOP_CLUSTERID}
}

function push_bin_nfs
{
    count=-1
    while (( count != 0 ))
    do
        sleep 5
        echo "waiting for package decryption"
        count=$(find /opt/IBM/symphony_cloud_packages/*.gpg 2>/dev/null | wc -l)
        if [ $count == 0 ]; then
            mv /opt/IBM/symphony_cloud_packages ${SHARED_TOP}
            echo "symphony binary files moved"
        fi
    done
    if [ ${spectrum_scale} == true ]; then
        count=-1
        while (( count != 0 ))
        do
            sleep 5
            echo "waiting for package decryption"
            count=$(find /opt/IBM/gpfs_cloud_rpms/*.gpg 2>/dev/null | wc -l)
            if [ $count == 0 ]; then
                mv /opt/IBM/gpfs_cloud_rpms ${SHARED_TOP}
                echo "scale binary files moved"
            fi
        done
    fi
}

function install_symp
{
    if ! rpm -q --quiet egocore ; then
      echo "Symphony package not found"
      /bin/bash ${SHARED_TOP}/symphony_cloud_packages/install_symphony.sh
      echo "installed symphony"
    fi
}

function install_scale
{
      /bin/bash ${SHARED_TOP}/gpfs_cloud_rpms/install_scale.sh
      echo "installed scale"
}

function bare_metal_mtu9000
{
  echo ${worker_node_type}
  echo "MTU=9000" >> "/etc/sysconfig/network-scripts/ifcfg-ens1"
  systemctl restart NetworkManager
}

function mtu9000
{
    #Change the MTU setting
    #ip link set mtu 9000 dev eth0
    #echo "MTU=9000" >> /etc/sysconfig/network-scripts/ifcfg-eth0
    #echo "PEERDNS=no" >> /etc/sysconfig/network-scripts/ifcfg-eth0
    ip route replace $CLUSTER_CIDR dev eth0 proto kernel scope link src $HOST_IP mtu 9000
    echo 'ip route replace '$CLUSTER_CIDR' dev eth0 proto kernel scope link src '$HOST_IP' mtu 9000' >> /etc/sysconfig/network-scripts/route-eth0
}

function update_hosts
{
    #Fully qualified domain name of the management_node host
    echo "${HOST_IP} ${HOST_NAME}${domainName} ${HOST_NAME}" > /tmp/hosts
    mkdir -p ${HOSTS_FILES} && cp /tmp/hosts ${HOSTS_FILES}/${HOST_NAME}
    touch ${EGO_HOSTS_FILE}
    cat /tmp/hosts >> ${EGO_HOSTS_FILE}
    chown ${CLUSTERADMIN} ${EGO_HOSTS_FILE}
    chmod 644 ${EGO_HOSTS_FILE}
    cat ${HOSTS_FILES}/* > /tmp/hosts
    cp /tmp/hosts /etc/hosts
    echo "${LOCAL_HOST_IPV4}" >> /etc/hosts
    echo "${LOCAL_HOST_IPV6}" >> /etc/hosts
    chmod 644 /etc/hosts
    rm -f /tmp/hosts
}

function update_hosts_noshare
{
    #Fully qualified domain name of the management_node host
    echo "${HOST_IP} ${HOST_NAME}${domainName} ${HOST_NAME}" > /tmp/hosts
    cat ${HOSTS_FILES}/* >> /tmp/hosts
    cp /tmp/hosts /etc/hosts
    echo "${LOCAL_HOST_IPV4}" >> /etc/hosts
    echo "${LOCAL_HOST_IPV6}" >> /etc/hosts
    chmod 644 /etc/hosts
    rm -f /tmp/hosts
}

function update_clusterid
{
    #change cluster ID
    if [ "${clusterID}" != "" ]; then
        echo "Renaming cluster to ${clusterID}"
        if [ -f ${EGO_TOP}/kernel/conf/ego.cluster.IBMCloudSym731Cluster ]; then
            mv ${EGO_TOP}/kernel/conf/ego.cluster.IBMCloudSym731Cluster ${EGO_TOP}/kernel/conf/ego.cluster.${clusterID}
        fi
        if [ -f ${EGO_TOP}/kernel/conf/ego.shared ]; then
            sed -i -e "s|IBMCloudSym731Cluster|${clusterID}|g" ${EGO_TOP}/kernel/conf/ego.shared
        fi
    fi
}

function create_sshkey
{
    #set ssh keys for root
    rm -rf ${SHARED_TOP_CLUSTERID}/root/.ssh
    mkdir -p ${SHARED_TOP_CLUSTERID}/root/.ssh
    ssh-keygen -t rsa -f ${SHARED_TOP_CLUSTERID}/root/.ssh/id_rsa -q -N ""
    cp ${SHARED_TOP_CLUSTERID}/root/.ssh/id_rsa.pub ${SHARED_TOP_CLUSTERID}/root/.ssh/authorized_keys
    mkdir -p /root/.ssh
    cat ${SHARED_TOP_CLUSTERID}/root/.ssh/id_rsa.pub >> /root/.ssh/authorized_keys
    cp ${SHARED_TOP_CLUSTERID}/root/.ssh/id_rsa /root/.ssh/.
    echo "${temp_public_key}" >> /root/.ssh/authorized_keys
    echo "StrictHostKeyChecking no" >> ~/.ssh/config
}

function copy_sshkey
{
    mkdir -p /root/.ssh
    cat ${SHARED_TOP_CLUSTERID}/root/.ssh/id_rsa.pub >> /root/.ssh/authorized_keys
    if [ ${spectrum_scale} == true ]; then
      echo "${temp_public_key}" >> /root/.ssh/authorized_keys
    fi
    cp ${SHARED_TOP_CLUSTERID}/root/.ssh/id_rsa /root/.ssh/.
    echo "StrictHostKeyChecking no" >> ~/.ssh/config
}

function create_sslkey
{
    echo "Regenerating SSL certificates"
    TOPDIR=${EGO_TOP}/jre
    KEYTOOL=`find ${TOPDIR} -name keytool`
    if [ "${KEYTOOL}" == "" ]; then
        echo "Can not find keytool"
        exit 1
    fi
    JAVATOOL=`find ${TOPDIR} -name java`
    if [ "${JAVATOOL}" == "" ]; then
        echo "Can not find java"
        exit 1
    fi

    dnsname=${HOST_NAME}
    domain=${domainName}
    if [ "$domain" = "" ]; then
        domain="*.ibm.com"
    else
        domain="*${domainName}"
    fi

    cd ${EGO_TOP}/wlp/usr/shared/resources/security

    # backup current certificates
    CERT_TMP_DIR=TMP_`date +%s`
    mkdir -p ${CERT_TMP_DIR}
    [ -f servercertcasigned.pem ] && mv servercertcasigned.pem ${CERT_TMP_DIR}
    [ -f serverKeyStore.jks ] && mv serverKeyStore.jks ${CERT_TMP_DIR}
    [ -f srvcertreq.csr ] && mv srvcertreq.csr ${CERT_TMP_DIR}
    [ -f serverTrustStore.jks ] && mv serverTrustStore.jks ${CERT_TMP_DIR}
    [ -f user.key ] && mv user.key ${CERT_TMP_DIR}
    [ -f user.p12 ] && mv user.p12 ${CERT_TMP_DIR}
    [ -f user.pem ] && mv user.pem ${CERT_TMP_DIR}

    ${KEYTOOL} -genkeypair -noprompt -alias srvalias -dname "CN=$domain,O=Platform,C=CA" -keystore serverKeyStore.jks -storepass Liberty -keypass Liberty -keyalg rsa -validity 1095 -keysize 2048 -sigalg SHA256withRSA -ext "san=dns:$dnsname"
    ${KEYTOOL} -certreq -alias srvalias -file srvcertreq.csr -storepass Liberty -keystore serverKeyStore.jks -ext "san=dns:$dnsname"
    ${KEYTOOL} -gencert -infile srvcertreq.csr -outfile servercertcasigned.pem -alias caalias -keystore caKeyStore.jks -storepass Liberty -validity 1095 -ext "san=dns:$dnsname"
    ${KEYTOOL} -importcert -noprompt -alias caalias -file cacert.pem -keystore serverKeyStore.jks -storepass Liberty
    ${KEYTOOL} -import -noprompt -alias srvalias -file servercertcasigned.pem -storepass Liberty -keystore serverKeyStore.jks
    ${KEYTOOL} -importcert -noprompt -alias srvalias -file cacert.pem -keystore serverTrustStore.jks -storepass Liberty

    # Provide a EGO level CA file for all SOAM/EGO SSL
    ${KEYTOOL} -importkeystore -srckeystore serverKeyStore.jks -destkeystore user.p12 -srcstoretype JKS -deststoretype PKCS12 -srcstorepass Liberty -deststorepass Liberty -srcalias srvalias -destalias srvalias -srckeypass Liberty -destkeypass Liberty -noprompt > /dev/null 2>&1
    ${JAVATOOL} -cp keyAndCertManagement.jar com.ibm.platform.computing.keyAndCertManagement.PrivateKeyAndCertificateHelper "user.p12" pkcs12 Liberty "user.key" "user.pem" > /dev/null 2>&1

    chown -R ${CLUSTERADMIN} ./

    if [ ! -f serverTrustStore.jks ]; then
        echo "SSL certificates generation failed, restoring original certificates."
        cp ${CERT_TMP_DIR}/* .
    fi
    mkdir -p ${SHARED_TOP_SYM}/security && cp ${EGO_TOP}/wlp/usr/shared/resources/security/* ${SHARED_TOP_SYM}/security/. && chown -R ${CLUSTERADMIN} ${SHARED_TOP_SYM}/security/.
}

function copy_sslkey
{
    # Share CA Certificate
    cp -f ${SHARED_TOP_SYM}/security/* ${EGO_TOP}/wlp/usr/shared/resources/security/.
}

function HF_provider_config
{
    IBM_CLOUD_PROVIDERS_CONF=${EGO_TOP}/hostfactory/conf/providers
    IBM_CLOUD_PROVIDERS_CONF_FILE=${IBM_CLOUD_PROVIDERS_CONF}/hostProviders.json
    IBM_CLOUD_PROVIDER_CONF=${IBM_CLOUD_PROVIDERS_CONF}/ibmcloudgen2inst
    IBM_CLOUD_CREDENTIALS_FILE=${IBM_CLOUD_PROVIDER_CONF}/credentials
    IBM_CLOUD_SHARED_CREDENTIALS_FILE=${SHARED_TOP_SYM}/hostfactory/conf/providers/ibmcloudgen2inst/credentials
    IBM_CLOUD_CONFIG_FILE=${IBM_CLOUD_PROVIDER_CONF}/ibmcloudgen2instprov_config.json
    IBM_CLOUD_TEMPLATE_FILE=${IBM_CLOUD_PROVIDER_CONF}/ibmcloudgen2instprov_templates.json
    IBM_CLOUD_REQUESTOR_CONF=${EGO_TOP}/hostfactory/conf/requestors
    IBM_CLOUD_REQUESTOR_CONF_FILE=${IBM_CLOUD_REQUESTOR_CONF}/hostRequestors.json

    #enable HF
    [ -f ${EGO_TOP}/eservice/esc/conf/services/hostfactory.xml ] && sed -i -e "s|MANUAL|AUTOMATIC|g" ${EGO_TOP}/eservice/esc/conf/services/hostfactory.xml

    #update providers
    sed -i -e "s|ibmcloud|ibmcloudgen2|g" $IBM_CLOUD_PROVIDERS_CONF_FILE
    #update requestors
    sed -i -e "s|\[\"awsinst\"\]|\[\"ibmcloudgen2inst\"\]|g" $IBM_CLOUD_REQUESTOR_CONF_FILE
    sed -i -e "s|\"ibmcloudinst\"|\"ibmcloudgen2inst\"|g" $IBM_CLOUD_REQUESTOR_CONF_FILE
    #enable only symA requestor, which is first
    sed -i -e "0,/\"enabled\": 0,/s||\"enabled\": 1,|" $IBM_CLOUD_REQUESTOR_CONF_FILE

    #update IBM gen2 Credentials API keys
    sed -i -e "s|VPC_APIKEY=.*|VPC_APIKEY=${VPC_APIKEY_VALUE}|g" $IBM_CLOUD_CREDENTIALS_FILE
    sed -i -e "s|RESOURCE_RECORDS_APIKEY=.*|RESOURCE_RECORDS_APIKEY=${VPC_APIKEY_VALUE}|g" $IBM_CLOUD_CREDENTIALS_FILE
    sed -i -e "s|\"IBMCLOUDGEN2_CREDENTIAL_FILE\":.*|\"IBMCLOUDGEN2_CREDENTIAL_FILE\": \"${IBM_CLOUD_SHARED_CREDENTIALS_FILE}\",|g" $IBM_CLOUD_CONFIG_FILE

cat <<- EOF > $IBM_CLOUD_PROVIDER_PP_SCRIPT
#!/bin/bash

set -x
echo START >> /var/log/postprovisionscripts.log 2>&1
date '+%Y-%m-%d %H:%M:%S'

export HOST_NAME=\$(hostname)
export HOST_IP=\$(ip addr show eth0 | awk '\$1 == "inet" {gsub(/\/.*$/, "", \$2); print \$2}')

#Change the MTU setting
ip link set mtu 9000 dev eth0
echo "MTU=9000" >> /etc/sysconfig/network-scripts/ifcfg-eth0
echo "PEERDNS=no" >> /etc/sysconfig/network-scripts/ifcfg-eth0

if ! $hyperthreading; then
    for vcpu in \$(cat /sys/devices/system/cpu/cpu*/topology/thread_siblings_list | cut -s -d- -f2 | cut -d- -f2 | uniq); do
        echo 0 > /sys/devices/system/cpu/cpu\${vcpu}/online
    done
fi

#mount NFS
mkdir $SHARED_TOP
chmod 1777 $SHARED_TOP
echo "${nfsHostIP}:${SHARED_TOP}      ${SHARED_TOP}      nfs ro,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,_netdev 0 0" >> /etc/fstab
mount $SHARED_TOP

MAX_LOOP=100
for (( i=1; i <= $MAX_LOOP; ++i ))
do
    if [ 'mountpoint -q $SHARED_TOP' ]; then
        break;
    fi
    echo "Waiting for mount point $SHARED_TOP to be created $I/10"
    sleep ${DELAY}
    mount $SHARED_TOP
done
if [ ! 'mountpoint -q $SHARED_TOP' ]; then
    echo "ERROR: Mount point $SHARED_TOP does not exist, cluster deployment timed-out."
    exit 1
fi

if [ ${spectrum_scale} == true ]; then
    export TMP_HOST_NAME=\$(grep -F "\${HOST_IP} " ${SHARED_HOSTS_FILE} | awk '{ print \$3 }')
    if [ -n "\${TMP_HOST_NAME}" ]; then
        export HOST_NAME=\${TMP_HOST_NAME}
        hostnamectl set-hostname \${HOST_NAME}
    fi
fi
#Fully qualified domain name of the management_node host
echo "\${HOST_IP} \${HOST_NAME}${domainName} \${HOST_NAME}" > /tmp/hosts
cat ${HOSTS_FILES}/* >> /tmp/hosts
cp /tmp/hosts /etc/hosts
echo "${LOCAL_HOST_IPV4}" >> /etc/hosts
echo "${LOCAL_HOST_IPV6}" >> /etc/hosts
chmod 644 /etc/hosts
rm -f /tmp/hosts
if [ ${spectrum_scale} == true ]; then
    cat ${SHARED_HOSTS_FILE} >> /etc/hosts
fi
# copy ssh key
mkdir -p /root/.ssh
cat ${SHARED_TOP_CLUSTERID}/root/.ssh/id_rsa.pub >> /root/.ssh/authorized_keys
cp ${SHARED_TOP_CLUSTERID}/root/.ssh/id_rsa /root/.ssh/.

# Share CA Certificate
cp -f ${SHARED_TOP_SYM}/security/* ${EGO_TOP}/wlp/usr/shared/resources/security/.

#enable SSL
if [ "${enableSSL}" == "Y" ]; then
    # enable SSL for all components
    echo "EGO_TRANSPORT_SECURITY=SSL" >> ${EGO_TOP}/kernel/conf/ego.conf
    echo "EGO_KD_TS_PORT=27820" >> ${EGO_TOP}/kernel/conf/ego.conf
    echo "#EGO_PEM_TRANSPORT_SECURITY=SSL" >> ${EGO_TOP}/kernel/conf/ego.conf
    echo "#EGO_KD_PEM_TS_PORT=27821" >> ${EGO_TOP}/kernel/conf/ego.conf
    echo "#EGO_PEM_TS_PORT=27822" >> ${EGO_TOP}/kernel/conf/ego.conf
fi

source ${EGO_TOP}/profile.platform
#parse shared ego.conf for primary management_node
export EGO_MANAGEMENT_NODE_LIST=\$(gawk -F= '/EGO_MASTER_LIST/{print \$2}' ${SHARED_EGO_CONF_FILE} | tr -d \")
export PRIMARY_MANAGEMENT_NODE=\$(echo \$EGO_MANAGEMENT_NODE_LIST | cut -d' ' -f1)

egosetsudoers.sh
egosetrc.sh
export EGOCONFIG_DISABLE_HOST_CHECK=Y
su ${CLUSTERADMIN} -c 'egoconfig join \${PRIMARY_MANAGEMENT_NODE} -f'
su ${CLUSTERADMIN} -c 'egoconfig addresourceattr "[resourcemap ibmcloud*cloudprovider] [resource corehoursaudit]"'
echo "source ${EGO_TOP}/profile.platform" >> /root/.bashrc
sleep $STARTUP_DELAY
systemctl start ego
echo END >> /var/log/postprovisionscripts.log 2>&1
EOF

#Update IBM gen2 template
cat << EOF > $IBM_CLOUD_TEMPLATE_FILE
{
"templates": [
{
    "templateId": "Template-IBMCloudGen2VM-1",
    "maxNumber": ${hf_maxNum},
    "attributes": {
        "type": ["String", "X86_64"],
        "ncores": ["Numeric", "1"],
        "ncpus": ["Numeric", "${hf_ncores}"],
        "nram": ["Numeric", "${hf_memInMB}"],
        "priceInfo": ["String", "price:0.1,billingTimeUnitType:prorated_hour,billingTimeUnitNumber:1,billingRoundoffType:unit"]
    },
    "imageId": "${imageID}",
    "subnetId": "${subnetID}",
    "vpcId": "${vpcID}",
    "resourceGroupId": "${resourceGroupID}",
    "vmType": "${hf_profile}",
    "securityGroupIds": ["${securityGroupID}"],
    "sshkey_id": "${sshkey_ID}",
    "region": "${regionName}",
    "zone": "${zoneName}",
    "postProvisionFile": "${IBM_CLOUD_PROVIDER_SHARED_PP_SCRIPT}",
    "hostPrefix": "${hostPrefix}"
}
]
}
EOF
}

function enable_SSL_primary
{
    #enable SSL
    #change SDK ports and enable SSL
    SD_XML=$(find ${EGO_TOP}/soam/*/eservice -name sd.xml)
    if [ "${enableSSL}" == "Y" ]; then
        [ -f ${SD_XML} ] && sed -i -e "/<ego:EnvironmentVariable name=\"SD_SDK_PORT\">17874<\/ego:EnvironmentVariable>/i \
         <ego:EnvironmentVariable name=\"SSM_SDK_ADDR\">21000-21010<\/ego:EnvironmentVariable>\n \
         <ego:EnvironmentVariable name=\"SD_SOAP_TRANSPORT\">TCPIPv4SSL</ego:EnvironmentVariable>\n \
         <ego:EnvironmentVariable name=\"SD_SOAP_TRANSPORT_ARG\">\$EGO_DEFAULT_TS_PARAMS</ego:EnvironmentVariable>\n \
         <ego:EnvironmentVariable name=\"SDSOAPCLIENT_ARG\">\$EGO_CLIENT_TS_PARAMS</ego:EnvironmentVariable>\n \
         <ego:EnvironmentVariable name=\"SSM_SDK_TRANSPORT\">TCPIPv4SSL</ego:EnvironmentVariable>\n \
         <ego:EnvironmentVariable name=\"SSM_SDK_TRANSPORT_ARG\">\$EGO_DEFAULT_TS_PARAMS</ego:EnvironmentVariable>\n \
         <ego:EnvironmentVariable name=\"SDK_TRANSPORT\">TCPIPv4SSL</ego:EnvironmentVariable>\n \
         <ego:EnvironmentVariable name=\"SDK_TRANSPORT_ARG\">\$EGO_CLIENT_TS_PARAMS</ego:EnvironmentVariable>\n \
         <ego:EnvironmentVariable name=\"SD_SDK_TRANSPORT\">TCPIPv4SSL</ego:EnvironmentVariable>\n \
         <ego:EnvironmentVariable name=\"SD_SDK_TRANSPORT_ARG\">\$EGO_DEFAULT_TS_PARAMS</ego:EnvironmentVariable> \
         " ${SD_XML}

        # change RS SSL config
        RS_XML=${EGO_TOP}/eservice/esc/conf/services/rs.xml
        [ -f ${RS_XML} ] && sed -i -e "/<ego:EnvironmentVariable name=\"REPOSITORY_SERVICE_PORT\">17873<\/ego:EnvironmentVariable>/i \
         <ego:EnvironmentVariable name=\"RS_RSSDK_TRANSPORT\">TCPIPv4SSL</ego:EnvironmentVariable>\n \
         <ego:EnvironmentVariable name=\"RS_RSSDK_TRANSPORT_ARG\">\$EGO_DEFAULT_TS_PARAMS</ego:EnvironmentVariable>\n \
         <ego:EnvironmentVariable name=\"RSSDK_TRANSPORT_ARG\">\$EGO_CLIENT_TS_PARAMS</ego:EnvironmentVariable> \
         " ${RS_XML}

        # enable SSL for all components
        echo "EGO_TRANSPORT_SECURITY=SSL" >> ${EGO_TOP}/kernel/conf/ego.conf
        echo "EGO_KD_TS_PORT=27820" >> ${EGO_TOP}/kernel/conf/ego.conf
        echo "#EGO_PEM_TRANSPORT_SECURITY=SSL" >> ${EGO_TOP}/kernel/conf/ego.conf
        echo "#EGO_KD_PEM_TS_PORT=27821" >> ${EGO_TOP}/kernel/conf/ego.conf
        echo "#EGO_PEM_TS_PORT=27822" >> ${EGO_TOP}/kernel/conf/ego.conf
    else
        [ -f ${SD_XML} ] && sed -i -e "/<ego:EnvironmentVariable name=\"SD_SDK_PORT\">17874<\/ego:EnvironmentVariable>/i \
         <ego:EnvironmentVariable name=\"SSM_SDK_ADDR\">21000-21010<\/ego:EnvironmentVariable>\n \
         " ${SD_XML}
    fi
}

function enable_SSL_compute
{
    #enable SSL
    if [ "${enableSSL}" == "Y" ]; then
        # enable SSL for all components
        echo "EGO_TRANSPORT_SECURITY=SSL" >> ${EGO_TOP}/kernel/conf/ego.conf
        echo "EGO_KD_TS_PORT=27820" >> ${EGO_TOP}/kernel/conf/ego.conf
        echo "#EGO_PEM_TRANSPORT_SECURITY=SSL" >> ${EGO_TOP}/kernel/conf/ego.conf
        echo "#EGO_KD_PEM_TS_PORT=27821" >> ${EGO_TOP}/kernel/conf/ego.conf
        echo "#EGO_PEM_TS_PORT=27822" >> ${EGO_TOP}/kernel/conf/ego.conf
    fi
}

function patch_image
{
    echo "Patching image config"
    rm -f /root/preconfig*.sh
    if [ ! -f /usr/bin/python ]; then
        ln -s /usr/bin/python3 /usr/bin/python
    fi
}

function config_symprimary
{
    source ${EGO_TOP}/profile.platform
    egosetsudoers.sh
    egosetrc.sh
    su ${CLUSTERADMIN} -c 'egoconfig join ${HOST_NAME} -f'
    su ${CLUSTERADMIN} -c 'egoconfig setentitlement $ENTITLEMENT_FILE'
    su ${CLUSTERADMIN} -c 'egoconfig mghost ${SHARED_TOP_SYM} -f'
    source ${EGO_TOP}/profile.platform

    #fix up
    mkdir -p ${SHARED_TOP_SYM}/kernel/audit && chown -R ${CLUSTERADMIN} ${SHARED_TOP_SYM}/kernel/audit
    mkdir -p ${SHARED_TOP_SYM}/kernel/work/data && chown -R ${CLUSTERADMIN} ${SHARED_TOP_SYM}/kernel/work/data

    mkdir -p ${SHARED_TOP_SYM}/hostfactory/${IBM_CLOUD_PROVIDER_WORK}
    mkdir -p ${SHARED_TOP_SYM}/${IBM_CLOUD_PROVIDER_SCRIPTS} && cp ${IBM_CLOUD_PROVIDER_PP_SCRIPT} ${IBM_CLOUD_PROVIDER_SHARED_PP_SCRIPT}
    chown -R ${CLUSTERADMIN} ${SHARED_TOP_SYM}/hostfactory

    touch ${EGO_HOSTS_FILE} && chown ${CLUSTERADMIN} ${EGO_HOSTS_FILE}
    cat /etc/hosts >> ${EGO_HOSTS_FILE}
    export EGO_MANAGEMENT_NODE_LIST=`gawk -F= '/EGO_MASTER_LIST/{print $2}' ${SHARED_EGO_CONF_FILE} | tr -d \"`
}

function config_symfailover
{
    source ${EGO_TOP}/profile.platform
    #parse shared ego.conf for primary management_node
    export EGO_MANAGEMENT_NODE_LIST=`gawk -F= '/EGO_MASTER_LIST/{print $2}' ${SHARED_EGO_CONF_FILE} | tr -d \"`
    export PRIMARY_MANAGEMENT_NODE=`echo $EGO_MANAGEMENT_NODE_LIST | cut -d' ' -f1`
    export NEW_MANAGEMENT_NODE_LIST=$(echo ${EGO_MANAGEMENT_NODE_LIST} | tr ' ' ','),${HOST_NAME}

    egosetsudoers.sh
    egosetrc.sh
    export EGOCONFIG_DISABLE_HOST_CHECK=Y
    su ${CLUSTERADMIN} -c 'egoconfig join ${PRIMARY_MANAGEMENT_NODE} -f'
    su ${CLUSTERADMIN} -c 'egoconfig mghost ${SHARED_TOP_SYM} -f'
    source ${EGO_TOP}/profile.platform
    su ${CLUSTERADMIN} -c 'egoconfig masterlist ${NEW_MANAGEMENT_NODE_LIST}'
}

function config_symmanagement
{
    source ${EGO_TOP}/profile.platform
    #parse shared ego.conf for primary management_node
    export EGO_MANAGEMENT_NODE_LIST=`gawk -F= '/EGO_MASTER_LIST/{print $2}' ${SHARED_EGO_CONF_FILE} | tr -d \"`
    export PRIMARY_MANAGEMENT_NODE=`echo $EGO_MANAGEMENT_NODE_LIST | cut -d' ' -f1`

    egosetsudoers.sh
    egosetrc.sh
    #short cut to avoid locking
    if (( numExpectedManagementHosts > 3 )); then
        sleep $(($RANDOM%15))
    fi
    export EGOCONFIG_DISABLE_HOST_CHECK=Y
    su ${CLUSTERADMIN} -c 'egoconfig join ${PRIMARY_MANAGEMENT_NODE} -f'
    su ${CLUSTERADMIN} -c 'egoconfig mghost ${SHARED_TOP_SYM} -f'
    source ${EGO_TOP}/profile.platform
}

function config_symcompute
{
    source ${EGO_TOP}/profile.platform
    #parse shared ego.conf for primary management_node
    export EGO_MANAGEMENT_NODE_LIST=`gawk -F= '/EGO_MASTER_LIST/{print $2}' ${SHARED_EGO_CONF_FILE} | tr -d \"`
    export PRIMARY_MANAGEMENT_NODE=`echo $EGO_MANAGEMENT_NODE_LIST | cut -d' ' -f1`

    egosetsudoers.sh
    egosetrc.sh
    export EGOCONFIG_DISABLE_HOST_CHECK=Y
    su ${CLUSTERADMIN} -c 'egoconfig join ${PRIMARY_MANAGEMENT_NODE} -f'
    su ${CLUSTERADMIN} -c 'egoconfig addresourceattr "[resourcemap ibmcloud*cloudprovider] [resource corehoursaudit]"'
}

function wait_for_management_hosts
{
    # wait for all management_node hosts to report their IP address
    CURRENT_HOSTS=0
    while (( CURRENT_HOSTS < numExpectedManagementHosts ))
    do
        sleep $DELAY
        sleep $(($RANDOM%5))
        if [ "${egoHostRole}" == "compute" ]; then
            echo "${HOST_IP} ${HOST_NAME}${domainName} ${HOST_NAME}" > /tmp/hosts
        fi
        cat ${HOSTS_FILES}/* >> /tmp/hosts
        cat /tmp/hosts >> /etc/hosts
        echo "${LOCAL_HOST_IPV4}" >> /etc/hosts
        echo "${LOCAL_HOST_IPV6}" >> /etc/hosts
        chmod 644 /etc/hosts
        CURRENT_HOSTS=`wc -l < /tmp/hosts`
        rm -f /tmp/hosts
    done
}

function wait_for_candidate_hosts
{
    # wait for all candidate hosts to update MANAGEMENT_NODES_LIST
    CURRENT_HOSTS=0
    EXPECTED_PRIMARY_HOSTS=1
    if (( numExpectedManagementHosts > 1 )); then
        EXPECTED_PRIMARY_HOSTS=2
    fi

    while (( CURRENT_HOSTS < EXPECTED_PRIMARY_HOSTS ))
    do
        sleep $DELAY
        sleep $(($RANDOM%5))
        # if candidate list changed need to restart ego
        NEW_EGO_MANAGEMENT_NODES_LIST=`gawk -F= '/EGO_MASTER_LIST/{print $2}' ${SHARED_EGO_CONF_FILE} | tr -d \"`
        if [ "${NEW_EGO_MANAGEMENT_NODES_LIST}" != "${EGO_MANAGEMENT_NODES_LIST}" ]; then
            echo "New candidate joined, need to restart ego"
            EGO_MANAGEMENT_NODES_LIST=${NEW_EGO_MANAGEMENT_NODES_LIST}
            systemctl restart ego
        fi
        words=( $EGO_MANAGEMENT_NODES_LIST )
        CURRENT_HOSTS=${#words[@]}
    done
}

function wait_for_candidate_hosts_norestart
{
    # wait for all candidate hosts to update MANAGEMENT_NODES_LIST
    CURRENT_HOSTS=0
    EXPECTED_PRIMARY_HOSTS=1
    if (( numExpectedManagementHosts > 1 )); then
        EXPECTED_PRIMARY_HOSTS=2
    fi

    export EGO_MANAGEMENT_NODE_LIST=`gawk -F= '/EGO_MASTER_LIST/{print $2}' ${SHARED_EGO_CONF_FILE} | tr -d \"`
    while (( CURRENT_HOSTS < EXPECTED_PRIMARY_HOSTS ))
    do
        sleep $DELAY
        sleep $(($RANDOM%5))
        # if candidate list changed need to restart ego
        NEW_EGO_MANAGEMENT_NODES_LIST=`gawk -F= '/EGO_MASTER_LIST/{print $2}' ${SHARED_EGO_CONF_FILE} | tr -d \"`
        if [ "${NEW_EGO_MANAGEMENT_NODES_LIST}" != "${EGO_MANAGEMENT_NODES_LIST}" ]; then
            echo "New candidate joined"
            EGO_MANAGEMENT_NODES_LIST=${NEW_EGO_MANAGEMENT_NODES_LIST}
        fi
        words=( $EGO_MANAGEMENT_NODES_LIST )
        CURRENT_HOSTS=${#words[@]}
    done
}

function disable_perf
{
    [ -f ${EGO_TOP}/perf/conf/datasource.xml ] && sed -i -e "s|localhost|${HOST_NAME}|g" ${EGO_TOP}/perf/conf/datasource.xml 
    [ -f ${EGO_TOP}/eservice/esc/conf/services/derby_service.xml ] && sed -i -e "s|localhost|${HOST_NAME}|g" ${EGO_TOP}/eservice/esc/conf/services/derby_service.xml
    #disable PERF
    [ -f ${EGO_TOP}/eservice/esc/conf/services/derby_service.xml ] && sed -i -e "s|AUTOMATIC|MANUAL|g" ${EGO_TOP}/eservice/esc/conf/services/derby_service.xml
    [ -f ${EGO_TOP}/eservice/esc/conf/services/plc_service.xml ] && sed -i -e "s|AUTOMATIC|MANUAL|g" ${EGO_TOP}/eservice/esc/conf/services/plc_service.xml
    [ -f ${EGO_TOP}/eservice/esc/conf/services/purger_service.xml ] && sed -i -e "s|AUTOMATIC|MANUAL|g" ${EGO_TOP}/eservice/esc/conf/services/purger_service.xml
}

function update_passwords
{
    for I in 1 2 3 4 5
    do
        if egosh user logon -u Admin -x Admin; then
            break;
        fi
        echo "Waiting cluster is up $I/5"
        sleep ${DELAY}
    done
    if [ "${guestPswd}" != "" ]; then
        egosh user modify -u Guest -x ${guestPswd}
    fi
    if [ "${adminPswd}" != "" ]; then
        echo y | egosh user modify -u Admin -x ${adminPswd}
    fi
    egosh user logoff
}

function start_ego
{
    echo "source ${EGO_TOP}/profile.platform" >> /root/.bashrc
    sleep $STARTUP_DELAY
    systemctl start ego
}

function set_ego_password
{
    for I in 1 2 3 4 5
    do
        if egosh user logon -u Admin -x Admin; then
            break;
        fi
        echo "Waiting cluster is up $I/5"
        sleep ${DELAY}
    done

    #Update EGO password
    executecmd='.\'
    EGOUSERNAME="$executecmd${EgoUserName}"
    egosh ego execpasswd -u $EGOUSERNAME -x ${EgoPassword} -noverify
    sed -i -e "s|egoadmin|.\\\egoadmin|g" $EGO_CONFDIR/ConsumerTrees.xml

    # Re-register symping app
    soamview app symping7.3.1 -p >sp.xml 
    soamreg sp.xml -f
    #Restart ego process
    egosh ego restart -f
    egosh user logoff
}

##################################################################

if [ -z "${egoHostRole}" ]; then
    export egoHostRole=compute
fi
echo "This host has EGO role ${egoHostRole}"

if [ "${egoHostRole}" == "primary" ]; then
    mount_nfs
    wait_for_nfs
    clean_shared
    mtu9000
    update_hosts
    update_clusterid
    create_sshkey
    if [ ${worker_node_type} == "baremetal" ]; then
      push_bin_nfs
    fi
    create_sslkey
    scale_create_shared_hosts_file
    HF_provider_config
    disable_perf
    scale_disable_hf
    patch_image
    enable_SSL_primary
    config_symprimary
    #unlock install
    touch $DONE_FILE
    start_ego
    wait_for_management_hosts
    scale_append_hosts_file
    update_passwords
    wait_for_candidate_hosts
    if [ ${windows_worker_node} == true ]; then
        set_ego_password
    fi
    rm -f $DONE_FILE
elif [ "${egoHostRole}" == "secondary" ]; then
    mount_nfs
    wait_for_nfs
    mtu9000
    wait_for_primary_host
    update_hosts
    copy_sshkey
    copy_sslkey
    patch_image
    config_symfailover
    start_ego
    wait_for_management_hosts
    scale_append_hosts_file
elif [ "${egoHostRole}" == "management_node" ]; then
    mount_nfs
    wait_for_nfs
    mtu9000
    wait_for_candidate_hosts_norestart
    update_hosts
    copy_sshkey
    copy_sslkey
    patch_image
    config_symmanagement
    start_ego
    wait_for_management_hosts
    scale_append_hosts_file
elif [ "${egoHostRole}" == "scale_storage" ]; then
    config_hyperthreading
    mount_nfs
    wait_for_nfs
    mtu9000
    wait_for_candidate_hosts_norestart
    scale_update_worker_hostname
    update_hosts_noshare
    copy_sshkey
    wait_for_management_hosts
    scale_append_hosts_file
else
    config_hyperthreading
    mount_nfs_readonly
    wait_for_nfs
    copy_sshkey
    scale_update_worker_hostname
    update_hosts_noshare
    scale_append_hosts_file
    if [ ${worker_node_type} == "baremetal" ]; then
      install_scale
      bare_metal_mtu9000
    else
      mtu9000
    fi
    install_symp
    wait_for_candidate_hosts_norestart
    copy_sslkey
    patch_image
    enable_SSL_compute
    config_symcompute
    start_ego
    wait_for_management_hosts
fi