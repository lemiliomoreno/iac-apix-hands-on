import json

from aws_cdk import (
    Stack,
    aws_lambda as lambda_,
    aws_logs as logs,
    aws_apigateway as apigw,
)
from constructs import Construct


class ServerlessStack(Stack):
    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        api = apigw.RestApi(
            self,
            "HelloWorldApi",
            rest_api_name="hello-world-api",
        )

        hello_world_function = lambda_.Function(
            self,
            "HelloWorldFunction",
            code=lambda_.Code.from_asset("src/hello_world"),
            runtime=lambda_.Runtime.PYTHON_3_11,
            handler="hello_world.handler",
            log_retention=logs.RetentionDays.TWO_WEEKS,
        )

        hello_world_integration = apigw.LambdaIntegration(
            handler=hello_world_function,
            request_templates={
                "application/json": json.dumps({"statusCode": "200"}),
            },
        )

        hello_world_resource = api.root.add_resource("hello")
        hello_world_resource.add_method("GET", hello_world_integration)
