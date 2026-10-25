-- ==============================================================================
-- Script: 09_AddNotificationEnhancements.sql
-- Description: Enhances notification mechanisms:
--              1. Granular notifications to JP on every approval & rejection step
--              2. Notifications to voucher creator on every update
--              3. Read / Unread status management for notifications
--              4. Send notification with comments to lower-level participants / creator
-- ==============================================================================

USE [ApprovalWorkflowDB];
GO

-- ==============================================================================
-- 1. Procedure: dbo.usp_SaveVoucher (Updated to notify creator if not JP)
-- ==============================================================================
CREATE OR ALTER PROCEDURE dbo.usp_SaveVoucher
(
    @Svoucherno        NVARCHAR(50),
    @dDate             DATE,
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

    -- Basic input validation
    IF @Svoucherno IS NULL OR LTRIM(RTRIM(@Svoucherno)) = N''
    BEGIN
        THROW 50001, N'Voucher number is required and cannot be empty.', 1;
    END

    IF @dDate IS NULL
    BEGIN
        THROW 50002, N'Voucher date is required.', 1;
    END

    IF @Amount IS NULL OR @Amount < 0.00
    BEGIN
        THROW 50003, N'Voucher amount must be a non-negative number.', 1;
    END

    IF NOT EXISTS (SELECT 1 FROM M_Users WHERE UserId = @CreatedByUserId AND Bactive = 1)
    BEGIN
        THROW 50004, N'Creating user does not exist or account is inactive.', 1;
    END

    -- Prevent duplicate voucher numbers
    IF EXISTS (SELECT 1 FROM t_Header WHERE Svoucherno = @Svoucherno)
    BEGIN
        THROW 50005, N'A voucher with this voucher number already exists.', 1;
    END

    -- Compute workflow level using the scalar function
    SET @WorkflowLevel = dbo.fn_GetVoucherApprovalLevel(@Amount);

    BEGIN TRANSACTION;
    BEGIN TRY
        IF @WorkflowLevel = 0
        BEGIN
            -- Level 0: Auto-approved on save
            SET @AuthStatus = 1; -- Approved

            INSERT INTO t_Header (Svoucherno, dDate, sNarration, Amount, iAuthStatus, dPostDate, CreatedDate, CreatedBy)
            VALUES (@Svoucherno, @dDate, @sNarration, @Amount, @AuthStatus, @dDate, GETDATE(), @CreatedByUserId);

            SET @NewHeaderId = SCOPE_IDENTITY();

            -- Create notification for JP (UserId = 1, iAlerttype = 0)
            INSERT INTO t_Authdata (iHeaderId, iAlerttype, iLevel, iUserType, iUser, sAlerts, sUsercomments, iStepOrder, iStatus, dActionDate, iActionedBy)
            VALUES (@NewHeaderId, 0, 0, 1, 1,
                    N'Notification: Level 0 Voucher auto-approved (Amount: ' + NCHAR(8377) + CAST(@Amount AS NVARCHAR(20)) + N')',
                    N'Auto-approved on creation per Level 0 rule', 0, 0, GETDATE(), @CreatedByUserId);

            -- Also notify Creator if creator is not JP
            IF @CreatedByUserId IS NOT NULL AND @CreatedByUserId <> 1
            BEGIN
                INSERT INTO t_Authdata (iHeaderId, iAlerttype, iLevel, iUserType, iUser, sAlerts, sUsercomments, iStepOrder, iStatus, dActionDate, iActionedBy)
                VALUES (@NewHeaderId, 0, 0, 1, @CreatedByUserId,
                        N'Your voucher ' + @Svoucherno + N' was created and auto-approved under Level 0 rule',
                        N'Auto-approved on creation per Level 0 rule', 0, 0, GETDATE(), @CreatedByUserId);
            END

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
            INSERT INTO t_Authdata (iHeaderId, iAlerttype, iLevel, iUserType, iUser, sAlerts, sUsercomments, iStepOrder, iStatus, dActionDate, iActionedBy)
            VALUES (@NewHeaderId, 0, @WorkflowLevel, 1, 1,
                    N'Notification: Voucher ' + @Svoucherno + N' created at Level ' + CAST(@WorkflowLevel AS NVARCHAR(10)) + N' (Amount: ' + NCHAR(8377) + CAST(@Amount AS NVARCHAR(20)) + N')',
                    NULL, 0, 0, GETDATE(), @CreatedByUserId);

            -- Also notify Creator if creator is not JP
            IF @CreatedByUserId IS NOT NULL AND @CreatedByUserId <> 1
            BEGIN
                INSERT INTO t_Authdata (iHeaderId, iAlerttype, iLevel, iUserType, iUser, sAlerts, sUsercomments, iStepOrder, iStatus, dActionDate, iActionedBy)
                VALUES (@NewHeaderId, 0, @WorkflowLevel, 1, @CreatedByUserId,
                        N'Your voucher ' + @Svoucherno + N' was submitted for Level ' + CAST(@WorkflowLevel AS NVARCHAR(10)) + N' approval',
                        NULL, 0, 0, GETDATE(), @CreatedByUserId);
            END

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
-- 2. Procedure: dbo.usp_ApproveVoucher (Updated to create notifications for JP and Creator)
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
        -- Lock voucher header row to prevent concurrent race conditions
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

            -- Granular notification to JP for this final approval
            INSERT INTO t_Authdata (iHeaderId, iAlerttype, iLevel, iUserType, iUser, sAlerts, sUsercomments, iStepOrder, iStatus, dActionDate, iActionedBy)
            VALUES (@iHeaderId, 0, @CurrentLevel, 1, 1,
                    N'Voucher ' + @VoucherNo + N' was fully approved and posted by ' + @ActingUsername,
                    @Comments, @CurrentStepOrder, 0, GETDATE(), @ActingUserId);

            -- Notification to creator (if not JP)
            IF @VoucherCreatedBy IS NOT NULL AND @VoucherCreatedBy <> 1
            BEGIN
                INSERT INTO t_Authdata (iHeaderId, iAlerttype, iLevel, iUserType, iUser, sAlerts, sUsercomments, iStepOrder, iStatus, dActionDate, iActionedBy)
                VALUES (@iHeaderId, 0, @CurrentLevel, 1, @VoucherCreatedBy,
                        N'Your voucher ' + @VoucherNo + N' was fully approved and posted by ' + @ActingUsername,
                        @Comments, @CurrentStepOrder, 0, GETDATE(), @ActingUserId);
            END
        END
        ELSE
        BEGIN
            SET @ResponseMessage = N'Approval stage completed successfully. Voucher advanced to next stage.';

            -- Granular notification to JP for this intermediate approval step
            INSERT INTO t_Authdata (iHeaderId, iAlerttype, iLevel, iUserType, iUser, sAlerts, sUsercomments, iStepOrder, iStatus, dActionDate, iActionedBy)
            VALUES (@iHeaderId, 0, @CurrentLevel, 1, 1,
                    N'Voucher ' + @VoucherNo + N' was approved at Step ' + CAST(@CurrentStepOrder AS NVARCHAR(10)) + N' (Level ' + CAST(@CurrentLevel AS NVARCHAR(10)) + N') by ' + @ActingUsername,
                    @Comments, @CurrentStepOrder, 0, GETDATE(), @ActingUserId);

            -- Notification to creator (if not JP)
            IF @VoucherCreatedBy IS NOT NULL AND @VoucherCreatedBy <> 1
            BEGIN
                INSERT INTO t_Authdata (iHeaderId, iAlerttype, iLevel, iUserType, iUser, sAlerts, sUsercomments, iStepOrder, iStatus, dActionDate, iActionedBy)
                VALUES (@iHeaderId, 0, @CurrentLevel, 1, @VoucherCreatedBy,
                        N'Your voucher ' + @VoucherNo + N' was approved at Step ' + CAST(@CurrentStepOrder AS NVARCHAR(10)) + N' by ' + @ActingUsername,
                        @Comments, @CurrentStepOrder, 0, GETDATE(), @ActingUserId);
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

-- ==============================================================================
-- 3. Procedure: dbo.usp_RejectVoucher (Updated to create notifications for JP and Creator)
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
        -- Lock voucher header row
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

        -- Granular notification to JP on rejection
        INSERT INTO t_Authdata (iHeaderId, iAlerttype, iLevel, iUserType, iUser, sAlerts, sUsercomments, iStepOrder, iStatus, dActionDate, iActionedBy)
        VALUES (@iHeaderId, 0, @CurrentLevel, 1, 1,
                N'Voucher ' + @VoucherNo + N' was rejected at Step ' + CAST(@CurrentStepOrder AS NVARCHAR(10)) + N' by ' + @ActingUsername,
                @Comments, @CurrentStepOrder, 0, GETDATE(), @ActingUserId);

        -- Notification to creator (if not JP)
        IF @VoucherCreatedBy IS NOT NULL AND @VoucherCreatedBy <> 1
        BEGIN
            INSERT INTO t_Authdata (iHeaderId, iAlerttype, iLevel, iUserType, iUser, sAlerts, sUsercomments, iStepOrder, iStatus, dActionDate, iActionedBy)
            VALUES (@iHeaderId, 0, @CurrentLevel, 1, @VoucherCreatedBy,
                    N'Your voucher ' + @VoucherNo + N' was rejected at Step ' + CAST(@CurrentStepOrder AS NVARCHAR(10)) + N' by ' + @ActingUsername,
                    @Comments, @CurrentStepOrder, 0, GETDATE(), @ActingUserId);
        END

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
-- 4. Procedure: dbo.usp_GetNotifications (Enhanced with filtering & action user info)
-- ==============================================================================
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
          OR (@NormalizedFilter = N'UNREAD' AND a.iStatus = 0)
          OR (@NormalizedFilter = N'READ' AND a.iStatus = 3)
      )
    ORDER BY a.iAuthId DESC;
