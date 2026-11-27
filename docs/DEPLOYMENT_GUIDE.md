# Deployment guide

A complete first-time walkthrough: from this folder to a running, monitored application on AWS, deployed by `git push`.
Allow roughly an hour the first time, most of it spent on AWS and GitHub account setup.

**Windows users:** run the shell commands in *Git Bash* or *WSL*. Docker Desktop is only needed for the local stack.

## 0. What you need

| Need | Notes |
|---|---|
| GitHub account + `git` | The repo hosts the code, runs the pipeline and stores the container image. |
| [GitHub CLI](https://cli.github.com) (`gh`) | Optional but recommended: `scripts/setup-github.sh` uses it. Run `gh auth login` once. |
| AWS account + [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) | Needed once, to create the Terraform state bucket. |
| An SSH client with `ssh-keygen` | Included with Git Bash, WSL, macOS and Linux. |

Terraform, Ansible and Docker do **not** need to be installed on your computer for the pipeline: GitHub's runners have them. (Install them only if you want to run things by hand; see section 9.)

## 1. Put the project on GitHub

1. On GitHub, create a new empty repository (for example `autodeploy`; private or public both work).
2. From this folder:

```bash
git init -b main
git add .
git commit -m "Initial commit: AutoDeploy"
git remote add origin https://github.com/<your-user>/autodeploy.git
git push -u origin main
```

The push starts the **CI/CD** workflow. Because AWS is not configured yet, it runs *test → validate → build → publish image* and ends **green** without deploying. Open the **Actions** tab to see it; this confirms the CI half works before you spend any AWS money.

## 2. Create AWS credentials for the pipeline

Use a dedicated IAM user, not your root account.

1. AWS Console → **IAM → Users → Create user** → name `autodeploy-pipeline` (no console access).
2. **Permissions → Create policy → JSON**, paste the following (replace `<TF_STATE_BUCKET>` with the bucket name you create in step 3; you can edit the policy afterwards), name it `autodeploy-pipeline`, and attach it to the user:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    { "Effect": "Allow", "Action": "ec2:*", "Resource": "*" },
    { "Effect": "Allow",
      "Action": ["s3:ListBucket", "s3:GetBucketLocation"],
      "Resource": "arn:aws:s3:::<TF_STATE_BUCKET>" },
    { "Effect": "Allow",
      "Action": ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"],
      "Resource": "arn:aws:s3:::<TF_STATE_BUCKET>/*" }
  ]
}
```

   (For a throw-away learning account you may attach `AdministratorAccess` instead. The policy above is the least privilege this project needs.)

3. User → **Security credentials → Create access key** → use case *Application running outside AWS*. Copy the **Access key ID** and **Secret access key** now; the secret is shown only once.

## 3. Create the Terraform state bucket (once)

Terraform records what it built in a *state file*. The pipeline runs on a fresh machine every time, so the state must live somewhere shared: a private S3 bucket.

Run this with **your own administrator credentials** (`aws configure`, or `AWS_PROFILE=...`), not the pipeline user:

```bash
AWS_REGION=ap-south-1 scripts/bootstrap-backend.sh
```

It creates a versioned, encrypted, non-public bucket named `autodeploy-tfstate-<account-id>` and prints the values you need next. (`ap-south-1` is Mumbai; pick the region closest to you and use it consistently everywhere below.)

## 4. Give the pipeline its configuration

### Option A: one command (recommended)

```bash
scripts/setup-github.sh
```

It asks for the AWS access key, the region, the state bucket and an optional Grafana password (Enter generates a strong one and shows it once). It also creates an SSH key pair at `~/.ssh/autodeploy_key` if you do not have one, and stores everything in your repository's secrets and variables. Use `--dry-run` first to see what it would set.

### Option B: manually

GitHub repo → **Settings → Secrets and variables → Actions**. Create **repository** secrets and variables (not environment-level ones):

| Type | Name | Value |
|---|---|---|
| Secret | `AWS_ACCESS_KEY_ID` | from step 2 |
| Secret | `AWS_SECRET_ACCESS_KEY` | from step 2 |
| Secret | `SSH_PRIVATE_KEY` | contents of `~/.ssh/autodeploy_key` (create with `scripts/generate-ssh-key.sh`) |
| Secret | `SSH_PUBLIC_KEY` | contents of `~/.ssh/autodeploy_key.pub` |
| Secret | `GRAFANA_ADMIN_PASSWORD` | your choice: 8+ characters, no single quote `'` |
| Variable | `AWS_REGION` | e.g. `ap-south-1` |
| Variable | `TF_STATE_BUCKET` | bucket name from step 3 |
| Variable | `DEPLOY_TO_AWS` | `true` (this is the switch that turns deployment on) |
| Variable (optional) | `EC2_INSTANCE_TYPE` | default `t3.small` |
| Variable (optional) | `ALLOWED_SSH_CIDRS` | JSON list, e.g. `["203.0.113.10/32"]`; default is open to all |

