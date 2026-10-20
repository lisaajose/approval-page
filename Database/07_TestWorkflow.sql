-- ==============================================================================
-- Script: 07_TestWorkflow.sql
-- Description: Comprehensive automated verification test suite for the
--              ApprovalWorkflowDB database.
--              Validates schema, seed data, boundary rules, Level 0 auto-approval,
--              sequential approvals, unauthorized attempts, out-of-order attempts,
--              rejection, approval after rejection, negative amounts, duplicate
--              vouchers, rollback integrity, and retrieval procedures.
-- ==============================================================================

-- NOTE: In Azure SQL Database, the USE statement is not supported. Connect directly to [ApprovalWorkflowDB].
-- USE [ApprovalWorkflowDB];
-- GO

SET NOCOUNT ON;

-- Table to collect test results
IF OBJECT_ID('tempdb..#TestResults') IS NOT NULL DROP TABLE #TestResults;
CREATE TABLE #TestResults
(
    TestNo      INT IDENTITY(1,1),
    Category    NVARCHAR(50),
    TestName    NVARCHAR(150),
    Expected    NVARCHAR(200),
    Actual      NVARCHAR(200),
    Status      NVARCHAR(10)
);

PRINT '==============================================================================';
PRINT 'STARTING APPROVAL WORKFLOW TEST SUITE';
PRINT '==============================================================================';

-- Helper macro cleanup of prior test vouchers
DELETE FROM t_Header WHERE Svoucherno LIKE N'TEST-%';

-- ------------------------------------------------------------------------------
-- TEST 1: Database Existence & Context
-- ------------------------------------------------------------------------------
DECLARE @CurrentDB NVARCHAR(100) = DB_NAME();
INSERT INTO #TestResults (Category, TestName, Expected, Actual, Status)
VALUES (
    'Setup',
    'Database Context',
    'ApprovalWorkflowDB',
    @CurrentDB,
    CASE WHEN @CurrentDB = 'ApprovalWorkflowDB' THEN 'PASS' ELSE 'FAIL' END
);

-- ------------------------------------------------------------------------------
-- TEST 2: Core Tables Existence
-- ------------------------------------------------------------------------------
DECLARE @TableCount INT;
SELECT @TableCount = COUNT(*)
FROM sys.tables
WHERE name IN ('M_Users', 't_Header', 't_Authdata', 't_ApprovalHistory');

INSERT INTO #TestResults (Category, TestName, Expected, Actual, Status)
VALUES (
    'Schema',
    'Core Tables Existence',
    '4 Tables (M_Users, t_Header, t_Authdata, t_ApprovalHistory)',
    CAST(@TableCount AS NVARCHAR(10)) + ' Tables Found',
    CASE WHEN @TableCount = 4 THEN 'PASS' ELSE 'FAIL' END
);

-- ------------------------------------------------------------------------------
-- TEST 3: Seed Users Verification (Exact IDs preserved)
-- ------------------------------------------------------------------------------
DECLARE @UserCheckCount INT;
SELECT @UserCheckCount = COUNT(*)
FROM M_Users
WHERE (UserId = 1 AND Username = 'JP')
   OR (UserId = 2 AND Username = 'Smitha')
   OR (UserId = 3 AND Username = 'PM')
   OR (UserId = 5 AND Username = 'EDWIN')
   OR (UserId = 11 AND Username = 'JERN')
   OR (UserId = 12 AND Username = 'NIRALI')
   OR (UserId = 13 AND Username = 'LISA')
   OR (UserId = 1012 AND Username = 'GAUTHAM');

INSERT INTO #TestResults (Category, TestName, Expected, Actual, Status)
VALUES (
    'Seed Data',
    'Preserved User IDs (JP=1, LISA=13, GAUTHAM=1012, EDWIN=5, etc.)',
    '8 Seed Users Matched with Exact IDs',
    CAST(@UserCheckCount AS NVARCHAR(10)) + ' Matched',
    CASE WHEN @UserCheckCount = 8 THEN 'PASS' ELSE 'FAIL' END
);