END;
GO

-- ==============================================================================
-- 5. Procedure: dbo.usp_UpdateNotificationStatus (Mark Read / Unread)
-- ==============================================================================
CREATE OR ALTER PROCEDURE dbo.usp_UpdateNotificationStatus
(
    @UserId       INT,
    @AuthIds      NVARCHAR(MAX),  -- Comma-separated list of iAuthId values, or 'ALL'
    @NewStatus    INT,            -- 0 = Unread, 3 = Read
    @UpdatedCount INT = NULL OUTPUT
)
AS
BEGIN
    SET NOCOUNT ON;

    IF @NewStatus NOT IN (0, 1, 2, 3)
    BEGIN
        THROW 50030, N'Invalid notification status value. Allowed values are 0 (Unread) and 3 (Read).', 1;
    END

    IF @AuthIds IS NULL OR LTRIM(RTRIM(@AuthIds)) = N''
    BEGIN
        SET @UpdatedCount = 0;
        RETURN;
    END

    IF UPPER(LTRIM(RTRIM(@AuthIds))) = N'ALL'
    BEGIN
        UPDATE t_Authdata
        SET iStatus = @NewStatus
        WHERE iAlerttype = 0
          AND iUser = @UserId;

        SET @UpdatedCount = @@ROWCOUNT;
    END
    ELSE
    BEGIN
        UPDATE t_Authdata
        SET iStatus = @NewStatus
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

