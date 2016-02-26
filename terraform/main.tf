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

resource "template_file" "project_json" {
    depends_on = ["aws_iam_role.lambda_role"]
    template = "${file("${path.module}/project_json.tpl")}"
    vars {
        role_arn = "${aws_iam_role.lambda_role.arn}"
    }
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

# TODO
# Bug in here somewhere, the Event doesn't fully create as the Lambda function
# never gets the Event Source added to it.
resource "aws_cloudwatch_event_target" "lambda" {
  depends_on = ["aws_iam_role.lambda_role"] # we need the Lambda arn to exist
  rule = "${aws_cloudwatch_event_rule.instance_termination.name}"
  target_id = "chef_node_cleanup"
  arn = "arn:aws:lambda:${var.region}:${var.account_number}:function:chef_node_cleanup"
}

# dummy resource to copy the json file
resource "null_resource" "copy_template" {
  provisioner "local-exec" {
    command = "echo '${template_file.project_json.rendered}' > lambda/project.json"
  }
}

# dummy resource to wait while things get consistent in aws
resource "null_resource" "sleep" {
    provisioner "local-exec" {
      command = "sleep 10"
    }
}

# dummy resource to deploy lambda function using apex
resource "null_resource" "apex_deploy" {
  depends_on = ["null_resource.sleep"]
  provisioner "local-exec" {
    command = "apex deploy -C lambda/"
  }
}
