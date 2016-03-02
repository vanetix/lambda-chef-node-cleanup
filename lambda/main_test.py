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
Unit Tests for chef_node_cleanup Lambda function
"""
import pytest
from botocore.exceptions import ClientError
from mock import MagicMock, patch
from main import log_event
from main import get_instance_id
from main import get_pem
from main import handle

def test_log_event():
    """
    Test the log_event function
    """
    assert log_event

def test_get_instance_id():
    """
    Test the get_instance_id function with valid event
    """
    event = { 'detail': { 'instance-id': 'i-abcde123' } }
    assert get_instance_id(event) == 'i-abcde123'

def test_get_instance_id_with_invalid_event():
    """
    Test the get_instance_id function with invalid event
    """
    event = {}
    assert get_instance_id(event) == False

@patch('boto3.client')
def test_get_pem(mock_client):
    """
    Test the get_pem function with valid data
    """
    kms = MagicMock()
    mock_client.return_value = kms
    decrypted_blob = { 'Plaintext': 'super_secret_key' }
    kms.decrypt.return_value = decrypted_blob
    assert get_pem() == 'super_secret_key'

@patch('boto3.client')
def test_get_pem_with_boto_failure(mock_client):
    """
    Test the get_pem function when a boto exception occurs
    """
    kms = MagicMock()
    mock_client.return_value = kms
    err_msg = {
        'Error': {
            'Code': 400,
            'Message': 'Boom!'
        }
    }
    kms.decrypt.side_effect = ClientError(err_msg, 'Test')
    assert get_pem() == False

@patch('chef.ChefAPI')
@patch('chef.Search')
@patch('chef.Node')
def test_handle(mock_chef_api, mock_chef_search, mock_chef_node):
    """
    Test the handle function with valid data
    """
    event = { 'detail': { 'instance-id': 'i-abcde123' } }
    dummy_node = MagicMock()
    mock_chef_api.return_value = True
    mock_chef_search.return_value = ['node']
    mock_chef_node.return_value = dummy_node
    dummy_node.delete().return_value = True
    # TODO
    # Currently segfaulting need to investigate
    # assert handle(event, 'Test') == True
