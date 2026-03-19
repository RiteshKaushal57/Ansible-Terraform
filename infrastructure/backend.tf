terraform {
  backend "s3" {
    bucket       = "ansible-terraform-statefile"
    key          = "dev/todo-app/terraform.tfstate"
    region       = "ap-south-1"
    use_lockfile = true
    encrypt      = true
  }
}