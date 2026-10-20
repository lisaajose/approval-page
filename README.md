# Amount-Based Approval Workflow Management System
## ASP.NET Core MVC (.NET 8) + Microsoft SQL Server Express

A complete, production-ready implementation of an **Amount-Based Financial Voucher Approval Workflow System** built with **ASP.NET Core MVC (.NET 8)** and **Microsoft SQL Server Express**.

---

## 1. Architectural Overview & Design Philosophy

The core architectural requirement is that **all business workflow logic, state transitions, validation, approval routing, and concurrency controls reside strictly within SQL Server Stored Procedures**.

The .NET web layer serves as a responsive, secure presentation interface that interacts with SQL Server exclusively through parameterized stored procedure calls using `Microsoft.Data.SqlClient`.

```
+-------------------------------------------------------------------------+
|                  ASP.NET Core MVC Application (.NET 8)                  |
|                                                                         |
|  [VoucherController]    [ApprovalController]    [AuthController]        |
|           \                      /                       |              |
|        [IVoucherService]    [IApprovalService]   [IUserContextService]  |
|           (VoucherService)     (ApprovalService)   (UserContextService) |
|                   \                  /                   |              |
|              [ISqlConnectionFactory] (SqlConnection)     |              |
+--------------------------|----------------------------------------------+
                           | Microsoft.Data.SqlClient (ADO.NET)
                           | CommandType.StoredProcedure
                           v
+-------------------------------------------------------------------------+
|               Microsoft SQL Server Express (ApprovalWorkflowDB)         |
|                                                                         |
|   Unified Workflow Engine:                                              |
|   • dbo.usp_ApprovalWorkflow     (Unified SAVE, APPROVE, REJECT actions)|
|                                                                         |
|   Specialized Stored Procedures:                                        |
|   • dbo.usp_SaveVoucher          (Transactional creation & assignments) |
|   • dbo.usp_GetPendingApprovals  (Sequential queue for active user)     |
|   • dbo.usp_GetVoucherDetails    (Header, 4-cell panel, history, notifs)|
|   • dbo.usp_ApproveVoucher       (UPDLOCK concurrency & stage advance)  |
|   • dbo.usp_RejectVoucher        (Atomic rejection & termination)       |
|   • dbo.usp_GetNotifications     (Isolated notification query)          |
|   • dbo.usp_ValidateUserLogin    (Credential & active user validation)  |
|                                                                         |
|   Deterministic Rules & Views:                                          |
|   • dbo.fn_GetVoucherApprovalLevel (Amount boundary resolution)         |
|   • dbo.vw_VoucherSummary          (Consolidated projection)            |
|                                                                         |
|   Core Tables:                                                          |
|   • M_Users             • t_Header            • t_Authdata              |
|   Supporting Tables:                                                    |
|   • t_ApprovalHistory                                                   |
+-------------------------------------------------------------------------+
```

---

## 2. Business Workflow & Amount Boundary Matrix

The financial amount of each voucher automatically determines its approval level and required sequential approvers:

| Level | Amount Range | Notification Recipient | Approval Sequence | Workflow Behavior on Save |
|:---:|:---|:---:|:---|:---|
| **Level 0** | ₹0.00 – ₹50.00 | **JP** | *No approval required* | **Auto-Approved immediately** (`iAuthStatus = 1`, `dPostDate` set). Notification recorded for JP. |
| **Level 1** | ₹50.01 – ₹100.00 | **JP** | **Lisa** | Pending Level 1 approval. JP receives notification. |
| **Level 2** | ₹100.01 – ₹500.00 | **JP** | **Lisa** &rarr; **Gautham** | 2-Stage Sequential. Lisa must approve before Gautham can act. |
| **Level 3** | ₹500.01 – ₹1,000.00 | **JP** | **Lisa** &rarr; **Gautham** &rarr; **Edwin** | 3-Stage Sequential. Preceding stages must complete in order. |
| **Level 4** | > ₹1,000.00 | **JP** | **Lisa** &rarr; **Gautham** &rarr; **Edwin** &rarr; **JP** | 4-Stage Sequential. JP acts as final approver. |

*Note: Boundary ranges are upper-inclusive and strictly centralized in `dbo.fn_GetVoucherApprovalLevel`.*

---

## 3. Database Schema

### 3.1 `M_Users`
- `UserId` (INT IDENTITY PRIMARY KEY): User primary key.
- `Username` (NVARCHAR(20) NOT NULL UNIQUE): User login handle.
- `Password` (NVARCHAR(256) NOT NULL): User credential validated via `dbo.usp_ValidateUserLogin`.
- `Email` (NVARCHAR(50) NOT NULL): User email address.
- `CreatedDate` (DATETIME): Account creation timestamp.
- `LastLoginDate` (DATETIME NULL): Updated upon successful authentication.
- `Bactive` (BIT DEFAULT 1): Active user flag.
- `UserRole` (INT NULL): Role classification (`1` = Admin, `2` = Approver).

