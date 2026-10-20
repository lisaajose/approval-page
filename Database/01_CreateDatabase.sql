-- ==============================================================================
-- Script: 01_CreateDatabase.sql
-- Description: Creates the ApprovalWorkflowDB database if it does not exist.
-- Target Engine: Microsoft SQL Server Express 2025 / 2022 / 2019
-- ==============================================================================

USE [master];
GO

IF NOT EXISTS (SELECT name FROM sys.databases WHERE name = N'ApprovalWorkflowDB')
BEGIN
    PRINT 'Creating database [ApprovalWorkflowDB]...';
    CREATE DATABASE [ApprovalWorkflowDB]
    COLLATE SQL_Latin1_General_CP1_CI_AS;
    PRINT 'Database [ApprovalWorkflowDB] created successfully.';
END
ELSE
BEGIN
    PRINT 'Database [ApprovalWorkflowDB] already exists. Skipping creation.';
END
GO

-- Configure Read Committed Snapshot Isolation (RCSI) for enhanced concurrency
-- while avoiding dirty reads or table lock escalations.
IF EXISTS (SELECT name FROM sys.databases WHERE name = N'ApprovalWorkflowDB' AND is_read_committed_snapshot_on = 0)
BEGIN
    PRINT 'Enabling READ_COMMITTED_SNAPSHOT on [ApprovalWorkflowDB]...';
    ALTER DATABASE [ApprovalWorkflowDB] SET READ_COMMITTED_SNAPSHOT ON WITH ROLLBACK IMMEDIATE;
    PRINT 'READ_COMMITTED_SNAPSHOT enabled successfully.';
END
GO
