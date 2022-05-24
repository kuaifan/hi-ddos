#!/bin/bash
ROOT_PATH=$(cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd) #"/root" 
LOG_PATH=$ROOT_PATH"/logs"

TIMENOW=$(date "+%Y-%m-%d %H:%M:%S")

WHILELIST_LOCAL_FILE=$ROOT_PATH"/whilelist.txt"
WHILELIST_DOWNLOAD_URL="http://127.0.0.1/whilelist.txt"
#"http://103.25.8.3:901/whilelist.txt"
DOWNLOAD_TIMEOUT=5

BLOCKED_STORE_FILE=$ROOT_PATH"/blocking.txt"

WEBHOOK_URL="http://1.1.1.1:65535/hooks/ipreport"

mkdir -p $LOG_PATH