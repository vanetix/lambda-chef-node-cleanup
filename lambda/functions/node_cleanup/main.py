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
"""
Remove a node from Chef server when a termination event is received
joshcb@amazon.com
v1.0.0
"""
from __future__ import print_function
import logging
import os
from base64 import b64decode
from botocore.exceptions import ClientError
import boto3
from chef import ChefAPI, Node, Search
from chef.exceptions import ChefServerNotFoundError

LOGGER = logging.getLogger()
LOGGER.setLevel(logging.INFO)
CHEF_SERVER_URL = 'https://ec2-52-35-252-248.us-west-2.compute.amazonaws.com/organizations/aws'
USERNAME = 'joshcb'
# Needed if using self signed certs
os.environ["SSL_CERT_FILE"] = "ec2-52-35-252-248.us-west-2.compute.amazonaws.com.crt"

def log_event(event):
    """Logs event information for debugging"""
    LOGGER.info("====================================================")
    LOGGER.info(event)
    LOGGER.info("====================================================")

def get_instance_id(event):
    """Parses InstanceID from the event dict and gets the FQDN from EC2 API"""
    try:
        return event['detail']['instance-id']
    except KeyError as err:
        LOGGER.error(err)
        return False

def get_pem():
    """Decrypt the Ciphertext Blob to get USERNAME's pem file"""
    try:
        with open('encrypted_pem.txt', 'r') as encrypted_pem:
            pem_file=encrypted_pem.read()
        kms = boto3.client('kms')
        return kms.decrypt(CiphertextBlob=b64decode(pem_file))['Plaintext']
    except (IOError, ClientError, KeyError) as err:
        LOGGER.error(err)
        return False

def handle(event, _context):
    """Lambda Handler"""
    log_event(event)

    with ChefAPI(CHEF_SERVER_URL, get_pem(), USERNAME):
        instance_id = get_instance_id(event)
        try:
            search = Search('node', 'ec2_instance_id:' + instance_id)
        except ChefServerNotFoundError as err:
            LOGGER.error(err)
            return False

        if len(search) != 0:
            for instance in search:
                node = Node(instance.object.name)
                try:
                    node.delete()
                    LOGGER.info('===SUCCESS===')
                    return True
                except ChefServerNotFoundError as err:
                    LOGGER.error(err)
                    return False
        else:
            LOGGER.info('=Instance does not appear to be Chef Server managed.=')
            return True
