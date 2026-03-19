# Bootstrap — Terraform Remote State Setup

## What This Is

Before any Terraform project can run with remote state, the storage backend must exist. This bootstrap folder is a one-time setup that creates the infrastructure needed to store Terraform state files remotely on AWS.

This is run ONCE before the main infrastructure project. After that it is never touched again.

---

## The Chicken and Egg Problem

Terraform stores its memory (state) in a backend. To create an S3 bucket using Terraform, Terraform needs a backend to store the state of creating that bucket. But the backend does not exist yet because the bucket has not been created yet.

```
To create S3 bucket → need state backend
State backend       → needs S3 bucket
```

This is why the bootstrap folder exists as a completely separate Terraform project with LOCAL state (no remote backend). It creates the remote backend, and then the main project uses that remote backend.

---

## Resources Created

```
aws_s3_bucket                              → stores terraform state files
aws_s3_bucket_versioning                   → keeps history of state changes
aws_s3_bucket_server_side_encryption       → encrypts state at rest
aws_s3_bucket_public_access_block          → blocks all public access
aws_dynamodb_table                         → state locking
```

Total: 5 resources

---

## Resources Explained

### S3 Bucket
```terraform
resource "aws_s3_bucket" "s3_bucket" {
  bucket = "ansible-terraform-statefile"
}
```
Stores the `terraform.tfstate` file. This file is Terraform's memory — it records every resource it has created, their IDs, and their current configuration. Without this file Terraform does not know what exists and would try to recreate everything.

Each project uses the same bucket but a different key (path) inside it:
```
ansible-terraform-statefile/
├── dev/todo-app/terraform.tfstate      ← this project
├── dev/eks/terraform.tfstate           ← previous project
└── prod/todo-app/terraform.tfstate     ← future production
```

### S3 Versioning
```terraform
resource "aws_s3_bucket_versioning" "s3_bucket_versioning" {
  versioning_configuration {
    status = "Enabled"
  }
}
```
Keeps every version of the state file. If something goes wrong during `terraform apply` and the state gets corrupted, you can restore a previous version from S3. This is like Git for your state file.

### Server Side Encryption
```terraform
rule {
  apply_server_side_encryption_by_default {
    sse_algorithm = "AES256"
  }
}
```
Encrypts the state file at rest in S3 using AES-256 encryption. This is critical because state files contain sensitive information — IP addresses, resource IDs, and sometimes even passwords and connection strings. You never want this readable by anyone who accesses the bucket.

### Public Access Block
```terraform
block_public_acls       = true
block_public_policy     = true
ignore_public_acls      = true
restrict_public_buckets = true
```
Blocks all public access to the bucket. State files must NEVER be publicly accessible. These four settings together ensure no one can accidentally make the bucket or its contents public.

### DynamoDB Table — State Locking
```terraform
resource "aws_dynamodb_table" "dynamodb_table" {
  name         = "ansible-terraform-state-lock"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"
}
```
Prevents two people from running `terraform apply` at the same time. When someone runs Terraform, it writes a lock entry to this DynamoDB table. If another person tries to run Terraform simultaneously, they get an error:
```
Error: Error acquiring the state lock
```
This prevents state file corruption in team environments. `PAY_PER_REQUEST` means you only pay when Terraform actually uses it — essentially free for personal projects.

`LockID` must be exactly this name with capital L and I — this is what the Terraform S3 backend looks for specifically.

---

## Why State Files Are Important

The state file is Terraform's source of truth. It maps your Terraform code to real AWS resources:

```
Terraform code                    State file                  AWS
──────────────                    ──────────                  ───
resource "aws_vpc" "main"    →    vpc_id = vpc-0abc123   →   actual VPC in AWS
resource "aws_instance"      →    instance_id = i-xyz    →   actual EC2 instance
```

Without state:
- Terraform does not know what it already created
- Running `terraform apply` again would try to create duplicates
- Running `terraform destroy` would not know what to delete

