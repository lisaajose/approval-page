# Amount-Based Approval Workflow System
## .NET + C# + Microsoft SQL Server Express + SSMS

A complete, production-grade implementation of an **Amount-Based Financial Voucher Approval Workflow System** built with **ASP.NET Core MVC (.NET 10)** and **Microsoft SQL Server Express**.

---

## 1. Architectural Overview & Design Philosophy

The core architectural requirement of this system is that **all business workflow logic, state transitions, validation, and concurrency controls reside strictly within the database** via SQL Server Stored Procedures, Functions, and Transactions.

The .NET application acts as an ergonomic, secure presentation and orchestration layer that communicates with SQL Server Express exclusively through `Microsoft.Data.SqlClient` using parameterized stored procedure calls.

```
+-------------------------------------------------------------------------+
|                  ASP.NET Core MVC Application (.NET 10)                 |
|                                                                         |
|  [VoucherController]    [ApprovalController]    [UserContextService]    |
|           \                      /                       |              |
|        [IVoucherService]    [IApprovalService]           |              |
|           (VoucherService)     (ApprovalService)         |              |
|                   \                  /                   |              |
|              [ISqlConnectionFactory] (SqlConnection)     |              |
+--------------------------|----------------------------------------------+
                           | Microsoft.Data.SqlClient (ADO.NET)
                           | CommandType.StoredProcedure
                           v
+-------------------------------------------------------------------------+
|               Microsoft SQL Server Express (ApprovalWorkflowDB)         |
|                                                                         |
|   Stored Procedures:                                                    |
|   • dbo.usp_SaveVoucher          (Transactional creation & assignments) |
|   • dbo.usp_GetPendingApprovals  (Sequential queue for active user)     |
|   • dbo.usp_GetVoucherDetails    (Header, 4-slot panel, notifs, audit) |
|   • dbo.usp_ApproveVoucher       (UPDLOCK concurrency & stage advance)  |
|   • dbo.usp_RejectVoucher        (Atomic rejection & termination)       |
|   • dbo.usp_GetNotifications     (Isolated notification query)          |
|                                                                         |
|   Database Rules & Logic:                                               |
|   • dbo.fn_GetVoucherApprovalLevel (Deterministic boundary function)   |
|   • dbo.vw_VoucherSummary          (Read-only consolidated projection)  |
|                                                                         |
|   Preserved Core Tables:                                                |
|   • M_Users             • t_Header            • t_Authdata              |
|   Supporting Tables:                                                    |
|   • t_ApprovalHistory                                                   |
+-------------------------------------------------------------------------+
```

---

## 2. Business Workflow & Amount Boundary Policy

The financial amount of each voucher determines its approval level and required sequential approvers.

### Confirmed Boundary Resolution (Upper-Inclusive Policy):
As confirmed during design clarification, boundaries are resolved upper-inclusively to remove overlap ambiguity:

| Level | Amount Range | Notification Recipient | Approval Sequence | Behavior on Save |
|:---:|:---|:---:|:---|:---|
| **Level 0** | ₹0.00 – ₹50.00 | **JP** (UserId: 1) | *No approver required* | **Auto-Approved immediately** (`iAuthStatus = 1`, `dPostDate` set). Notification recorded for JP. |
| **Level 1** | ₹50.01 – ₹100.00 | **JP** (UserId: 1) | **Lisa** (UserId: 13) | Pending Lisa approval (`iAuthStatus = 0`). JP notified. |
| **Level 2** | ₹100.01 – ₹500.00 | **JP** (UserId: 1) | **Lisa** (13) &rarr; **Gautham** (1012) | 2-Stage Sequential. Lisa must approve first before Gautham can act. |
| **Level 3** | ₹500.01 – ₹1,000.00 | **JP** (UserId: 1) | **Lisa** (13) &rarr; **Gautham** (1012) &rarr; **Edwin** (5) | 3-Stage Sequential. Preceding stages must complete in exact order. |
| **Level 4** | > ₹1,000.00 | **JP** (UserId: 1) | **Lisa** (13) &rarr; **Gautham** (1012) &rarr; **Edwin** (5) &rarr; **JP** (1) | 4-Stage Sequential. JP is final approver. |

> **Important Boundary Isolation**: The boundary evaluation logic is strictly centralized in the SQL scalar function `dbo.fn_GetVoucherApprovalLevel(@Amount)`. Boundary ranges are not scattered or duplicated across procedures.

