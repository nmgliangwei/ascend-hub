#!/bin/bash
# Copyright © Huawei Technologies Co., Ltd. 2024. All rights reserved.

if [[ "$#" -ne 3 ]]; then
    echo "Need param: <model_id> <listen_ip> <listen_port>"
    exit 1
fi

# remove the last '/'
#MODEL_ID=$(echo "$1" | cut -d "=" -f2 | sed "s/\/*$//g")
MODEL_ID=$1
LISTEN_IP=$2
LISTEN_PORT=$3

MODEL_DIR="/home/HwHiAiUser/model"

sleep 3

source /usr/local/Ascend/ascend-toolkit/set_env.sh
source /usr/local/Ascend/nnal/atb/set_env.sh
export LD_PRELOAD=$(ls /usr/local/lib/python3.11/site-packages/scikit_learn.libs/libgomp-*):$LD_PRELOAD
export PATH="/home/HwHiAiUser/.cargo/bin:$PATH"

if [[ -n $(id | grep uid=0) ]];then
    source /usr/local/Ascend/mxRag/script/set_env.sh
else
    source /home/HwHiAiUser/Ascend/mxRag/script/set_env.sh
fi

function check_model_exists() {
    if [[ ! -e "${MODEL_ID}/config.json" ]]; then
        echo "Model '${MODEL_ID}' does not exist."
        return 1
    else
        echo "Model '${MODEL_ID}' exists."
        return 0
    fi
}

function download_model() {
    local retry_time=1
    local max_retries=5
    echo "Downloading model '${MODEL_ID}' from modelscope ..."
    while [[ ${retry_time} -le ${max_retries} ]]; do
        if  git clone "https://www.modelscope.cn/${MODEL_ID}" "${MODEL_DIR}/${MODEL_ID##*/}" && cd "${MODEL_DIR}/${MODEL_ID##*/}" && git lfs pull; then
            echo "Download successful."
            return 0
        else
            retry_time=$((retry_time + 1))
            echo "Download failed, try again."
            sleep 5
        fi
    done
    echo "Maximum retries ${max_retries} reached. Download failed."
    return 1
}

function start_tei_service() {
    if [[ -z ${TEI_NPU_DEVICE} ]]; then
        export TEI_NPU_DEVICE=0
        echo "run on device 0"
    fi
    echo "Starting TEI service on ${LISTEN_IP}:${LISTEN_PORT}..."
    #cd "${MODEL_DIR}"
    text-embeddings-router \
      --model-id "${MODEL_ID}" \
      --port "${LISTEN_PORT}" \
      --hostname "${LISTEN_IP}"
}

function main() {
    if ! check_model_exists; then
        #if ! download_model; then
        #    echo "Download model ${MODEL_ID} failed"
        #    exit 1
        #fi
        echo "check ${MODEL_ID} failed"
    fi

    start_tei_service
}

main
