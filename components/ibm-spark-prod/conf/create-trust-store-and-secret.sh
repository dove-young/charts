#!/bin/bash

exec_cmd()
{
    CMD=$1
    eval $CMD
    if [ $? -ne 0 ]
    then
        echo "Error : failed to execute the command: $CMD"
        exit 1
    fi
}
kubectl_retry(){
cmd=$1
count=$2
while [[ $count -gt 0 ]]
do
    echo "count $count"
    eval $cmd
    exit_code=$?
    echo "exit_code : $exit_code"
    if [ $exit_code -eq 0 ]
    then
       return 0
    fi
    count=$(($count - 1))
    return $exit_code
done
}

truststore_password=$1
truststore_secret_name=$2
os_truststore_secret_name=$3
icp4d_cert_path=$4

#--------------------------
# Main
#--------------------------

java_trust_store=/opt/ibm/java/jre/lib/security/cacerts

line_begin="-----BEGIN CERTIFICATE-----"
count=0
cert_file=$icp4d_cert_path/certificate.pem
tmp_cert_file=/tmp/certificate.pem
cat $cert_file > $tmp_cert_file
echo -e "\n" >> $tmp_cert_file
mkdir -p /tmp/certs/

while read line ; do
    if [[ "$line" == "$line_begin" ]]
    then
    count=$(($count + 1))
    fi
    echo "$line" >> /tmp/certs/cert_$count.pem
done < $tmp_cert_file

for filename in /tmp/certs/*.pem
do
    exec_cmd "keytool -importcert -alias $filename -file $filename -keystore $java_trust_store -storepass $truststore_password -noprompt"
done

echo -n "$truststore_password" > /tmp/password.txt

exec_cmd "cp -r /tmp/certs/*.pem /etc/pki/ca-trust/source/anchors/"
exec_cmd "update-ca-trust"

exec_cmd "chmod 744 /etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem"
exec_cmd "cat $tmp_cert_file >> /etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem"
exec_cmd "chmod 444 /etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem"

kubectl_retry "./tmp/kubectl delete secret $truststore_secret_name" 3
kubectl_retry "./tmp/kubectl delete secret $os_truststore_secret_name" 3
kubectl_retry "./tmp/kubectl create secret generic $truststore_secret_name --from-file=$java_trust_store --from-file=/tmp/password.txt" 3
if [ $? -ne 0 ]
then
   echo "Error : failed to create $truststore_secret_name secret"
   exit 1
fi
kubectl_retry "./tmp/kubectl create secret generic $os_truststore_secret_name --from-file=/etc/pki/ca-trust/extracted/openssl/ca-bundle.trust.crt --from-file=/etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem" 3
if [ $? -ne 0 ]
then
   echo "Error : failed to create $os_truststore_secret_name secret"
   exit 1
fi

exit 0