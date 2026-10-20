-- ==============================================================================
-- Script: 03_CreateConstraintsAndIndexes.sql
-- Description: Creates primary keys, foreign keys, unique constraints,
--              check constraints, and indexes for data integrity and performance.
-- ==============================================================================

USE [ApprovalWorkflowDB];
GO

-- 1. Primary Keys
IF NOT EXISTS (SELECT * FROM sys.key_constraints WHERE name = 'PK_M_Users')
BEGIN
    ALTER TABLE M_Users ADD CONSTRAINT PK_M_Users PRIMARY KEY CLUSTERED (UserId);
    PRINT 'Primary key [PK_M_Users] created.';
END
GO

IF NOT EXISTS (SELECT * FROM sys.key_constraints WHERE name = 'PK_t_Header')
BEGIN
    ALTER TABLE t_Header ADD CONSTRAINT PK_t_Header PRIMARY KEY CLUSTERED (iHeaderId);
    PRINT 'Primary key [PK_t_Header] created.';
END
GO

IF NOT EXISTS (SELECT * FROM sys.key_constraints WHERE name = 'PK_t_Authdata')
BEGIN
    ALTER TABLE t_Authdata ADD CONSTRAINT PK_t_Authdata PRIMARY KEY CLUSTERED (iAuthId);
    PRINT 'Primary key [PK_t_Authdata] created.';
END
GO

IF NOT EXISTS (SELECT * FROM sys.key_constraints WHERE name = 'PK_t_ApprovalHistory')
BEGIN
    ALTER TABLE t_ApprovalHistory ADD CONSTRAINT PK_t_ApprovalHistory PRIMARY KEY CLUSTERED (iHistoryId);
    PRINT 'Primary key [PK_t_ApprovalHistory] created.';
END
GO

-- 2. Unique Constraints
IF NOT EXISTS (SELECT * FROM sys.key_constraints WHERE name = 'UQ_M_Users_Username')
BEGIN
    ALTER TABLE M_Users ADD CONSTRAINT UQ_M_Users_Username UNIQUE NONCLUSTERED (Username);
    PRINT 'Unique constraint [UQ_M_Users_Username] created.';
END
GO

IF NOT EXISTS (SELECT * FROM sys.key_constraints WHERE name = 'UQ_t_Header_Svoucherno')
BEGIN
    ALTER TABLE t_Header ADD CONSTRAINT UQ_t_Header_Svoucherno UNIQUE NONCLUSTERED (Svoucherno);
    PRINT 'Unique constraint [UQ_t_Header_Svoucherno] created.';
END
GO

-- 3. Foreign Keys
-- Cascade delete on voucher header deletion for clean cleanup in tests/management
IF NOT EXISTS (SELECT * FROM sys.foreign_keys WHERE name = 'FK_t_Authdata_t_Header')
BEGIN
    ALTER TABLE t_Authdata ADD CONSTRAINT FK_t_Authdata_t_Header
        FOREIGN KEY (iHeaderId) REFERENCES t_Header(iHeaderId) ON DELETE CASCADE;
    PRINT 'Foreign key [FK_t_Authdata_t_Header] created.';
END
GO

IF NOT EXISTS (SELECT * FROM sys.foreign_keys WHERE name = 'FK_t_ApprovalHistory_t_Header')
BEGIN
    ALTER TABLE t_ApprovalHistory ADD CONSTRAINT FK_t_ApprovalHistory_t_Header
        FOREIGN KEY (iHeaderId) REFERENCES t_Header(iHeaderId) ON DELETE CASCADE;
    PRINT 'Foreign key [FK_t_ApprovalHistory_t_Header] created.';
END
GO

-- NOTE ON iUser FOREIGN KEY:
-- As required by the schema design specifications, t_Authdata.iUser can refer to a UserId (iUserType=1),
-- a RoleId (iUserType=2), or an EmpId (iUserType=3). A simplistic unconditional FK to M_Users.UserId
-- would violate this polymorphism. Validation is strictly enforced at the stored procedure layer when iUserType = 1.

-- 4. Check Constraints
IF NOT EXISTS (SELECT * FROM sys.check_constraints WHERE name = 'CK_t_Header_Amount')
BEGIN
    ALTER TABLE t_Header ADD CONSTRAINT CK_t_Header_Amount CHECK (Amount >= 0.00);
    PRINT 'Check constraint [CK_t_Header_Amount] created.';
END
GO

IF NOT EXISTS (SELECT * FROM sys.check_constraints WHERE name = 'CK_t_Header_iAuthStatus')
BEGIN
    ALTER TABLE t_Header ADD CONSTRAINT CK_t_Header_iAuthStatus CHECK (iAuthStatus IN (0, 1, 2));
    PRINT 'Check constraint [CK_t_Header_iAuthStatus] created.';
END
GO

IF NOT EXISTS (SELECT * FROM sys.check_constraints WHERE name = 'CK_t_Authdata_iAlerttype')
BEGIN
    ALTER TABLE t_Authdata ADD CONSTRAINT CK_t_Authdata_iAlerttype CHECK (iAlerttype IN (0, 1));
    PRINT 'Check constraint [CK_t_Authdata_iAlerttype] created.';
END
GO

IF NOT EXISTS (SELECT * FROM sys.check_constraints WHERE name = 'CK_t_Authdata_iUserType')
BEGIN
    ALTER TABLE t_Authdata ADD CONSTRAINT CK_t_Authdata_iUserType CHECK (iUserType IN (1, 2, 3));
    PRINT 'Check constraint [CK_t_Authdata_iUserType] created.';
END
GO

IF NOT EXISTS (SELECT * FROM sys.check_constraints WHERE name = 'CK_t_Authdata_iStatus')
BEGIN
    ALTER TABLE t_Authdata ADD CONSTRAINT CK_t_Authdata_iStatus CHECK (iStatus IN (0, 1, 2, 3));
    PRINT 'Check constraint [CK_t_Authdata_iStatus] created.';
END
GO

-- 5. Indexes for fast query lookup and concurrency protection
IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'IX_t_Header_Status_Date')
BEGIN
    CREATE NONCLUSTERED INDEX IX_t_Header_Status_Date
    ON t_Header (iAuthStatus, dDate)
    INCLUDE (Svoucherno, Amount);
    PRINT 'Index [IX_t_Header_Status_Date] created.';
END
GO

IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'IX_t_Authdata_PendingApprovals')
BEGIN
    CREATE NONCLUSTERED INDEX IX_t_Authdata_PendingApprovals
    ON t_Authdata (iUser, iAlerttype, iStatus, iStepOrder)
    INCLUDE (iHeaderId, iLevel, sAlerts);
    PRINT 'Index [IX_t_Authdata_PendingApprovals] created.';
END
GO

IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'IX_t_Authdata_HeaderLookup')
BEGIN
    CREATE NONCLUSTERED INDEX IX_t_Authdata_HeaderLookup
    ON t_Authdata (iHeaderId, iStepOrder)
    INCLUDE (iAlerttype, iUser, iStatus, dActionDate);
    PRINT 'Index [IX_t_Authdata_HeaderLookup] created.';
END
GO

IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'IX_t_ApprovalHistory_Header')
BEGIN
    CREATE NONCLUSTERED INDEX IX_t_ApprovalHistory_Header
    ON t_ApprovalHistory (iHeaderId, dActionDate);
    PRINT 'Index [IX_t_ApprovalHistory_Header] created.';
END
GO
