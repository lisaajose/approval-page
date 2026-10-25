-- ==============================================================================
-- Script: 10_AddVoucherResubmission.sql
-- Description: Supports editing and resubmitting rejected vouchers:
--              1. Adds iCycle column to t_Authdata and t_ApprovalHistory
--              2. Preserves full multi-cycle history across revisions
--              3. Creates dbo.usp_ResubmitVoucher procedure
--              4. Updates dbo.usp_GetVoucherDetails to expose all cycles in Auth Info
--              5. Updates dbo.usp_ApproveVoucher and dbo.usp_RejectVoucher with cycle awareness
-- ==============================================================================

USE [ApprovalWorkflowDB];
GO

-- 1. Add iCycle column to t_Authdata if not present
IF NOT EXISTS (SELECT * FROM sys.columns WHERE object_id = OBJECT_ID('t_Authdata') AND name = 'iCycle')
BEGIN
    ALTER TABLE t_Authdata ADD iCycle INT NOT NULL CONSTRAINT DF_t_Authdata_iCycle DEFAULT 1;
    PRINT 'Added [iCycle] column to [t_Authdata].';
END
GO

-- 2. Add iCycle column to t_ApprovalHistory if not present
IF NOT EXISTS (SELECT * FROM sys.columns WHERE object_id = OBJECT_ID('t_ApprovalHistory') AND name = 'iCycle')
BEGIN
    ALTER TABLE t_ApprovalHistory ADD iCycle INT NOT NULL CONSTRAINT DF_t_ApprovalHistory_iCycle DEFAULT 1;
    PRINT 'Added [iCycle] column to [t_ApprovalHistory].';
END
GO

