import aws_cdk as core
import aws_cdk.assertions as assertions

from aws_cdk_ec2.aws_cdk_ec2_stack import AwsCdkEc2Stack

# example tests. To run these tests, uncomment this file along with the example
# resource in aws_cdk_ec2/aws_cdk_ec2_stack.py
def test_sqs_queue_created():
    app = core.App()
    stack = AwsCdkEc2Stack(app, "aws-cdk-ec2")
    template = assertions.Template.from_stack(stack)

#     template.has_resource_properties("AWS::SQS::Queue", {
#         "VisibilityTimeout": 300
#     })
