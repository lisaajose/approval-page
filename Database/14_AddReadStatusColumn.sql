-- ==============================================================================
-- Script: 14_AddReadStatusColumn.sql
-- Description: Adds a separate iReadStatus column (0 = Unread, 1 = Read) to t_Authdata.
--              Leaves iStatus strictly for approval decisions (0 = Pending, 1 = Approved, 2 = Rejected).
--              Updates check constraints, indexes, and notification stored procedures.
-- ==============================================================================

USE [ApprovalWorkflowDB];
GO

-- 1. Add iReadStatus column to t_Authdata if not already present
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('t_Authdata') AND name = 'iReadStatus')
BEGIN
    ALTER TABLE t_Authdata
    ADD iReadStatus INT NOT NULL CONSTRAINT DF_t_Authdata_iReadStatus DEFAULT 0;
    PRINT 'Column [iReadStatus] added to [t_Authdata] with DEFAULT 0.';
END
ELSE
BEGIN
    PRINT 'Column [iReadStatus] already exists in [t_Authdata].';
END
GO

-- 2. Migrate existing notification read states
-- Previously, read notifications used iStatus = 3.
-- Migrate read notifications to iReadStatus = 1 and reset iStatus to 0.
UPDATE t_Authdata
SET iReadStatus = 1
WHERE iStatus = 3;

UPDATE t_Authdata
SET iStatus = 0
WHERE iStatus = 3;
PRINT 'Migrated existing read notifications to iReadStatus = 1, and normalized iStatus = 0.';
GO

-- 3. Update check constraints on t_Authdata
-- iStatus: strictly 0 = Pending, 1 = Approved, 2 = Rejected
IF EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = 'CK_t_Authdata_iStatus')
BEGIN
    ALTER TABLE t_Authdata DROP CONSTRAINT CK_t_Authdata_iStatus;
END
ALTER TABLE t_Authdata ADD CONSTRAINT CK_t_Authdata_iStatus CHECK (iStatus IN (0, 1, 2));
PRINT 'Updated check constraint [CK_t_Authdata_iStatus] to CHECK (iStatus IN (0, 1, 2)).';
GO

-- iReadStatus: strictly 0 = Unread, 1 = Read
IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = 'CK_t_Authdata_iReadStatus')
BEGIN
    ALTER TABLE t_Authdata ADD CONSTRAINT CK_t_Authdata_iReadStatus CHECK (iReadStatus IN (0, 1));
    PRINT 'Created check constraint [CK_t_Authdata_iReadStatus] to CHECK (iReadStatus IN (0, 1)).';
END
GO

-- 4. Create / update index for notifications
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_t_Authdata_Notifications' AND object_id = OBJECT_ID('t_Authdata'))
BEGIN
    CREATE NONCLUSTERED INDEX IX_t_Authdata_Notifications
    ON t_Authdata (iUser, iAlerttype, iReadStatus)
    INCLUDE (iHeaderId, iLevel, sAlerts, sUsercomments, iStatus, dActionDate, iActionedBy);
    PRINT 'Index [IX_t_Authdata_Notifications] created.';
END
GO

-- 5. Update dbo.usp_GetNotifications
CREATE OR ALTER PROCEDURE dbo.usp_GetNotifications
(
    @UserId INT,
    @Filter NVARCHAR(20) = N'ALL'
)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @NormalizedFilter NVARCHAR(20) = UPPER(LTRIM(RTRIM(ISNULL(@Filter, N'ALL'))));

    SELECT
        a.iAuthId,
        a.iHeaderId,
        h.Svoucherno,
        h.dDate,
        h.Amount,
        h.iAuthStatus,
        CASE h.iAuthStatus
            WHEN 0 THEN N'Pending'
            WHEN 1 THEN N'Approved'
            WHEN 2 THEN N'Rejected'
            ELSE N'Unknown'
        END AS HeaderStatusDescription,
        a.iLevel,
        a.sAlerts,
        a.sUsercomments,
        a.iStatus,
        a.iReadStatus,
        h.CreatedDate,
        uCreator.Username AS CreatedByUsername,
        a.dActionDate,
        uAction.Username AS ActionedByUsername
    FROM t_Authdata a
    INNER JOIN t_Header h ON a.iHeaderId = h.iHeaderId
    LEFT JOIN M_Users uCreator ON h.CreatedBy = uCreator.UserId
    LEFT JOIN M_Users uAction ON a.iActionedBy = uAction.UserId
    WHERE a.iAlerttype = 0 -- Notification alert
      AND a.iUser = @UserId
      AND (
          @NormalizedFilter = N'ALL'
          OR (@NormalizedFilter = N'UNREAD' AND a.iReadStatus = 0)
          OR (@NormalizedFilter = N'READ' AND a.iReadStatus = 1)
      )
    ORDER BY a.iAuthId DESC;
END;
GO
PRINT 'Procedure [dbo.usp_GetNotifications] updated.';
GO