---

## 3. Preserved Database Schema & Extensions

### 3.1 `M_Users` (Preserved)
- `UserId` (INT IDENTITY PRIMARY KEY): Seeded with exact original IDs (`1, 2, 3, 5, 11, 12, 13, 1012`).
- `Username` (NVARCHAR(20) NOT NULL UNIQUE)
- `Password` (NVARCHAR(256) NOT NULL): Sized for secure hash support; seeded with development placeholder hashes (`DevPlaceholderHash_Password123!`).
- `Email` (NVARCHAR(50) NOT NULL): Seeded with local dev placeholders (`<username>@approvalworkflow.local`).
- `CreatedDate` (DATETIME DEFAULT GETDATE())
- `LastLoginDate` (DATETIME NULL)
- `Bactive` (BIT DEFAULT 1)
- `UserRole` (INT NULL)

### 3.2 `t_Header` (Preserved)
- `iHeaderId` (INT IDENTITY PRIMARY KEY)
- `Svoucherno` (NVARCHAR(50) NOT NULL UNIQUE)
- `dDate` (DATE NOT NULL DEFAULT GETDATE())
- `sNarration` (NVARCHAR(100) NULL)
- `Amount` (DECIMAL(18,2) NOT NULL CHECK >= 0.00)
- `iAuthStatus` (INT NOT NULL CHECK IN (0, 1, 2)): `0` = Pending, `1` = Approved, `2` = Rejected
- `dPostDate` (DATE NULL): Populated when fully approved. Remains `NULL` while pending or rejected.
- `CreatedDate`, `CreatedBy` (Audit tracking)

### 3.3 `t_Authdata` (Preserved with Workflow Columns)
- `iAuthId` (INT IDENTITY PRIMARY KEY)
- `iHeaderId` (INT NOT NULL FK to `t_Header`)
- `iAlerttype` (INT NOT NULL CHECK IN (0, 1)): `0` = Notification, `1` = Approval Alert
- `iLevel` (INT NOT NULL): Workflow Level (0, 1, 2, 3, 4)
- `iUserType` (INT NOT NULL CHECK IN (1, 2, 3)): `1` = User, `2` = Role, `3` = Employee
- `iUser` (INT NOT NULL): Assigned recipient ID
- `sAlerts` (NVARCHAR(100) NULL): Notification / Alert message
- `sUsercomments` (NVARCHAR(100) NULL): User remarks on approval/rejection
- `iStepOrder` (INT NOT NULL DEFAULT 1): Sequential stage number (1, 2, 3, 4)
- `iStatus` (INT NOT NULL DEFAULT 0): `0` = Pending, `1` = Approved, `2` = Rejected, `3` = Notified
- `dActionDate` (DATETIME NULL)
- `iActionedBy` (INT NULL)

### 3.4 `t_ApprovalHistory` (Supporting Immutable Audit Log)
- `iHistoryId` (INT IDENTITY PRIMARY KEY)
- `iHeaderId` (INT NOT NULL FK to `t_Header`)
- `iLevel` (INT NOT NULL)
- `iStepOrder` (INT NOT NULL)
- `iActionUser` (INT NOT NULL)
- `sAction` (NVARCHAR(20) NOT NULL): `'CREATED'`, `'AUTO_APPROVED'`, `'APPROVED'`, `'REJECTED'`
- `sComments` (NVARCHAR(250) NULL)
- `dActionDate` (DATETIME NOT NULL DEFAULT GETDATE())

---

## 4. SQL Scripts Organization & Execution Order

All database scripts are located in the `Database/` directory and are safe to run repeatedly (idempotent):

| Script | Purpose | Execution Notes |
|:---|:---|:---|
| `01_CreateDatabase.sql` | Creates `ApprovalWorkflowDB` and enables Read Committed Snapshot Isolation (RCSI). | Run against `master`. |
| `02_CreateTables.sql` | Creates `M_Users`, `t_Header`, `t_Authdata`, and `t_ApprovalHistory`. | Run against `ApprovalWorkflowDB`. |
| `03_CreateConstraintsAndIndexes.sql` | Adds PKs, FKs, Unique constraints, Check constraints, and composite lookup indexes. | Run against `ApprovalWorkflowDB`. |
| `04_SeedUsers.sql` | Seeds the 8 users with preserved IDs using `SET IDENTITY_INSERT`. | Run against `ApprovalWorkflowDB`. |
| `05_CreateFunctionsAndViews.sql` | Creates `dbo.fn_GetVoucherApprovalLevel` and `dbo.vw_VoucherSummary`. | Run against `ApprovalWorkflowDB`. |
| `06_CreateStoredProcedures.sql` | Compiles `usp_SaveVoucher`, `usp_GetPendingApprovals`, `usp_GetVoucherDetails`, `usp_ApproveVoucher`, `usp_RejectVoucher`, `usp_GetNotifications`, and `usp_GetAllUsers`. | Run against `ApprovalWorkflowDB`. |
| `07_TestWorkflow.sql` | Automated test suite validating all 19 functional and security scenarios. | Run against `ApprovalWorkflowDB`. |

