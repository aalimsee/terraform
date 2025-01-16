provider "aws" {
  region = "us-east-1"
}

provider "aws" {
  alias  = "seconday-region"
  region = "ap-southeast-1"
}