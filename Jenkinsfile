pipeline {
    agent any
    
    tools {
        terraform 'Terraform' // Use the name configured in Global Tool Configuration
    }
    
    environment {
        AWS_ACCESS_KEY_ID     = credentials('aws-access-key-id')
        AWS_SECRET_ACCESS_KEY = credentials('aws-secret-access-key')
        AWS_DEFAULT_REGION    = 'us-east-1'
        CONFIG_DIR = 'config'
        SCRIPTS_DIR = 'scripts'
        VENV_PATH = "${WORKSPACE}/venv"
    }
    
    parameters {
        choice(name: 'DEPLOYMENT_MODE', choices: ['all', 'single'], description: 'Deploy all config files or a single one')
        string(name: 'CONFIG_FILE', defaultValue: 'tst2_feature_flags.json', description: 'Name of the feature flags JSON file (used only when DEPLOYMENT_MODE is "single")')
        booleanParam(name: 'MERGE_CONFIGS', defaultValue: true, description: 'Merge with existing AppConfig instead of overwriting')
    }
    
    stages {
        stage('Checkout') {
            steps {
                checkout scm
            }
        }
        
        stage('Setup') {
            steps {
                script {
                    env.BRANCH_NAME = 'dev'
                    env.CONFIG_VERSION = 1
                    
                    // Make the merge script executable if it exists
                    sh "chmod +x ${env.SCRIPTS_DIR}/merge_appconfig.py || echo 'Script not found, will be created later'"
                    
                    // Install required Python packages
	                sh '''
	                    
	                    # Install python3-full and python3-venv (if possible)
	                    apt-get update -y && apt-get install -y python3-full python3-venv || true

	                    echo "Checking Python installation..."
	                    python3 --version
	                    
	                    # Create a virtual environment
	                    echo "Creating virtual environment at ${VENV_PATH}"
	                    python3 -m venv ${VENV_PATH}
	                    
	                    # Activate virtual environment and install dependencies
	                    . ${VENV_PATH}/bin/activate
	                    pip install --upgrade pip
	                    pip install boto3
	                    
	                    # Verify installations
	                    pip list | grep boto3
	                '''
                    
                    // Determine which config files to process
                    if (params.DEPLOYMENT_MODE == 'all') {
                        // Find all JSON files in the config directory
                        def configFiles = sh(script: "find ${env.CONFIG_DIR} -name \"*.json\" -type f || echo \"\"", returnStdout: true).trim()
                        
                        if (configFiles) {
                            env.CONFIG_FILES = configFiles.split("\n").join(",")
                            echo "Found config files: ${env.CONFIG_FILES}"
                        } else {
                            echo "No JSON files found in ${env.CONFIG_DIR}"
                            env.CONFIG_FILES = "${env.CONFIG_DIR}/${params.CONFIG_FILE}" // Default to the param
                            echo "Defaulting to: ${env.CONFIG_FILES}"
                        }
                    } else {
                        // Use the single specified config file
                        env.CONFIG_FILES = "${env.CONFIG_DIR}/${params.CONFIG_FILE}"
                        echo "Using single config file: ${env.CONFIG_FILES}"
                    }
                    
                    // Verify config files exist
                    def configFilesExist = sh(script: "for f in \$(echo ${env.CONFIG_FILES} | tr ',' ' '); do if [ ! -f \"\$f\" ]; then echo \"\$f does not exist\"; exit 1; fi; done", returnStatus: true)
                    if (configFilesExist != 0) {
                        error "One or more configuration files do not exist."
                    }
                }
            }
        }
        
		stage('Prepare Merged Configs') {
		    when {
		        expression { return params.MERGE_CONFIGS }
		    }
		    steps {
		        script {
		            def configFiles = env.CONFIG_FILES.split(",")
		            
		            configFiles.each { configFilePath ->
		                def configFileName = configFilePath.trim().split("/")[-1]
		                def configNameWithoutExt = configFileName.replaceAll("\\.[jJ][sS][oO][nN]\$", "")
		                
		                echo "Preparing merged configuration for: ${configNameWithoutExt}"
		                
		                // Run the Python script for each config file to create merged files
		                // The script will now automatically preserve existing values and metadata
		                sh """
		                    # Activate virtual environment
		                    . ${env.VENV_PATH}/bin/activate
		                    
		                    # Run the merge script
		                    python3 ${env.SCRIPTS_DIR}/merge_appconfig.py \
		                        --config-file ${configFilePath} \
		                        --app-name ${configNameWithoutExt} \
		                        --env-name ${env.BRANCH_NAME} \
		                        --profile-name ${configNameWithoutExt} \
		                        --debug \
		                        --force-create
		                """
		            }
		        }
		    }
		}
        
        stage('Initialize Terraform') {
            steps {
                dir('terraform') {
                    sh 'terraform init -reconfigure'
                }
            }
        }
        
        stage('Process Config Files') {
            steps {
                script {
                    def configFiles = env.CONFIG_FILES.split(",")
                    
                    // Debug the config files
                    echo "Config files to process: ${configFiles}"
                    
                    // Create a map to store Terraform variables
                    def tfVars = [:]
                    tfVars.put("environment", env.BRANCH_NAME)
                    tfVars.put("config_version", env.CONFIG_VERSION)
                    
                    // Add config files information to variables
                    tfVars.put("config_file_count", configFiles.size())
                    
                    def configFileNames = []
                    def configFilePaths = []
                    
                    configFiles.eachWithIndex { configFilePath, index ->
                        def configFileName = configFilePath.trim().split("/")[-1]
                        def configNameWithoutExt = configFileName.replaceAll("\\.[jJ][sS][oO][nN]\$", "")
                        
                        echo "Processing config file ${index + 1}: ${configFileName}"
                        
                        // Add to arrays for Terraform
                        configFileNames.add(configNameWithoutExt)
                        // Adjust the path to be relative to the terraform directory
                        configFilePaths.add("../" + configFilePath.trim())
                    }
                    
                    // Add arrays to Terraform vars
                    tfVars.put("config_file_names", configFileNames)
                    tfVars.put("config_file_paths", configFilePaths)
                    
                    // Debug the Terraform variables
                    echo "Terraform variables to be written: ${tfVars}"
                    
                    // Write all variables to a file for Terraform to use
                    def tfVarsContent = groovy.json.JsonOutput.toJson(tfVars)
                    writeFile file: "terraform/terraform.tfvars.json", text: tfVarsContent
                    
                    echo "Created Terraform variables file with ${configFiles.size()} config files"
                }
            }
        }
        
        stage('Terraform Plan') {
            steps {
                dir('terraform') {
                    sh 'terraform plan -var-file=terraform.tfvars.json -out=tfplan'
                }
            }
        }
        
        stage('Terraform Apply') {
            steps {
                dir('terraform') {
                    sh 'terraform apply -auto-approve tfplan'
                }
            }
        }
    }
    
    post {
        success {
            echo "AWS AppConfig infrastructure setup completed successfully!"
            echo "Note: Configuration versions have been created but not deployed. Use Angular UI to deploy them."
        }
        failure {
            echo "AWS AppConfig infrastructure setup failed!"
        }
        always {
            // Clean up workspace
            cleanWs()
        }
    }
}