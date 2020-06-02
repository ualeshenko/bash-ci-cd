#!/bin/bash

ENV="default"
PATH_PROJECT="/path/to/proj/source/"
PROJ="`basename ${PATH_PROJECT}`"
ALL_BRANCH=( development staging production )
REGISTRY="000000000001.dkr.ecr.zone.amazonaws.com"
REGISTRY_IMAGE="${REGISTRY}/`echo ${PROJ} | tr '[:upper:]' '[:lower:]'`:${ENV}"
URL_S3_ENV="s3://name_bucket/${PROJ}"
NAME_ENV="config.json or .env or ..."
PATH_TO_ENV="././././"
PATH_TO_DOCKERFILE="./path/to/Dockerfile"
WERCKER_GOOGLE_CHAT_NOTIFIER_URL='https://chat.googleapis.com/v1/spaces/AAAA7d-RSrg/messages_many_words_words_words_pikachu_threadKey=spaces/AAAAAAAAA/threads/0000000'

cd "${PATH_PROJECT}"

info () {
    lgreen='\033[1;32m'
    nc='\033[0m'
    printf "${lgreen}[Info] ${@}${nc}\n"
}

error () {
    lgreen='\033[1;31m'
    nc='\033[0m'
    printf "${lgreen}[Error] ${@}${nc}\n"
}

download_env () {
    aws s3 cp \ 
	    "${URL_S3_ENV}/${ENV}/${NAME_ENV}" \
	    "${PATH_TO_ENV}"
}

cleaner () {
    rm "${PATH_TO_ENV}"
}

build_app () {
    download_env || error "Failed to load environment files from AWS S3" ; exit 1

    $(aws ecr get-login --no-include-email --region us-east-1) || error "Failed login to AWS ECR" ; exit 1

    IMAGE="${PROJ}:${ENV}"

    MEMORY=$(df -h / | grep -oe ".[0-9]\%")
  
    if [ `echo ${MEMORY%*%}` -ge "90" ] ; then
        info "Space left less than ${SPACE} on device."
	docker system prune -f
    fi

    if [ -e "${PATH_TO_DOCKERFILE}" ]; then
        docker build --no-cache -t "${IMAGE}" -f "${PATH_TO_DOCKERFILE}" .
        docker tag "${IMAGE}" "${REGISTRY_IMAGE}"

	docker push "${REGISTRY_IMAGE}"
        docker rmi "${REGISTRY_IMAGE}" 2>/dev/null || true

	cleaner
    else
        error "File .ci-cd/Dockerfile not exist" ; exit 1
    fi
}

deploy_app () {
    cd "/srv/services/${ENV}"
    docker stack deploy \
            --with-registry-auth \
            --prune \
            -c docker-compose.yml `basename $(pwd)`
}

checker () {
    if [ "${ENV}" == "production" ]; then
        git checkout master
    else
        git checkout "${ENV}"
    fi

    CURRENT_COMMIT=`git rev-parse --short HEAD` && git pull > /dev/null
    NEW_COMMIT=`git rev-parse --short HEAD`

    if [ "${CURRENT_COMMIT}" == "${NEW_COMMIT}" ]; then
        info "[ `date +%d.%m.%y---%H:%M:%S` ] --- Already up to date --- `git rev-parse --abbrev-ref HEAD`" && continue
    else
        build_app && info "Success build"
    fi
}

send_notification () {
    cd "${PATH_PROJECT}"
    COMMIT=$(echo `git log -1 | tail -n 1`)
    AUTHOR=$(git log -1 | grep -oe "Author:[a-z0-9 ].*")
    TIMESTAMP=$(date +%d-%m-%Y_%H:%M:%S)    
    MESSAGE="*[${PROJ} CI/CD]*\`\`\`
             \n${TIMESTAMP}
             \n${AUTHOR}
             \n${NEW_COMMIT}
	     \n${PROJ}
             \nSTATUS --- ${STATUS}\`\`\`"

    curl -H "Content-Type: application/json" -X POST -d "{\"text\":\"$MESSAGE\"}" -s "$WERCKER_GOOGLE_CHAT_NOTIFIER_URL"

}

main () {
    for branch in "${ALL_BRANCH[@]}"; do
        ENV="${branch}"
        if [ "${ENV}" == master ]; then
            ENV="production"
        fi

        if ps aux  | grep -oe "[d]ocker build --no-cache -t ${PROJ}" ; then
            error "INFO: Pipeline <${PROJ}> has already started" ; exit 0
        else        
            checker
            deploy_app
        fi
    done
}

main |& systemd-cat -t "${PROJ}"_`date +%d_%m_%y`

