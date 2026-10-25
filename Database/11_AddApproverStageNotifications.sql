-- ==============================================================================
-- 11_AddApproverStageNotifications.sql
-- Updates dbo.usp_SaveVoucher, dbo.usp_ApproveVoucher, and dbo.usp_ResubmitVoucher
-- so that whenever a voucher is created or advances to an approver's stage,
-- an informational notification (iAlerttype = 0) is generated for that approver.
-- ==============================================================================

USE [ApprovalWorkflowDB];
GO

-- ==============================================================================
-- 1. Procedure: dbo.usp_SaveVoucher
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

    BEGIN TRY
        BEGIN TRANSACTION;

        -- Validate input parameters
        IF @Svoucherno IS NULL OR LTRIM(RTRIM(@Svoucherno)) = N''
        BEGIN
            THROW 50001, N'Voucher number is required.', 1;
        END

        IF @dDate IS NULL
        BEGIN
            THROW 50002, N'Voucher date is required.', 1;
        END

        IF @Amount IS NULL OR @Amount < 0
        BEGIN
            THROW 50003, N'Voucher amount must be zero or a positive value.', 1;
        END

        -- Check for duplicate voucher number
        IF EXISTS (SELECT 1 FROM t_Header WHERE Svoucherno = @Svoucherno)
        BEGIN
            THROW 50004, N'A voucher with this voucher number already exists.', 1;
        END

        -- Determine workflow level based on business policy:
        -- Level 0: 0.00 to 50.00
        -- Level 1: 50.01 to 100.00
        -- Level 2: 100.01 to 500.00
        -- Level 3: 500.01 to 1000.00
        -- Level 4: > 1000.00
        SET @WorkflowLevel = dbo.fn_GetVoucherApprovalLevel(@Amount);

        IF @WorkflowLevel = 0
        BEGIN
            -- Level 0: Auto-approved immediately
            SET @AuthStatus = 1; -- Approved

            INSERT INTO t_Header (Svoucherno, dDate, sNarration, Amount, iAuthStatus, dPostDate, CreatedDate, CreatedBy)
            VALUES (@Svoucherno, @dDate, @sNarration, @Amount, @AuthStatus, CAST(GETDATE() AS DATE), GETDATE(), @CreatedByUserId);

            SET @NewHeaderId = SCOPE_IDENTITY();

            -- Notify JP (UserId = 1) of auto-approval (iAlerttype = 0)
            INSERT INTO t_Authdata (iHeaderId, iAlerttype, iLevel, iUserType, iUser, sAlerts, sUsercomments, iStepOrder, iStatus, dActionDate, iActionedBy)
            VALUES (@NewHeaderId, 0, 0, 1, 1,
                    N'Notification: Voucher ' + @Svoucherno + N' auto-approved (Amount: ' + NCHAR(8377) + CAST(@Amount AS NVARCHAR(20)) + N')',
                    N'Auto-approved under Level 0 policy', 0, 0, GETDATE(), @CreatedByUserId);

            -- Also notify Creator if creator is not JP
            IF @CreatedByUserId IS NOT NULL AND @CreatedByUserId <> 1
            BEGIN
                INSERT INTO t_Authdata (iHeaderId, iAlerttype, iLevel, iUserType, iUser, sAlerts, sUsercomments, iStepOrder, iStatus, dActionDate, iActionedBy)
                VALUES (@NewHeaderId, 0, 0, 1, @CreatedByUserId,
                        N'Your voucher ' + @Svoucherno + N' was auto-approved and posted',
                        N'Auto-approved under Level 0 policy', 0, 0, GETDATE(), @CreatedByUserId);
            END

            -- Log to audit history
            INSERT INTO t_ApprovalHistory (iHeaderId, iLevel, iStepOrder, iActionUser, sAction, sComments, dActionDate)
            VALUES (@NewHeaderId, 0, 0, @CreatedByUserId, N'AUTO_APPROVED', N'Auto-approved under Level 0 policy (<= 50.00)', GETDATE());

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

            -- Notification to Step 1 Approver (Lisa - UserId 13) that a voucher requires approval
            INSERT INTO t_Authdata (iHeaderId, iAlerttype, iLevel, iUserType, iUser, sAlerts, sUsercomments, iStepOrder, iStatus, dActionDate, iActionedBy)
            VALUES (@NewHeaderId, 0, 1, 1, 13,
                    N'Voucher ' + @Svoucherno + N' requires your Level 1 approval (Amount: ' + NCHAR(8377) + CAST(@Amount AS NVARCHAR(20)) + N')',
                    NULL, 1, 0, GETDATE(), @CreatedByUserId);

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
-- 2. Procedure: dbo.usp_ApproveVoucher
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

    BEGIN TRY
        BEGIN TRANSACTION;

        -- Verify voucher exists
        DECLARE @VoucherNo NVARCHAR(50);
        DECLARE @Amount DECIMAL(18,2);
        DECLARE @CurrentAuthStatus INT;
        DECLARE @VoucherCreatedBy INT;

        SELECT
            @VoucherNo = Svoucherno,
            @Amount = Amount,
            @CurrentAuthStatus = iAuthStatus,
            @VoucherCreatedBy = CreatedBy
        FROM t_Header
        WHERE iHeaderId = @iHeaderId;

        IF @VoucherNo IS NULL
        BEGIN
            THROW 50011, N'Voucher does not exist.', 1;
        END

        IF @CurrentAuthStatus = 1
        BEGIN
            THROW 50012, N'Voucher is already fully approved.', 1;
        END

        IF @CurrentAuthStatus = 2
        BEGIN
            THROW 50013, N'Cannot approve: Voucher has been rejected.', 1;
        END

        -- Determine the active cycle
        DECLARE @ActiveCycle INT;
        SELECT @ActiveCycle = ISNULL(MAX(iCycle), 1)
        FROM t_Authdata
        WHERE iHeaderId = @iHeaderId;

        -- Find the current pending stage for this cycle
        DECLARE @AuthId INT;
        DECLARE @AssignedUserId INT;
        DECLARE @CurrentStepOrder INT;
        DECLARE @CurrentLevel INT;

        SELECT TOP 1
            @AuthId = iAuthId,
            @AssignedUserId = iUser,
            @CurrentStepOrder = iStepOrder,
            @CurrentLevel = iLevel
        FROM t_Authdata
        WHERE iHeaderId = @iHeaderId
          AND iAlerttype = 1
          AND iCycle = @ActiveCycle
          AND iStatus = 0
        ORDER BY iStepOrder ASC;

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

            -- Notification to the NEXT approver whose approval is now required
            DECLARE @NextUserId INT;
            DECLARE @NextStepOrder INT;
            DECLARE @NextLevel INT;

            SELECT TOP 1
                @NextUserId = iUser,
                @NextStepOrder = iStepOrder,
                @NextLevel = iLevel
            FROM t_Authdata
            WHERE iHeaderId = @iHeaderId
              AND iAlerttype = 1
              AND iCycle = @ActiveCycle
              AND iStatus = 0
            ORDER BY iStepOrder ASC;

            IF @NextUserId IS NOT NULL
            BEGIN
                INSERT INTO t_Authdata (iHeaderId, iAlerttype, iLevel, iUserType, iUser, sAlerts, sUsercomments, iStepOrder, iStatus, dActionDate, iActionedBy, iCycle)
                VALUES (@iHeaderId, 0, @NextLevel, 1, @NextUserId,
                        N'Voucher ' + @VoucherNo + N' requires your Level ' + CAST(@NextStepOrder AS NVARCHAR(10)) + N' approval (Amount: ' + NCHAR(8377) + CAST(@Amount AS NVARCHAR(20)) + N')',
                        @Comments, @NextStepOrder, 0, GETDATE(), @ActingUserId, @ActiveCycle);
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
-- 3. Procedure: dbo.usp_ResubmitVoucher
-- ==============================================================================
CREATE OR ALTER PROCEDURE dbo.usp_ResubmitVoucher
(
    @iHeaderId         INT,
    @ActingUserId      INT,
    @NewAmount         DECIMAL(18,2),
    @NewNarration      NVARCHAR(100) = NULL,
    @NewDate           DATE,
    @NewWorkflowLevel  INT = NULL OUTPUT,
    @NewCycle          INT = NULL OUTPUT,
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
        THROW 50020, N'Acting user does not exist or account is inactive.', 1;
    END

    BEGIN TRY
        BEGIN TRANSACTION;

        -- Verify voucher exists and check its current status and creator
        DECLARE @VoucherNo NVARCHAR(50);
        DECLARE @CurrentAuthStatus INT;
        DECLARE @CreatedBy INT;

        SELECT
            @VoucherNo = Svoucherno,
            @CurrentAuthStatus = iAuthStatus,
            @CreatedBy = CreatedBy
        FROM t_Header
        WHERE iHeaderId = @iHeaderId;

        IF @VoucherNo IS NULL
        BEGIN
            THROW 50021, N'Voucher does not exist.', 1;
        END

        -- Business Rule: Only rejected vouchers can be edited and resubmitted
        IF @CurrentAuthStatus <> 2
        BEGIN
            THROW 50022, N'Only rejected vouchers can be edited and resubmitted.', 1;
        END

        -- Business Rule: Only creator or admin can edit & resubmit
        IF @CreatedBy <> @ActingUserId
        BEGIN
            DECLARE @UserRole INT;
            SELECT @UserRole = UserRole FROM M_Users WHERE UserId = @ActingUserId;
            IF @UserRole <> 1
            BEGIN
                THROW 50023, N'Unauthorized: Only the creator of the voucher can edit and resubmit it.', 1;
            END
        END

        -- Determine current cycle number and increment for the new cycle
        DECLARE @PrevCycle INT;
        SELECT @PrevCycle = ISNULL(MAX(iCycle), 1)
        FROM t_Authdata
        WHERE iHeaderId = @iHeaderId;

        SET @NewCycle = @PrevCycle + 1;

        -- Recalculate workflow level based on new amount
        SET @NewWorkflowLevel = dbo.fn_GetVoucherApprovalLevel(@NewAmount);

        IF @NewWorkflowLevel = 0
        BEGIN
            -- Auto-approved under Level 0 policy
            UPDATE t_Header
            SET
                Amount = @NewAmount,
                sNarration = @NewNarration,
                dDate = @NewDate,
                iAuthStatus = 1, -- Approved
                dPostDate = CAST(GETDATE() AS DATE)
            WHERE iHeaderId = @iHeaderId;

            -- Log auto-approval notification for JP
            INSERT INTO t_Authdata (iHeaderId, iAlerttype, iLevel, iUserType, iUser, sAlerts, sUsercomments, iStepOrder, iStatus, dActionDate, iActionedBy, iCycle)
            VALUES (@iHeaderId, 0, 0, 1, 1,
                    N'Voucher ' + @VoucherNo + N' resubmitted and auto-approved under Level 0 policy (Cycle ' + CAST(@NewCycle AS NVARCHAR(10)) + N')',
                    N'Auto-approved under Level 0 policy', 0, 0, GETDATE(), @ActingUserId, @NewCycle);

            -- Log to history
            INSERT INTO t_ApprovalHistory (iHeaderId, iLevel, iStepOrder, iActionUser, sAction, sComments, dActionDate, iCycle)
            VALUES (@iHeaderId, 0, 0, @ActingUserId, N'RESUBMIT_AUTO_APPROVED',
                    N'Voucher edited and auto-approved under Level 0 policy (Cycle ' + CAST(@NewCycle AS NVARCHAR(10)) + N')',
                    GETDATE(), @NewCycle);

            SET @ResponseMessage = N'Voucher edited and auto-approved under Level 0 policy. Cycle ' + CAST(@NewCycle AS NVARCHAR(10)) + N' started and completed.';
        END
        ELSE
        BEGIN
            -- Levels 1 to 4: Reset status to Pending (0) and start new approval cycle
            UPDATE t_Header
            SET
                Amount = @NewAmount,
                sNarration = @NewNarration,
                dDate = @NewDate,
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

            -- Notification for Step 1 Approver (Lisa - UserId 13)
            INSERT INTO t_Authdata (iHeaderId, iAlerttype, iLevel, iUserType, iUser, sAlerts, sUsercomments, iStepOrder, iStatus, dActionDate, iActionedBy, iCycle)
            VALUES (@iHeaderId, 0, 1, 1, 13,
                    N'Voucher ' + @VoucherNo + N' resubmitted and requires Level 1 approval (Cycle ' + CAST(@NewCycle AS NVARCHAR(10)) + N')',
                    NULL, 1, 0, GETDATE(), @ActingUserId, @NewCycle);

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
