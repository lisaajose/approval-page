-- ==============================================================================
-- Script: 05_CreateFunctionsAndViews.sql
-- Description: Creates helper functions and views.
--              fn_GetVoucherApprovalLevel encapsulates the boundary logic in a
--              single authoritative database rule.
-- ==============================================================================

USE [ApprovalWorkflowDB];
GO

-- 1. Scalar Function: fn_GetVoucherApprovalLevel
-- Evaluates the financial amount and returns the applicable workflow level.
-- User-selected policy: Upper-inclusive boundaries:
--   Level 0: ₹0.00 - ₹50.00
--   Level 1: ₹50.01 - ₹100.00
--   Level 2: ₹100.01 - ₹500.00
--   Level 3: ₹500.01 - ₹1,000.00
--   Level 4: > ₹1,000.00
CREATE OR ALTER FUNCTION dbo.fn_GetVoucherApprovalLevel
(
    @Amount DECIMAL(18,2)
)
RETURNS INT
AS
BEGIN
    IF @Amount IS NULL OR @Amount < 0.00
        RETURN -1; -- Invalid amount indicator

    IF @Amount <= 50.00
        RETURN 0;

    IF @Amount <= 100.00
        RETURN 1;

    IF @Amount <= 500.00
        RETURN 2;

    IF @Amount <= 1000.00
        RETURN 3;

    -- Amount > 1000.00
    RETURN 4;
END;
GO

-- 2. View: vw_VoucherSummary
-- Consolidated view of vouchers with current active approval step information
CREATE OR ALTER VIEW dbo.vw_VoucherSummary
AS
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
    -- Determine current active pending approval step
    curStep.iStepOrder AS CurrentPendingStepOrder,
    curStep.iLevel AS CurrentPendingLevel,
    curStep.iUser AS CurrentPendingUserId,
    curUser.Username AS CurrentPendingUsername,
    curStep.sAlerts AS CurrentPendingAlert
FROM t_Header h
LEFT JOIN M_Users uCreator ON h.CreatedBy = uCreator.UserId
OUTER APPLY (
    -- The earliest pending approval step for this voucher
    SELECT TOP 1
        a.iAuthId,
        a.iStepOrder,
        a.iLevel,
        a.iUser,
        a.sAlerts
    FROM t_Authdata a
    WHERE a.iHeaderId = h.iHeaderId
      AND a.iAlerttype = 1 -- Approval alert
      AND a.iStatus = 0    -- Pending
      -- Preceding steps must be completed
      AND NOT EXISTS (
          SELECT 1 FROM t_Authdata prevStep
          WHERE prevStep.iHeaderId = h.iHeaderId
            AND prevStep.iAlerttype = 1
            AND prevStep.iStepOrder < a.iStepOrder
            AND prevStep.iStatus <> 1
      )
    ORDER BY a.iStepOrder ASC
) curStep
LEFT JOIN M_Users curUser ON curStep.iUser = curUser.UserId;
GO