## 5. Deploy

Push any commit to `main`, or go to **Actions → CI/CD → Run workflow**.

What you will see, in order:

1. **Lint & unit tests**, **Validate infrastructure & configs**
2. **Build & publish image**: published as `ghcr.io/<you>/autodeploy:sha-<commit>`
3. **Terraform - provision AWS**: creates the VPC, subnet, firewall, EC2 server and Elastic IP (the first run creates everything; later runs report *no changes*)
4. **Ansible - configure server & deploy**: waits for the new server, installs Docker, starts the stack, then checks its health
5. **Verify deployment**: smoke test from the internet. The run **summary** page lists the URLs.

The first run takes noticeably longer than later ones because it creates the server and installs Docker.

Open `http://<elastic-ip>/` for the application and `http://<elastic-ip>/grafana/` for Grafana (user `admin`, the password you chose). The **AutoDeploy - Overview** dashboard is the landing page.

## 6. Demo script (for presentations and viva)

1. **Show the running app.** Point out the *Version* card (`sha-...`) and the *Healthy* badge.
2. **Release a change.** Edit the subtitle in `app/templates/index.html`, commit, push. Show the pipeline stages running. When it finishes, refresh the page: new version, uptime restarted.
3. **Show monitoring.** In another terminal run `scripts/load-test.sh http://<elastic-ip> 120`. Watch request rate, latency and the error rate (the script injects occasional HTTP 500s) move in Grafana. The *Deployed version* panel matches the page.
4. **Show the safety net.** Make a test fail on purpose (for example change an assertion in `app/tests/test_app.py`) and push to a branch with a pull request: the pipeline fails at *Lint & unit tests* and nothing is deployed.
5. **Roll back.** Actions → **Redeploy / Rollback** → enter the previous tag (see the repository's **Packages** page). The older version is live again within minutes, verified by the same smoke test.
6. **Show Infrastructure as Code.** Open `terraform/main.tf`; in the AWS console show the instance, VPC and security group (only ports 22 and 80) that Terraform created.
7. **Clean up.** Actions → **Destroy infrastructure** → type `destroy`.

## 7. Operations

| Task | How |
|---|---|
| Roll back / redeploy a tag | Actions → **Redeploy / Rollback** |
| Change the instance size | Set repository variable `EC2_INSTANCE_TYPE`, push. Terraform resizes the instance in place (a short stop/start; the disk, Elastic IP and Docker volumes are kept, and the containers restart on their own). |
| Restrict SSH to your IP | Set variable `ALLOWED_SSH_CIDRS` to `["<your-ip>/32"]`. Note the pipeline's own runners then cannot SSH in; use a self-hosted runner in that case. |
| Look at logs | `ssh -i ~/.ssh/autodeploy_key ubuntu@<ip>` then `cd /opt/autodeploy && sudo docker compose logs -f app` |
| Open Prometheus | `ssh -i ~/.ssh/autodeploy_key -N -L 9090:127.0.0.1:9090 ubuntu@<ip>` then <http://localhost:9090> |
| Disable the demo `/api/simulate` endpoint | Run the playbook with `-e app_enable_simulate=false` (or change the default in `ansible/roles/app/defaults/main.yml`) |
| Change the Grafana password | Grafana only reads the password on its first start. On the server: `cd /opt/autodeploy && sudo docker compose exec grafana grafana cli admin reset-admin-password '<new>'`, and update the secret too. |
| Stop all AWS charges | Actions → **Destroy infrastructure**. The small state bucket is kept; delete it by hand in S3 if you are completely done. |

## 8. Troubleshooting

| Symptom | Likely cause and fix |
|---|---|
| Pipeline is green but nothing deploys | Repository variable `DEPLOY_TO_AWS` is not `true`, or you pushed a branch other than `main`. |
| `Deployment is not configured: Missing secrets/variables: ...` | The named secrets or variables are missing. They must be **repository**-level (not environment-level) and spelled exactly as in section 4. |
| Terraform `UnauthorizedOperation` / `AccessDenied` | The IAM policy is missing permissions, or the bucket name in the policy differs from `TF_STATE_BUCKET`. |
| Terraform `Error acquiring the state lock` | A previous run was cancelled mid-way. Wait a few minutes; if it persists and no run is active, delete the object `autodeploy/production/terraform.tfstate.tflock` in the state bucket. |
| `ssh_public_key must be an OpenSSH public key` | `SSH_PUBLIC_KEY` holds the wrong file. It must be the `.pub` contents starting with `ssh-ed25519`. |
| Ansible `UNREACHABLE` / `Permission denied (publickey)` | `SSH_PRIVATE_KEY` does not match `SSH_PUBLIC_KEY` (regenerate both together), or the key was pasted without its header/footer lines. If you changed keys after the server existed, run **Destroy** and deploy again. |
| `pull access denied` for the image | Re-run the whole workflow (the registry token is per run). Ensure Settings → Actions → General allows the workflow to run and that the organisation does not block GHCR packages. |
| Smoke test fails on Grafana | On the server: `sudo docker compose -f /opt/autodeploy/docker-compose.yml logs grafana`. A very small instance (`t3.micro`) may need more time; re-run the workflow. |
| Containers restart / out-of-memory on a small instance | Use `t3.small` or larger. |
| `terraform init` warns the lock file is missing | Normal on the first run. After your first local `terraform init`, commit `terraform/.terraform.lock.hcl` so provider versions are pinned. |
| Port 8080 in use locally | Set another `NGINX_PORT` (and `PUBLIC_URL`) in `.env`. |

## 9. Running the pieces by hand (optional)

Useful for learning and debugging. Needs Terraform ≥ 1.10, Ansible (`pip install ansible`), and AWS credentials in your environment.

```bash
# 1. Infrastructure
cp terraform/terraform.tfvars.example terraform/terraform.tfvars   # edit: region, ssh_public_key
cp terraform/backend.hcl.example     terraform/backend.hcl         # edit: bucket, region
make tf-init
make tf-apply
cd terraform && terraform output && cd ..

# 2. Configuration + deployment (image must already exist in GHCR)
export GRAFANA_ADMIN_PASSWORD='choose-a-password'
export GHCR_USERNAME='<your-github-user>'          # only if the package is private
export GHCR_TOKEN='<personal access token with read:packages>'
make deploy IP=<elastic-ip> IMAGE=ghcr.io/<you>/autodeploy:sha-<commit>

# 3. Check
scripts/smoke-test.sh http://<elastic-ip> sha-<commit>
```

## 10. Using OIDC instead of long-lived AWS keys (optional hardening)

Static access keys are the simplest option for a student project. For production, switch the `aws-actions/configure-aws-credentials` steps in `.github/workflows/deploy.yml` and `destroy.yml` to an IAM role assumed through GitHub's OIDC provider (`role-to-assume: arn:aws:iam::<account>:role/...`, plus `id-token: write` permission) and delete the two AWS key secrets.
