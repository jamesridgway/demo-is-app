node {
    stage("Clone repository") {
        checkout scm
    }
    stage('Build') {
        sh './build/build.sh'
    }
    stage('Deploy') {
        sh './build/deploy.sh'
    }
}