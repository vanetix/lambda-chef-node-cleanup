# Automatically Delete Terminated Instances in Chef Server with AWS Lambda
Using CloudWatch Events, when an instance is terminated a Lambda function is triggered that will remove the node from Chef server for you.

For this example, we'll use Lambda, CloudWatch Events, and AWS KMS.

## Details
When an instance terminates, CloudWatch events will pass a JSON object containing the Instance ID to a Lambda function.  The JSON object does not contain any other identifying information of the instance, such as DNS name or Public IP Address.  Additionally, since the instance is now in a terminated state we cannot query any other identifying information about the instance.  This is important to understand because it effects how we must query for the node in Chef Server in order to delete it automatically.

The Lambda function then communicates with the Chef Server using a request hashed with a valid private key of a valid Chef Server user with appropriate permissions.  The Lambda expects an AWS KMS encrypted version of the private key which it will decrypt on the fly to sign all requests to the Chef Server.  The Lambda then makes a request to find a matching node in the Chef Server and finally a request to delete that node.

# WARNING: PyChef is Modified Outside of the Official Release
The version [PyChef](https://github.com/coderanger/pychef) included is 0.2.3 and does not support Amazon Linux.  To fix this, `rsa.py` in PyChef inside this repository is modified to allow it function on Amazon Linux as this is the underlying OS for Lambda functions.  `rsa.py` is modified to use the correct libcrypto library: `libcrypto.so` to `libcrypto.so.10`.

An open Pull Request will solve this better:  https://github.com/coderanger/pychef/pull/49

# Prerequisites
## Terraform
Install [Terraform](https://www.terraform.io)
## Deploying the Lambda Function
This example uses [Apex](https://github.com/apex/apex) to deploy and version the Lambda function, but as long as you zip everything up in the `node_cleanup` directory you should be good to go.  You'll also want to delete the `local-exec` provisioner for `apex deploy` in the `terraform/main.tf` file if you aren't using Apex.
## KMS
Chef Server uses public key encryption to authenticate API requests.  This requires the client to hash the requests using a valid private key.  With this example, we'll use KMS to store an encrypted copy of our private key and then decrypt it on the fly with the Lambda function.

1. Create a Key in KMS.
* Store the encrypted certificate in KMS using the AWS CLI tools:  `aws kms encrypt --key-id KEY_FROM_STEP_1 --plaintext file://your_private_key.pem`
* You will receive a JSON response with a CiphertextBlob if successful.  Copy this CiphertextBlob into a new file called `encrypted_pem.txt` and store it in the same directory as the Lambda function (required so it can be packaged up with the function itself).
* If you will use the supplied Terraform example in this repository you do not need to add a Key User yet.  If you are following this as a reference and already have an IAM role for your Lambda function you can add it now as a Key User.

## Lambda Function
Modify the `CHEF_SERVER_URL` and `USERNAME` variables as appropriate in `lambda/functions/node_cleanup/main.py`.

## Chef Server Permissions
The user making the request needs the appropriate permissions in Chef Server to query and delete nodes.  As described above, you'll need access to the private key for this user.

## Chef Nodes
The Lambda function is expecting that all nodes/instances managed by Chef have an attribute called `ec2_instance_id` with a value of the EC2 Instance ID (e.g. i-abcde123).  If this attribute is not present or not populated properly the function will not delete the node.

### Some Alternatives to the ec2_instance_id Attribute
Remember, CloudWatch Events will give us the Instance ID when an instance is terminated, but at that point other distinguishing information, like FQDN and IP Address, are already gone.  Using the Instance ID as an attribute or as a node name are probably the most convenient options, but they are not the only options.

#### Naming Nodes with the Instance ID
Instead of using an attribute, a simple alternative would be to name all nodes using their Instance ID.  Then you can modify the Lambda function to just fetch the Node by name instead of using "Search".
```
node = Node('instance-id')
node.delete()
```

#### AWS Config
If you prefer to not explicitly name your nodes and you do not want to include an attribute, another option is to let Chef use the fully qualified domain name (FQDN) of the instance as the node name (I believe this is the default behavior if you don't assign a name to a node during bootstrapping).  You can then query AWS Config in the Lambda function to retrieve the PrivateDNSName attribute and reconstruct the FQDN as it is a known pattern (ip-172-31-23-14.us-west-2.compute.internal).  Like above, you can then simply change the Lambda function to query for the node directly.

# Using This Example
Assuming the above Prerequisites section was followed, simply run `terraform apply terraform` from the parent directory.  This will create all the infrastructure resources required and deploy the Lambda function using Apex.  If you aren't using Apex you can comment out the provisioner in `terraform/main.tf`.

After running Terraform, you will need to manually add the IAM Role created as a Key User for the KMS Key you created earlier.  You can do this by using the console and adding the role name that was printed to the screen as output from Terraform ("chef_node_cleanup_lambda", by default).

# Destroying
To cleanup:
1. `apex delete -C lambda/`
* `terraform destroy terraform`

# License
Copyright 2016 Amazon.com, Inc. or its affiliates. All Rights Reserved.

Licensed under the Apache License, Version 2.0 (the "License"). You may not use this file except in compliance with the License. A copy of the License is located at

    http://aws.amazon.com/apache2.0/

or in the "license" file accompanying this file. This file is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the License for the specific language governing permissions and limitations under the License.
