# This function is triggered via API Gateway when a user acts on the Slack interactive message sent by approval_requester.py.

from urllib.parse import parse_qs
import json
import os
import boto3

SLACK_VERIFICATION_TOKEN = os.environ['SLACK_VERIFICATION_TOKEN']

#Triggered by API Gateway
#It kicks off a particular CodePipeline project
def lambda_handler(event, context):
	#print("Received event: " + json.dumps(event, indent=2))
	body = parse_qs(event['body'])
	payload = json.loads(body['payload'][0])

	# Validate Slack token
	if SLACK_VERIFICATION_TOKEN == payload['token']:
		action = json.loads(payload['actions'][0]['value'])
		codepipeline_name = action["codePipelineName"]
		send_slack_message(action)

		user = payload['user']['name']
		# This will replace the interactive message with a simple text response.
		# You can implement a more complex message update if you would like.
		return  {
			"isBase64Encoded": "false",
			"statusCode": 200,
		 	"body": f"{{\"text\": \"The approval on {codepipeline_name} has been confirmed by {user}\"}}"
		}
	else:
		return  {
			"isBase64Encoded": "false",
			"statusCode": 403,
			"body": "{\"error\": \"This request does not include a vailid verification token.\"}"
		}


def send_slack_message(action_details):
	codepipeline_status = "Approved" if action_details["approve"] else "Rejected"
	codepipeline_name = action_details["codePipelineName"]
	token = action_details["codePipelineToken"]

	client = boto3.client('codepipeline')
	response_approval = client.put_approval_result(
							pipelineName=codepipeline_name,
							stageName='Approval',
							actionName='ApprovalOrDeny',
							result={'summary':'','status':codepipeline_status},
							token=token)
	print(response_approval)