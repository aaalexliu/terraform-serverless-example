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

# The AWS_PROXY integration type causes API gateway to call into the API of another
# AWS service. In this case, it will call the AWS Lambda API to create an "invocation"
# of the Lambda function.

# Unfortunately the proxy resource cannot match an empty path at the root of the API.
# To handle that, a similar configuration must be applied to the root resource that
# is built in to the REST API object:

resource "aws_api_gateway_method" "proxy_root" {
  rest_api_id = aws_api_gateway_rest_api.example.id
  resource_id = aws_api_gateway_rest_api.example.root_resource_id
  http_method = "ANY"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "lambda_root" {
  rest_api_id = aws_api_gateway_rest_api.example.id
  resource_id = aws_api_gateway_method.proxy_root.resource_id
  http_method = aws_api_gateway_method.proxy_root.http_method

  integration_http_method = "POST"
  type = "AWS_PROXY"
  uri = aws_lambda_function.example.invoke_arn
}



# Finally, you need to create an API Gateway "deployment" in order to activate the
# configuration and expose the API at a URL that can be used for testing:

resource "aws_api_gateway_deployment" "example" {
  depends_on = [
    aws_api_gateway_integration.lambda,
    aws_api_gateway_integration.lambda_root,
  ]

  rest_api_id = aws_api_gateway_rest_api.example.id
  stage_name = "test"
}

# By default any two AWS services have no access to one another, until access
# is explicitly granted. For Lambda functions, access is granted using the 
# aws_lambda_permission resource, which should be added to the lambda.tf file 
# created in an earlier step:

resource "aws_lambda_permission" "apigw" {
  statement_id = "AllowAPIGatewayInvoke"
  action = "lambda:InvokeFunction"
  function_name = aws_lambda_function.example.function_name
  principal = "apigateway.amazonaws.com"

  # The "/*/*" portion grants access from any method on any resource
   # within the API Gateway REST API.
  source_arn =  "${aws_api_gateway_rest_api.example.execution_arn}/*/*"
}