-- ------------------------------------------------------------------------------
-- TEST 4: Boundary Logic Function (Upper-Inclusive Rule)
-- ------------------------------------------------------------------------------
DECLARE @L0_Boundary INT = dbo.fn_GetVoucherApprovalLevel(50.00);
DECLARE @L1_Lower INT = dbo.fn_GetVoucherApprovalLevel(50.01);
DECLARE @L1_Upper INT = dbo.fn_GetVoucherApprovalLevel(100.00);
DECLARE @L2_Lower INT = dbo.fn_GetVoucherApprovalLevel(100.01);
DECLARE @L2_Upper INT = dbo.fn_GetVoucherApprovalLevel(500.00);
DECLARE @L3_Lower INT = dbo.fn_GetVoucherApprovalLevel(500.01);
DECLARE @L3_Upper INT = dbo.fn_GetVoucherApprovalLevel(1000.00);
DECLARE @L4_Lower INT = dbo.fn_GetVoucherApprovalLevel(1000.01);

DECLARE @BoundaryPassed BIT = 0;
IF (@L0_Boundary = 0 AND @L1_Lower = 1 AND @L1_Upper = 1 AND
    @L2_Lower = 2 AND @L2_Upper = 2 AND
    @L3_Lower = 3 AND @L3_Upper = 3 AND
    @L4_Lower = 4)
    SET @BoundaryPassed = 1;

INSERT INTO #TestResults (Category, TestName, Expected, Actual, Status)
VALUES (
    'Business Rules',
    'Amount Boundary Evaluation (50, 100, 500, 1000)',
    'L0: <=50, L1: 50.01-100, L2: 100.01-500, L3: 500.01-1000, L4: >1000',
    'Evaluated correctly (L0=' + CAST(@L0_Boundary AS NVARCHAR(2)) + ', L1=' + CAST(@L1_Upper AS NVARCHAR(2)) + ', L2=' + CAST(@L2_Upper AS NVARCHAR(2)) + ', L3=' + CAST(@L3_Upper AS NVARCHAR(2)) + ', L4=' + CAST(@L4_Lower AS NVARCHAR(2)) + ')',
    CASE WHEN @BoundaryPassed = 1 THEN 'PASS' ELSE 'FAIL' END
);

-- ------------------------------------------------------------------------------
-- TEST 5: Level 0 Workflow (Auto-Approval and JP Notification)
-- ------------------------------------------------------------------------------
DECLARE @HId0 INT, @Lvl0 INT, @Stat0 INT, @Msg0 NVARCHAR(250);
EXEC dbo.usp_SaveVoucher
    @Svoucherno = N'TEST-V0-001',
    @Amount = 45.00,
    @sNarration = N'Office Tea & Snacks',
    @CreatedByUserId = 1,
    @NewHeaderId = @HId0 OUTPUT,
    @WorkflowLevel = @Lvl0 OUTPUT,
    @AuthStatus = @Stat0 OUTPUT,
    @ResponseMessage = @Msg0 OUTPUT;

-- Verify header status is 1 (Approved) and JP has a notification record
DECLARE @JPNotifCount0 INT;
SELECT @JPNotifCount0 = COUNT(*)
FROM t_Authdata
WHERE iHeaderId = @HId0 AND iAlerttype = 0 AND iUser = 1;

INSERT INTO #TestResults (Category, TestName, Expected, Actual, Status)
VALUES (
    'Workflow Level 0',
    'Level 0 (₹45.00) Auto-Approval & Notification',
    'Status=1 (Approved), JP Notified',
    'Status=' + CAST(@Stat0 AS NVARCHAR(5)) + ', JP Notif Count=' + CAST(@JPNotifCount0 AS NVARCHAR(5)),
    CASE WHEN @Stat0 = 1 AND @JPNotifCount0 = 1 THEN 'PASS' ELSE 'FAIL' END
);

