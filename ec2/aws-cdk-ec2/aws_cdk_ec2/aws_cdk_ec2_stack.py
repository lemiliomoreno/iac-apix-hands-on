from aws_cdk import (
    # Duration,
    Stack,
    # aws_sqs as sqs
    aws_ec2 as ec2,
)
from constructs import Construct

class AwsCdkEc2Stack(Stack):

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        vpc = ec2.Vpc(
            self,
            "ApixVpc",
            max_azs=2,
        )

        instance = ec2.Instance(self, "ApixInstance",
            vpc=vpc,
            instance_type=ec2.InstanceType.of(ec2.InstanceClass.T3, ec2.InstanceSize.MICRO),
            machine_image=ec2.AmazonLinuxImage(generation=ec2.AmazonLinuxGeneration.AMAZON_LINUX_2),
        )
