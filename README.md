# Project 9: Continues Delivery of Java Webapp
In project 5, I deployed a Continues Integration pipeline using Jenkins. The pipeline deployed an app that is written in Java, built and stored the artifacts on Nexus Server, Containerized the app and stored it in ECR. This project was the continuation, taking the image from ECR and deploying to ECS, Tested the project in staging and promotted it to Production. 

## Architecture
![](cd-jenkins-architecture)

## Steps
1. Branches and Webhook
Create a new branch from ci-jenkins by running this git command within the project folder
```
git checkout -b cicd-jenkins
```
For webhooks, login to the project repository in Github and goto settings -> Webhooks -> Edit webhooks, then enter the public IP of the Jenkins EC instance -> save and test connection

2. AWS IAM and ECR
Create an AWS IAM user
```
Name: cicd-jenkins
Policies: - AmazonECS_FullAccess
          - AmazonEC2ContainerRegistryFullAccess
Programatic access = true(download CSV file)
```

In ECR, create a private repository
```Name: vprofileappimg```

3. Jenkins configurations

Open Jenkins webpage, and install the following plugins
``` - Docker pipeline
    - CloudBees Docker Build and Publish
    - Amazon ECR
    - Pipeline: AWS Steps
```
Go to manage Jenkins -> Credentials -> new credentials -> kind AWS credentials
```
    ID: awscreds
    description: awscreds
    Access Key ID: <paste the access keys for jenkins IAM user created above>
    Secret Key ID: <paste the secret key for jenkins>
```
and create.

Next ssh into JenkinsServer and run the following to install awscli and docker engine

```
sudo -i
apt update && apt install awscli -y
apt-get update
apt-get install ca-certificates curl gnupg
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg
echo \
  "deb [arch="$(dpkg --print-architecture)" signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  "$(. /etc/os-release && echo "$VERSION_CODENAME")" stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update
sudo apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
```
Verify if the pipeline for project 5 is working, necessary for the next steps
![](continues integration pipeline)

