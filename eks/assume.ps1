$access_key_id = ""
$secret_access_key = ""
$default_region = "us-west-2"
$cluster_name = ""

$env:AWS_ACCESS_KEY_ID = $access_key_id
$env:AWS_SECRET_ACCESS_KEY = $secret_access_key
$env:AWS_DEFAULT_REGION = $default_region

aws eks update-kubeconfig --region $default_region --name $cluster_name
