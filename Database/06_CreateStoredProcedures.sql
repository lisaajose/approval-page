-- ==============================================================================
-- Script: 06_CreateStoredProcedures.sql
-- Description: Creates the full suite of stored procedures governing the
--              approval workflow system:
--              1. dbo.usp_SaveVoucher
--              2. dbo.usp_GetPendingApprovals
--              3. dbo.usp_GetVoucherDetails
--              4. dbo.usp_ApproveVoucher
--              5. dbo.usp_RejectVoucher
--              6. dbo.usp_GetNotifications
--              7. dbo.usp_GetAllUsers
-- ==============================================================================

-- NOTE: In Azure SQL Database, the USE statement is not supported. Connect directly to [ApprovalWorkflowDB].
-- USE [ApprovalWorkflowDB];
-- GO

-- ==============================================================================
-- 1. Procedure: dbo.usp_SaveVoucher
-- Purpose: Creates a new voucher, determines workflow level, creates JP notification,
--          and generates sequential approval assignments.
-- ==============================================================================
CREATE OR ALTER PROCEDURE dbo.usp_SaveVoucher
(
    @Svoucherno        NVARCHAR(50),
    @dDate             DATE = NULL,
    @sNarration        NVARCHAR(100) = NULL,
    @Amount            DECIMAL(18,2),
    @CreatedByUserId   INT,
    @NewHeaderId       INT = NULL OUTPUT,
    @WorkflowLevel     INT = NULL OUTPUT,
    @AuthStatus        INT = NULL OUTPUT,
    @ResponseMessage   NVARCHAR(250) = NULL OUTPUT
)
AS
BEGIN
    SET NOCOUNT ON;

    -- Validate input parameters
    IF @Svoucherno IS NULL OR LTRIM(RTRIM(@Svoucherno)) = N''
    BEGIN
        THROW 50001, N'Voucher number is required and cannot be empty.', 1;
    END

    IF @Amount IS NULL OR @Amount < 0.00
    BEGIN
        THROW 50002, N'Voucher amount cannot be negative or null.', 1;
    END

    IF NOT EXISTS (SELECT 1 FROM M_Users WHERE UserId = @CreatedByUserId AND Bactive = 1)
    BEGIN
        THROW 50003, N'Creator user does not exist or account is inactive.', 1;
    END

    -- Check voucher number uniqueness
    IF EXISTS (SELECT 1 FROM t_Header WHERE Svoucherno = @Svoucherno)
    BEGIN
        THROW 50004, N'Voucher number already exists. Voucher numbers must be unique.', 1;
    END

    -- Set default voucher date to current date if not provided
    SET @dDate = ISNULL(@dDate, CAST(GETDATE() AS DATE));

    -- Determine workflow level using the authoritative database function
    SET @WorkflowLevel = dbo.fn_GetVoucherApprovalLevel(@Amount);

    IF @WorkflowLevel < 0
    BEGIN
        THROW 50005, N'Invalid voucher amount for workflow determination.', 1;
    END

    BEGIN TRANSACTION;
    BEGIN TRY

        IF @WorkflowLevel = 0
        BEGIN
            -- Level 0 (₹0 - ₹50): No approver required.
            -- Policy: Auto-approved immediately upon save, post date set, notification to JP.
            SET @AuthStatus = 1; -- Approved

            INSERT INTO t_Header (Svoucherno, dDate, sNarration, Amount, iAuthStatus, dPostDate, CreatedDate, CreatedBy)
            VALUES (@Svoucherno, @dDate, @sNarration, @Amount, @AuthStatus, @dDate, GETDATE(), @CreatedByUserId);

            SET @NewHeaderId = SCOPE_IDENTITY();

            -- Create notification for JP (UserId = 1, iAlerttype = 0)
            INSERT INTO t_Authdata (iHeaderId, iAlerttype, iLevel, iUserType, iUser, sAlerts, sUsercomments, iStepOrder, iStatus, dActionDate, iActionedBy)
            VALUES (@NewHeaderId, 0, 0, 1, 1,
                    N'Notification: Level 0 Voucher auto-approved (Amount: ₹' + CAST(@Amount AS NVARCHAR(20)) + N')',
                    N'Auto-approved on creation per Level 0 rule', 0, 3, GETDATE(), @CreatedByUserId);

            -- Log to history
            INSERT INTO t_ApprovalHistory (iHeaderId, iLevel, iStepOrder, iActionUser, sAction, sComments, dActionDate)
            VALUES (@NewHeaderId, 0, 0, @CreatedByUserId, N'AUTO_APPROVED', N'Level 0 voucher auto-approved on save', GETDATE());

            SET @ResponseMessage = N'Voucher created and auto-approved under Level 0 policy. Notification sent to JP.';
        END
        ELSE
        BEGIN
            -- Levels 1 to 4: Pending approval
            SET @AuthStatus = 0; -- Pending

            INSERT INTO t_Header (Svoucherno, dDate, sNarration, Amount, iAuthStatus, dPostDate, CreatedDate, CreatedBy)
            VALUES (@Svoucherno, @dDate, @sNarration, @Amount, @AuthStatus, NULL, GETDATE(), @CreatedByUserId);

            SET @NewHeaderId = SCOPE_IDENTITY();

            -- JP is the notification recipient at all specified levels (iAlerttype = 0)
            INSERT INTO t_Authdata (iHeaderId, iAlerttype, iLevel, iUserType, iUser, sAlerts, sUsercomments, iStepOrder, iStatus)
            VALUES (@NewHeaderId, 0, @WorkflowLevel, 1, 1,
                    N'Notification: Voucher ' + @Svoucherno + N' created at Level ' + CAST(@WorkflowLevel AS NVARCHAR(10)) + N' (Amount: ₹' + CAST(@Amount AS NVARCHAR(20)) + N')',
                    NULL, 0, 0);

            -- Approval assignments (iAlerttype = 1):
            -- Level 1: Lisa (UserId = 13)
            INSERT INTO t_Authdata (iHeaderId, iAlerttype, iLevel, iUserType, iUser, sAlerts, sUsercomments, iStepOrder, iStatus)
            VALUES (@NewHeaderId, 1, 1, 1, 13, N'Level 1 Approval Required (Lisa)', NULL, 1, 0);

            -- Level 2: Level 1 (Lisa) then Gautham (UserId = 1012)
            IF @WorkflowLevel >= 2
            BEGIN
                INSERT INTO t_Authdata (iHeaderId, iAlerttype, iLevel, iUserType, iUser, sAlerts, sUsercomments, iStepOrder, iStatus)
                VALUES (@NewHeaderId, 1, 2, 1, 1012, N'Level 2 Approval Required (Gautham)', NULL, 2, 0);
            END

            -- Level 3: Level 1 + Level 2 then Edwin (UserId = 5)
            IF @WorkflowLevel >= 3
            BEGIN
                INSERT INTO t_Authdata (iHeaderId, iAlerttype, iLevel, iUserType, iUser, sAlerts, sUsercomments, iStepOrder, iStatus)
                VALUES (@NewHeaderId, 1, 3, 1, 5, N'Level 3 Approval Required (Edwin)', NULL, 3, 0);
            END

            -- Level 4: Level 1 + Level 2 + Level 3 then JP (UserId = 1)
            IF @WorkflowLevel >= 4
            BEGIN
                INSERT INTO t_Authdata (iHeaderId, iAlerttype, iLevel, iUserType, iUser, sAlerts, sUsercomments, iStepOrder, iStatus)
                VALUES (@NewHeaderId, 1, 4, 1, 1, N'Level 4 Approval Required (JP)', NULL, 4, 0);
            END

            -- Log creation to history
            INSERT INTO t_ApprovalHistory (iHeaderId, iLevel, iStepOrder, iActionUser, sAction, sComments, dActionDate)
            VALUES (@NewHeaderId, @WorkflowLevel, 0, @CreatedByUserId, N'CREATED',
                    N'Voucher submitted for Level ' + CAST(@WorkflowLevel AS NVARCHAR(10)) + N' workflow', GETDATE());

            SET @ResponseMessage = N'Voucher created successfully and assigned to Level ' + CAST(@WorkflowLevel AS NVARCHAR(10)) + N' approval workflow.';
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
-- 2. Procedure: dbo.usp_GetPendingApprovals
-- Purpose: Returns pending vouchers where the given user is the authorized,
--          eligible approver for the CURRENT stage.
-- ==============================================================================
CREATE OR ALTER PROCEDURE dbo.usp_GetPendingApprovals
(
    @UserId INT
)
AS
BEGIN
    SET NOCOUNT ON;

    -- Validate user
    IF NOT EXISTS (SELECT 1 FROM M_Users WHERE UserId = @UserId AND Bactive = 1)
    BEGIN
        THROW 50006, N'User does not exist or is inactive.', 1;
    END

    SELECT
        h.iHeaderId,
        h.Svoucherno,
        h.dDate,
        h.sNarration,
        h.Amount,
        h.iAuthStatus,
        h.CreatedDate,
        uCreator.Username AS CreatedByUsername,
        dbo.fn_GetVoucherApprovalLevel(h.Amount) AS WorkflowLevel,
        a.iAuthId,
        a.iLevel,
        a.iStepOrder,
        a.sAlerts,
        a.iStatus AS AssignmentStatus
    FROM t_Header h
    INNER JOIN t_Authdata a ON h.iHeaderId = a.iHeaderId
    LEFT JOIN M_Users uCreator ON h.CreatedBy = uCreator.UserId
    WHERE h.iAuthStatus = 0          -- Voucher must be pending
      AND a.iAlerttype = 1           -- Approval alert
      AND a.iUser = @UserId          -- Assigned to the requesting user
      AND a.iStatus = 0              -- This step is pending
      -- Check that all preceding steps have been completed (sequential rule)
      AND NOT EXISTS (
          SELECT 1 FROM t_Authdata prevStep
          WHERE prevStep.iHeaderId = h.iHeaderId
            AND prevStep.iAlerttype = 1
            AND prevStep.iStepOrder < a.iStepOrder
            AND prevStep.iStatus <> 1
      )
    ORDER BY h.dDate DESC, h.iHeaderId DESC;
