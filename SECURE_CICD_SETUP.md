# Secure CI/CD Setup for K3s Cluster

This guide explains how to set up GitLab CI/CD for your K3s cluster using **IAM roles with OIDC federation** instead of storing personal AWS credentials.

## 🔒 Security Benefits

- **No stored credentials**: Uses temporary credentials via OIDC federation
- **Branch-based permissions**: Different roles for main vs feature branches
- **Minimal permissions**: Follows principle of least privilege
- **Automatic rotation**: Credentials are generated fresh for each job
- **Audit trail**: All actions logged in AWS CloudTrail

## 📋 Prerequisites

1. **GitLab CLI (glab)** installed and authenticated
   ```bash
   brew install glab           # macOS
   glab auth login            # Authenticate
   ```

2. **AWS CLI** configured with administrative permissions
   ```bash
   aws configure              # or aws sso login
   ```

3. **Terraform** installed
   ```bash
   brew install terraform     # macOS
   ```

## 🚀 Quick Setup

Run the automated setup script:

```bash
./setup_secure_gitlab_ci.sh --gitlab-project username/project-name
```

Or follow the manual steps below.

## 📖 Manual Setup Steps

### Step 1: Create IAM Roles

1. Update Terraform variables:
   ```bash
   cd terraform
   export TF_VAR_gitlab_project_path="your-username/your-project"
   ```

2. Apply IAM configuration:
   ```bash
   terraform init -backend=false
   terraform apply -target=aws_iam_openid_connect_provider.gitlab \
                   -target=aws_iam_role.gitlab_cicd_main \
                   -target=aws_iam_role.gitlab_cicd_feature
   ```

3. Get role ARNs:
   ```bash
   MAIN_ROLE_ARN=$(terraform output -raw gitlab_cicd_main_role_arn)
   FEATURE_ROLE_ARN=$(terraform output -raw gitlab_cicd_feature_role_arn)
   ```

### Step 2: Configure GitLab Variables

Set these variables in your GitLab project (Settings → CI/CD → Variables):

| Variable | Value | Masked |
|----------|--------|---------|
| `AWS_DEFAULT_REGION` | us-west-2 | No |
| `AWS_ACCOUNT_ID` | your-account-id | No |
| `GITLAB_CICD_MAIN_ROLE_ARN` | arn:aws:iam::account:role/gitlab-k3s-cicd-main | No |
| `GITLAB_CICD_FEATURE_ROLE_ARN` | arn:aws:iam::account:role/gitlab-k3s-cicd-feature | No |
| `TF_VAR_terraform_state_bucket` | your-terraform-state-bucket | No |
| `TF_VAR_vpc_id` | vpc-xxxxxxxx | No |
| `TF_VAR_subnet_id` | subnet-xxxxxxxx | No |
| `TF_VAR_security_group_id` | sg-xxxxxxxx | No |

### Step 3: Use Secure Pipeline

Replace your `.gitlab-ci.yml` with `.gitlab-ci-oidc.yml`:

```bash
cp .gitlab-ci-oidc.yml .gitlab-ci.yml
```

## 🏗️ How It Works

### OIDC Federation Process

1. **GitLab job starts** → Generates JWT token
2. **AWS STS** → Validates JWT against OIDC provider
3. **IAM role assumed** → Temporary credentials issued
4. **Pipeline runs** → Uses temporary credentials
5. **Job ends** → Credentials automatically expire

### Role Permissions

#### Main Branch Role (`gitlab-k3s-cicd-main`)
- Full EC2 management for k3s clusters
- ECR push/pull access
- S3/DynamoDB for Terraform state
- SSM for instance management

#### Feature Branch Role (`gitlab-k3s-cicd-feature`)
- Read-only EC2 access
- ECR pull-only access
- Terraform plan (no apply)
- No destructive operations

### Pipeline Stages

```yaml
stages:
  - validate    # Code validation (all branches)
  - plan       # Terraform plan (all branches)
  - build      # Container builds (main branch only)
  - deploy     # Infrastructure + app deployment (main branch, manual)
  - cleanup    # Resource cleanup (feature branches, manual)
```

## 🔧 Configuration Files

### Core Files Created

- `terraform/cicd_iam_role.tf` - IAM roles and OIDC provider
- `.gitlab-ci-oidc.yml` - Secure pipeline configuration
- `setup_secure_gitlab_ci.sh` - Automated setup script

### Security Policies

The IAM policies follow the principle of least privilege:

- **Region-scoped**: Operations limited to specified AWS region
- **Resource-scoped**: EC2 actions limited to k3s-tagged resources
- **Action-scoped**: Only necessary permissions granted
- **Time-bound**: Credentials expire after job completion

## 🛡️ Security Best Practices

### ✅ What This Setup Provides

- No long-lived credentials stored in GitLab
- Branch-based access control
- Automatic credential rotation
- Comprehensive audit logging
- Minimal permission sets

### ⚠️ Additional Recommendations

1. **Monitor CloudTrail logs** for unusual activity
2. **Regularly review IAM policies** for permission creep
3. **Use separate AWS accounts** for prod/dev environments
4. **Enable MFA** on your AWS root account
5. **Rotate GitLab project access tokens** regularly

## 🐛 Troubleshooting

### Common Issues

**Error: "AssumeRoleWithWebIdentity failed"**
- Check GitLab project path in role trust policy
- Verify OIDC provider thumbprint
- Ensure CI_JOB_JWT_V2 is available

**Error: "Access denied"**
- Check IAM policy permissions
- Verify role ARN in GitLab variables
- Check AWS region configuration

**Error: "Invalid identity token"**
- GitLab project path mismatch
- Branch name not matching conditions
- OIDC provider configuration issue

### Debug Commands

```bash
# Check role trust policy
aws iam get-role --role-name gitlab-k3s-cicd-main

# Validate OIDC provider
aws iam list-open-id-connect-providers

# Test assume role (requires valid JWT)
aws sts assume-role-with-web-identity \
  --role-arn $ROLE_ARN \
  --role-session-name test \
  --web-identity-token $JWT_TOKEN
```

## 🔄 Migration from Stored Credentials

If migrating from the old setup:

1. Run the secure setup script
2. Remove old AWS access key variables from GitLab
3. Update `.gitlab-ci.yml` to use OIDC version
4. Test with a feature branch first
5. Delete unused IAM users/keys

## 📚 Additional Resources

- [AWS IAM OIDC Federation](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_providers_create_oidc.html)
- [GitLab CI/CD Security](https://docs.gitlab.com/ee/ci/security/)
- [AWS Security Best Practices](https://aws.amazon.com/architecture/security-identity-compliance/)

---

**🔒 Remember**: This setup eliminates the need for storing any personal AWS credentials in GitLab, significantly improving your security posture!