### 3.2 `t_Header`
- `iHeaderId` (INT IDENTITY PRIMARY KEY): Voucher ID.
- `Svoucherno` (NVARCHAR(50) NOT NULL UNIQUE): Voucher number identifier.
- `dDate` (DATE NOT NULL): Voucher transaction date.
- `sNarration` (NVARCHAR(100) NULL): Transaction description.
- `Amount` (DECIMAL(18,2) NOT NULL): Currency value.
- `iAuthStatus` (INT NOT NULL): `0` = Pending, `1` = Approved, `2` = Rejected.
- `dPostDate` (DATE NULL): Recorded on final approval; `NULL` while pending or rejected.
- `CreatedDate`, `CreatedBy`: Audit metadata.

### 3.3 `t_Authdata`
- `iAuthId` (INT IDENTITY PRIMARY KEY): Task ID.
- `iHeaderId` (INT NOT NULL FK): Reference to `t_Header`.
- `iAlerttype` (INT NOT NULL): `0` = Notification, `1` = Approval Alert.
- `iLevel` (INT NOT NULL): Workflow level (0 to 4).
- `iUserType` (INT NOT NULL): `1` = User, `2` = Role, `3` = Employee.
- `iUser` (INT NOT NULL): Assigned recipient ID.
- `sAlerts` (NVARCHAR(100) NULL): Alert description.
- `sUsercomments` (NVARCHAR(100) NULL): Decision remarks recorded on action.
- `iStepOrder` (INT NOT NULL): Sequence position (1, 2, 3, 4).
- `iStatus` (INT NOT NULL): `0` = Pending, `1` = Approved, `2` = Rejected, `3` = Notified.
- `dActionDate` (DATETIME NULL): Timestamp when stage was actioned.
- `iActionedBy` (INT NULL): User ID who completed the action.

### 3.4 `t_ApprovalHistory`
- `iHistoryId` (INT IDENTITY PRIMARY KEY): Immutable event record.
- `iHeaderId` (INT NOT NULL FK): Target voucher.
- `sAction` (NVARCHAR(20) NOT NULL): `CREATED`, `AUTO_APPROVED`, `APPROVED`, `REJECTED`.
- `sComments` (NVARCHAR(250) NULL): Remarks recorded with action.
- `dActionDate` (DATETIME NOT NULL): Timestamp.

---

## 4. Database Setup & Execution Order

All SQL scripts are idempotent and located in `Database/`:

1. `01_CreateDatabase.sql`: Creates database and enables Read Committed Snapshot Isolation (RCSI).
2. `02_CreateTables.sql`: Creates tables with proper data types and primary keys.
3. `03_CreateConstraintsAndIndexes.sql`: Adds foreign keys, check constraints, and composite indexes.
4. `04_SeedUsers.sql`: Seeds user accounts with preserved IDs using `SET IDENTITY_INSERT`.
5. `05_CreateFunctionsAndViews.sql`: Creates scalar functions and summary views.
6. `06_CreateStoredProcedures.sql`: Compiles workflow stored procedures including `usp_ApprovalWorkflow`.
7. `07_TestWorkflow.sql`: Automated test suite covering 19 functional and security scenarios.
8. `08_AddApprovalWorkflowProcedure.sql`: Unified workflow entry point procedure.

Execute via `sqlcmd`:
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

## 5. Security & Authentication Architecture

- **Encrypted Cookie Authentication**: Built on ASP.NET Core Data Protection (`HMAC-SHA256` signed and encrypted tickets).
- **HTTP Protection Flags**: `HttpOnly`, `SameSite=Lax`, and sliding expiration enabled.
- **Rate Limiting**: Configured with fixed-window partition limiting on login endpoints (`HTTP 429` on excessive attempts).
- **Stored Procedure Validation**: Login credentials verified through `dbo.usp_ValidateUserLogin` with active account verification.
- **CSRF Defense**: All POST actions protected with ASP.NET Core Anti-Forgery Tokens (`[ValidateAntiForgeryToken]`).
- **Concurrency Protection**: Stored procedures utilize `WITH (UPDLOCK, ROWLOCK)` in atomic transactions to prevent double-approvals or race conditions.

---

## 6. User Interface Features

- **Responsive Sidebar & Navigation**: Context-aware navigation with active route highlights.
- **Notifications Menu**: Accessible exclusively to the designated notification recipient (JP).
- **Four-Cell Approval Details Panel**: Arranged vertically for Lisa, Gautham, Edwin, and JP displaying step order, alert type, workflow level, alert message, comments, and real-time status.
- **In-Place Actions**: Approve and Reject actions with comment inputs appear directly within the active stage card for the authorized approver.
- **Auth Info Modal**: Accessible on the voucher page, displaying the task assignment matrix and complete audit history trail.
- **Clean Form Interface**: Clean transaction creation with dynamic approval level and routing previews.

---

## 7. How to Run

### Prerequisites
- .NET 8.0 SDK
- Microsoft SQL Server Express (`.\SQLEXPRESS`)

### Run Application
```powershell
# Restore and build
dotnet build

# Run application on localhost
dotnet run --urls "http://localhost:5000"
```

Navigate to: `http://localhost:5000`