-- 6. Update dbo.usp_UpdateNotificationStatus
CREATE OR ALTER PROCEDURE dbo.usp_UpdateNotificationStatus
(
    @UserId       INT,
    @AuthIds      NVARCHAR(MAX),  -- Comma-separated list of iAuthId values, or 'ALL'
    @NewStatus    INT,            -- 0 = Unread, 1 = Read (3 accepted for backward compatibility)
    @UpdatedCount INT = NULL OUTPUT
)
AS
BEGIN
    SET NOCOUNT ON;

    -- Normalize 3 (legacy Read value) to 1 (Read)
    DECLARE @TargetReadStatus INT = CASE WHEN @NewStatus = 3 THEN 1 ELSE @NewStatus END;

    IF @TargetReadStatus NOT IN (0, 1)
    BEGIN
        THROW 50030, N'Invalid notification read status value. Allowed values are 0 (Unread) and 1 (Read).', 1;
    END

    IF @AuthIds IS NULL OR LTRIM(RTRIM(@AuthIds)) = N''
    BEGIN
        SET @UpdatedCount = 0;
        RETURN;
    END

    IF UPPER(LTRIM(RTRIM(@AuthIds))) = N'ALL'
    BEGIN
        UPDATE t_Authdata
        SET iReadStatus = @TargetReadStatus
        WHERE iAlerttype = 0
          AND iUser = @UserId;

        SET @UpdatedCount = @@ROWCOUNT;
    END
    ELSE
    BEGIN
        UPDATE t_Authdata
        SET iReadStatus = @TargetReadStatus
        WHERE iAlerttype = 0
          AND iUser = @UserId
          AND iAuthId IN (
              SELECT TRY_CAST(value AS INT)
              FROM STRING_SPLIT(@AuthIds, N',')
              WHERE TRY_CAST(value AS INT) IS NOT NULL
          );

        SET @UpdatedCount = @@ROWCOUNT;
    END
END;
GO
PRINT 'Procedure [dbo.usp_UpdateNotificationStatus] updated.';
GO

-- 7. Update dbo.usp_GetVoucherDetails (preserves iCycle if present)
CREATE OR ALTER PROCEDURE dbo.usp_GetVoucherDetails
(
    @iHeaderId INT
)
AS
BEGIN
    SET NOCOUNT ON;

    -- Determine active cycle (defaults to 1 if iCycle column exists, else 1)
    DECLARE @ActiveCycle INT = 1;
    IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('t_Authdata') AND name = 'iCycle')
    BEGIN
        SELECT @ActiveCycle = ISNULL(MAX(iCycle), 1)
        FROM t_Authdata
        WHERE iHeaderId = @iHeaderId;
    END

    -- Result Set 1: Header information
    SELECT
        h.iHeaderId,
        h.Svoucherno,
        h.dDate,
        h.sNarration,
        h.Amount,
        h.iAuthStatus,
        CASE h.iAuthStatus
            WHEN 0 THEN N'Pending'
            WHEN 1 THEN N'Approved'
            WHEN 2 THEN N'Rejected'
            ELSE N'Unknown'
        END AS AuthStatusDescription,
        h.dPostDate,
        h.CreatedDate,
        h.CreatedBy,
        u.Username AS CreatedByUsername,
        dbo.fn_GetVoucherApprovalLevel(h.Amount) AS WorkflowLevel,
        @ActiveCycle AS CurrentCycle
    FROM t_Header h
    LEFT JOIN M_Users u ON h.CreatedBy = u.UserId
    WHERE h.iHeaderId = @iHeaderId;

    -- Result Set 2: 4-Cell Approval Flow Slots for active cycle
    SELECT
        a.iAuthId,
        a.iHeaderId,
        a.iAlerttype,
        a.iLevel,
        a.iStepOrder,
        a.iUserType,
        a.iUser,
        u.Username AS AssignedUsername,
        a.sAlerts,
        a.sUsercomments,
        a.iStatus,
        CASE a.iStatus
            WHEN 0 THEN N'Pending'
            WHEN 1 THEN N'Approved'
            WHEN 2 THEN N'Rejected'
            ELSE N'Unknown'
        END AS StepStatusDescription,
        a.dActionDate,
        a.iActionedBy,
        actUser.Username AS ActionedByUsername,
        CASE 
            WHEN a.iStatus = 0 AND NOT EXISTS (
                SELECT 1 FROM t_Authdata p
                WHERE p.iHeaderId = a.iHeaderId
                  AND p.iAlerttype = 1
                  AND p.iStepOrder < a.iStepOrder
                  AND p.iStatus <> 1
            ) THEN CAST(1 AS BIT)
            ELSE CAST(0 AS BIT)
        END AS IsCurrentActiveStage
    FROM t_Authdata a
    LEFT JOIN M_Users u ON a.iUser = u.UserId
    LEFT JOIN M_Users actUser ON a.iActionedBy = actUser.UserId
    WHERE a.iHeaderId = @iHeaderId
      AND a.iAlerttype = 1 -- Approval alerts
    ORDER BY a.iStepOrder ASC;

    -- Result Set 3: Notifications
    SELECT
        a.iAuthId,
        a.iHeaderId,
        a.iAlerttype,
        a.iLevel,
        a.iUser,
        u.Username,
        a.sAlerts,
        a.sUsercomments,
        a.iStatus,
        a.iReadStatus,
        a.dActionDate
    FROM t_Authdata a
    LEFT JOIN M_Users u ON a.iUser = u.UserId
    WHERE a.iHeaderId = @iHeaderId
      AND a.iAlerttype = 0 -- Notifications
    ORDER BY a.iAuthId ASC;

    -- Result Set 4: Full Audit History
    SELECT
        h.iHistoryId,
        h.iHeaderId,
        h.iLevel,
        h.iStepOrder,
        h.iActionUser,
        u.Username AS ActionUsername,
        h.sAction,
        h.sComments,
        h.dActionDate
    FROM t_ApprovalHistory h
    LEFT JOIN M_Users u ON h.iActionUser = u.UserId
    WHERE h.iHeaderId = @iHeaderId
    ORDER BY h.dActionDate ASC, h.iHistoryId ASC;
END;
GO
PRINT 'Procedure [dbo.usp_GetVoucherDetails] updated.';
GO

