#!/bin/bash

#
# DEFAULT VALUES
# MODIFY TO FIT YOUR NEEDS
#
### ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ ##

# Image ID. Picking up the latest Ubuntu image (in this case 14.04
ami='ami-9eaa1cf6'         
# Name tag for the instance
instanceName=BaseSpaceDev  
# Type of instance
InstanceType=m3.xlarge     
# Size of the /data and /genomes volumes (in GB), do not exceed 1000 GB
data=250
genomes=25
# Should the volume survive a terminiation of the Instance ( true|false )
deleteOnTermination=true

#
# If you have a  keyPair you want to use, set the path of the private key here
# Otherwise, It will  get a random name assigned to it and saved in ~/.ssh
# ------------------------------------------------------------
keyPairPath='' 


#
# STARTING CONFIGURATIO OF THE INSTANCE
#
# DO NOT EDIT PAST THAT POINT UNLESS YOU KNOW WHAT YOU ARE DOING
#
#### ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ ##
echo Configuring an AWS instance with the BaseSpace Developer tools

# Creating/Extracting the name of the private key
# ------------------------------------------------------------
if [[ $keyPairPath = '' ]]; then 
    keyName=$(cat /dev/urandom | tr -dc [:alpha:] |fold -w 8 | head -1)
    keyPairPath=~/.ssh/$keyName
else 
    keyName=$(basename $keyPairPath)
fi

#
# Creating and uploading a new RSA key pair or select and existing one
# I am assuming ssh-keygen exist, could be test for sake of sanity
# ------------------------------------------------------------
mkdir -p ~/.ssh

ssh-keygen -N '' -f $keyPairPath > /dev/null

kfp=$(aws ec2 import-key-pair --key-name "$keyName" \
    --public-key-material "$( cat $keyPairPath.pub )" \
    --query 'KeyFingerprint')
		
# If not successful 
if [[ -z $kfp ]]; then echo Could not upload ssh key, bailing out!; exit; fi;

#
# CREATING A SECURITY GROUP, ONLY PORT 22 WILL BE OPEN
#
### ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ ##

#
# First, define the firewall attribute in JSON, then compact it
# ------------------------------------------------------------
firewall=$(perl -lpe 's/\s+//g'  <<EOF | tr -d '\n'
[
    {
        "IpProtocol": "tcp",
        "FromPort"  : 22,
        "ToPort"    : 22,
        "IpRanges"  : [
                        { "CidrIp" : "0.0.0.0/0" }
                      ]
     }
]
EOF
)

#
# Second, create a new securiy group
# ------------------------------------------------------------
GroupId=$(aws --out text ec2 create-security-group \
              --group-name BaseSpaceDev-$RANDOM \
              --description "BaseSpaceDev initial security group" \
              --query 'GroupId')

#
# Finally, configure the security group in AWS
# ------------------------------------------------------------
aws ec2 authorize-security-group-ingress --group-id "$GroupId" --ip-permissions "$firewall"

echo Security Group successfully created

#
# CONFIGURING INSTANCES VOLUMES
# 
### ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ ##


# Setting up the volumes and their size
# Two extra volumes will be added
# the /data volume used by spacedock to dowload and store data file
# the /genomes data that normally gets an ebs volume attached with the iGenome
# In our case, it's empty and will make the dafault size fairly smaller
# to what it should be in reality
# ------------------------------------------------------------

# Creating JSON then compacting
# ------------------------------------------------------------
volumes=$(perl -lpe 's/\s+//g'  <<EOF | tr -d '\n'
[
    {
       "DeviceName" : "/dev/sda1",
       "Ebs"        : {
                         "VolumeSize" : 10,
                         "DeleteOnTermination": true
                       }
    },
    {
        "DeviceName": "/dev/sdf",
        "Ebs"      : {
                       "VolumeSize" : $data,
                       "DeleteOnTermination": $deleteOnTermination
                     }
    },
    {
        "DeviceName": "/dev/sdg",
        "Ebs"      : {
                       "VolumeSize" : $genomes,
                       "DeleteOnTermination": $deleteOnTermination
                      }
    }

]
EOF
)



#
# SPINNING OF THE INSTANCES
#
### ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ ##

echo Starting an AWS instance
## Create a new instance
instance_id=$(aws --output text ec2 run-instances \
    --image-id $ami \
    --instance-type $InstanceType \
    --key-name $keyName \
    --security-group-ids $GroupId \
    --block-device-mappings "$volumes" \
    --query 'Instances[*].InstanceId' \
    2> /dev/null)

