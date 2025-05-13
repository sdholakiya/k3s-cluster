terraform {
  backend "s3" {
    bucket         = ""  # Provided during terraform init via -backend-config
    key            = ""  # Provided during terraform init via -backend-config
    region         = ""  # Provided during terraform init via -backend-config
    dynamodb_table = ""  # Provided during terraform init via -backend-config
    encrypt        = true
  }
}