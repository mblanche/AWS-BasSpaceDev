AWS-BasSpaceDev
===============

A script that automate the creation of an AWS instance with the tools and 
configuration to run a local SpaceDock Agent service.

- This script assume that 
  1. You have a working AWS account allowing the creation of instances
  2. You have successfully installed on your local machine the 
  AWS CLI tools available here http://docs.aws.amazon.com/cli/latest/userguide/installing.html
  3. That you have successfully configured the AWS CLI tools following the steps here http://docs.aws.amazon.com/cli/latest/userguide/cli-chap-getting-started.html

- For the intrepide:
  
  AnEC2 m3.xlarge running a vanilla Ubuntu 14.04.01 server with the SpaceDock pre-requesite can be started by running 
  the bash script:
  
  $ ./BaseSpaceDev.sh

  Just wait for the script to terminate. Then, you can copy and paste the ssh command to your terminal and will be 
  connected to you BaseSpace development server. Pasting the SpaceDock service from the BaseSpace developer pages (in your 
  Native App Form Builder tab), will start the agent that will respong to your app request.

- For the curious,
  
  Several settings can be configured in the script.
  - The instance (and volumes)  name 
  - The type of instance that will be spun
  - The size of the attached volumes
  - Whether to delete or not the attched volume on termination

- For the adventurous

  Fork me!!
     