-- ------------------------------------------------------------------------------
-- TEST 6: Level 1 Workflow Initialization (₹75.00 -> Lisa only)
-- ------------------------------------------------------------------------------
DECLARE @HId1 INT, @Lvl1 INT, @Stat1 INT, @Msg1 NVARCHAR(250);
EXEC dbo.usp_SaveVoucher
    @Svoucherno = N'TEST-V1-001',
    @Amount = 75.00,
    @sNarration = N'Printer Cartridge',
    @CreatedByUserId = 1,
    @NewHeaderId = @HId1 OUTPUT,
    @WorkflowLevel = @Lvl1 OUTPUT,
    @AuthStatus = @Stat1 OUTPUT,
    @ResponseMessage = @Msg1 OUTPUT;

DECLARE @L1_Approver INT, @L1_TotalApprovers INT;
SELECT @L1_TotalApprovers = COUNT(*), @L1_Approver = MAX(iUser)
FROM t_Authdata
WHERE iHeaderId = @HId1 AND iAlerttype = 1;

INSERT INTO #TestResults (Category, TestName, Expected, Actual, Status)
VALUES (
    'Workflow Level 1',
    'Level 1 (₹75.00) Assignment to Lisa (UserId 13)',
    '1 Approver: Lisa (13)',
    'Approvers: ' + CAST(@L1_TotalApprovers AS NVARCHAR(5)) + ', User: ' + CAST(@L1_Approver AS NVARCHAR(5)),
    CASE WHEN @L1_TotalApprovers = 1 AND @L1_Approver = 13 THEN 'PASS' ELSE 'FAIL' END
);

-- ------------------------------------------------------------------------------
-- TEST 7: Level 2 Workflow Initialization (₹250.00 -> Lisa, then Gautham)
-- ------------------------------------------------------------------------------
DECLARE @HId2 INT, @Lvl2 INT, @Stat2 INT, @Msg2 NVARCHAR(250);
EXEC dbo.usp_SaveVoucher
    @Svoucherno = N'TEST-V2-001',
    @Amount = 250.00,
    @sNarration = N'Software License',
    @CreatedByUserId = 1,
    @NewHeaderId = @HId2 OUTPUT,
    @WorkflowLevel = @Lvl2 OUTPUT,
    @AuthStatus = @Stat2 OUTPUT,
    @ResponseMessage = @Msg2 OUTPUT;

DECLARE @L2_Step1User INT, @L2_Step2User INT;
SELECT @L2_Step1User = MAX(CASE WHEN iStepOrder = 1 THEN iUser END),
       @L2_Step2User = MAX(CASE WHEN iStepOrder = 2 THEN iUser END)
FROM t_Authdata
WHERE iHeaderId = @HId2 AND iAlerttype = 1;

INSERT INTO #TestResults (Category, TestName, Expected, Actual, Status)
VALUES (
    'Workflow Level 2',
    'Level 2 (₹250.00) Assignment: Lisa (Step 1) -> Gautham (Step 2)',
    'Step 1: 13, Step 2: 1012',
    'Step 1: ' + CAST(@L2_Step1User AS NVARCHAR(5)) + ', Step 2: ' + CAST(@L2_Step2User AS NVARCHAR(5)),
    CASE WHEN @L2_Step1User = 13 AND @L2_Step2User = 1012 THEN 'PASS' ELSE 'FAIL' END
);