END;
GO

-- ==============================================================================
-- 3. Procedure: dbo.usp_GetVoucherDetails
-- Purpose: Retrieves complete voucher header, the 4 vertical approval slots,
--          notifications, and full audit history.
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
        curUser.Username AS CurrentPendingUsername
    FROM t_Header h
    LEFT JOIN M_Users uCreator ON h.CreatedBy = uCreator.UserId
    OUTER APPLY (
        SELECT TOP 1 a.iStepOrder, a.iUser
        FROM t_Authdata a
        WHERE a.iHeaderId = h.iHeaderId
          AND a.iAlerttype = 1
          AND a.iStatus = 0
          AND NOT EXISTS (
              SELECT 1 FROM t_Authdata prevStep
              WHERE prevStep.iHeaderId = h.iHeaderId
                AND prevStep.iAlerttype = 1
                AND prevStep.iStepOrder < a.iStepOrder
                AND prevStep.iStatus <> 1
          )
        ORDER BY a.iStepOrder ASC
    ) curStep
    LEFT JOIN M_Users curUser ON curStep.iUser = curUser.UserId
    WHERE h.iHeaderId = @iHeaderId;

    -- Result Set 2: Approval Slots (The up to 4 sequential stages)
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
        -- Determine if this specific step is the CURRENT active pending stage
        CASE
            WHEN a.iStatus = 0 AND NOT EXISTS (
                SELECT 1 FROM t_Authdata p
                WHERE p.iHeaderId = a.iHeaderId
                  AND p.iAlerttype = 1
                  AND p.iStepOrder < a.iStepOrder
                  AND p.iStatus <> 1
            ) THEN 1
            ELSE 0
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