-- ==============================================================================
-- 3. Procedure: dbo.usp_ResubmitVoucher
-- Purpose: Allows creator to edit a rejected voucher and restart workflow from Step 1
-- ==============================================================================
CREATE OR ALTER PROCEDURE dbo.usp_ResubmitVoucher
(
    @iHeaderId         INT,
    @ActingUserId      INT,
    @dDate             DATE,
    @sNarration        NVARCHAR(100) = NULL,
    @Amount            DECIMAL(18,2),
    @NewWorkflowLevel  INT = NULL OUTPUT,
    @ResponseMessage   NVARCHAR(250) = NULL OUTPUT
)
AS
BEGIN
    SET NOCOUNT ON;

    IF @dDate IS NULL
    BEGIN
        THROW 50051, N'Voucher date is required.', 1;
    END

    IF @Amount IS NULL OR @Amount < 0.00
    BEGIN
        THROW 50052, N'Voucher amount must be a non-negative number.', 1;
    END

    BEGIN TRANSACTION;
    BEGIN TRY
        DECLARE @CurrentAuthStatus INT, @CurrentCreatedBy INT, @VoucherNo NVARCHAR(50);
        SELECT
            @CurrentAuthStatus = iAuthStatus,
            @CurrentCreatedBy = CreatedBy,
            @VoucherNo = Svoucherno
        FROM t_Header WITH (UPDLOCK, ROWLOCK)
        WHERE iHeaderId = @iHeaderId;

        IF @VoucherNo IS NULL
        BEGIN
            THROW 50053, N'Voucher not found.', 1;
        END

        IF @CurrentAuthStatus <> 2
        BEGIN
            THROW 50054, N'Only rejected vouchers can be edited and resubmitted for a new approval cycle.', 1;
        END

        -- Strict Authorization: Only creator (or system administrator) can edit
        IF @ActingUserId <> @CurrentCreatedBy AND NOT EXISTS (SELECT 1 FROM M_Users WHERE UserId = @ActingUserId AND UserRole = 1)
        BEGIN
            THROW 50055, N'Unauthorized: Only the creator of the voucher can edit and resubmit it.', 1;
        END

        -- Determine current cycle number
        DECLARE @CurrentCycle INT;
        SELECT @CurrentCycle = ISNULL(MAX(iCycle), 1)
        FROM t_Authdata
        WHERE iHeaderId = @iHeaderId;

        DECLARE @NewCycle INT = @CurrentCycle + 1;

        -- Recompute workflow level based on new amount
        SET @NewWorkflowLevel = dbo.fn_GetVoucherApprovalLevel(@Amount);

        DECLARE @CreatorUsername NVARCHAR(50);
        SELECT @CreatorUsername = Username FROM M_Users WHERE UserId = @ActingUserId;

        IF @NewWorkflowLevel = 0
        BEGIN
            -- Level 0 Auto-approves
            UPDATE t_Header
            SET
                dDate = @dDate,
                sNarration = @sNarration,
                Amount = @Amount,
                iAuthStatus = 1, -- Approved
                dPostDate = @dDate
            WHERE iHeaderId = @iHeaderId;

            -- Notification for JP
            INSERT INTO t_Authdata (iHeaderId, iAlerttype, iLevel, iUserType, iUser, sAlerts, sUsercomments, iStepOrder, iStatus, dActionDate, iActionedBy, iCycle)
            VALUES (@iHeaderId, 0, 0, 1, 1,
                    N'Voucher ' + @VoucherNo + N' resubmitted & auto-approved under Level 0 rule (Cycle ' + CAST(@NewCycle AS NVARCHAR(10)) + N')',
                    N'Auto-approved on resubmission per Level 0 rule', 0, 0, GETDATE(), @ActingUserId, @NewCycle);

            -- Notification for Creator (if not JP)
            IF @ActingUserId <> 1
            BEGIN
                INSERT INTO t_Authdata (iHeaderId, iAlerttype, iLevel, iUserType, iUser, sAlerts, sUsercomments, iStepOrder, iStatus, dActionDate, iActionedBy, iCycle)
                VALUES (@iHeaderId, 0, 0, 1, @ActingUserId,
                        N'Your voucher ' + @VoucherNo + N' was resubmitted and auto-approved (Cycle ' + CAST(@NewCycle AS NVARCHAR(10)) + N')',
                        N'Auto-approved on resubmission per Level 0 rule', 0, 0, GETDATE(), @ActingUserId, @NewCycle);
            END

            -- Audit log
            INSERT INTO t_ApprovalHistory (iHeaderId, iLevel, iStepOrder, iActionUser, sAction, sComments, dActionDate, iCycle)
            VALUES (@iHeaderId, 0, 0, @ActingUserId, N'RESUBMITTED_AUTO',
                    N'Voucher edited and auto-approved under Level 0 rule (Cycle ' + CAST(@NewCycle AS NVARCHAR(10)) + N')', GETDATE(), @NewCycle);

            SET @ResponseMessage = N'Voucher edited and auto-approved under Level 0 rule. Notification sent to JP.';
        END
        ELSE
        BEGIN
            -- Levels 1 to 4: Reset status to Pending (0)
            UPDATE t_Header
            SET
                dDate = @dDate,
                sNarration = @sNarration,
                Amount = @Amount,
                iAuthStatus = 0, -- Pending
                dPostDate = NULL
            WHERE iHeaderId = @iHeaderId;

            -- Notification for JP
            INSERT INTO t_Authdata (iHeaderId, iAlerttype, iLevel, iUserType, iUser, sAlerts, sUsercomments, iStepOrder, iStatus, dActionDate, iActionedBy, iCycle)
            VALUES (@iHeaderId, 0, @NewWorkflowLevel, 1, 1,
                    N'Voucher ' + @VoucherNo + N' resubmitted for Level ' + CAST(@NewWorkflowLevel AS NVARCHAR(10)) + N' approval (Cycle ' + CAST(@NewCycle AS NVARCHAR(10)) + N')',
                    NULL, 0, 0, GETDATE(), @ActingUserId, @NewCycle);

            -- Notification for Creator (if not JP)
            IF @ActingUserId <> 1
            BEGIN
                INSERT INTO t_Authdata (iHeaderId, iAlerttype, iLevel, iUserType, iUser, sAlerts, sUsercomments, iStepOrder, iStatus, dActionDate, iActionedBy, iCycle)
                VALUES (@iHeaderId, 0, @NewWorkflowLevel, 1, @ActingUserId,
                        N'Your voucher ' + @VoucherNo + N' was resubmitted (Cycle ' + CAST(@NewCycle AS NVARCHAR(10)) + N')',
                        NULL, 0, 0, GETDATE(), @ActingUserId, @NewCycle);
            END

            -- Generate fresh approval assignments for the new cycle starting at Step 1:
            -- Level 1: Lisa (UserId 13)
            INSERT INTO t_Authdata (iHeaderId, iAlerttype, iLevel, iUserType, iUser, sAlerts, sUsercomments, iStepOrder, iStatus, iCycle)
            VALUES (@iHeaderId, 1, 1, 1, 13, N'Level 1 Approval Required (Lisa)', NULL, 1, 0, @NewCycle);

            -- Level 2: Gautham (UserId 1012)
            IF @NewWorkflowLevel >= 2
            BEGIN
                INSERT INTO t_Authdata (iHeaderId, iAlerttype, iLevel, iUserType, iUser, sAlerts, sUsercomments, iStepOrder, iStatus, iCycle)
                VALUES (@iHeaderId, 1, 2, 1, 1012, N'Level 2 Approval Required (Gautham)', NULL, 2, 0, @NewCycle);
            END

            -- Level 3: Edwin (UserId 5)
            IF @NewWorkflowLevel >= 3
            BEGIN
                INSERT INTO t_Authdata (iHeaderId, iAlerttype, iLevel, iUserType, iUser, sAlerts, sUsercomments, iStepOrder, iStatus, iCycle)
                VALUES (@iHeaderId, 1, 3, 1, 5, N'Level 3 Approval Required (Edwin)', NULL, 3, 0, @NewCycle);
            END

            -- Level 4: JP (UserId 1)
            IF @NewWorkflowLevel >= 4
            BEGIN
                INSERT INTO t_Authdata (iHeaderId, iAlerttype, iLevel, iUserType, iUser, sAlerts, sUsercomments, iStepOrder, iStatus, iCycle)
                VALUES (@iHeaderId, 1, 4, 1, 1, N'Level 4 Approval Required (JP)', NULL, 4, 0, @NewCycle);
            END

            -- Log resubmission in audit history
            INSERT INTO t_ApprovalHistory (iHeaderId, iLevel, iStepOrder, iActionUser, sAction, sComments, dActionDate, iCycle)
            VALUES (@iHeaderId, @NewWorkflowLevel, 0, @ActingUserId, N'RESUBMITTED',
                    N'Voucher edited and resubmitted for Level ' + CAST(@NewWorkflowLevel AS NVARCHAR(10)) + N' workflow (Cycle ' + CAST(@NewCycle AS NVARCHAR(10)) + N')',
                    GETDATE(), @NewCycle);

            SET @ResponseMessage = N'Voucher edited and resubmitted successfully for Level ' + CAST(@NewWorkflowLevel AS NVARCHAR(10)) + N' approval cycle ' + CAST(@NewCycle AS NVARCHAR(10)) + N'.';
        END

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO

-- ==============================================================================
-- 4. Procedure: dbo.usp_GetVoucherDetails (Updated to return active cycle and all cycles)
-- ==============================================================================
CREATE OR ALTER PROCEDURE dbo.usp_GetVoucherDetails
(
    @iHeaderId INT
)
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM t_Header WHERE iHeaderId = @iHeaderId)
    BEGIN
        THROW 50007, N'Voucher not found.', 1;
    END

    -- Determine highest/active cycle
    DECLARE @MaxCycle INT;
    SELECT @MaxCycle = ISNULL(MAX(iCycle), 1)
    FROM t_Authdata
    WHERE iHeaderId = @iHeaderId;

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
        END AS StatusDescription,
        h.dPostDate,
        h.CreatedDate,
        h.CreatedBy,
        uCreator.Username AS CreatedByUsername,
        dbo.fn_GetVoucherApprovalLevel(h.Amount) AS WorkflowLevel,
        curStep.iStepOrder AS CurrentPendingStepOrder,
        curStep.iUser AS CurrentPendingUserId,
        curUser.Username AS CurrentPendingUsername,
        @MaxCycle AS CurrentCycle
    FROM t_Header h
    LEFT JOIN M_Users uCreator ON h.CreatedBy = uCreator.UserId
    OUTER APPLY (
        SELECT TOP 1 a.iStepOrder, a.iUser
        FROM t_Authdata a
        WHERE a.iHeaderId = h.iHeaderId
          AND a.iAlerttype = 1
          AND a.iCycle = @MaxCycle
          AND a.iStatus = 0
          AND NOT EXISTS (
              SELECT 1 FROM t_Authdata prevStep
              WHERE prevStep.iHeaderId = h.iHeaderId
                AND prevStep.iAlerttype = 1
                AND prevStep.iCycle = a.iCycle
                AND prevStep.iStepOrder < a.iStepOrder
                AND prevStep.iStatus <> 1
          )
        ORDER BY a.iStepOrder ASC
    ) curStep
    LEFT JOIN M_Users curUser ON curStep.iUser = curUser.UserId
    WHERE h.iHeaderId = @iHeaderId;

    -- Result Set 2: Approval Slots for the ACTIVE CYCLE (1..4 vertical panel)
    SELECT
        a.iAuthId,
        a.iHeaderId,
        a.iAlerttype,
        a.iLevel,
        a.iStepOrder,
        a.iUser,
        u.Username,
        a.sAlerts,
        a.sUsercomments,
        a.iStatus,
        CASE a.iStatus
            WHEN 0 THEN N'Pending'
            WHEN 1 THEN N'Approved'
            WHEN 2 THEN N'Rejected'
            WHEN 3 THEN N'Completed'
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
                  AND p.iCycle = a.iCycle
                  AND p.iStepOrder < a.iStepOrder
                  AND p.iStatus <> 1
            ) THEN 1
            ELSE 0
        END AS IsCurrentActiveStage,
        a.iCycle
    FROM t_Authdata a
    LEFT JOIN M_Users u ON a.iUser = u.UserId
    LEFT JOIN M_Users actUser ON a.iActionedBy = actUser.UserId
    WHERE a.iHeaderId = @iHeaderId
      AND a.iAlerttype = 1
      AND a.iCycle = @MaxCycle
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
        a.dActionDate,
        a.iCycle
    FROM t_Authdata a
    LEFT JOIN M_Users u ON a.iUser = u.UserId
    WHERE a.iHeaderId = @iHeaderId
      AND a.iAlerttype = 0
    ORDER BY a.iAuthId ASC;

    -- Result Set 4: Full Audit History (Preserved across all cycles)
    SELECT
        h.iHistoryId,
        h.iHeaderId,
        h.iLevel,
        h.iStepOrder,
        h.iActionUser,
        u.Username AS ActionUsername,
        h.sAction,
        h.sComments,
        h.dActionDate,
        h.iCycle
    FROM t_ApprovalHistory h
    LEFT JOIN M_Users u ON h.iActionUser = u.UserId
    WHERE h.iHeaderId = @iHeaderId
    ORDER BY h.dActionDate ASC, h.iHistoryId ASC;

    -- Result Set 5: ALL Approval Slots Across ALL Cycles (For Auth Info Modal)
    SELECT
        a.iAuthId,
        a.iHeaderId,
        a.iAlerttype,
        a.iLevel,
        a.iStepOrder,
        a.iUser,
        u.Username,
        a.sAlerts,
        a.sUsercomments,
        a.iStatus,
        CASE a.iStatus
            WHEN 0 THEN N'Pending'
            WHEN 1 THEN N'Approved'
            WHEN 2 THEN N'Rejected'
            WHEN 3 THEN N'Completed'
            ELSE N'Unknown'
        END AS StepStatusDescription,
        a.dActionDate,
        a.iActionedBy,
        actUser.Username AS ActionedByUsername,
        a.iCycle
    FROM t_Authdata a
    LEFT JOIN M_Users u ON a.iUser = u.UserId
    LEFT JOIN M_Users actUser ON a.iActionedBy = actUser.UserId
    WHERE a.iHeaderId = @iHeaderId
      AND a.iAlerttype = 1
    ORDER BY a.iCycle ASC, a.iStepOrder ASC;