## Testing to see of instance got created
if [[ -z $instance_id ]]; then echo Failed to spin the instance, bailing out!; fi

echo Waiting for the instance to be up and running

i=0
while state=$(aws ec2 describe-instances \
    --instance-ids $instance_id \
    --output text \
    --query 'Reservations[*].Instances[*].State.Name'); ! [ "$state" == "running" ]
do
    if [[ $i -eq 30 ]]; then echo -ne "\r"; i=0; fi;
    ((i++))
    echo -n '.'
    sleep 0.2
done

## Tagging the instance with a name
aws ec2 create-tags --resources $instance_id --tags Key=Name,Value=$instanceName
## Tagging the volumes with name
for i in  {1..2} ; do 
    volume_id=$(aws ec2 describe-instances \
        --instance-ids $instance_id \
	--output text \
        --query "Reservations[*].Instances[*].BlockDeviceMappings[$i].Ebs.VolumeId")
    if [[ "$i" = "1" ]]; then tag="instanceName data"; else tag="$instanceName genomes"; fi
    aws ec2 create-tags --resources $volume_id --tags Key=Name,Value="$tag"
done

## Recovering the public IP and publice DNS entry
ip_address=$(aws ec2 describe-instances \
             --instance-ids $instance_id \
             --output text \
             --query 'Reservations[*].Instances[*].PublicIpAddress')

dns_address=$(aws ec2 describe-instances \
              --instance-ids $instance_id \
              --output text \
              --query 'Reservations[*].Instances[*].PublicDnsName')

## Waiting for the SSH to up and running
echo
echo Waiting for the SSH server to be up and running
i=0
while ! nc -zv -w 1 $ip_address 22 2>&1 | grep -q succeeded; do
    if [[ $i -eq 15 ]]; then echo -ne "\r\033[K"; i=0; fi;
    ((i++))
    echo -n '.'
    sleep 0.2
done

#
# CONFIGURING THE INSTANCE WITH BASESPACE DEV TOOLS
#
### ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ ##
echo
echo Upgrading packages and OS then rebooting...

## Setting up the ssh process
ssh="ssh -t -i $keyPairPath -q -o StrictHostKeyChecking=no ubuntu@$ip_address"

## Updating the distro, then rebooting
$ssh /bin/bash <<EOF
sudo -i 
export DEBIAN_FRONTEND=noninteractive     
apt-get update -q
apt-get dist-upgrade -q -y
reboot
EOF

echo
echo Watiting for the AWS instance to reboot
i=0
while ! nc -zv -w 1 $ip_address 22 2>&1 | grep -q succeeded; do
    if [[ $i -eq 15 ]]; then echo -ne "\r\033[K"; i=0; fi;
    ((i++))
    echo -n '.'
    sleep 0.2
done

echo
echo The AWS instance is backonline, pushing the BaseSpace Development tools

#
# Pushing the configuration to get BaseSpace working
# ------------------------------------------------------------
$ssh /bin/bash <<EOF
## 
sudo -i
export DEBIAN_FRONTEND=noninteractive

# Create ext4 file systems
mkfs.ext4 /dev/xvdf
mkfs.ext4 /dev/xvdg

# Creating the mount points
mkdir -p /data
mkdir -p /genomes

# Adding the new volumes to the automount
echo '/dev/xvdf /data    ext4 defaults,nofail 0 2' | tee -a /etc/fstab
echo '/dev/xvdg /genomes ext4 defaults,nofail 0 2' | tee -a /etc/fstab

# Mounting the volumes
mount -a

# Adding the basepace repo to the apt-get list
echo deb http://basespace-apt.s3.amazonaws.com spacedock main | tee -a /etc/apt/sources.list
apt-get update -q 

# Installing the packages (and my favorite text editor)
apt-get install -q -y --force-yes mono-complete docker.io spacedock

# Linking the apt-get installed mono to /usr/local/bin
ln -s /usr/bin/mono /usr/local/bin/mono

# Configuring docker
echo  'DOCKER_OPTS="-d -H tcp://0.0.0.0:4243 -H unix:///var/run/docker.sock"' | tee -a /etc/default/docker.io

# Not sure what that does but seems to dowload security keys
mozroots --machine --import --sync

# Restarting docker and spacedock services
service docker.io restart
EOF

## End
echo
echo
echo "You can now log into your BaseSpace Development instance by typing the following in your terminal:"
echo ssh -i $keyPairPath ubuntu@$dns_address
