# Copyright 2016 Amazon.com, Inc. or its affiliates. All Rights Reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License"). You may not use this file
# except in compliance with the License. A copy of the License is located at
#
#     http://aws.amazon.com/apache2.0/
#
# or in the "license" file accompanying this file. This file is distributed on an "AS IS"
# BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
# License for the specific language governing permissions and limitations under the License.
provider "aws" {
  region = "${var.region}"
}

# Lambda Role with Required Policy
resource "aws_iam_role_policy" "lambda_policy" {
    name = "chef_node_cleanup_lambda"
    role = "${aws_iam_role.lambda_role.id}"
    policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "*"
    }
  ]
}
EOF
}

resource "aws_iam_role" "lambda_role" {
    name = "chef_node_cleanup_lambda"
    assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}
output "lambda_role_arn" {
  value = "${aws_iam_role.lambda_role.name}"
}

# Lambda Function
resource "aws_lambda_function" "lambda_function" {
    filename = "lambda_function_payload.zip"
    function_name = "chef_node_cleanup"
    role = "${aws_iam_role.lambda_role.arn}"
    handler = "main.handle"
    description = "Automatically delete nodes from Chef Server on termination"
    memory_size = 128
    runtime = "python2.7"
    timeout = 5
    source_code_hash = "${base64encode(sha256(file("lambda_function_payload.zip")))}"
}

resource "aws_lambda_permission" "allow_cloudwatch" {
    statement_id = "AllowExecutionFromCloudWatch"
    action = "lambda:InvokeFunction"
    function_name = "${aws_lambda_function.lambda_function.arn}"
    principal = "events.amazonaws.com"
    source_arn = "${aws_cloudwatch_event_rule.instance_termination.arn}"
}

# CloudWatch Event Rule and Event Target
resource "aws_cloudwatch_event_rule" "instance_termination" {
  depends_on = ["aws_iam_role.lambda_role"] # we need the Lambda arn to exist
  name = "Chef_Node_Cleanup_Lambda"
  description = "Trigger the chef_node_cleanup Lambda when an instance terminates"
  event_pattern = <<PATTERN
  {
    "source": [ "aws.ec2" ],
    "detail-type": [ "EC2 Instance State-change Notification" ],
    "detail": {
      "state": [ "terminated" ]
    }
  }
PATTERN
}

resource "aws_cloudwatch_event_target" "lambda" {
  depends_on = ["aws_iam_role.lambda_role"] # we need the Lambda arn to exist
  rule = "${aws_cloudwatch_event_rule.instance_termination.name}"
  target_id = "chef_node_cleanup"
  arn = "${aws_lambda_function.lambda_function.arn}"
}