4. Docker Build in Pipeline
Open VSCode, open Dockerfile, under the multistage/app folder, should contain the following code: 
```
FROM openjdk:11 AS BUILD_IMAGE
RUN apt update && apt install maven -y
RUN git clone https://github.com/devopshydclub/vprofile-project.git
RUN cd vprofile-project && git checkout docker && mvn install

FROM tomcat:9-jre11

RUN rm -rf /usr/local/tomcat/webapps/*

COPY --from=BUILD_IMAGE vprofile-project/target/vprofile-v2.war /usr/local/tomcat/webapps/ROOT.war

EXPOSE 8080
CMD ["catalina.sh", "run"]

```
Edit the stage pipeline file(StagePipeline/Jenkinsfile) and give it the following contents
```
/*def COLOR_MAP [
    'SUCCESS': 'good',
    'FAILURE': 'danger',
]*/
pipeline {
    agent any
    tools {
        maven "MAVEN3"
        jdk "OracleJDK8"
    }
    
    environment {
        SNAP_REPO = 'vprofile-snapshot'
		NEXUS_USER = 'admin'
		NEXUS_PASS = 'admin123'
		RELEASE_REPO = 'vprofile-release'
		CENTRAL_REPO = 'vpro-maven-central'
		NEXUSIP = '172.31.20.72'
		NEXUSPORT = '8081'
		NEXUS_GRP_REPO = 'vpro-maven-group'
        NEXUS_LOGIN = 'nexuslogin'
        SONARSERVER = 'sonarserver'
        SONARSCANNER = 'sonarscanner'
        registryCredential = 'ecr:us-east-1:awscreds'
        appRegistry = '997450571655.dkr.ecr.us-east-1.amazonaws.com/vprofileappimg'    
        vprofileRegistry = "https://997450571655.dkr.ecr.us-east-1.amazonaws.com/vprofileappimg"
        cluster = "vprostaging"
        service = "vproappstagesvc"
    }

    stages {
        stage('Build'){
            steps {
                sh 'mvn -s settings.xml -DskipTests install'
            }
            post {
                success {
                    echo "Now Archiving."
                    archiveArtifacts artifacts: '**/*.war'
                }
            }
        }

        stage('Test'){
            steps {
                sh 'mvn -s settings.xml test'
            }

        }

        stage('Checkstyle Analysis') {
            steps {
                sh 'mvn -s settings.xml checkstyle:checkstyle'

            }
        }

        stage('CODE ANALYSIS with SONARQUBE') {
          
		  environment {
             scannerHome = tool "${SONARSCANNER}"
          }

          steps {
            
            withSonarQubeEnv("${SONARSERVER}") {
               sh "${scannerHome}/bin/sonar-scanner -Dsonar.projectKey=vprofile \
                   -Dsonar.projectName=vprofile-repo \
                   -Dsonar.projectVersion=1.0 \
                   -Dsonar.sources=src/ \
                   -Dsonar.java.binaries=target/test-classes/com/visualpathit/account/controllerTest/ \
                   -Dsonar.junit.reportsPath=target/surefire-reports/ \
                   -Dsonar.jacoco.reportsPath=target/jacoco.exec \
                   -Dsonar.java.checkstyle.reportPaths=target/checkstyle-result.xml"
            }

            

            timeout(time: 10, unit: 'MINUTES') {
               waitForQualityGate abortPipeline: true
            }
          }
        }  

        stage("UploadArtifact"){
            steps{
                nexusArtifactUploader(
                  nexusVersion: 'nexus3',
                  protocol: 'http',
                  nexusUrl: "${NEXUSIP}:${NEXUSPORT}",
                  groupId: 'QA',
                  version: "${env.BUILD_ID}-${env.BUILD_TIMESTAMP}",
                  repository: "${RELEASE_REPO}",
                  credentialsId: "${NEXUS_LOGIN}",
                  artifacts: [
                    [artifactId: 'vproapp',
                     classifier: '',
                     file: 'target/vprofile-v2.war',
                     type: 'war']
                  ]
                )
            }
        }  

        stage('Build App Image'){
            steps {
                script {
                    dockerImage = docker.build( appRegistry + ":$BUILD_NUMBER", "./Docker-files/app/multistage/")
                }
            }
        }
        
        stage('Upload App Image') {
          steps{
            script {
              docker.withRegistry( vprofileRegistry, registryCredential ) {
                dockerImage.push("$BUILD_NUMBER")
                dockerImage.push('latest')
              }
            }
          }
        } 

        stage('Deploy to ECS staging') {
            steps {
                withAWS(credentials: 'awscreds', region: 'us-east-2') {
                    sh 'aws ecs update-service --cluster ${cluster} --service ${service} --force-new-deployment'
                } 
            }
        }
    }

    post {
        always {
            echo 'Slack Notifications'
            slackSend channel: '#jenkinscicd',
                colo: COLOR_MAP[currentBuild.currentResult],
                message: "*${currentBuild.currentResult}:* Job ${env.JOB_NAME} build ${env.BUILD_NUMBER}"
        }
    }
}

```
Make sure to modify: 
    - NEXUS_IP=private ip of NexusServer 
    - the AWS region where the project is done.
    - appRegistry = the URL of the registry(vprofileappimg) that was create in ECR
    - vprofileRegistry = the URL of the app repository

Back to Jenkins, create new pipeline:
```
name: vprofile-cicd-pipeline-docker
project type: pipeline
Project settings: 
    - BuildTriggers: Github hook trigger for GITScm polling
    - Pipeline : pipeline script from scm
                SCM: Git
                Repo url: Add the ssh url of your Github repository
                login: githublogin(saved in project 5)
                branch: cicd-jenkins
                Jenkinsfile: StagePipeline/Jenkinsfile
```

--> save and build now
![](jenkins-build-cicd-success)
![](vprofileappimg)

5. AWS ECS Setup
 - Create a cluster:
    ```
    cluster name: vprostaging
    monitoring: user container insights = true
    tags: Name=vprostaging
    ```
 - Creat a task defination
 ```
 name: vproappstagetask
 container name: vproapp
           image uri: copy the uri of the registry from where it will fetch image
           port: 8080
           CPU: 1V, memory: 2GB
 ```
 review and create

 - Create a service to use the task defination
 Click and open the created cluster, then -> services -> new service
   ```
   compute configuration: Lauch type
   task definition: vproappstagetask
   service name: vproappstagesvc
   Networking: create security group
              name: vproappstagesg
              inbout rule: all traffic from anywhere
    Load balancing:
        create new load balancer = true
        name: vproappstageelb
        listener port:80
        Targetgroup: vproappstagetg
        Healthcheck : /login
        Healthcheck grace period: 30s
   ```
   Verify and create. 
   During creation, modify the target group healthcheck under advanced options and overide healthchecks to 8080. 
   ![](healthcheck overide)

   ![](task creation success)

6. Pipeline for ECS
Verify the running container, cluster -> service -> tasks -> networking
7. Promote to Prod
8. Backup Stack