### Executing Scripts in SSMS:
1. Open **SQL Server Management Studio (SSMS)**.
2. Connect to `.\SQLEXPRESS` (ensure **Trust Server Certificate** is checked).
3. Open files `01_CreateDatabase.sql` through `07_TestWorkflow.sql` in order and execute each (`F5`).

### Or via `sqlcmd`:
```powershell
sqlcmd -S ".\SQLEXPRESS" -E -C -i "Database\01_CreateDatabase.sql"
sqlcmd -S ".\SQLEXPRESS" -E -C -i "Database\02_CreateTables.sql"
sqlcmd -S ".\SQLEXPRESS" -E -C -i "Database\03_CreateConstraintsAndIndexes.sql"
sqlcmd -S ".\SQLEXPRESS" -E -C -i "Database\04_SeedUsers.sql"
sqlcmd -S ".\SQLEXPRESS" -E -C -i "Database\05_CreateFunctionsAndViews.sql"
sqlcmd -S ".\SQLEXPRESS" -E -C -i "Database\06_CreateStoredProcedures.sql"
sqlcmd -S ".\SQLEXPRESS" -E -C -i "Database\07_TestWorkflow.sql"
```

---

## 5. Stored Procedures & Transactional Concurrency

### 5.1 `dbo.usp_SaveVoucher`
- Validates voucher number uniqueness and positive amounts.
- Calls `dbo.fn_GetVoucherApprovalLevel(@Amount)` to assign workflow level.
- Wraps voucher creation, notification alert for JP, and sequential approval slots into an atomic transaction (`BEGIN TRANSACTION ... TRY ... CATCH ... ROLLBACK`).

### 5.2 `dbo.usp_GetPendingApprovals`
- Validates user exists and is active.
- Queries `t_Authdata` where `iAlerttype = 1` and `iUser = @UserId` and `iStatus = 0`.
- **Enforces sequential eligibility**: Excludes vouchers where any prerequisite step (`prevStep.iStepOrder < a.iStepOrder`) is not yet approved (`prevStep.iStatus <> 1`).

### 5.3 `dbo.usp_GetVoucherDetails`
- Returns 4 distinct result sets in a single call:
  1. Header information (with status, amounts, and current active pending assignee).
  2. The 4 sequential approval slots (with stage flags, assigned user, comments, and decision state).
  3. Notification records (JP notification).
  4. Audit history log from `t_ApprovalHistory`.

### 5.4 `dbo.usp_ApproveVoucher`
- Uses `SELECT ... FROM t_Header WITH (UPDLOCK, ROWLOCK)` to prevent race conditions during concurrent approval clicks.
- Validates that voucher is currently `Pending` (`0`). **Throws Error 50013 if rejected.**
- Enforces strict user authorization: acting user must match the assigned user for the lowest pending stage.
- Verifies all prerequisite stages are complete.
- When the final stage is approved, updates `t_Header.iAuthStatus = 1` and sets `dPostDate = GETDATE()`.

### 5.5 `dbo.usp_RejectVoucher`
- Uses row-level update lock (`UPDLOCK, ROWLOCK`).
- Checks voucher is `Pending`.
- Marks the active stage as `Rejected` (`2`) with mandatory comments.
- Terminates all subsequent stages for the voucher.
- Atomically sets `t_Header.iAuthStatus = 2` (Rejected).

---

## 6. The 4-Slot Vertical Approval Details UI

Per the Guide Line specification, the **Approval Details Screen** features a dedicated single panel containing **four cells or slots arranged vertically**:
- **Slot 1 (Level 1)**: Lisa (UserId: 13)
- **Slot 2 (Level 2)**: Gautham (UserId: 1012)
- **Slot 3 (Level 3)**: Edwin (UserId: 5)
- **Slot 4 (Level 4)**: JP (UserId: 1)

