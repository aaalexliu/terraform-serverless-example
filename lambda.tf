provider "aws" {
  region = "us-east-1"
}

resource "aws_lambda_function" "example" {
  function_name = "ServerlessExample"

  # The bucket name as created earlier with "aws s3api create-bucket"
  s3_bucket = "terraform-serverless-example-alex"
  s3_key    = "v1.0.0/example.zip"

  # "main" is the filename within the zip file (main.js) and "handler"
  # is the name of the property under which the handler function was
  # exported in that file.
  handler = "main.handler"
  runtime = "nodejs10.x"

  role = aws_iam_role.lambda_exec.arn
}

# IAM role which dictates what other AWS services the Lambda function
# may access.
resource "aws_iam_role" "lambda_exec" {
  name = "serverless_example_lambda"

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



resource "aws_api_gateway_rest_api" "example" {
  name = "ServerlessExample"
  description = "Terraform Serverless Application Example"
}

# All incoming requests to API Gateway must match with a configured resource
# and method in order to be handled. Append the following to the lambda.tf 
# file to define a single proxy resource

resource "aws_api_gateway_resource" "proxy" {
  rest_api_id = aws_api_gateway_rest_api.example.id
  parent_id = aws_api_gateway_rest_api.example.root_resource_id
  path_part = "{proxy+}"
}

# The special path_part value "{proxy+}" activates proxy behavior, which means 
# that this resource will match any request path. Similarly, the 
# aws_api_gateway_method block uses a http_method of "ANY", which allows any
# request method to be used. Taken together, this means that all incoming requests
# will match this resource.

resource "aws_api_gateway_method" "proxy" {
  rest_api_id = aws_api_gateway_rest_api.example.id
  resource_id = aws_api_gateway_resource.proxy.id
  http_method = "ANY"
  authorization = "NONE"
}

# Each method on an API gateway resource has an integration which specifies
# where incoming requests are routed. Add the following configuration to specify
# that requests to this method should be sent to the Lambda function defined earlier:

resource "aws_api_gateway_integration" "lambda" {
  rest_api_id = aws_api_gateway_rest_api.example.id
  resource_id = aws_api_gateway_method.proxy.resource_id
  http_method = aws_api_gateway_method.proxy.http_method

  integration_http_method = "POST"
  type = "AWS_PROXY"
  uri = aws_lambda_function.example.invoke_arn
}