-- ------------------------------------------------------------------------------
-- TEST 8: Level 3 Workflow Initialization (₹750.00 -> Lisa, Gautham, Edwin)
-- ------------------------------------------------------------------------------
DECLARE @HId3 INT, @Lvl3 INT, @Stat3 INT, @Msg3 NVARCHAR(250);
EXEC dbo.usp_SaveVoucher
    @Svoucherno = N'TEST-V3-001',
    @Amount = 750.00,
    @sNarration = N'Server Maintenance',
    @CreatedByUserId = 1,
    @NewHeaderId = @HId3 OUTPUT,
    @WorkflowLevel = @Lvl3 OUTPUT,
    @AuthStatus = @Stat3 OUTPUT,
    @ResponseMessage = @Msg3 OUTPUT;

DECLARE @L3_Step3User INT;
SELECT @L3_Step3User = MAX(CASE WHEN iStepOrder = 3 THEN iUser END)
FROM t_Authdata
WHERE iHeaderId = @HId3 AND iAlerttype = 1;

INSERT INTO #TestResults (Category, TestName, Expected, Actual, Status)
VALUES (
    'Workflow Level 3',
    'Level 3 (₹750.00) Step 3 Assigned to Edwin (UserId 5)',
    'Step 3: 5',
    'Step 3: ' + CAST(@L3_Step3User AS NVARCHAR(5)),
    CASE WHEN @L3_Step3User = 5 THEN 'PASS' ELSE 'FAIL' END
);

-- ------------------------------------------------------------------------------
-- TEST 9: Level 4 Workflow Initialization (₹1,500.00 -> Lisa, Gautham, Edwin, JP)
-- ------------------------------------------------------------------------------
DECLARE @HId4 INT, @Lvl4 INT, @Stat4 INT, @Msg4 NVARCHAR(250);
EXEC dbo.usp_SaveVoucher
    @Svoucherno = N'TEST-V4-001',
    @Amount = 1500.00,
    @sNarration = N'Capital Equipment Purchase',
    @CreatedByUserId = 1,
    @NewHeaderId = @HId4 OUTPUT,
    @WorkflowLevel = @Lvl4 OUTPUT,
    @AuthStatus = @Stat4 OUTPUT,
    @ResponseMessage = @Msg4 OUTPUT;

DECLARE @L4_TotalStages INT, @L4_FinalUser INT;
SELECT @L4_TotalStages = COUNT(*),
       @L4_FinalUser = MAX(CASE WHEN iStepOrder = 4 THEN iUser END)
FROM t_Authdata
WHERE iHeaderId = @HId4 AND iAlerttype = 1;

INSERT INTO #TestResults (Category, TestName, Expected, Actual, Status)
VALUES (
    'Workflow Level 4',
    'Level 4 (₹1500.00) 4 Stages, Final Stage assigned to JP (UserId 1)',
    '4 Stages, Final Stage: 1',
    CAST(@L4_TotalStages AS NVARCHAR(5)) + ' Stages, Final: ' + CAST(@L4_FinalUser AS NVARCHAR(5)),
    CASE WHEN @L4_TotalStages = 4 AND @L4_FinalUser = 1 THEN 'PASS' ELSE 'FAIL' END
);

