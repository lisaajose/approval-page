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
    @Action            NVARCHAR(10),             -- 'SAVE', 'APPROVE', 'REJECT', 'NOTIFY'
    @HeaderId          INT = NULL,
    @VoucherNo         NVARCHAR(50) = NULL,
    @VoucherDate       DATE = NULL,
    @Narration         NVARCHAR(100) = NULL,
    @Amount            DECIMAL(18,2) = NULL,
    @UserId            INT,
    @UserComment       NVARCHAR(250) = NULL,
    @TargetUserId      INT = NULL,
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
    ELSE IF @NormalizedAction = N'NOTIFY'
    BEGIN
        EXEC dbo.usp_SendVoucherNotification
            @iHeaderId       = @HeaderId,
            @ActingUserId    = @UserId,
            @TargetUserId    = @TargetUserId,
            @Comment         = @UserComment,
            @ResponseMessage = @ResponseMessage OUTPUT;

        SELECT 
            @AuthStatus = iAuthStatus,
            @WorkflowLevel = dbo.fn_GetVoucherApprovalLevel(Amount)
        FROM t_Header 
        WHERE iHeaderId = @HeaderId;

        SET @NewHeaderId = @HeaderId;
    END
    ELSE IF @NormalizedAction = N'RESUBMIT' OR @NormalizedAction = N'EDIT'
    BEGIN
        EXEC dbo.usp_ResubmitVoucher
            @iHeaderId       = @HeaderId,
            @ActingUserId    = @UserId,
            @dDate           = @VoucherDate,
            @sNarration      = @Narration,
            @Amount          = @Amount,
            @NewWorkflowLevel = @WorkflowLevel OUTPUT,
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
        THROW 50099, N'Invalid workflow action specified. Supported actions are SAVE, APPROVE, REJECT, NOTIFY, RESUBMIT.', 1;
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
        SET @Message = N'Invalid username or password.';
    END
END;
GO
