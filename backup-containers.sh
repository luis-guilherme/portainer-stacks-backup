#!/bin/bash
BACKUP_DIR="/srv/backup"
NET_BACKUP="user@host.net:/volume1/Backups/containers"
API_KEY="ptr_dsfRET43fge4g3g34G#443f34c3=="
API_ENDPOINT="https://portainer.host:9443/api"

#get date
formatted_date=$(date +%Y%m%d)
#formatted_date=$(date -d "yesterday" +%Y%m%d)

# Send a GET request to the API to retrieve the list of stacks
stacks=$(curl -k -s -X GET "${API_ENDPOINT}/stacks" -H "X-API-Key:${API_KEY}")
stack_names=$(echo "$stacks" | jq -r '.[] | .Name')
stack_ids=$(echo "$stacks" | jq -r '.[] | .Id')
stack_endpoint_ids=$(echo $stacks | jq -r '.[] | .EndpointId')

# Store the stack names in an array
IFS=$'\n' read -rd '' -a stack_name_array <<<"$stack_names"
IFS=$'\n' read -rd '' -a stack_id_array <<<"$stack_ids"
IFS=$'\n' read -rd '' -a stack_endpointid_array <<<"$stack_endpoint_ids"

for index in "${!stack_name_array[@]}"; do

    stack_name="${stack_name_array[$index]}"
    stack_id="${stack_id_array[$index]}"
    stack_endpointid="${stack_endpointid_array[$index]}"

    echo "Stopping stack: ${stack_name} with id ${stack_id} on endpoint ${stack_endpointid}"

    # Send a POST request to stop each stack
    response=$(curl -k -s -X POST -H "X-API-Key:$API_KEY" $API_ENDPOINT/stacks/$stack_id/stop?endpointId=$stack_endpointid)

    # Handle the response and check if the stack was stopped successfully
    if [[ "$response" == *"Status\":2"* ]]; then
        echo "Stack stopped successfully: $stack_name"

        echo "Backing up docker compose file"
        STACK_BACKUP_DIR="${BACKUP_DIR}/${formatted_date}/${stack_name}"
        echo "Creating backup folder ${STACK_BACKUP_DIR}"
        mkdir -p "${STACK_BACKUP_DIR}"

        curl -k -s -X GET "${API_ENDPOINT}/stacks/$stack_id/file" -H "X-API-Key:${API_KEY}" | jq -r '.StackFileContent' > ${STACK_BACKUP_DIR}/docker_compose_$stack_name.yml

        # get volumes list, remove lines that have comment "#ignore-backup", get contents before ":",  remove contents after "#" (all comments), remove starting "- " and delete empty lines
        stack_volumes=$(curl -k -s -X GET "${API_ENDPOINT}/stacks/$stack_id/file" -H "X-API-Key:${API_KEY}" | jq -r '.StackFileContent' | yq '.services[].volumes' - | grep -v "#ignore-backup" - |cut -d ":" -f 1 | cut -d "#" -f 1 | sed 's/^- //' | sed '/^$/d')
        IFS=$'\n' read -rd '' -a tmp_stack_volume_array  <<<"$stack_volumes"
        stack_volume_array=()

        for volindex in "${!tmp_stack_volume_array[@]}"; do
            volume="${tmp_stack_volume_array[$volindex]}"
            # yq returns null for services without mapped volumes
            if [[ "$volume" != "null" ]] ; then
                stack_volume_array+=("$volume")
                echo "Backing up volume ${volume}"
            fi
        done

        if [[ "${#stack_volume_array[@]}" -gt 0 ]]; then
            sudo tar -czvf "${STACK_BACKUP_DIR}/${stack_name}.tar.gz" "${stack_volume_array[@]}"
        else
            echo "No volumes to backup"
        fi
        echo "Starting stack: ${stack_name} with id ${stack_id}"

        # Send a POST request to start each stack
        response=$(curl -k -s -X POST -H "X-API-Key:$API_KEY" $API_ENDPOINT/stacks/$stack_id/start)
        # Handle the response and check if the stack was started successfully
        if [[ "$response" == *"Status\":1"* ]]; then
            echo "Stack started successfully: $stack_name"
        else
            echo "Failed to start stack: $stack_name"
           # Handle the failure case as needed
        fi

        if [[ "${#stack_volume_array[@]}" -gt 0 ]]; then
            scp -r "${BACKUP_DIR}/${formatted_date}" "${NET_BACKUP}"
            rm -rf "${BACKUP_DIR}/${formatted_date}"
        fi

    else
        echo "Failed to stop stack: $stack_name"
       # Handle the failure case as needed
    fi
done
