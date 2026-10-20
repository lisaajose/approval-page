-- ==============================================================================
-- Script: 02_CreateTables.sql
-- Description: Creates the core tables (M_Users, t_Header, t_Authdata)
--              and the supporting audit table (t_ApprovalHistory).
-- ==============================================================================

USE [ApprovalWorkflowDB];
GO

-- 1. Table: M_Users (Original table with exact names and preserved columns)
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'M_Users')
BEGIN
    PRINT 'Creating table [M_Users]...';
    CREATE TABLE M_Users
    (
        UserId        INT IDENTITY(1,1) NOT NULL,
        Username      NVARCHAR(20) NOT NULL,
        Password      NVARCHAR(256) NOT NULL, -- Sized to accommodate SHA-256 / PBKDF2 hash representations
        Email         NVARCHAR(50) NOT NULL,
        CreatedDate   DATETIME NOT NULL CONSTRAINT DF_M_Users_CreatedDate DEFAULT GETDATE(),
        LastLoginDate DATETIME NULL,
        Bactive       BIT NULL CONSTRAINT DF_M_Users_Bactive DEFAULT 1,
        UserRole      INT NULL
    );
    PRINT 'Table [M_Users] created.';
END
ELSE
BEGIN
    PRINT 'Table [M_Users] already exists.';
END
GO

-- 2. Table: t_Header (Original table with exact names and preserved columns)
-- Authorization status: 0 = Pending, 1 = Approved, 2 = Rejected
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 't_Header')
BEGIN
    PRINT 'Creating table [t_Header]...';
    CREATE TABLE t_Header
    (
        iHeaderId    INT IDENTITY(1,1) NOT NULL,
        Svoucherno   NVARCHAR(50) NOT NULL,
        dDate        DATE NOT NULL CONSTRAINT DF_t_Header_dDate DEFAULT CAST(GETDATE() AS DATE),
        sNarration   NVARCHAR(100) NULL,
        Amount       DECIMAL(18,2) NOT NULL,
        iAuthStatus  INT NOT NULL CONSTRAINT DF_t_Header_iAuthStatus DEFAULT 0,
        dPostDate    DATE NULL,
        CreatedDate  DATETIME NOT NULL CONSTRAINT DF_t_Header_CreatedDate DEFAULT GETDATE(),
        CreatedBy    INT NULL
    );
    PRINT 'Table [t_Header] created.';
END
ELSE
BEGIN
    PRINT 'Table [t_Header] already exists.';
END
GO

-- 3. Table: t_Authdata (Original table preserved with essential workflow tracking columns)
-- iAlerttype: 0 = Notification, 1 = Approval Alert
-- iUserType:  1 = User, 2 = Role, 3 = Employee
-- iStatus:    0 = Pending, 1 = Approved, 2 = Rejected, 3 = Notified / Info
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 't_Authdata')
BEGIN
    PRINT 'Creating table [t_Authdata]...';
    CREATE TABLE t_Authdata
    (
        iAuthId        INT IDENTITY(1,1) NOT NULL,
        iHeaderId      INT NOT NULL,
        iAlerttype     INT NOT NULL,       -- 0 = Notification, 1 = Approval Alert
        iLevel         INT NOT NULL,       -- Approval Level (0, 1, 2, 3, 4)
        iUserType      INT NOT NULL,       -- 1 = User, 2 = Role, 3 = Employee
        iUser          INT NOT NULL,       -- User ID, Role ID, or Employee ID
        sAlerts        NVARCHAR(100) NULL, -- Alert message / prompt
        sUsercomments  NVARCHAR(100) NULL, -- User comments on action
        iStepOrder     INT NOT NULL CONSTRAINT DF_t_Authdata_iStepOrder DEFAULT 1, -- Sequential stage order (1..4)
        iStatus        INT NOT NULL CONSTRAINT DF_t_Authdata_iStatus DEFAULT 0,    -- 0 = Pending, 1 = Approved, 2 = Rejected, 3 = Notified
        dActionDate    DATETIME NULL,      -- Timestamp when approval/rejection was recorded
        iActionedBy    INT NULL            -- The actual UserId who performed the action
    );
    PRINT 'Table [t_Authdata] created.';
END
ELSE
BEGIN
    PRINT 'Table [t_Authdata] already exists.';
END
GO

-- 4. Table: t_ApprovalHistory (Supporting audit log table)
-- Records an immutable history of every workflow lifecycle event
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 't_ApprovalHistory')
BEGIN
    PRINT 'Creating table [t_ApprovalHistory]...';
    CREATE TABLE t_ApprovalHistory
    (
        iHistoryId    INT IDENTITY(1,1) NOT NULL,
        iHeaderId     INT NOT NULL,
        iLevel        INT NOT NULL,
        iStepOrder    INT NOT NULL,
        iActionUser   INT NOT NULL,
        sAction       NVARCHAR(20) NOT NULL, -- 'CREATED', 'AUTO_APPROVED', 'APPROVED', 'REJECTED'
        sComments     NVARCHAR(250) NULL,
        dActionDate   DATETIME NOT NULL CONSTRAINT DF_t_ApprovalHistory_dActionDate DEFAULT GETDATE()
    );
    PRINT 'Table [t_ApprovalHistory] created.';
END
ELSE
BEGIN
    PRINT 'Table [t_ApprovalHistory] already exists.';
END
GO
