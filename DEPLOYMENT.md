# Render & Azure SQL Deployment Guide

This guide walks you through deploying the **ASP.NET Core MVC Approval Workflow** to **Render** using **Docker** and **Microsoft Azure SQL Database**.

---

## 1. Prerequisites Checklist

- GitHub repository: `https://github.com/lisaajose/approval-page`
- An active [Microsoft Azure account](https://portal.azure.com)
- An active [Render account](https://render.com)
- [SQL Server Management Studio (SSMS)](https://learn.microsoft.com/en-us/sql/ssms/download-sql-server-management-studio-ssms) or Azure Data Studio

---

## 2. Commit and Push Deployment Files to GitHub

From your local repository root, stage, commit, and push the deployment assets:

```powershell
git add .gitignore .dockerignore Dockerfile appsettings.Production.json Program.cs Database/ DEPLOYMENT.md
git commit -m "Configure Dockerfile, dynamic port binding, and Azure SQL script compatibility for Render deployment"
git push origin main
```

---

## 3. Provision Microsoft Azure SQL Database

1. Log in to the [Azure Portal](https://portal.azure.com).
2. In the search bar, type **SQL databases** and select **SQL databases**.
3. Click **+ Create**.
4. Configure the database details:
   - **Subscription**: Select your active subscription.
   - **Resource group**: Select existing or click *Create new* (e.g. `rg-approvalworkflow`).
   - **Database name**: Enter `ApprovalWorkflowDB` *(exact name expected by default)*.
   - **Server**: Click *Create new*:
     - **Server name**: e.g., `sql-approvalworkflow-prod` (must be globally unique, e.g. `sql-approvalworkflow-prod.database.windows.net`).
     - **Location**: Choose a region close to your Render service (e.g., *East US*).
     - **Authentication method**: Select **Use SQL authentication** (or SQL and Microsoft Entra authentication).
     - **Server admin login**: e.g., `sqladmin`
     - **Password**: Enter a strong password and save it securely.
     - Click **OK**.
   - **Compute + storage**: Click *Configure database* and choose **Basic** (5 DTUs, ~5 USD/month) or **General Purpose Serverless** with auto-pause to minimize costs.
5. In the **Networking** tab:
   - **Connectivity method**: Select **Public endpoint**.
   - **Firewall rules**:
     - Set **Allow Azure services and resources to access this server** to **Yes** (recommended for cloud workloads).
     - Set **Add current client IP address** to **Yes** (allows your local machine to connect via SSMS).
6. Click **Review + create**, then **Create**.
7. Wait 2–3 minutes for deployment to complete.

---

## 4. Run SQL Schema Scripts via SSMS

Because Azure SQL Database does not allow `USE [database_name]` context-switching and manages database creation via Azure Resource Manager:

1. Open **SQL Server Management Studio (SSMS)**.
2. In the **Connect to Server** window:
   - **Server type**: Database Engine
   - **Server name**: `<your-server-name>.database.windows.net` (e.g. `sql-approvalworkflow-prod.database.windows.net`)
   - **Authentication**: SQL Server Authentication
   - **Login**: Your admin login (e.g. `sqladmin`)
   - **Password**: Your admin password
   - Click **Options >>** and go to **Connection Properties**:
     - In **Connect to database**, enter or select: `ApprovalWorkflowDB` *(critical for Azure SQL)*.
   - Click **Connect**.
3. In Object Explorer, expand `Databases` -> `ApprovalWorkflowDB`.
4. Open and execute the scripts in the following order:

| Step | Script File | Purpose in Azure SQL |
|---|---|---|
| 1 | `Database/01_CreateDatabase.sql` | *Optional note*: In Azure SQL, database creation was already done in Step 3. You can review the notes in this script or skip it. |
| 2 | `Database/02_CreateTables.sql` | Creates `M_Users`, `t_Header`, `t_Authdata`, and `t_ApprovalHistory`. |
| 3 | `Database/03_CreateConstraintsAndIndexes.sql` | Adds PKs, unique constraints, FK cascades, check constraints, and performance indexes. |
| 4 | `Database/04_SeedUsers.sql` | Seeds initial users (JP, Smitha, PM, EDWIN, JERN, NIRALI, LISA, GAUTHAM) with default test passwords matching their IDs. |
| 5 | `Database/05_CreateFunctionsAndViews.sql` | Creates `dbo.fn_GetVoucherApprovalLevel` function and `dbo.vw_VoucherSummary` view. |
| 6 | `Database/06_CreateStoredProcedures.sql` | Deploys all stored procedures: `usp_SaveVoucher`, `usp_GetPendingApprovals`, `usp_GetVoucherDetails`, `usp_ApproveVoucher`, `usp_RejectVoucher`, `usp_GetNotifications`, `usp_GetAllUsers`, `usp_ApprovalWorkflow`, `usp_ValidateUserLogin`. |
| 7 | `Database/08_AddApprovalWorkflowProcedure.sql` | *(Optional/Idempotent)* Re-applies `dbo.usp_ApprovalWorkflow` and `dbo.usp_ValidateUserLogin` if run separately. |
| 8 | `Database/07_TestWorkflow.sql` | Runs the automated 20-point verification test suite. Confirm that all test cases return `PASS`. |

---

## 5. Configure Azure SQL Firewall for Render

Render assigns dynamic outbound IP addresses across shared clusters. To allow Render containers to connect to Azure SQL:

1. Go to your **SQL Server** in the Azure Portal (not just the database page).
2. Under **Security**, click **Networking**.
3. Under **Exceptions**, check the box:
   - **Allow Azure services and resources to access this server**
4. Under **Firewall rules**, add a rule to allow external outbound cloud connections:
   - Rule Name: `AllowAllRender`
   - Start IP: `0.0.0.0`
   - End IP: `255.255.255.255`
   *(Alternatively, if you use a Render Paid Team plan with dedicated static outbound IPs, add only Render's static IPs).*
5. Click **Save**.

---

## 6. Obtain Your Azure SQL Connection String

In the Azure Portal, open your `ApprovalWorkflowDB` database:
1. Click **Connection strings** under **Settings** on the left menu.
2. Select the **ADO.NET (SQL authentication)** tab.
3. The format looks like:
   ```text
   Server=tcp:<your-server-name>.database.windows.net,1433;Initial Catalog=ApprovalWorkflowDB;Persist Security Info=False;User ID=<your-username>;Password=<your-password>;MultipleActiveResultSets=False;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;
   ```
4. Replace `<your-password>` with your actual SQL admin password.

---

## 7. Create and Deploy Web Service on Render

1. Log in to your [Render Dashboard](https://dashboard.render.com).
2. Click **New +** -> **Web Service**.
3. Choose **Build and deploy from a Git repository**.
4. Select or connect your GitHub repository: `https://github.com/lisaajose/approval-page`.
5. Configure the service settings:
   - **Name**: e.g., `approval-workflow-app`
   - **Region**: Choose the region closest to your Azure SQL server (e.g. *Oregon (US West)* or *Ohio (US East)*).
   - **Branch**: `main`
   - **Runtime**: **Docker** *(Render detects the root `Dockerfile` automatically)*.
   - **Instance Type**: **Free** (or Starter/Standard).
6. Expand the **Environment Variables** section and add:

| Key | Value | Description |
|---|---|---|
| `ASPNETCORE_ENVIRONMENT` | `Production` | Sets ASP.NET Core environment to Production. |
| `ConnectionStrings__ApprovalWorkflowDb` | `Server=tcp:<your-server>.database.windows.net,1433;Initial Catalog=ApprovalWorkflowDB;Persist Security Info=False;User ID=<admin>;Password=<password>;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;` | Production Azure SQL connection string. Uses double underscores `__` to map into `ConnectionStrings:ApprovalWorkflowDb`. |

7. Click **Create Web Service**.

---

## 8. Monitor Build, Deployment, and Runtime Logs

1. **Build Logs**:
   - Render runs `docker build` using the multi-stage Dockerfile.
   - It will download `mcr.microsoft.com/dotnet/sdk:8.0`, restore NuGet packages, and publish `ApprovalWorkflow.dll`.
   - The final stage copies the published binaries into `mcr.microsoft.com/dotnet/aspnet:8.0`.
2. **Runtime Logs**:
   - Render launches the container and supplies the dynamic `$PORT` variable (typically port 10000).
   - The entrypoint binds Kestrel to `http://0.0.0.0:${PORT}`.
   - You should see:
     ```text
     info: Microsoft.Hosting.Lifetime[14]
           Now listening on: http://0.0.0.0:10000
     info: Microsoft.Hosting.Lifetime[0]
           Application started. Press Ctrl+C to shut down.
     info: Microsoft.Hosting.Lifetime[0]
           Hosting environment: Production
     ```
3. Once the health check passes, Render assigns your public URL:
   `https://<your-service-name>.onrender.com`

---

## 9. Comprehensive End-to-End Verification

Open `https://<your-service-name>.onrender.com` in your browser:

### A. Authentication & Roles
- Default seed user credentials:
  - **JP** (UserId: `1`, Password: `1`, Role: 1 - Finance / Creator / Level 0 Approver)
  - **Smitha** (UserId: `2`, Password: `2`, Role: 2 - Level 1 Approver)
  - **PM** (UserId: `3`, Password: `3`, Role: 2 - Level 2 Approver)
  - **EDWIN** (UserId: `5`, Password: `5`, Role: 2 - Level 3 Approver)
  - **GAUTHAM** (UserId: `1012`, Password: `1012`, Role: 2 - Level 4 Approver)
- Log in as **JP** (password `1`). Verify login succeeds and redirects to the Voucher list page.

### B. Level 0 Auto-Approval Test (<= ₹50)
1. Click **Create Voucher**.
2. Voucher No: `VCH-PROD-001`, Amount: `45.00`, Narration: `Level 0 Auto approval verification`.
3. Click **Submit Voucher**.
4. Verify: Status is immediately **Approved** (`iAuthStatus = 1`), Level 0 is auto-approved by JP.

### C. Multi-Level Sequential Approval Test (> ₹1000)
1. While logged in as **JP**, click **Create Voucher**.
2. Voucher No: `VCH-PROD-002`, Amount: `1500.00`, Narration: `Level 4 Multi-stage verification`.
3. Click **Submit Voucher**.
4. Verify: Status is **Pending** (`iAuthStatus = 0`), Workflow Level: **4**.
5. Log out and log in as **Smitha** (UserId `2`, password `2`).
6. Go to **Pending Approvals** (`/Approval/Pending`). You should see `VCH-PROD-002` waiting for Stage 1.
7. Click **Approve**. Confirm Stage 1 completes.
8. Log in sequentially as **PM** (Level 2), **EDWIN** (Level 3), and **GAUTHAM** (Level 4) to approve stages 2, 3, and 4.
9. Verify: After Gautham's approval, the voucher status transitions to **Approved**.

### D. Rejection Test
1. Log in as **JP**, create a voucher with Amount `250.00` (Level 2).
2. Log in as **Smitha**, reject the voucher with comment `"Rejected for budget review"`.
3. Verify: Voucher status transitions to **Rejected** (`iAuthStatus = 2`). Preceding and subsequent actions lock down permanently.
