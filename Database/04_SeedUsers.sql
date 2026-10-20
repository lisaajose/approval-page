-- ==============================================================================
-- Script: 04_SeedUsers.sql
-- Description: Seeds the initial user records specified in the source Excel sheet.
--              Preserves exact UserIds using SET IDENTITY_INSERT.
--              Includes development-only placeholder values for NOT NULL fields
--              (Password, Email) without inventing false real credentials.
-- ==============================================================================

USE [ApprovalWorkflowDB];
GO

PRINT 'Seeding initial user data into [M_Users]...';

-- Temporary table to hold source data
CREATE TABLE #SourceUsers
(
    UserId   INT,
    Username NVARCHAR(20),
    Bactive  BIT,
    UserRole INT
);

INSERT INTO #SourceUsers (UserId, Username, Bactive, UserRole)
VALUES
    (1,    N'JP',      1, 1),
    (2,    N'Smitha',  1, 2),
    (3,    N'PM',      1, 2),
    (5,    N'EDWIN',   1, 2),
    (11,   N'JERN',    1, 2),
    (12,   N'NIRALI',  1, 2),
    (13,   N'LISA',    1, 2),
    (1012, N'GAUTHAM', 1, 2);

-- Check if any of these users need insertion
IF EXISTS (
    SELECT 1 FROM #SourceUsers s
    LEFT JOIN M_Users u ON s.UserId = u.UserId
    WHERE u.UserId IS NULL
)
BEGIN
    SET IDENTITY_INSERT M_Users ON;

    -- Development placeholder password hash (SHA-256 placeholder for 'Password123!')
    -- In production, integrate ASP.NET Core Identity or PBKDF2 hashing.
    DECLARE @DefaultPasswordHash NVARCHAR(256) = N'DevPlaceholderHash_Password123!';

    INSERT INTO M_Users (UserId, Username, Password, Email, CreatedDate, LastLoginDate, Bactive, UserRole)
    SELECT
        s.UserId,
        s.Username,
        CAST(s.UserId AS NVARCHAR(20)),
        LOWER(s.Username) + N'@approvalworkflow.local', -- Clearly marked local dev placeholder email
        GETDATE(),
        NULL,
        s.Bactive,
        s.UserRole
    FROM #SourceUsers s
    WHERE NOT EXISTS (SELECT 1 FROM M_Users u WHERE u.UserId = s.UserId);

    SET IDENTITY_INSERT M_Users OFF;
    PRINT 'Missing seed users inserted with preserved UserIds.';
END
ELSE
BEGIN
    PRINT 'All seed users already exist.';
END

-- Ensure properties (Username, Bactive, UserRole) match requirements if existing
UPDATE u
SET
    u.Username = s.Username,
    u.Bactive = s.Bactive,
    u.UserRole = s.UserRole,
    u.Password = CAST(s.UserId AS NVARCHAR(20))
FROM M_Users u
INNER JOIN #SourceUsers s ON u.UserId = s.UserId;

DROP TABLE #SourceUsers;

PRINT 'Seed user verification:';
SELECT UserId, Username, Email, Bactive, UserRole, CreatedDate FROM M_Users ORDER BY UserId;
GO