-- ==============================================================================
-- 6. Procedure: dbo.usp_SendVoucherNotification (Custom comment notification)
-- ==============================================================================
CREATE OR ALTER PROCEDURE dbo.usp_SendVoucherNotification
(
    @iHeaderId       INT,
    @ActingUserId    INT,
    @TargetUserId    INT,
    @Comment         NVARCHAR(250),
    @ResponseMessage NVARCHAR(250) = NULL OUTPUT
)
AS
BEGIN
    SET NOCOUNT ON;

    IF @Comment IS NULL OR LTRIM(RTRIM(@Comment)) = N''
    BEGIN
        THROW 50040, N'Notification comment cannot be empty.', 1;
    END

    -- Validate voucher
    DECLARE @VoucherNo NVARCHAR(50), @VoucherLevel INT;
    SELECT 
        @VoucherNo = Svoucherno,
        @VoucherLevel = dbo.fn_GetVoucherApprovalLevel(Amount)
    FROM t_Header 
    WHERE iHeaderId = @iHeaderId;

    IF @VoucherNo IS NULL
    BEGIN
        THROW 50041, N'Voucher not found.', 1;
    END

    -- Validate sender
    DECLARE @ActingUsername NVARCHAR(50);
    SELECT @ActingUsername = Username 
    FROM M_Users 
    WHERE UserId = @ActingUserId AND Bactive = 1;

    IF @ActingUsername IS NULL
    BEGIN
        THROW 50042, N'Sender user does not exist or account is inactive.', 1;
    END

    -- Validate recipient
    DECLARE @TargetUsername NVARCHAR(50);
    SELECT @TargetUsername = Username 
    FROM M_Users 
    WHERE UserId = @TargetUserId AND Bactive = 1;

    IF @TargetUsername IS NULL
    BEGIN
        THROW 50043, N'Recipient user does not exist or account is inactive.', 1;
    END

    BEGIN TRANSACTION;
    BEGIN TRY
        -- Insert notification alert for target user
        INSERT INTO t_Authdata
        (
            iHeaderId,
            iAlerttype,
            iLevel,
            iUserType,
            iUser,
            sAlerts,
            sUsercomments,
            iStepOrder,
            iStatus,
            dActionDate,
            iActionedBy
        )
        VALUES
        (
            @iHeaderId,
            0, -- Notification
            @VoucherLevel,
            1, -- User
            @TargetUserId,
            N'Remarks from ' + @ActingUsername + N' on Voucher ' + @VoucherNo,
            @Comment,
            0,
            0, -- Unread
            GETDATE(),
            @ActingUserId
        );

        -- Audit history entry
        INSERT INTO t_ApprovalHistory
        (
            iHeaderId,
            iLevel,
            iStepOrder,
            iActionUser,
            sAction,
            sComments,
            dActionDate
        )
        VALUES
        (
            @iHeaderId,
            @VoucherLevel,
            0,
            @ActingUserId,
            N'NOTIFIED',
            N'Notification sent to ' + @TargetUsername + N': ' + @Comment,
            GETDATE()
        );

        SET @ResponseMessage = N'Notification sent successfully to ' + @TargetUsername + N'.';

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO
