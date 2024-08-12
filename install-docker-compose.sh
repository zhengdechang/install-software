#!/bin/bash
CURRENT_TIME=$(date '+%Y%m%d%H%M%S')
LOG_FILE_PREFIX="log/$CURRENT_TIME"
CURRENT_DIR=$PWD
echo $CURRENT_DIR
sudo su - & cd $CURRENT_DIR
[[ ! -d log ]] && mkdir -p log
echo welcome every body
apt-get remove docker docker-engine docker.io containerd runc | tee $LOG_FILE_PREFIX.log
apt-get update | tee -a $LOG_FILE_PREFIX.log
apt-get install \
    ca-certificates \
    curl \
    gnupg \
    lsb-release -y | tee -a $LOG_FILE_PREFIX.log
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
apt-get update
apt-get install docker-ce docker-ce-cli containerd.io -y
usermod -aG docker $(whoami)
curl -L "https://github.com/docker/compose/releases/download/1.29.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose
ln -s /usr/local/bin/docker-compose /usr/bin/docker-compose
