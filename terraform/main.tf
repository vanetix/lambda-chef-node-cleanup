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

# dummy resource to copy the json file
resource "null_resource" "copy_template" {
  provisioner "local-exec" {
    command = "echo '${template_file.project_json.rendered}' > project.json"
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
  provisioner "local-exec" {
    command = "apex deploy"
  }
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

resource "aws_cloudwatch_event_target" "lambda" {
  rule = "${aws_cloudwatch_event_rule.instance_termination.name}"
  target_id = "chef_node_cleanup"
  arn = "arn:aws:lambda:${var.region}:${var.account_number}:function:chef_node_cleanup"
}
