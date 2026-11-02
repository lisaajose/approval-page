-- ==============================================================================
-- 13_AddApprovalMatrixXmlSupport.sql
-- Adds two stored procedures to the ApprovalWorkflowDB:
--   1. dbo.usp_ImportApprovalMatrixFromXml  - Atomically replaces matrix policies
--      by parsing a submitted XML document. Admin-only; runs in a transaction.
--   2. dbo.usp_ExportApprovalMatrixAsXml    - Returns the current matrix as
--      a well-formed XML document for download or backup.
-- ==============================================================================

USE [ApprovalWorkflowDB];
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================
-- 1. IMPORT: Parse XML and atomically replace matrix policies
-- ============================================================
CREATE OR ALTER PROCEDURE dbo.usp_ImportApprovalMatrixFromXml
(
    @ActingUserId    INT,
    @XmlData         XML,
    @ResponseMessage NVARCHAR(500) OUTPUT
)
AS
BEGIN
    SET NOCOUNT ON;
    SET QUOTED_IDENTIFIER ON;
    SET ANSI_NULLS ON;

    -- Security: Only admins (UserRole = 1) may import
    DECLARE @UserRole INT;
    SELECT @UserRole = UserRole
    FROM   M_Users
    WHERE  UserId = @ActingUserId AND Bactive = 1;

    IF @UserRole IS NULL OR @UserRole <> 1
    BEGIN
        SET @ResponseMessage = N'Unauthorized: Only administrators can import approval matrix policies.';
        THROW 50060, @ResponseMessage, 1;
    END

    -- Parse XML into a staging table
    DECLARE @Staging TABLE
    (
        iLevel               INT            NOT NULL,
        sLevelName           NVARCHAR(50)   NOT NULL,
        mMinAmount           DECIMAL(18,2)  NOT NULL,
        mMaxAmount           DECIMAL(18,2)  NULL,
        iRequiredApprovers   INT            NOT NULL,
        sApproverDescription NVARCHAR(100) NOT NULL,
        sPolicyDescription   NVARCHAR(200)  NOT NULL
    );

    BEGIN TRY
        -- Shred XML nodes into staging table using wildcard namespace (*:TagName)
        INSERT INTO @Staging
               (iLevel, sLevelName, mMinAmount, mMaxAmount,
                iRequiredApprovers, sApproverDescription, sPolicyDescription)
        SELECT
            TRY_CAST(p.value('@level',        'NVARCHAR(10)')  AS INT),
            ISNULL(p.value('@name',          'NVARCHAR(50)'), N'Level ' + p.value('@level', 'NVARCHAR(10)')),
            TRY_CAST(p.value('(*:MinAmount)[1]','NVARCHAR(30)')  AS DECIMAL(18,2)),
            NULLIF(TRY_CAST(NULLIF(RTRIM(LTRIM(p.value('(*:MaxAmount)[1]','NVARCHAR(30)'))),'') AS DECIMAL(18,2)), NULL),
            TRY_CAST(p.value('(*:RequiredApprovers)[1]','NVARCHAR(10)') AS INT),
            ISNULL(p.value('(*:ApproverDescription)[1]', 'NVARCHAR(100)'), N''),
            ISNULL(p.value('(*:PolicyDescription)[1]',   'NVARCHAR(200)'), N'')
        FROM @XmlData.nodes('/*:ApprovalMatrix/*:Policy') AS T(p);

        -- Validate: at least one row parsed
        IF NOT EXISTS (SELECT 1 FROM @Staging)
        BEGIN
            SET @ResponseMessage = N'Import failed: No valid <Policy> elements found in the XML document.';
            THROW 50061, @ResponseMessage, 1;
        END

        -- Validate: no null/unparseable levels or amounts
        IF EXISTS (SELECT 1 FROM @Staging WHERE iLevel IS NULL OR mMinAmount IS NULL OR iRequiredApprovers IS NULL)
        BEGIN
            SET @ResponseMessage = N'Import failed: One or more policies have invalid or missing Level, MinAmount, or RequiredApprovers values.';
            THROW 50062, @ResponseMessage, 1;
        END

        -- Validate: all Level values must already exist in t_ApprovalMatrixPolicy
        -- (we only allow updating thresholds of existing levels, not adding/removing levels)
        IF EXISTS (
            SELECT 1 FROM @Staging s
            WHERE NOT EXISTS (SELECT 1 FROM t_ApprovalMatrixPolicy p WHERE p.iLevel = s.iLevel)
        )
        BEGIN
            SET @ResponseMessage = N'Import failed: XML contains Level values that do not exist in the current matrix. Only existing levels can be updated.';
            THROW 50063, @ResponseMessage, 1;
        END

        -- Validate: MinAmount must be >= 0
        IF EXISTS (SELECT 1 FROM @Staging WHERE mMinAmount < 0)
        BEGIN
            SET @ResponseMessage = N'Import failed: MinAmount cannot be negative.';
            THROW 50064, @ResponseMessage, 1;
        END

        -- Validate: MaxAmount must be greater than MinAmount when present
        IF EXISTS (SELECT 1 FROM @Staging WHERE mMaxAmount IS NOT NULL AND mMaxAmount <= mMinAmount)
        BEGIN
            SET @ResponseMessage = N'Import failed: MaxAmount must be greater than MinAmount for all policies.';
            THROW 50065, @ResponseMessage, 1;
        END

        -- Validate: Only the highest level should have NULL MaxAmount
        DECLARE @MaxLevel INT = (SELECT MAX(iLevel) FROM @Staging);
        IF EXISTS (SELECT 1 FROM @Staging WHERE mMaxAmount IS NULL AND iLevel <> @MaxLevel)
        BEGIN
            SET @ResponseMessage = N'Import failed: Only the highest level may have an unlimited MaxAmount (NULL). All other levels require a MaxAmount.';
            THROW 50066, @ResponseMessage, 1;
        END

        -- Atomically apply changes in a transaction
        BEGIN TRANSACTION;

            UPDATE p
            SET
                p.mMinAmount           = s.mMinAmount,
                p.mMaxAmount           = s.mMaxAmount,
                p.iRequiredApprovers   = s.iRequiredApprovers,
                p.sApproverDescription = CASE WHEN LEN(s.sApproverDescription) > 0 THEN s.sApproverDescription ELSE p.sApproverDescription END,
                p.sPolicyDescription   = CASE WHEN LEN(s.sPolicyDescription) > 0 THEN s.sPolicyDescription ELSE p.sPolicyDescription END,
                p.sLevelName           = CASE WHEN LEN(s.sLevelName) > 0 THEN s.sLevelName ELSE p.sLevelName END
            FROM   t_ApprovalMatrixPolicy p
            INNER JOIN @Staging s ON p.iLevel = s.iLevel;

        COMMIT TRANSACTION;

        DECLARE @RowCount INT = (SELECT COUNT(*) FROM @Staging);
        SET @ResponseMessage = N'Import successful: ' + CAST(@RowCount AS NVARCHAR(10)) + N' policy level(s) updated from XML.';

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;

        DECLARE @ErrMsg NVARCHAR(4000) = ERROR_MESSAGE();
        DECLARE @ErrNum INT            = ERROR_NUMBER();

        IF @ErrNum IN (50060, 50061, 50062, 50063, 50064, 50065, 50066)
        BEGIN
            -- Already set @ResponseMessage before THROW; re-throw with same message
            THROW;
        END

        SET @ResponseMessage = N'Import failed due to a database error: ' + @ErrMsg;
        THROW 50069, @ResponseMessage, 1;
    END CATCH
END;
GO

-- ============================================================
-- 2. EXPORT: Return the current matrix policies as XML
-- ============================================================
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE dbo.usp_ExportApprovalMatrixAsXml
AS
BEGIN
    SET NOCOUNT ON;
    SET QUOTED_IDENTIFIER ON;
    SET ANSI_NULLS ON;

    SELECT
        iLevel              AS [@level],
        sLevelName          AS [@name],
        mMinAmount          AS [MinAmount],
        ISNULL(CAST(mMaxAmount AS NVARCHAR(30)), '') AS [MaxAmount],
        iRequiredApprovers  AS [RequiredApprovers],
        sApproverDescription AS [ApproverDescription],
        sPolicyDescription  AS [PolicyDescription]
    FROM t_ApprovalMatrixPolicy
    ORDER BY iLevel ASC
    FOR XML PATH('Policy'), ROOT('ApprovalMatrix'), TYPE;
END;
GO
