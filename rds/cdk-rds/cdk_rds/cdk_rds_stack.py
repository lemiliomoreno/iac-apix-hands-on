from aws_cdk import (
    Stack,
    aws_ec2 as ec2,
    aws_rds as rds,
)
from constructs import Construct


class CdkRdsStack(Stack):

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        vpc = ec2.Vpc(
            self,
            "ApixVpc",
            max_azs=2,
        )

        db_sg = ec2.SecurityGroup(
            self,
            "ApixDbSecurityGroup",
            vpc=vpc,
            allow_all_ipv6_outbound=True,
            allow_all_outbound=True,
        )

        db_sg.add_ingress_rule(
            peer=ec2.Peer.any_ipv4(),
            connection=ec2.Port.tcp(5432),
        )

        database_cluster = rds.DatabaseCluster(
            self,
            "ApixServerlessCluster",
            engine=rds.DatabaseClusterEngine.aurora_postgres(
                version=rds.AuroraPostgresEngineVersion.VER_16_1
            ),
            serverless_v2_min_capacity=0.5,
            serverless_v2_max_capacity=16,
            credentials=rds.Credentials.from_generated_secret("clusteradmin"),
            vpc_subnets=ec2.SubnetSelection(
                subnet_type=ec2.SubnetType.PUBLIC,
            ),
            vpc=vpc,
            writer=rds.ClusterInstance.serverless_v2("writer1"),
            readers=[
                rds.ClusterInstance.serverless_v2("reader1", scale_with_writer=True),
            ],
            security_groups=[
                db_sg,
            ],
        )