-- ==============================================================================
-- 4. Procedure: dbo.usp_ApproveVoucher
-- Purpose: Atomically validates authorization, stage sequence, and records approval.
--          Advances workflow or marks voucher fully approved and posted.
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

    -- Validate acting user
    IF NOT EXISTS (SELECT 1 FROM M_Users WHERE UserId = @ActingUserId AND Bactive = 1)
    BEGIN
        THROW 50010, N'Acting user does not exist or account is inactive.', 1;
    END

    BEGIN TRANSACTION;
    BEGIN TRY
        -- Lock voucher header row to prevent concurrent race conditions
        DECLARE @CurrentAuthStatus INT;
        SELECT @CurrentAuthStatus = iAuthStatus
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
            THROW 50013, N'Voucher has been rejected. Rejected vouchers cannot subsequently be approved.', 1;
        END

        -- Identify current active pending approval stage
        DECLARE @AuthId INT, @CurrentStepOrder INT, @CurrentLevel INT, @AssignedUserId INT;

        SELECT TOP 1
            @AuthId = a.iAuthId,
            @CurrentStepOrder = a.iStepOrder,
            @CurrentLevel = a.iLevel,
            @AssignedUserId = a.iUser
        FROM t_Authdata a WITH (UPDLOCK, ROWLOCK)
        WHERE a.iHeaderId = @iHeaderId
          AND a.iAlerttype = 1
          AND a.iStatus = 0
        ORDER BY a.iStepOrder ASC;

        IF @AuthId IS NULL
        BEGIN
            THROW 50014, N'No pending approval stage found for this voucher.', 1;
        END

        -- Strict Authorization: The acting user must match the assigned approver
        IF @ActingUserId <> @AssignedUserId
        BEGIN
            THROW 50015, N'Unauthorized: You are not assigned to approve the current workflow stage.', 1;
        END

        -- Sequential Integrity: Ensure no prerequisite stage is incomplete
        IF EXISTS (
            SELECT 1 FROM t_Authdata
            WHERE iHeaderId = @iHeaderId
              AND iAlerttype = 1
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

        -- Record audit history
        INSERT INTO t_ApprovalHistory (iHeaderId, iLevel, iStepOrder, iActionUser, sAction, sComments, dActionDate)
        VALUES (@iHeaderId, @CurrentLevel, @CurrentStepOrder, @ActingUserId, N'APPROVED', @Comments, GETDATE());

        -- Check if any remaining pending stages exist
        IF NOT EXISTS (
            SELECT 1 FROM t_Authdata
            WHERE iHeaderId = @iHeaderId
              AND iAlerttype = 1
              AND iStatus = 0
        )
        BEGIN
            -- All stages complete: Mark voucher approved and assign posting date
            UPDATE t_Header
            SET
                iAuthStatus = 1,
                dPostDate = CAST(GETDATE() AS DATE)
            WHERE iHeaderId = @iHeaderId;

            SET @ResponseMessage = N'Voucher fully approved and posted successfully.';
        END
        ELSE
        BEGIN
            SET @ResponseMessage = N'Approval stage completed successfully. Voucher advanced to next stage.';
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
-- 5. Procedure: dbo.usp_RejectVoucher
-- Purpose: Atomically records rejection, marks header as Rejected, and prevents
--          any subsequent approvals.
-- ==============================================================================
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

    -- Validate acting user
    IF NOT EXISTS (SELECT 1 FROM M_Users WHERE UserId = @ActingUserId AND Bactive = 1)
    BEGIN
        THROW 50021, N'Acting user does not exist or account is inactive.', 1;
    END

    BEGIN TRANSACTION;
    BEGIN TRY
        -- Lock voucher header row
        DECLARE @CurrentAuthStatus INT;
        SELECT @CurrentAuthStatus = iAuthStatus
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

        -- Identify current active pending stage
        DECLARE @AuthId INT, @CurrentStepOrder INT, @CurrentLevel INT, @AssignedUserId INT;

        SELECT TOP 1
            @AuthId = a.iAuthId,
            @CurrentStepOrder = a.iStepOrder,
            @CurrentLevel = a.iLevel,
            @AssignedUserId = a.iUser
        FROM t_Authdata a WITH (UPDLOCK, ROWLOCK)
        WHERE a.iHeaderId = @iHeaderId
          AND a.iAlerttype = 1
          AND a.iStatus = 0
        ORDER BY a.iStepOrder ASC;

        IF @AuthId IS NULL
        BEGIN
            THROW 50025, N'No pending approval stage found for this voucher.', 1;
        END

        -- Authorization check: User must be assigned to current stage
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

        -- Cancel any subsequent stages for this voucher
        UPDATE t_Authdata
        SET
            iStatus = 2,
            sUsercomments = N'Workflow terminated due to rejection at Step ' + CAST(@CurrentStepOrder AS NVARCHAR(10))
        WHERE iHeaderId = @iHeaderId
          AND iAlerttype = 1
          AND iStepOrder > @CurrentStepOrder;

        -- Update header to Rejected (2)
        UPDATE t_Header
        SET iAuthStatus = 2
        WHERE iHeaderId = @iHeaderId;

        -- Record audit history
        INSERT INTO t_ApprovalHistory (iHeaderId, iLevel, iStepOrder, iActionUser, sAction, sComments, dActionDate)
        VALUES (@iHeaderId, @CurrentLevel, @CurrentStepOrder, @ActingUserId, N'REJECTED', @Comments, GETDATE());

        SET @ResponseMessage = N'Voucher rejected successfully. Workflow terminated.';

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
-- 6. Procedure: dbo.usp_GetNotifications
-- Purpose: Retrieves notifications for the intended recipient (e.g. JP).
--          Notification records DO NOT grant approval authority.
-- ==============================================================================
CREATE OR ALTER PROCEDURE dbo.usp_GetNotifications
(
    @UserId INT
)
AS
BEGIN
    SET NOCOUNT ON;

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
        h.CreatedDate,
        uCreator.Username AS CreatedByUsername
    FROM t_Authdata a
    INNER JOIN t_Header h ON a.iHeaderId = h.iHeaderId
    LEFT JOIN M_Users uCreator ON h.CreatedBy = uCreator.UserId
    WHERE a.iAlerttype = 0 -- Notification alert
      AND a.iUser = @UserId
    ORDER BY h.CreatedDate DESC, a.iAuthId DESC;
END;
GO

-- ==============================================================================
-- 7. Procedure: dbo.usp_GetAllUsers
-- Purpose: Utility procedure to list active users for application login/switching
-- ==============================================================================
CREATE OR ALTER PROCEDURE dbo.usp_GetAllUsers
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        UserId,
        Username,
        Email,
        UserRole,
        Bactive,
        CreatedDate,
        LastLoginDate
    FROM M_Users
    ORDER BY
        CASE
            WHEN UserId = 1 THEN 1       -- JP
            WHEN UserId = 13 THEN 2      -- LISA
            WHEN UserId = 1012 THEN 3    -- GAUTHAM
            WHEN UserId = 5 THEN 4       -- EDWIN
            ELSE 5
        END,
        UserId ASC;
END;
GO
-- ==============================================================================
-- Script: 08_AddApprovalWorkflowProcedure.sql
-- Description: Creates the consolidated dbo.usp_ApprovalWorkflow stored procedure
--              mandated by the master prompt for SAVE, APPROVE, and REJECT actions,
--              as well as user authentication verification.
-- ==============================================================================

-- NOTE: In Azure SQL Database, the USE statement is not supported. Connect directly to [ApprovalWorkflowDB].
-- USE [ApprovalWorkflowDB];
-- GO

-- ==============================================================================
-- Procedure: dbo.usp_ApprovalWorkflow
-- Purpose: Unified single entrypoint for Save, Approve, and Reject actions
-- ==============================================================================
CREATE OR ALTER PROCEDURE dbo.usp_ApprovalWorkflow
(
    @Action            NVARCHAR(10),             -- 'SAVE', 'APPROVE', 'REJECT'
    @HeaderId          INT = NULL,
    @VoucherNo         NVARCHAR(50) = NULL,
    @VoucherDate       DATE = NULL,
    @Narration         NVARCHAR(100) = NULL,
    @Amount            DECIMAL(18,2) = NULL,
    @UserId            INT,
    @UserComment       NVARCHAR(100) = NULL,
    @NewHeaderId       INT = NULL OUTPUT,
    @WorkflowLevel     INT = NULL OUTPUT,
    @AuthStatus        INT = NULL OUTPUT,
    @ResponseMessage   NVARCHAR(250) = NULL OUTPUT
)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @NormalizedAction NVARCHAR(10) = UPPER(LTRIM(RTRIM(ISNULL(@Action, N''))));

    IF @NormalizedAction = N'SAVE'
    BEGIN
        EXEC dbo.usp_SaveVoucher
            @Svoucherno      = @VoucherNo,
            @dDate           = @VoucherDate,
            @sNarration      = @Narration,
            @Amount          = @Amount,
            @CreatedByUserId = @UserId,
            @NewHeaderId     = @NewHeaderId OUTPUT,
            @WorkflowLevel   = @WorkflowLevel OUTPUT,
            @AuthStatus      = @AuthStatus OUTPUT,
            @ResponseMessage = @ResponseMessage OUTPUT;
    END
    ELSE IF @NormalizedAction = N'APPROVE'
    BEGIN
        EXEC dbo.usp_ApproveVoucher
            @iHeaderId       = @HeaderId,
            @ActingUserId    = @UserId,
            @Comments        = @UserComment,
            @ResponseMessage = @ResponseMessage OUTPUT;

        SELECT 
            @AuthStatus = iAuthStatus,
            @WorkflowLevel = dbo.fn_GetVoucherApprovalLevel(Amount)
        FROM t_Header 
        WHERE iHeaderId = @HeaderId;

        SET @NewHeaderId = @HeaderId;
    END
    ELSE IF @NormalizedAction = N'REJECT'
    BEGIN
        EXEC dbo.usp_RejectVoucher
            @iHeaderId       = @HeaderId,
            @ActingUserId    = @UserId,
            @Comments        = @UserComment,
            @ResponseMessage = @ResponseMessage OUTPUT;

        SELECT 
            @AuthStatus = iAuthStatus,
            @WorkflowLevel = dbo.fn_GetVoucherApprovalLevel(Amount)
        FROM t_Header 
        WHERE iHeaderId = @HeaderId;

        SET @NewHeaderId = @HeaderId;
    END
    ELSE
    BEGIN
        THROW 50099, N'Invalid workflow action specified. Supported actions are SAVE, APPROVE, REJECT.', 1;
    END
END;
GO

-- ==============================================================================
-- Procedure: dbo.usp_ValidateUserLogin
-- Purpose: Validates login credentials and returns user details on success
-- ==============================================================================
CREATE OR ALTER PROCEDURE dbo.usp_ValidateUserLogin
(
    @UsernameOrEmail NVARCHAR(50),
    @Password        NVARCHAR(256),
    @Success         BIT OUTPUT,
    @UserId          INT OUTPUT,
    @Username        NVARCHAR(20) OUTPUT,
    @UserRole        INT OUTPUT,
    @Message         NVARCHAR(250) OUTPUT
)
AS
BEGIN
    SET NOCOUNT ON;
    SET @Success = 0;
    SET @UserId = NULL;
    SET @Username = NULL;
    SET @UserRole = NULL;

    DECLARE @FoundUserId INT, @FoundUsername NVARCHAR(20), @FoundPassword NVARCHAR(256), @FoundBactive BIT, @FoundUserRole INT;

    SELECT TOP 1
        @FoundUserId = UserId,
        @FoundUsername = Username,
        @FoundPassword = Password,
        @FoundBactive = Bactive,
        @FoundUserRole = UserRole
    FROM M_Users
    WHERE (LOWER(Username) = LOWER(LTRIM(RTRIM(@UsernameOrEmail))) OR LOWER(Email) = LOWER(LTRIM(RTRIM(@UsernameOrEmail))));

    IF @FoundUserId IS NULL
    BEGIN
        SET @Message = N'Invalid username or email address.';
        RETURN;
    END

    IF @FoundBactive <> 1
    BEGIN
        SET @Message = N'User account is inactive. Please contact your administrator.';
        RETURN;
    END

    -- Password must match the user's UserId
    IF LTRIM(RTRIM(@Password)) = CAST(@FoundUserId AS NVARCHAR(20)) OR LTRIM(RTRIM(@Password)) = @FoundPassword
    BEGIN
        SET @Success = 1;
        SET @UserId = @FoundUserId;
        SET @Username = @FoundUsername;
        SET @UserRole = @FoundUserRole;
        SET @Message = N'Login successful.';

        -- Update last login timestamp
        UPDATE M_Users SET LastLoginDate = GETDATE() WHERE UserId = @FoundUserId;
    END
    ELSE
    BEGIN
        SET @Message = N'Invalid password entered.';
    END
END;
GO
