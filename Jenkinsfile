pipeline {
    agent {
        node {
            label ''
        }
    }
    environment {
       AERA_DIR = "$WORKSPACE/git/aera-containers"
       CORTEX_DIR = "$WORKSPACE/git/cortex-external-model-factory"
       CORTEX_API = "http://dev-cortex.aeratechnology.com/aera/cortex-be/api/v1/EMS/model/update/status"
       DOCKER_REGISTRY = "nexus.aeratechnology.com:8443"
    }
    stages
    {
        stage('Clone GIT repositories') {
            parallel {
                stage ('Clone Aera Containers GIT Repo') {
                    steps {
                        sh "echo CURRENT_STAGE=\\\"${STAGE_NAME}\\\" > $WORKSPACE/variables.sh"
                        checkout([
                        $class: 'GitSCM',
                        branches: [[name: '*/master']],
                        extensions: [
                                [$class: 'RelativeTargetDirectory', relativeTargetDir: "$AERA_DIR"],
                                [$class: 'WipeWorkspace'],
                                [$class: 'LocalBranch']
                            ],
                        userRemoteConfigs: [
                            [url: 'git@bitbucket.org:aeratechnology/aera-containers.git']
                            ]
                        ])
                    }
                }
                stage ('Clone Cortex Model Factory GIT Repo'){
                    steps {
                        sh "sed -i -e 's/^CURRENT_STAGE.*/CURRENT_STAGE=\\\"${STAGE_NAME}\\\"/g' $WORKSPACE/variables.sh"
                        checkout([
                        $class: 'GitSCM',
                        branches: [[name: '*/master']],
                        extensions: [
                                [$class: 'RelativeTargetDirectory', relativeTargetDir: "$CORTEX_DIR"],
                                [$class: 'WipeWorkspace'],
                                [$class: 'LocalBranch']
                            ],
                        userRemoteConfigs: [
                            [url: 'git@bitbucket.org:aeratechnology/cortex-external-model-factory.git']
                            ]
                        ])
                    }
                }
            }
            
            
        }
        stage ('Get model ID from commit log')
        {
            steps {
                sh "sed -i -e 's/^CURRENT_STAGE.*/CURRENT_STAGE=\\\"${STAGE_NAME}\\\"/g' $WORKSPACE/variables.sh"
                sh '''
                    #!/bin/bash
                    set +x
                    cd ${CORTEX_DIR} && MODEL_ID=$(git --no-pager log  --name-only --pretty="format:" --diff-filter=AM  | egrep  ".*/" |  cut -d"/" -f1 | uniq | head -1)
                    [ -z "${MODEL_ID}" ] && echo "No models commited today" && exit 1
                    echo "MODEL_ID=$MODEL_ID" | tee -a  $WORKSPACE/variables.sh
                '''
            }
        }
        stage ('Obtain TCP port for service'){
            steps {
                sh "sed -i -e 's/^CURRENT_STAGE.*/CURRENT_STAGE=\\\"${STAGE_NAME}\\\"/g' $WORKSPACE/variables.sh"
                sh '''
                    #!/bin/bash
                    set +x
                    RANGE_BEGIN=5000
                    RANGE_END=50000
                    USED_PORTS=$(/usr/local/bin/kubectl get --all-namespaces svc -o custom-columns=SERVICE:.spec.ports[].port | grep -v "SERVICE" | sort -n | uniq)
                    for PORT_TO_CHECK in `seq $RANGE_BEGIN $RANGE_END`
                    do
                        FOUND="FALSE"
                        for PORT in $USED_PORTS 
                        do
                            if [ $PORT_TO_CHECK == $PORT ] 
                            then
                                FOUND=TRUE
                            fi
                        done
                        if [ $FOUND == "FALSE" ] 
                            then 
                                PORT_TOUSE=$PORT_TO_CHECK
                                break
                        fi
                    done
                    [ -z "${PORT_TOUSE}" ] && echo "No available ports for service in k8s cluster" && exit 1
                    echo  "PORT_TOUSE=$PORT_TOUSE" >> $WORKSPACE/variables.sh
                '''
            }
        }
        
        stage ('Build and push Docker image') {
            steps {
                sh "sed -i -e 's/^CURRENT_STAGE.*/CURRENT_STAGE=\\\"${STAGE_NAME}\\\"/g' $WORKSPACE/variables.sh"
                sh '''
                    #!/bin/bash
                    set +x
                    source $WORKSPACE/variables.sh
                    TAG=${DOCKER_REGISTRY}/cortex-containers:${MODEL_ID}
                    echo "TAG=$TAG" | tee -a $WORKSPACE/variables.sh
                    cp ${AERA_DIR}/docker/cortex-external-model-factory/Dockerfile ${CORTEX_DIR}/
                    cd ${CORTEX_DIR}
                    sed -i -e "s/MODEL_ID/$MODEL_ID/g" Dockerfile
                    /usr/local/sbin/bin/docker build -t $TAG .
                    rm -rf ${CORTEX_DIR}/Dockerfile
                '''
                withDockerRegistry(registry: [url: "https://${env.DOCKER_REGISTRY}", credentialsId: 'nexus'], toolName: 'docker-hacked') {
                    sh '''
                        #!/bin/bash
                        set +x
                        source $WORKSPACE/variables.sh
                        /usr/local/sbin/bin/docker push $TAG
                        /usr/local/sbin/bin/docker image rm -f $TAG
                        
                    '''
                    }
            }
        }
        stage ('Generate manifest and deploy to Kubernetes'){
            steps {
                sh "sed -i -e 's/^CURRENT_STAGE.*/CURRENT_STAGE=\\\"${STAGE_NAME}\\\"/g' $WORKSPACE/variables.sh"
                sh '''
                    #!/bin/bash
                    set +x
                    source $WORKSPACE/variables.sh
                    mkdir -p ${AERA_DIR}/kubernetes/deployments/cortex-external-model-factory/dev/ && cp ${AERA_DIR}/kubernetes/deployments/cortex-external-model-factory/Deployment.yaml ${AERA_DIR}/kubernetes/deployments/cortex-external-model-factory/dev/${MODEL_ID}.yaml
                    cd ${AERA_DIR}/kubernetes/deployments/cortex-external-model-factory/dev/
                    sed -i -e "s/MODEL_ID/$MODEL_ID/g" ${MODEL_ID}.yaml
                    sed -i -e "s/PORT_TOUSE/$PORT_TOUSE/g" ${MODEL_ID}.yaml
                    sed -i -e "s|TAG|$TAG|g" ${MODEL_ID}.yaml
                    git add ${MODEL_ID}.yaml
                    git commit -m "Added or modified model: ${MODEL_ID}" ${MODEL_ID}.yaml || echo "No changes to commit"
                    git push origin master
                    /usr/local/bin/kubectl apply -f ${MODEL_ID}.yaml
                '''
            }
        }
    }
    post {
        failure {
            sh """
                #!/bin/bash
                set +x
                source $WORKSPACE/variables.sh 
                echo "Pipeline failed at stage: \\"\$CURRENT_STAGE\\", publishing result to ${CORTEX_API}"
                curl -X POST ${CORTEX_API} -H 'Content-Type: application/json' -d  "{\\"status\\":\\"fail\\", \\"modelId\\":\\"\${MODEL_ID}\\", \\"message\\": \\"Pipeline failed at stage: \${CURRENT_STAGE}\\"}"
            """
        }
        success {
            sh """
                #!/bin/bash
                set +x
                source $WORKSPACE/variables.sh 
                echo "Pipeline succeeded, publishing result to ${CORTEX_API}"
                curl -X POST ${CORTEX_API} -H 'Content-Type: application/json' -d  "{\\"status\\":\\"success\\", \\"modelId\\":\\"\${MODEL_ID}\\", \\"message\\": \\"Pipeline succeeded\\"}"
            """
        }
    }
}




















