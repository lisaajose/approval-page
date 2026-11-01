-- ==============================================================================
-- 12_AddApprovalMatrixPolicyTable.sql
-- Creates t_ApprovalMatrixPolicy table, updates dbo.fn_GetVoucherApprovalLevel to
-- dynamically query policies, and creates stored procedures for Admin management.
-- ==============================================================================

USE [ApprovalWorkflowDB];
GO

-- 1. Create table t_ApprovalMatrixPolicy if it doesn't exist
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 't_ApprovalMatrixPolicy')
BEGIN
    CREATE TABLE t_ApprovalMatrixPolicy
    (
        iLevel INT NOT NULL PRIMARY KEY,
        sLevelName NVARCHAR(50) NOT NULL,
        mMinAmount DECIMAL(18,2) NOT NULL,
        mMaxAmount DECIMAL(18,2) NULL,
        sApproverDescription NVARCHAR(100) NOT NULL,
        sPolicyDescription NVARCHAR(200) NOT NULL,
        iRequiredApprovers INT NOT NULL
    );

    INSERT INTO t_ApprovalMatrixPolicy (iLevel, sLevelName, mMinAmount, mMaxAmount, sApproverDescription, sPolicyDescription, iRequiredApprovers)
    VALUES
    (0, N'Level 0', 0.00, 50.00, N'No approvers (Auto-approved)', N'Auto-approved immediately; JP notified', 0),
    (1, N'Level 1', 50.01, 100.00, N'Lisa', N'Lisa; JP notified', 1),
    (2, N'Level 2', 100.01, 500.00, N'Lisa -> Gautham', N'Lisa -> Gautham; JP notified', 2),
    (3, N'Level 3', 500.01, 1000.00, N'Lisa -> Gautham -> Edwin', N'Lisa -> Gautham -> Edwin; JP notified', 3),
    (4, N'Level 4', 1000.01, NULL, N'Lisa -> Gautham -> Edwin -> JP', N'Lisa -> Gautham -> Edwin -> JP; JP notified', 4);
END
GO

-- 2. Update dbo.fn_GetVoucherApprovalLevel to read from t_ApprovalMatrixPolicy
CREATE OR ALTER FUNCTION dbo.fn_GetVoucherApprovalLevel
(
    @Amount DECIMAL(18,2)
)
RETURNS INT
AS
BEGIN
    IF @Amount IS NULL OR @Amount < 0.00
        RETURN -1; -- Invalid amount indicator

    DECLARE @Level INT;

    SELECT TOP 1 @Level = iLevel
    FROM t_ApprovalMatrixPolicy
    WHERE @Amount >= mMinAmount 
      AND (mMaxAmount IS NULL OR @Amount <= mMaxAmount)
    ORDER BY iLevel ASC;

    -- Fallback in case of gap or configuration anomaly: highest level
    IF @Level IS NULL
    BEGIN
        SELECT TOP 1 @Level = iLevel
        FROM t_ApprovalMatrixPolicy
        ORDER BY iLevel DESC;
    END

    RETURN ISNULL(@Level, 4);
END;
GO

-- 3. Procedure: dbo.usp_GetApprovalMatrixPolicies
CREATE OR ALTER PROCEDURE dbo.usp_GetApprovalMatrixPolicies
AS
BEGIN
    SET NOCOUNT ON;
    SELECT 
        iLevel,
        sLevelName,
        mMinAmount,
        mMaxAmount,
        sApproverDescription,
        sPolicyDescription,
        iRequiredApprovers
    FROM t_ApprovalMatrixPolicy
    ORDER BY iLevel ASC;
END;
GO

-- 4. Procedure: dbo.usp_UpdateApprovalMatrixPolicy
CREATE OR ALTER PROCEDURE dbo.usp_UpdateApprovalMatrixPolicy
(
    @ActingUserId INT,
    @Level INT,
    @MinAmount DECIMAL(18,2),
    @MaxAmount DECIMAL(18,2) = NULL,
    @ResponseMessage NVARCHAR(250) OUTPUT
)
AS
BEGIN
    SET NOCOUNT ON;

    -- Security validation: Only admins (UserRole = 1) can edit policies
    DECLARE @UserRole INT;
    SELECT @UserRole = UserRole FROM M_Users WHERE UserId = @ActingUserId AND Bactive = 1;

    IF @UserRole IS NULL OR @UserRole <> 1
    BEGIN
        SET @ResponseMessage = N'Unauthorized: Only administrators can update approval matrix policies.';
        THROW 50050, @ResponseMessage, 1;
    END

    IF NOT EXISTS (SELECT 1 FROM t_ApprovalMatrixPolicy WHERE iLevel = @Level)
    BEGIN
        SET @ResponseMessage = N'Invalid approval level specified.';
        THROW 50051, @ResponseMessage, 1;
    END

    IF @MinAmount < 0.00
    BEGIN
        SET @ResponseMessage = N'Minimum amount cannot be negative.';
        THROW 50052, @ResponseMessage, 1;
    END

    IF @MaxAmount IS NOT NULL AND @MaxAmount < @MinAmount
    BEGIN
        SET @ResponseMessage = N'Maximum amount cannot be less than minimum amount.';
        THROW 50053, @ResponseMessage, 1;
    END

    UPDATE t_ApprovalMatrixPolicy
    SET 
        mMinAmount = @MinAmount,
        mMaxAmount = @MaxAmount
    WHERE iLevel = @Level;

    SET @ResponseMessage = N'Approval matrix policy for Level ' + CAST(@Level AS NVARCHAR(10)) + N' updated successfully.';
END;
GO