---

## Why Remote State vs Local State

| | Local State | Remote State |
|---|---|---|
| Location | Your laptop | S3 bucket |
| Team access | Only you | Everyone on team |
| Risk | Lost if laptop dies | Safe in S3 with versioning |
| Locking | No | Yes via DynamoDB |
| Real projects | Never | Always |

---

## backend.tf in Main Project

After running bootstrap, the main infrastructure project points to this bucket:

```terraform
terraform {
  backend "s3" {
    bucket         = "ansible-terraform-statefile"
    key            = "dev/todo-app/terraform.tfstate"
    region         = "ap-south-1"
    use_lockfile   = true
    encrypt        = true
  }
}
```

| Argument | Purpose |
|---|---|
| `bucket` | Which S3 bucket to use |
| `key` | Path inside bucket for this project's state |
| `region` | AWS region of the bucket |
| `use_lockfile` | Enable state locking |
| `encrypt` | Encrypt state in transit |

---

## Questions and Answers

### Q: Can we create the S3 bucket using Terraform instead of manually?

Yes — and that is exactly what this bootstrap folder does. But it must be a SEPARATE Terraform project with local state because you cannot use remote state to create the thing that provides remote state. This is the chicken and egg problem.

The bootstrap project uses local state. The main project uses remote state in the bucket bootstrap created.

### Q: What happens if two people run terraform apply at the same time without DynamoDB locking?

Both processes read the current state at the same time, both make changes, and both try to write back. The second write overwrites the first, causing state corruption. You end up with a state file that does not match reality. This is why locking exists.

### Q: What is `use_lockfile = true` vs `dynamodb_table`?

`dynamodb_table` is the older way of doing state locking — requires a separate DynamoDB table. `use_lockfile = true` is a newer Terraform feature (v1.10+) that handles locking natively using S3 itself without needing DynamoDB. Both work — `use_lockfile` is simpler but only works with newer Terraform versions.

### Q: What happens if I accidentally delete the state file?

You lose Terraform's memory of what it created. Running `terraform apply` would try to create everything again causing duplicates or errors. Running `terraform destroy` would do nothing because Terraform does not know what exists. This is why versioning is enabled — you can restore a deleted state file from S3 version history.

### Q: Why `billing_mode = "PAY_PER_REQUEST"` for DynamoDB?

DynamoDB has two billing modes. Provisioned mode charges you for reserved capacity whether you use it or not. PAY_PER_REQUEST charges only when Terraform actually reads or writes to it — which happens only during terraform plan and apply. For a state locking table this is essentially free.

### Q: Can I reuse the same S3 bucket and DynamoDB table for multiple projects?

Yes. This is the recommended approach. One bucket, one DynamoDB table, used by all your Terraform projects. Each project just uses a different `key` path inside the bucket:
```
dev/project-1/terraform.tfstate
dev/project-2/terraform.tfstate
prod/project-1/terraform.tfstate
```

---

## Important Commands

```bash
# Run bootstrap once before main project
cd bootstrap
terraform init      # uses local state
terraform apply     # creates S3 bucket and DynamoDB table

# Then initialize main project with remote backend
cd ../infrastructure
terraform init -reconfigure    # use if backend config changed
terraform init -migrate-state  # use if you want to move existing state
```

## Folder Structure

```
Ansible_+_Terraform/
├── bootstrap/               ← run this FIRST, one time only
│   └── main.tf              ← creates S3 + DynamoDB, uses local state
│
└── infrastructure/          ← main project
    ├── backend.tf            ← points to S3 bucket bootstrap created
    └── ...
```

---

## Key Rule

**Never run `terraform destroy` in the bootstrap folder while your main infrastructure exists.** Destroying the S3 bucket deletes your state file and Terraform loses track of all created resources. Always destroy your main infrastructure first, then bootstrap if needed.