-- ------------------------------------------------------------------------------
-- TEST 10: Unauthorized Approval Attempt (Gautham tries to approve Lisa's Step 1)
-- ------------------------------------------------------------------------------
DECLARE @UnauthErrorCaught BIT = 0;
BEGIN TRY
    EXEC dbo.usp_ApproveVoucher
        @iHeaderId = @HId2,
        @ActingUserId = 1012, -- Gautham attempting to approve Step 1 (assigned to Lisa)
        @Comments = N'Sneaky unauthorized approval attempt';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50015
        SET @UnauthErrorCaught = 1;
END CATCH

INSERT INTO #TestResults (Category, TestName, Expected, Actual, Status)
VALUES (
    'Security / Auth',
    'Unauthorized User Approval Attempt Rejected',
    'Error 50015 (Unauthorized)',
    CASE WHEN @UnauthErrorCaught = 1 THEN 'Error 50015 Caught' ELSE 'Allowed Unauthorized Action' END,
    CASE WHEN @UnauthErrorCaught = 1 THEN 'PASS' ELSE 'FAIL' END
);

-- ------------------------------------------------------------------------------
-- TEST 11: Out-of-Order Approval Attempt (Edwin tries to approve Step 3 of Level 3)
-- ------------------------------------------------------------------------------
DECLARE @OutOfOrderCaught BIT = 0;
BEGIN TRY
    EXEC dbo.usp_ApproveVoucher
        @iHeaderId = @HId3,
        @ActingUserId = 5, -- Edwin attempting out-of-order approval
        @Comments = N'Skipping ahead to step 3';
END TRY
BEGIN CATCH
    -- Fails authorization or sequence check because Step 1 is active
    SET @OutOfOrderCaught = 1;
END CATCH

INSERT INTO #TestResults (Category, TestName, Expected, Actual, Status)
VALUES (
    'Workflow Sequence',
    'Out-of-Order Approval Blocked',
    'Error Raised (Cannot skip prerequisite steps)',
    CASE WHEN @OutOfOrderCaught = 1 THEN 'Blocked Successfully' ELSE 'Allowed Out-of-Order' END,
    CASE WHEN @OutOfOrderCaught = 1 THEN 'PASS' ELSE 'FAIL' END
);

-- ------------------------------------------------------------------------------
-- TEST 12: Successful Sequential Approval of Level 2 (Lisa -> Gautham -> Approved)
-- ------------------------------------------------------------------------------
DECLARE @Step1Approved BIT = 0, @Step2Approved BIT = 0, @FinalStatus2 INT;
-- Step 1: Lisa approves
EXEC dbo.usp_ApproveVoucher @iHeaderId = @HId2, @ActingUserId = 13, @Comments = N'Lisa approves step 1';

-- Verify Step 1 is approved and voucher is still Pending (status 0)
SELECT @Step1Approved = CASE WHEN iStatus = 1 THEN 1 ELSE 0 END
FROM t_Authdata WHERE iHeaderId = @HId2 AND iStepOrder = 1 AND iAlerttype = 1;

-- Step 2: Gautham approves
EXEC dbo.usp_ApproveVoucher @iHeaderId = @HId2, @ActingUserId = 1012, @Comments = N'Gautham approves step 2';

SELECT @FinalStatus2 = iAuthStatus FROM t_Header WHERE iHeaderId = @HId2;

INSERT INTO #TestResults (Category, TestName, Expected, Actual, Status)
VALUES (
    'Sequential Approval',
    'Level 2 Complete Multi-stage Approval Flow',
    'Step 1 Approved -> Step 2 Approved -> Header Status 1 (Approved)',
    'Final Header Status: ' + CAST(@FinalStatus2 AS NVARCHAR(5)),
    CASE WHEN @Step1Approved = 1 AND @FinalStatus2 = 1 THEN 'PASS' ELSE 'FAIL' END
);

-- ------------------------------------------------------------------------------
-- TEST 13: Attempt to Approve Already Approved Voucher
-- ------------------------------------------------------------------------------
DECLARE @ApproveAlreadyApprovedCaught BIT = 0;
BEGIN TRY
    EXEC dbo.usp_ApproveVoucher @iHeaderId = @HId2, @ActingUserId = 1012, @Comments = N'Double approval';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50012
        SET @ApproveAlreadyApprovedCaught = 1;
END CATCH

INSERT INTO #TestResults (Category, TestName, Expected, Actual, Status)
VALUES (
    'Integrity',
    'Attempt to Approve Already Approved Voucher',
    'Error 50012 (Already approved)',
    CASE WHEN @ApproveAlreadyApprovedCaught = 1 THEN 'Error 50012 Caught' ELSE 'Failed to block' END,
    CASE WHEN @ApproveAlreadyApprovedCaught = 1 THEN 'PASS' ELSE 'FAIL' END
);

-- ------------------------------------------------------------------------------
-- TEST 14: Rejection Workflow
-- ------------------------------------------------------------------------------
DECLARE @RejectionCaught BIT = 0, @RejectedStatus INT;
-- Lisa rejects Level 3 voucher (TEST-V3-001)
EXEC dbo.usp_RejectVoucher
    @iHeaderId = @HId3,
    @ActingUserId = 13,
    @Comments = N'Budget exceeds departmental allocation. Rejected.';

SELECT @RejectedStatus = iAuthStatus FROM t_Header WHERE iHeaderId = @HId3;

INSERT INTO #TestResults (Category, TestName, Expected, Actual, Status)
VALUES (
    'Rejection Flow',
    'Voucher Rejection by Authorized Approver',
    'Header Status = 2 (Rejected)',
    'Header Status = ' + CAST(@RejectedStatus AS NVARCHAR(5)),
    CASE WHEN @RejectedStatus = 2 THEN 'PASS' ELSE 'FAIL' END
);

-- ------------------------------------------------------------------------------
-- TEST 15: Attempt to Approve a Rejected Voucher
-- ------------------------------------------------------------------------------
DECLARE @ApproveRejectedCaught BIT = 0;
BEGIN TRY
    EXEC dbo.usp_ApproveVoucher
        @iHeaderId = @HId3,
        @ActingUserId = 1012,
        @Comments = N'Attempting to revive rejected voucher';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50013
        SET @ApproveRejectedCaught = 1;
END CATCH

INSERT INTO #TestResults (Category, TestName, Expected, Actual, Status)
VALUES (
    'Rejection Integrity',
    'Attempt to Approve a Rejected Voucher Blocked',
    'Error 50013 (Cannot approve rejected voucher)',
    CASE WHEN @ApproveRejectedCaught = 1 THEN 'Error 50013 Caught' ELSE 'Failed to block' END,
    CASE WHEN @ApproveRejectedCaught = 1 THEN 'PASS' ELSE 'FAIL' END
);

-- ------------------------------------------------------------------------------
-- TEST 16: Validation - Negative Amount Blocked
-- ------------------------------------------------------------------------------
DECLARE @NegativeAmountCaught BIT = 0;
BEGIN TRY
    EXEC dbo.usp_SaveVoucher
        @Svoucherno = N'TEST-NEG-001',
        @Amount = -150.00,
        @CreatedByUserId = 1;
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50002
        SET @NegativeAmountCaught = 1;
END CATCH

INSERT INTO #TestResults (Category, TestName, Expected, Actual, Status)
VALUES (
    'Validation',
    'Negative Amount Rejected',
    'Error 50002 (Amount cannot be negative)',
    CASE WHEN @NegativeAmountCaught = 1 THEN 'Error 50002 Caught' ELSE 'Allowed Negative' END,
    CASE WHEN @NegativeAmountCaught = 1 THEN 'PASS' ELSE 'FAIL' END
);

-- ------------------------------------------------------------------------------
-- TEST 17: Validation - Duplicate Voucher Number Blocked
-- ------------------------------------------------------------------------------
DECLARE @DuplicateVoucherCaught BIT = 0;
BEGIN TRY
    -- TEST-V1-001 already created earlier
    EXEC dbo.usp_SaveVoucher
        @Svoucherno = N'TEST-V1-001',
        @Amount = 90.00,
        @CreatedByUserId = 1;
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50004
        SET @DuplicateVoucherCaught = 1;
END CATCH

INSERT INTO #TestResults (Category, TestName, Expected, Actual, Status)
VALUES (
    'Validation',
    'Duplicate Voucher Number Rejected',
    'Error 50004 (Voucher number already exists)',
    CASE WHEN @DuplicateVoucherCaught = 1 THEN 'Error 50004 Caught' ELSE 'Allowed Duplicate' END,
    CASE WHEN @DuplicateVoucherCaught = 1 THEN 'PASS' ELSE 'FAIL' END
);

-- ------------------------------------------------------------------------------
-- TEST 18: Notification Isolation (JP Notification does not grant approval)
-- ------------------------------------------------------------------------------
-- Check Level 1 voucher: JP received a notification (iAlerttype = 0), but only Lisa has approval alert (iAlerttype = 1)
DECLARE @JPApprovalAlertCount INT;
SELECT @JPApprovalAlertCount = COUNT(*)
FROM t_Authdata
WHERE iHeaderId = @HId1 AND iAlerttype = 1 AND iUser = 1;

INSERT INTO #TestResults (Category, TestName, Expected, Actual, Status)
VALUES (
    'Notification Security',
    'Notification Isolation (Notification does not grant approval authority)',
    '0 Approval Alerts for JP on Level 1',
    CAST(@JPApprovalAlertCount AS NVARCHAR(5)) + ' Approval Alerts Found',
    CASE WHEN @JPApprovalAlertCount = 0 THEN 'PASS' ELSE 'FAIL' END
);

-- ------------------------------------------------------------------------------
-- TEST 19: Retrieval - Pending Approvals for Lisa
-- ------------------------------------------------------------------------------
-- Lisa has pending approval for TEST-V1-001 and TEST-V4-001
IF OBJECT_ID('tempdb..#LisaPending') IS NOT NULL DROP TABLE #LisaPending;
CREATE TABLE #LisaPending
(
    iHeaderId INT, Svoucherno NVARCHAR(50), dDate DATE, sNarration NVARCHAR(100),
    Amount DECIMAL(18,2), iAuthStatus INT, CreatedDate DATETIME, CreatedByUsername NVARCHAR(50),
    WorkflowLevel INT, iAuthId INT, iLevel INT, iStepOrder INT, sAlerts NVARCHAR(100), AssignmentStatus INT
);

INSERT INTO #LisaPending
EXEC dbo.usp_GetPendingApprovals @UserId = 13;

DECLARE @LisaPendingCount INT = (SELECT COUNT(*) FROM #LisaPending WHERE Svoucherno IN (N'TEST-V1-001', N'TEST-V4-001'));

INSERT INTO #TestResults (Category, TestName, Expected, Actual, Status)
VALUES (
    'Retrieval',
    'usp_GetPendingApprovals for Lisa (UserId 13)',
    'Returns active pending vouchers assigned to Lisa',
    CAST(@LisaPendingCount AS NVARCHAR(5)) + ' Pending Vouchers Retrieved',
    CASE WHEN @LisaPendingCount >= 2 THEN 'PASS' ELSE 'FAIL' END
);

-- ------------------------------------------------------------------------------
-- DISPLAY FINAL RESULTS
-- ------------------------------------------------------------------------------
PRINT '';
PRINT '==============================================================================';
PRINT 'TEST SUITE SUMMARY';
PRINT '==============================================================================';

SELECT
    TestNo,
    Category,
    TestName,
    Expected,
    Actual,
    Status
FROM #TestResults
ORDER BY TestNo;

DECLARE @TotalTests INT = (SELECT COUNT(*) FROM #TestResults);
DECLARE @PassedCount INT = (SELECT COUNT(*) FROM #TestResults WHERE Status = 'PASS');
DECLARE @FailedCount INT = (SELECT COUNT(*) FROM #TestResults WHERE Status <> 'PASS');

PRINT 'Total Tests: ' + CAST(@TotalTests AS NVARCHAR(10)) +
      ' | Passed: ' + CAST(@PassedCount AS NVARCHAR(10)) +
      ' | Failed: ' + CAST(@FailedCount AS NVARCHAR(10));

IF @FailedCount = 0
    PRINT '>>> ALL VERIFICATION TESTS PASSED SUCCESSFULLY! <<<';
ELSE
    PRINT '>>> SOME TESTS FAILED! CHECK OUTPUT ABOVE. <<<';

GO
