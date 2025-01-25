terraform {
  backend "s3" {
    bucket         = "challengeterraformstate"
    key            = "challenge/state_file"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "challenge-lock-table"
  }
}