Each slot cleanly displays:
- **Step / Slot order badge**
- **Assigned User Name and User ID**
- **Alert Type** (`Approval Alert` vs `Notification`)
- **Workflow Level**
- **Alert message**
- **User comments**
- **Current status badge** (`Approved`, `Rejected`, `Current Pending Stage`, or `Waiting for Prerequisite Stage`).

### Security & In-Place Actions:
- Action buttons (**Approve** and **Reject**) with a comment input appear **only on the active pending stage**, and **only when the current user matches the assigned approver**.
- If a user views a stage waiting for someone else, the system displays a security indicator showing which approver is required.
- In the top navbar, an **Active Actor switcher** allows seamless switching between JP, Lisa, Gautham, and Edwin for live multi-user simulation.

---

## 7. How to Run the Web Application

### Prerequisites:
- .NET 10 SDK or .NET 8 SDK
- Microsoft SQL Server Express (`.\SQLEXPRESS`)
- SQL Server Management Studio (SSMS)

### Configuration:
In `appsettings.json`, the connection string is pre-configured for local SQL Server Express:
```json
{
  "ConnectionStrings": {
    "ApprovalWorkflowDb": "Server=.\\SQLEXPRESS;Database=ApprovalWorkflowDB;Trusted_Connection=True;TrustServerCertificate=True;Integrated Security=True;"
  }
}
```

### Launching the Application:
```powershell
# Restore packages & build
dotnet build

# Run application on port 5000
dotnet run --urls "http://localhost:5000"
```
Open your browser to:
[http://localhost:5000](http://localhost:5000)

---

## 8. Verified Test Results

### 8.1 SQL Server Automated Test Suite (`07_TestWorkflow.sql`):
**19 out of 19 automated database tests PASSED:**
1. Database Context (`ApprovalWorkflowDB`) — **PASS**
2. Core Tables Existence (`M_Users`, `t_Header`, `t_Authdata`, `t_ApprovalHistory`) — **PASS**
3. Seed Users Exact IDs (JP=1, LISA=13, GAUTHAM=1012, EDWIN=5, etc.) — **PASS**
4. Amount Boundary Evaluation (₹50, ₹100, ₹500, ₹1,000) — **PASS**
5. Level 0 (₹45.00) Auto-Approval & Notification to JP — **PASS**
6. Level 1 (₹75.00) Assignment to Lisa — **PASS**
7. Level 2 (₹250.00) Assignment to Lisa &rarr; Gautham — **PASS**
8. Level 3 (₹750.00) Step 3 Assigned to Edwin — **PASS**
9. Level 4 (₹1,500.00) 4 Stages with final stage to JP — **PASS**
10. Unauthorized User Approval Attempt Blocked (Error 50015) — **PASS**
11. Out-of-Order Approval Blocked (Prerequisite stage required) — **PASS**
12. Level 2 Multi-stage Approval Flow (Lisa &rarr; Gautham &rarr; Approved) — **PASS**
13. Attempt to Approve Already Approved Voucher Blocked (Error 50012) — **PASS**
14. Rejection Flow by Authorized Approver — **PASS**
15. Attempt to Approve a Rejected Voucher Blocked (Error 50013) — **PASS**
16. Negative Amount Validation Blocked (Error 50002) — **PASS**
17. Duplicate Voucher Number Validation Blocked (Error 50004) — **PASS**
18. Notification Isolation (JP Notification does not confer approval rights) — **PASS**
19. `usp_GetPendingApprovals` for Lisa — **PASS**

### 8.2 End-to-End Web Integration Test:
- **Voucher Creation**: Submitted `LIVE-E2E-001` (₹250.00) via HTTP POST; voucher was created and assigned to Level 2 (Lisa & Gautham) via `dbo.usp_SaveVoucher`.
- **Sequential Approval 1**: Lisa approved Step 1 via web POST; `t_Authdata` updated to status `1`.
- **Sequential Approval 2**: Gautham approved Step 2 via web POST; `t_Header` updated to status `1` (Approved) and `dPostDate` populated.
- **Rejection Flow**: Submitted `LIVE-E2E-002` (₹750.00, Level 3); Lisa rejected voucher; `t_Header` updated to status `2` (Rejected) and workflow terminated.
