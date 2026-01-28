#!/bin/bash
# Copyright © Huawei Technologies Co., Ltd. 2024. All rights reserved.

if [[ "$#" -ne 3 ]]; then
    echo "Need param: <model_id> <listen_ip> <listen_port>"
    exit 1
fi

MODEL_ID=$1
LISTEN_IP=$2
LISTEN_PORT=$3
MODEL_DIR=$4
SERVED_MODEL_NAME=$5
MODEL_NAME=$(echo ${MODEL_ID} | cut -d'/' -f2)
MODEL_MEMORY_LIMIT=2048
SUPPORT_MODELS=("BAAI/bge-large-zh-v1.5")

sleep 3

source /usr/local/Ascend/ascend-toolkit/set_env.sh
source /usr/local/Ascend/nnal/atb/set_env.sh
export LD_PRELOAD=$(ls /usr/local/lib/python3.11/dist-packages/scikit_learn.libs/libgomp-*):$LD_PRELOAD
export PATH="/home/HwHiAiUser/.cargo/bin:$PATH"

if [[ -n $(id | grep uid=0) ]];then
    source /usr/local/Ascend/mxRag/script/set_env.sh
else
    source /home/HwHiAiUser/Ascend/mxRag/script/set_env.sh
fi

function check_model_support() {
    if [[ "${SUPPORT_MODELS[*]}" =~ ${MODEL_NAME} ]]; then
        echo "Support model $MODEL_NAME."
        return 0
    else
        echo "$MODEL_NAME dose not support."
        return 1
    fi
}

function check_model_exists() {
    if [[ ! -e "${MODEL_DIR}/${MODEL_ID##*/}/config.json" ]]; then
        echo "Model '${MODEL_DIR}/${MODEL_ID##*/}' does not exist."
        return 1
    else
        echo "Model '${MODEL_DIR}/${MODEL_ID##*/}' exists."
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
        if ! select_device; then
            echo "Available device not found"
            exit 1
        fi
    fi
    echo "Starting TEI service on ${LISTEN_IP}:${LISTEN_PORT}..."
    text-embeddings-router \
      --model-id "${MODEL_DIR}/${MODEL_ID##*/}" \
      --port "${LISTEN_PORT}" \
      --hostname "${LISTEN_IP}" \
      --served-model-name "{$SERVED_MODEL_NAME}"
}

function select_device() {
    echo "test npu-smi info"
    npu-smi info
    ret=$?
    if [[ $ret -ne 0 ]]; then
        echo "test npu-smi info failed"
        return 1
    fi


    while IFS=' ' read -r npu_id chip_id chip_logic_id; do
        if [[ $chip_logic_id =~ ^[0-9]+$ ]]; then
            local memory_type="DDR"
            chip_type=$(npu-smi info -t board -i "$npu_id" -c "$chip_id" | awk -F ":" '/Chip Name/ {print $2}' | sed 's/^[ \t]*//')
            if [[ $chip_type =~ ^910 ]]; then
                memory_type="HBM"
            fi
            local total_capacity
            local usage_rate
            local avail_capacity
            total_capacity=$(npu-smi info -t usages -i "$npu_id" -c "$chip_id" | grep "$memory_type Capacity(MB)" | cut -d ":" -f 2 | sed 's/^[ \t]*//')
            usage_rate=$(npu-smi info -t usages -i "$npu_id" -c "$chip_id" | grep "$memory_type Usage Rate(%)" | cut -d ":" -f 2 | sed 's/^[ \t]*//')
            avail_capacity=$(awk "BEGIN {printf \"%d\", $total_capacity - $total_capacity * ($usage_rate / 100)}")
            echo "NPU_ID: $npu_id, CHIP_ID: $chip_id， CHIP_LOGIC_ID: $chip_logic_id CHIP_TYPE: $chip_type, MEMORY_TYPE: $memory_type, CAPACITY: $total_capacity, USAGE_RATE: $usage_rate, AVAIL_CAPACITY: $avail_capacity"
            if [[ $avail_capacity -gt $MODEL_MEMORY_LIMIT ]]; then
                export TEI_NPU_DEVICE="$chip_logic_id"
                echo "Using NPU: $chip_logic_id start TEI service"
                return 0
            fi
        fi
    done <<< "$(npu-smi info -m | awk 'NR>1 {print $1, $2, $3}')"
    return 1
}

function main() {
:<<!
    if ! check_model_support; then
        echo "Check '<model_id>' failed"
        exit 1
    fi
!
    if ! check_model_exists; then
        if ! download_model; then
            echo "Download model ${MODEL_ID} failed"
            exit 1
        fi
    fi

    start_tei_service
}

main
