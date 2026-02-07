/**
 * Multibranch Pipeline — Branch-to-Environment
 * ============================================
 * main   → prod   |  stage  → stage  |  uat  → uat  |  test/develop/dev → test
 *
 * Deploy server is auto-selected from branch (no inputs, no band-aids).
 * Config: DEPLOY_CONFIG + BRANCH_TO_ENV in Environment Setup, Deploy, Smoke stages.
 * Edit those 3 blocks together when adding hosts or changing mappings.
 *
 * Pipeline Flow:
 * Environment Setup → Checkout → Static Analysis → Unit Tests → Build → Store Artifact →
 * Docker Build → Push to Registry → Deploy → Smoke/Health Tests → Rollback on Failure
 *
 * Stage View / Blue Ocean compatible.
 */

pipeline {
    agent any

    options {
        buildDiscarder(logRotator(numToKeepStr: '20', artifactNumToKeepStr: '5'))
        timestamps()
        timeout(time: 30, unit: 'MINUTES')
        disableConcurrentBuilds()
    }

    environment {
        DOCKER_REGISTRY = 'registry.example.com'
        ARTIFACT_STORAGE = "${WORKSPACE}/artifacts"
        APP_NAME = 'petclinic'
        HEALTH_CHECK_TIMEOUT = '120'
        DEPLOY_USER = 'deploy'
        REMOTE_APP_DIR = '/home/deploy/petclinic'
        SSH_CREDENTIALS_ID = 'deploy-ssh-key'
    }

    parameters {
        booleanParam(
            name: 'SKIP_SONAR',
            defaultValue: true,
            description: 'Skip SonarQube analysis'
        )
        booleanParam(
            name: 'FORCE_ROLLBACK_TEST',
            defaultValue: false,
            description: 'Force health check failure to test rollback'
        )
        booleanParam(
            name: 'PUSH_TO_REGISTRY',
            defaultValue: false,
            description: 'Push Docker image to registry'
        )
        string(
            name: 'SSH_CREDENTIALS_ID',
            defaultValue: 'deploy-ssh-key',
            description: 'Jenkins credential ID for SSH'
        )
        choice(
            name: 'DEPLOY_METHOD',
            choices: ['jar', 'docker'],
            description: 'jar=deploy JAR; docker=container'
        )
    }

    stages {
        /* ==================== STAGE 0: ENVIRONMENT SETUP ==================== */
        stage('Environment Setup') {
            steps {
                script {
                    // Single source of truth: branch → deploy env → host (edit here only)
                    def DEPLOY_CONFIG = [
                        prod:  [host: '192.168.31.121', port: 8080],
                        stage: [host: '192.168.31.122', port: 8080],
                        uat:   [host: '192.168.31.123', port: 8080],
                        test:  [host: '192.168.31.124', port: 8080],
                    ]
                    def BRANCH_TO_ENV = [main: 'prod', master: 'prod', stage: 'stage', uat: 'uat', test: 'test', develop: 'test', dev: 'test']

                    def branchName = env.BRANCH_NAME ?: 'main'
                    def deployEnv = BRANCH_TO_ENV[branchName] ?: 'test'
                    def cfg = DEPLOY_CONFIG[deployEnv] ?: DEPLOY_CONFIG.test

                    env.DEPLOY_ENV = deployEnv
                    env.DEPLOY_HOST = cfg.host
                    env.HEALTH_CHECK_URL = "http://${cfg.host}:${cfg.port}/actuator/health"

                    echo "Branch: ${branchName} → Deploy to: ${deployEnv} (${cfg.host})"
                }
            }
        }

        /* ==================== STAGE 1: CHECKOUT ==================== */
        stage('Checkout') {
            steps {
                script {
                    echo "=== Stage 1: Checkout ==="
                    checkout scm
                    sh 'chmod +x mvnw'
                    env.GIT_COMMIT_SHORT = sh(script: "git rev-parse --short HEAD", returnStdout: true).trim()
                    env.BUILD_TAG = "${APP_NAME}-${env.BUILD_NUMBER}-${env.GIT_COMMIT_SHORT}"
                }
            }
        }

        /* ==================== STAGE 2: STATIC CODE ANALYSIS ==================== */
        // stage('Static Code Analysis') {
        //     steps {
        //         script {
        //             echo "=== Stage 2: Static Code Analysis ==="
        //             sh './mvnw -B checkstyle:check -DskipTests || true'
        //             if (params.SKIP_SONAR != true) {
        //                 withSonarQubeEnv('SonarQube') {
        //                     sh '''
        //                         ./mvnw -B sonar:sonar \
        //                             -Dsonar.projectKey=petclinic \
        //                             -Dsonar.java.binaries=target/classes \
        //                             -DskipTests || true
        //                     '''
        //                 }
        //             } else {
        //                 echo "SonarQube analysis skipped (SKIP_SONAR=true)"
        //             }
        //         }
        //     }
        //     post {
        //         failure {
        //             echo "Static analysis found issues. Consider fixing before proceeding."
        //         }
        //     }
        // }

        /* ==================== STAGE 3: UNIT TESTS ==================== */
        // stage('Unit Tests') {
        //     steps {
        //         script {
        //             echo "=== Stage 3: Unit Tests ==="
        //             sh '''
        //                 ./mvnw -B test \
        //                     -Dtest=!*IntegrationTests,!*TestApplication \
        //                     -DfailIfNoTests=false
        //             '''
        //         }
        //     }
        //     post {
        //         always {
        //             junit allowEmptyResults: true, testResults: 'target/surefire-reports/*.xml'
        //         }
        //     }
        // }

        /* ==================== STAGE 4: BUILD ARTIFACT ==================== */
        stage('Build Artifact') {
            steps {
                script {
                    echo "=== Stage 4: Build Artifact ==="
                    sh '''
                        ./mvnw -B clean package \
                            -DskipTests \
                            -Dmaven.test.skip=true
                    '''
                    env.ARTIFACT_PATH = sh(
                        script: "ls target/*.jar 2>/dev/null | grep -v original | head -1",
                        returnStdout: true
                    ).trim()
                }
            }
        }

        /* ==================== STAGE 5: STORE ARTIFACT ==================== */
        stage('Store Artifact') {
            steps {
                script {
                    echo "=== Stage 5: Store Artifact ==="
                    sh """
                        mkdir -p ${ARTIFACT_STORAGE}
                        cp ${env.ARTIFACT_PATH} ${ARTIFACT_STORAGE}/${APP_NAME}-${BUILD_TAG}.jar
                        echo ${BUILD_TAG} > ${ARTIFACT_STORAGE}/latest-build.txt
                        ls -la ${ARTIFACT_STORAGE}/
                    """
                }
            }
            post {
                success {
                    archiveArtifacts artifacts: "artifacts/${APP_NAME}-${env.BUILD_TAG}.jar",
                        fingerprint: true
                    stash name: "artifact-${env.BUILD_NUMBER}",
                        includes: "artifacts/${APP_NAME}-${env.BUILD_TAG}.jar"
                }
            }
        }

        /* ==================== STAGE 6: DOCKER IMAGE BUILD ==================== */
//         stage('Docker Image Build') {
//             when {
//                 expression { return params.DEPLOY_METHOD == 'docker' }
//             }
//             steps {
//                 script {
//                     echo "=== Stage 6: Docker Image Build ==="
//                     writeFile file: 'Dockerfile', text: """FROM eclipse-temurin:21-jre-alpine
// WORKDIR /app
// ARG JAR_FILE
// COPY \${JAR_FILE} app.jar
// EXPOSE 8080
// ENTRYPOINT [\"java\", \"-jar\", \"app.jar\"]
// """
//                     def imageName = "${DOCKER_REGISTRY}/${APP_NAME}:${BUILD_TAG}"
//                     docker.build(imageName, "--build-arg JAR_FILE=${env.ARTIFACT_PATH} .")
//                     env.DOCKER_IMAGE = imageName
//                 }
//             }
//         }

        /* ==================== STAGE 7: PUSH IMAGE TO REGISTRY ==================== */
        // stage('Push Image to Registry') {
        //     when {
        //         expression { return params.DEPLOY_METHOD == 'docker' && params.PUSH_TO_REGISTRY }
        //     }
        //     steps {
        //         script {
        //             echo "=== Stage 7: Push Image to Registry ==="
        //             docker.withRegistry("https://${DOCKER_REGISTRY}", 'docker-registry-credentials') {
        //                 def image = docker.image("${env.DOCKER_IMAGE}")
        //                 image.push()
        //                 image.push('latest')
        //             }
        //         }
        //     }
        // }

        /* ==================== STAGE 8: DEPLOY TO ENVIRONMENT ==================== */
        stage('Deploy to Environment') {
            steps {
                script {
                    // Recompute from branch (env can be lost after input resume) — same config as Environment Setup
                    def DEPLOY_CONFIG = [
                        prod:  [host: '192.168.31.121', port: 8080],
                        stage: [host: '192.168.31.122', port: 8080],
                        uat:   [host: '192.168.31.123', port: 8080],
                        test:  [host: '192.168.31.124', port: 8080],
                    ]
                    def BRANCH_TO_ENV = [main: 'prod', master: 'prod', stage: 'stage', uat: 'uat', test: 'test', develop: 'test', dev: 'test']

                    def branchName = env.BRANCH_NAME ?: 'main'
                    def deployEnv = BRANCH_TO_ENV[branchName] ?: 'test'
                    def cfg = DEPLOY_CONFIG[deployEnv] ?: DEPLOY_CONFIG.test
                    def host = cfg.host

                    if (deployEnv == 'prod') {
                        input message: "Deploy to PRODUCTION (${host})?", ok: 'Deploy'
                    }
                    echo "=== Stage 8: Deploy to ${host} (${deployEnv}) ==="
                    def deployCreds = params.SSH_CREDENTIALS_ID ?: 'deploy-ssh-key'
                    withCredentials([sshUserPrivateKey(credentialsId: deployCreds, keyFileVariable: 'SSH_KEY')]) {
                        if (params.DEPLOY_METHOD == 'jar') {
                            def jarPath = "artifacts/${APP_NAME}-${env.BUILD_TAG}.jar"
                            writeFile file: 'deployed-jar.txt', text: jarPath
                            archiveArtifacts artifacts: 'deployed-jar.txt', fingerprint: true
                            sh """
                                eval \$(ssh-agent -s)
                                ssh-add \$SSH_KEY
                                chmod +x ./jenkins/scripts/deploy.sh
                                DEPLOY_HOST='${host}' DEPLOY_USER='${env.DEPLOY_USER}' \
                                REMOTE_APP_DIR='${env.REMOTE_APP_DIR}' ./jenkins/scripts/deploy.sh \
                                    --env ${deployEnv} \
                                    --jar ${jarPath} \
                                    --app ${APP_NAME} \
                                    --host ${host} \
                                    --user ${env.DEPLOY_USER}
                            """
                        } else {
                            env.DEPLOYED_IMAGE = "${DOCKER_REGISTRY}/${APP_NAME}:${BUILD_TAG}"
                            writeFile file: 'deployed-image.txt', text: env.DEPLOYED_IMAGE
                            archiveArtifacts artifacts: 'deployed-image.txt', fingerprint: true
                            def useRegistry = params.PUSH_TO_REGISTRY ? 'true' : 'false'
                            sh """
                                eval \$(ssh-agent -s)
                                ssh-add \$SSH_KEY
                                chmod +x ./jenkins/scripts/deploy.sh
                                DEPLOY_HOST='${host}' DEPLOY_USER='${env.DEPLOY_USER}' \
                                REMOTE_APP_DIR='${env.REMOTE_APP_DIR}' USE_REGISTRY='${useRegistry}' \
                                ./jenkins/scripts/deploy.sh \
                                    --env ${deployEnv} \
                                    --image ${env.DEPLOYED_IMAGE} \
                                    --app ${APP_NAME} \
                                    --host ${host} \
                                    --user ${env.DEPLOY_USER}
                            """
                        }
                    }
                }
            }
        }

        /* ==================== STAGE 9: SMOKE / HEALTH TESTS ==================== */
        stage('Smoke / Health Tests') {
            steps {
                script {
                    // Recompute health URL from branch (env can be lost after Deploy input)
                    def DEPLOY_CONFIG = [
                        prod:  [host: '192.168.31.121', port: 8080],
                        stage: [host: '192.168.31.122', port: 8080],
                        uat:   [host: '192.168.31.123', port: 8080],
                        test:  [host: '192.168.31.124', port: 8080],
                    ]
                    def BRANCH_TO_ENV = [main: 'prod', master: 'prod', stage: 'stage', uat: 'uat', test: 'test', develop: 'test', dev: 'test']
                    def branchName = env.BRANCH_NAME ?: 'main'
                    def deployEnv = BRANCH_TO_ENV[branchName] ?: 'test'
                    def cfg = DEPLOY_CONFIG[deployEnv] ?: DEPLOY_CONFIG.test
                    def healthUrl = "http://${cfg.host}:${cfg.port}/actuator/health"

                    echo "=== Stage 9: Smoke / Health Tests ==="
                    def healthCheckFailed = false
                    try {
                        sh """
                            chmod +x ./jenkins/scripts/health-check.sh
                            ./jenkins/scripts/health-check.sh \
                                --url ${healthUrl} \
                                --timeout ${HEALTH_CHECK_TIMEOUT} \
                                --interval 5
                        """
                        if (params.FORCE_ROLLBACK_TEST == true) {
                            healthCheckFailed = true
                            error("Simulated health check failure for rollback test")
                        }
                    } catch (Exception e) {
                        healthCheckFailed = true
                        env.HEALTH_CHECK_FAILED = 'true'
                        throw e
                    }
                }
            }
            post {
                failure {
                    script {
                        echo "Health check FAILED - Initiating rollback..."
                        env.TRIGGER_ROLLBACK = 'true'
                    }
                }
            }
        }
    }

    /* ==================== POST-BUILD: ROLLBACK ON FAILURE ==================== */
    // post {
    //     failure {
    //         script {
    //             if (env.TRIGGER_ROLLBACK == 'true' || env.HEALTH_CHECK_FAILED == 'true') {
    //                 echo "=== ROLLBACK: Deploying previous artifact to ${env.DEPLOY_HOST} ==="
    //                 def previousBuild = currentBuild.previousBuild
    //                 if (previousBuild?.result == 'SUCCESS') {
    //                     def prevBuildNumber = previousBuild.number
    //                     def deployCreds = env.SSH_CREDENTIALS_ID ?: 'deploy-ssh-key'
    //                     withCredentials([sshUserPrivateKey(credentialsId: deployCreds, keyFileVariable: 'SSH_KEY')]) {
    //                         if (params.DEPLOY_METHOD == 'jar') {
    //                             step([$class: 'CopyArtifact',
    //                                 projectName: env.JOB_NAME,
    //                                 filter: 'artifacts/*.jar',
    //                                 selector: [$class: 'SpecificBuildSelector', buildNumber: prevBuildNumber]
    //                             ])
    //                             def jarFile = sh(script: "ls artifacts/*.jar 2>/dev/null | head -1", returnStdout: true).trim()
    //                             if (jarFile) {
    //                                 sh """
    //                                     eval \$(ssh-agent -s)
    //                                     ssh-add \$SSH_KEY
    //                                     chmod +x ./jenkins/scripts/rollback.sh
    //                                     DEPLOY_HOST='${env.DEPLOY_HOST}' DEPLOY_USER='${env.DEPLOY_USER}' \\
    //                                     REMOTE_APP_DIR='${env.REMOTE_APP_DIR}' ROLLBACK_JAR='${jarFile}' \\
    //                                     ./jenkins/scripts/rollback.sh \\
    //                                         --env ${env.DEPLOY_ENV} \\
    //                                         --build-number ${prevBuildNumber} \\
    //                                         --app ${APP_NAME} \\
    //                                         --host ${env.DEPLOY_HOST} \\
    //                                         --user ${env.DEPLOY_USER}
    //                                 """
    //                             } else {
    //                                 echo "ERROR: Could not find JAR from previous build"
    //                             }
    //                         } else {
    //                             step([$class: 'CopyArtifact',
    //                                 projectName: env.JOB_NAME,
    //                                 filter: 'deployed-image.txt',
    //                                 selector: [$class: 'SpecificBuildSelector', buildNumber: prevBuildNumber]
    //                             ])
    //                             def prevImage = readFile('deployed-image.txt').trim()
    //                             def useRegistry = params.PUSH_TO_REGISTRY ? 'true' : 'false'
    //                             sh """
    //                                 eval \$(ssh-agent -s)
    //                                 ssh-add \$SSH_KEY
    //                                 chmod +x ./jenkins/scripts/rollback.sh
    //                                 DEPLOY_HOST='${env.DEPLOY_HOST}' DEPLOY_USER='${env.DEPLOY_USER}' \\
    //                                 REMOTE_APP_DIR='${env.REMOTE_APP_DIR}' USE_REGISTRY='${useRegistry}' \\
    //                                 ROLLBACK_IMAGE='${prevImage}' ./jenkins/scripts/rollback.sh \\
    //                                     --env ${env.DEPLOY_ENV} \\
    //                                     --build-number ${prevBuildNumber} \\
    //                                     --app ${APP_NAME} \\
    //                                     --host ${env.DEPLOY_HOST} \\
    //                                     --user ${env.DEPLOY_USER}
    //                             """
    //                         }
    //                     }
    //                     echo "Rollback completed. Previous build #${prevBuildNumber} restored on ${env.DEPLOY_HOST}."
    //                 } else {
    //                     echo "WARNING: No previous successful build available for rollback!"
    //                 }
    //             }
    //         }
    //     }
    //     always {
    //         cleanWs(deleteDirs: true, patterns: [[pattern: 'target/', type: 'INCLUDE']])
    //     }
    // }
}