END;
GO

-- ==============================================================================
-- 5. Update dbo.usp_ApproveVoucher & dbo.usp_RejectVoucher for cycle safety
-- ==============================================================================
CREATE OR ALTER PROCEDURE dbo.usp_ApproveVoucher
(
    @iHeaderId         INT,
    @ActingUserId      INT,
    @Comments          NVARCHAR(100) = NULL,
    @ResponseMessage   NVARCHAR(250) = NULL OUTPUT
)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @ActingUsername NVARCHAR(50);
    SELECT @ActingUsername = Username 
    FROM M_Users 
    WHERE UserId = @ActingUserId AND Bactive = 1;

    IF @ActingUsername IS NULL
    BEGIN
        THROW 50010, N'Acting user does not exist or account is inactive.', 1;
    END

    BEGIN TRANSACTION;
    BEGIN TRY
        DECLARE @CurrentAuthStatus INT, @VoucherNo NVARCHAR(50), @VoucherCreatedBy INT;
        SELECT 
            @CurrentAuthStatus = iAuthStatus,
            @VoucherNo = Svoucherno,
            @VoucherCreatedBy = CreatedBy
        FROM t_Header WITH (UPDLOCK, ROWLOCK)
        WHERE iHeaderId = @iHeaderId;

        IF @CurrentAuthStatus IS NULL
        BEGIN
            THROW 50011, N'Voucher not found.', 1;
        END

        IF @CurrentAuthStatus = 1
        BEGIN
            THROW 50012, N'Voucher has already been fully approved and posted.', 1;
        END

        IF @CurrentAuthStatus = 2
        BEGIN
            THROW 50013, N'Voucher has been rejected. Resubmit the voucher to start a new approval cycle.', 1;
        END

        -- Determine current active cycle
        DECLARE @ActiveCycle INT;
        SELECT @ActiveCycle = ISNULL(MAX(iCycle), 1)
        FROM t_Authdata
        WHERE iHeaderId = @iHeaderId AND iAlerttype = 1;

        -- Identify current active pending approval stage in this cycle
        DECLARE @AuthId INT, @CurrentStepOrder INT, @CurrentLevel INT, @AssignedUserId INT;

        SELECT TOP 1
            @AuthId = a.iAuthId,
            @CurrentStepOrder = a.iStepOrder,
            @CurrentLevel = a.iLevel,
            @AssignedUserId = a.iUser
        FROM t_Authdata a WITH (UPDLOCK, ROWLOCK)
        WHERE a.iHeaderId = @iHeaderId
          AND a.iAlerttype = 1
          AND a.iCycle = @ActiveCycle
          AND a.iStatus = 0
        ORDER BY a.iStepOrder ASC;

        IF @AuthId IS NULL
        BEGIN
            THROW 50014, N'No pending approval stage found for this voucher in the current cycle.', 1;
        END

        IF @ActingUserId <> @AssignedUserId
        BEGIN
            THROW 50015, N'Unauthorized: You are not assigned to approve the current workflow stage.', 1;
        END

        -- Sequential Integrity: Ensure no prerequisite stage in this cycle is incomplete
        IF EXISTS (
            SELECT 1 FROM t_Authdata
            WHERE iHeaderId = @iHeaderId
              AND iAlerttype = 1
              AND iCycle = @ActiveCycle
              AND iStepOrder < @CurrentStepOrder
              AND iStatus <> 1
        )
        BEGIN
            THROW 50016, N'Sequence violation: Prerequisite approval stages must be completed first.', 1;
        END

        -- Record the approval on this stage
        UPDATE t_Authdata
        SET
            iStatus = 1, -- Approved
            sUsercomments = @Comments,
            dActionDate = GETDATE(),
            iActionedBy = @ActingUserId
        WHERE iAuthId = @AuthId;

        -- Record audit history with cycle
        INSERT INTO t_ApprovalHistory (iHeaderId, iLevel, iStepOrder, iActionUser, sAction, sComments, dActionDate, iCycle)
        VALUES (@iHeaderId, @CurrentLevel, @CurrentStepOrder, @ActingUserId, N'APPROVED', @Comments, GETDATE(), @ActiveCycle);

        -- Check if any remaining pending stages exist in this cycle
        IF NOT EXISTS (
            SELECT 1 FROM t_Authdata
            WHERE iHeaderId = @iHeaderId
              AND iAlerttype = 1
              AND iCycle = @ActiveCycle
              AND iStatus = 0
        )
        BEGIN
            -- All stages complete
            UPDATE t_Header
            SET
                iAuthStatus = 1,
                dPostDate = CAST(GETDATE() AS DATE)
            WHERE iHeaderId = @iHeaderId;

            SET @ResponseMessage = N'Voucher fully approved and posted successfully.';

            -- Granular notification to JP
            INSERT INTO t_Authdata (iHeaderId, iAlerttype, iLevel, iUserType, iUser, sAlerts, sUsercomments, iStepOrder, iStatus, dActionDate, iActionedBy, iCycle)
            VALUES (@iHeaderId, 0, @CurrentLevel, 1, 1,
                    N'Voucher ' + @VoucherNo + N' was fully approved and posted by ' + @ActingUsername,
                    @Comments, @CurrentStepOrder, 0, GETDATE(), @ActingUserId, @ActiveCycle);

            -- Notification to creator (if not JP)
            IF @VoucherCreatedBy IS NOT NULL AND @VoucherCreatedBy <> 1
            BEGIN
                INSERT INTO t_Authdata (iHeaderId, iAlerttype, iLevel, iUserType, iUser, sAlerts, sUsercomments, iStepOrder, iStatus, dActionDate, iActionedBy, iCycle)
                VALUES (@iHeaderId, 0, @CurrentLevel, 1, @VoucherCreatedBy,
                        N'Your voucher ' + @VoucherNo + N' was fully approved and posted by ' + @ActingUsername,
                        @Comments, @CurrentStepOrder, 0, GETDATE(), @ActingUserId, @ActiveCycle);
            END
        END
        ELSE
        BEGIN
            SET @ResponseMessage = N'Approval stage completed successfully. Voucher advanced to next stage.';

            -- Granular notification to JP
            INSERT INTO t_Authdata (iHeaderId, iAlerttype, iLevel, iUserType, iUser, sAlerts, sUsercomments, iStepOrder, iStatus, dActionDate, iActionedBy, iCycle)
            VALUES (@iHeaderId, 0, @CurrentLevel, 1, 1,
                    N'Voucher ' + @VoucherNo + N' was approved at Step ' + CAST(@CurrentStepOrder AS NVARCHAR(10)) + N' (Level ' + CAST(@CurrentLevel AS NVARCHAR(10)) + N') by ' + @ActingUsername,
                    @Comments, @CurrentStepOrder, 0, GETDATE(), @ActingUserId, @ActiveCycle);

            -- Notification to creator (if not JP)
            IF @VoucherCreatedBy IS NOT NULL AND @VoucherCreatedBy <> 1
            BEGIN
                INSERT INTO t_Authdata (iHeaderId, iAlerttype, iLevel, iUserType, iUser, sAlerts, sUsercomments, iStepOrder, iStatus, dActionDate, iActionedBy, iCycle)
                VALUES (@iHeaderId, 0, @CurrentLevel, 1, @VoucherCreatedBy,
                        N'Your voucher ' + @VoucherNo + N' was approved at Step ' + CAST(@CurrentStepOrder AS NVARCHAR(10)) + N' by ' + @ActingUsername,
                        @Comments, @CurrentStepOrder, 0, GETDATE(), @ActingUserId, @ActiveCycle);
            END
        END

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_RejectVoucher
(
    @iHeaderId         INT,
    @ActingUserId      INT,
    @Comments          NVARCHAR(100),
    @ResponseMessage   NVARCHAR(250) = NULL OUTPUT
)
AS
BEGIN
    SET NOCOUNT ON;

    IF @Comments IS NULL OR LTRIM(RTRIM(@Comments)) = N''
    BEGIN
        THROW 50020, N'Comments are required when rejecting a voucher.', 1;
    END

    DECLARE @ActingUsername NVARCHAR(50);
    SELECT @ActingUsername = Username 
    FROM M_Users 
    WHERE UserId = @ActingUserId AND Bactive = 1;

    IF @ActingUsername IS NULL
    BEGIN
        THROW 50021, N'Acting user does not exist or account is inactive.', 1;
    END

    BEGIN TRANSACTION;
    BEGIN TRY
        DECLARE @CurrentAuthStatus INT, @VoucherNo NVARCHAR(50), @VoucherCreatedBy INT;
        SELECT 
            @CurrentAuthStatus = iAuthStatus,
            @VoucherNo = Svoucherno,
            @VoucherCreatedBy = CreatedBy
        FROM t_Header WITH (UPDLOCK, ROWLOCK)
        WHERE iHeaderId = @iHeaderId;

        IF @CurrentAuthStatus IS NULL
        BEGIN
            THROW 50022, N'Voucher not found.', 1;
        END

        IF @CurrentAuthStatus = 1
        BEGIN
            THROW 50023, N'Cannot reject a voucher that has already been approved and posted.', 1;
        END

        IF @CurrentAuthStatus = 2
        BEGIN
            THROW 50024, N'Voucher has already been rejected.', 1;
        END

        -- Determine current active cycle
        DECLARE @ActiveCycle INT;
        SELECT @ActiveCycle = ISNULL(MAX(iCycle), 1)
        FROM t_Authdata
        WHERE iHeaderId = @iHeaderId AND iAlerttype = 1;

        -- Identify current active pending stage in this cycle
        DECLARE @AuthId INT, @CurrentStepOrder INT, @CurrentLevel INT, @AssignedUserId INT;

        SELECT TOP 1
            @AuthId = a.iAuthId,
            @CurrentStepOrder = a.iStepOrder,
            @CurrentLevel = a.iLevel,
            @AssignedUserId = a.iUser
        FROM t_Authdata a WITH (UPDLOCK, ROWLOCK)
        WHERE a.iHeaderId = @iHeaderId
          AND a.iAlerttype = 1
          AND a.iCycle = @ActiveCycle
          AND a.iStatus = 0
        ORDER BY a.iStepOrder ASC;

        IF @AuthId IS NULL
        BEGIN
            THROW 50025, N'No pending approval stage found for this voucher.', 1;
        END

        IF @ActingUserId <> @AssignedUserId
        BEGIN
            THROW 50026, N'Unauthorized: You are not assigned to act upon the current stage.', 1;
        END

        -- Mark current stage as Rejected
        UPDATE t_Authdata
        SET
            iStatus = 2, -- Rejected
            sUsercomments = @Comments,
            dActionDate = GETDATE(),
            iActionedBy = @ActingUserId
        WHERE iAuthId = @AuthId;

        -- Cancel subsequent stages in THIS CYCLE ONLY
        UPDATE t_Authdata
        SET
            iStatus = 2,
            sUsercomments = N'Workflow terminated due to rejection at Step ' + CAST(@CurrentStepOrder AS NVARCHAR(10))
        WHERE iHeaderId = @iHeaderId
          AND iAlerttype = 1
          AND iCycle = @ActiveCycle
          AND iStepOrder > @CurrentStepOrder;

        -- Update header to Rejected (2)
        UPDATE t_Header
        SET iAuthStatus = 2
        WHERE iHeaderId = @iHeaderId;

        -- Record audit history with cycle
        INSERT INTO t_ApprovalHistory (iHeaderId, iLevel, iStepOrder, iActionUser, sAction, sComments, dActionDate, iCycle)
        VALUES (@iHeaderId, @CurrentLevel, @CurrentStepOrder, @ActingUserId, N'REJECTED', @Comments, GETDATE(), @ActiveCycle);

        -- Notification to JP
        INSERT INTO t_Authdata (iHeaderId, iAlerttype, iLevel, iUserType, iUser, sAlerts, sUsercomments, iStepOrder, iStatus, dActionDate, iActionedBy, iCycle)
        VALUES (@iHeaderId, 0, @CurrentLevel, 1, 1,
                N'Voucher ' + @VoucherNo + N' was rejected at Step ' + CAST(@CurrentStepOrder AS NVARCHAR(10)) + N' by ' + @ActingUsername,
                @Comments, @CurrentStepOrder, 0, GETDATE(), @ActingUserId, @ActiveCycle);

        -- Notification to creator (if not JP)
        IF @VoucherCreatedBy IS NOT NULL AND @VoucherCreatedBy <> 1
        BEGIN
            INSERT INTO t_Authdata (iHeaderId, iAlerttype, iLevel, iUserType, iUser, sAlerts, sUsercomments, iStepOrder, iStatus, dActionDate, iActionedBy, iCycle)
            VALUES (@iHeaderId, 0, @CurrentLevel, 1, @VoucherCreatedBy,
                    N'Your voucher ' + @VoucherNo + N' was rejected at Step ' + CAST(@CurrentStepOrder AS NVARCHAR(10)) + N' by ' + @ActingUsername,
                    @Comments, @CurrentStepOrder, 0, GETDATE(), @ActingUserId, @ActiveCycle);
        END

        SET @ResponseMessage = N'Voucher rejected successfully. Creator may edit and resubmit to restart workflow.';

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO
