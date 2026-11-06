using System.Data;
using ApprovalWorkflow.Data;
using ApprovalWorkflow.Models;
using Microsoft.Data.SqlClient;

namespace ApprovalWorkflow.Services
{
    public class VoucherService : IVoucherService
    {
        private readonly ISqlConnectionFactory _connectionFactory;
        private readonly ILogger<VoucherService> _logger;

        public VoucherService(ISqlConnectionFactory connectionFactory, ILogger<VoucherService> logger)
        {
            _connectionFactory = connectionFactory;
            _logger = logger;
        }

        public async Task<SaveVoucherResult> SaveVoucherAsync(CreateVoucherViewModel model, int createdByUserId)
        {
            try
            {
                using var connection = _connectionFactory.CreateConnection();
                await connection.OpenAsync();

                // Consolidated Domain Procedure: dbo.usp_Voucher_Lifecycle
                using var command = new SqlCommand("dbo.usp_Voucher_Lifecycle", connection)
                {
                    CommandType = CommandType.StoredProcedure
                };

                command.Parameters.Add("@Action", SqlDbType.NVarChar, 10).Value = "SAVE";
                command.Parameters.Add("@VoucherNo", SqlDbType.NVarChar, 50).Value = model.VoucherNo.Trim();
                command.Parameters.Add("@VoucherDate", SqlDbType.Date).Value = model.Date;
                command.Parameters.Add("@Narration", SqlDbType.NVarChar, 100).Value =
                    string.IsNullOrWhiteSpace(model.Narration) ? DBNull.Value : model.Narration.Trim();

                var amountParam = command.Parameters.Add("@Amount", SqlDbType.Decimal);
                amountParam.Precision = 18;
                amountParam.Scale = 2;
                amountParam.Value = model.Amount;

                command.Parameters.Add("@UserId", SqlDbType.Int).Value = createdByUserId;

                // OUTPUT parameters
                var pNewHeaderId = command.Parameters.Add("@NewHeaderId", SqlDbType.Int);
                pNewHeaderId.Direction = ParameterDirection.Output;

                var pWorkflowLevel = command.Parameters.Add("@WorkflowLevel", SqlDbType.Int);
                pWorkflowLevel.Direction = ParameterDirection.Output;

                var pAuthStatus = command.Parameters.Add("@AuthStatus", SqlDbType.Int);
                pAuthStatus.Direction = ParameterDirection.Output;

                var pResponseMessage = command.Parameters.Add("@ResponseMessage", SqlDbType.NVarChar, 250);
                pResponseMessage.Direction = ParameterDirection.Output;

                await command.ExecuteNonQueryAsync();

                int newHeaderId = (int)pNewHeaderId.Value;
                int workflowLevel = (int)pWorkflowLevel.Value;
                int authStatus = (int)pAuthStatus.Value;
                string responseMessage = pResponseMessage.Value?.ToString() ?? "Voucher saved successfully.";

                _logger.LogInformation("Voucher {VoucherNo} saved successfully via usp_ApprovalWorkflow. HeaderId: {HeaderId}, Level: {Level}",
                    model.VoucherNo, newHeaderId, workflowLevel);

                return new SaveVoucherResult
                {
                    Success = true,
                    HeaderId = newHeaderId,
                    WorkflowLevel = workflowLevel,
                    AuthStatus = authStatus,
                    Message = responseMessage
                };
            }
            catch (SqlException ex)
            {
                _logger.LogError(ex, "SQL Error while saving voucher {VoucherNo}", model.VoucherNo);
                return new SaveVoucherResult
                {
                    Success = false,
                    ErrorCode = ex.Number,
                    Message = ex.Message
                };
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Unexpected error saving voucher {VoucherNo}", model.VoucherNo);
                return new SaveVoucherResult
                {
                    Success = false,
                    Message = "An unexpected error occurred while saving the voucher: " + ex.Message
                };
            }
        }

        public async Task<OperationResult> ResubmitVoucherAsync(EditVoucherViewModel model, int actingUserId)
        {
            try
            {
                using var connection = _connectionFactory.CreateConnection();
                await connection.OpenAsync();

                using var command = new SqlCommand("dbo.usp_Voucher_Lifecycle", connection)
                {
                    CommandType = CommandType.StoredProcedure
                };
                command.Parameters.Add("@Action", SqlDbType.NVarChar, 20).Value = "RESUBMIT";
                command.Parameters.Add("@iHeaderId", SqlDbType.Int).Value = model.HeaderId;
                command.Parameters.Add("@ActingUserId", SqlDbType.Int).Value = actingUserId;
                command.Parameters.Add("@dDate", SqlDbType.Date).Value = model.Date;
                command.Parameters.Add("@sNarration", SqlDbType.NVarChar, 100).Value = (object?)model.Narration ?? DBNull.Value;
                command.Parameters.Add("@Amount", SqlDbType.Decimal).Value = model.Amount;

                var pWorkflowLevel = command.Parameters.Add("@NewWorkflowLevel", SqlDbType.Int);
                pWorkflowLevel.Direction = ParameterDirection.Output;

                var pMessage = command.Parameters.Add("@ResponseMessage", SqlDbType.NVarChar, 250);
                pMessage.Direction = ParameterDirection.Output;

                await command.ExecuteNonQueryAsync();

                string msg = pMessage.Value?.ToString() ?? "Voucher resubmitted successfully.";
                return OperationResult.Ok(msg);
            }
            catch (SqlException ex)
            {
                _logger.LogError(ex, "SQL Error resubmitting voucher {HeaderId}", model.HeaderId);
                return OperationResult.Fail(ex.Message, ex.Number);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Unexpected error resubmitting voucher {HeaderId}", model.HeaderId);
                return OperationResult.Fail("An error occurred while resubmitting the voucher: " + ex.Message);
            }
        }

        public async Task<VoucherDetailsViewModel> GetVoucherDetailsAsync(int headerId, int currentUserId)
        {
            var viewModel = new VoucherDetailsViewModel
            {
                CurrentUserId = currentUserId
            };

            using var connection = _connectionFactory.CreateConnection();
            await connection.OpenAsync();

            using var command = new SqlCommand("dbo.usp_Voucher_Lifecycle", connection)
            {
                CommandType = CommandType.StoredProcedure
            };
            command.Parameters.Add("@Action", SqlDbType.NVarChar, 20).Value = "GET_DETAILS";
            command.Parameters.Add("@iHeaderId", SqlDbType.Int).Value = headerId;

            using var reader = await command.ExecuteReaderAsync();

            // Result Set 1: Header information
            if (await reader.ReadAsync())
            {
                viewModel.Header = new Voucher
                {
                    HeaderId = reader.GetIntSafe("iHeaderId"),
                    VoucherNo = reader.GetString(reader.GetOrdinal("Svoucherno")),
                    Date = reader.GetDateTime(reader.GetOrdinal("dDate")),
                    Narration = reader.IsDBNull(reader.GetOrdinal("sNarration")) ? null : reader.GetString(reader.GetOrdinal("sNarration")),
                    Amount = reader.GetDecimal(reader.GetOrdinal("Amount")),
                    AuthStatus = reader.GetIntSafe("iAuthStatus"),
                    PostDate = reader.IsDBNull(reader.GetOrdinal("dPostDate")) ? null : reader.GetDateTime(reader.GetOrdinal("dPostDate")),
                    CreatedDate = reader.GetDateTime(reader.GetOrdinal("CreatedDate")),
                    CreatedBy = reader.GetNullableIntSafe("CreatedBy"),
                    CreatedByUsername = reader.IsDBNull(reader.GetOrdinal("CreatedByUsername")) ? null : reader.GetString(reader.GetOrdinal("CreatedByUsername")),
                    WorkflowLevel = reader.GetIntSafe("WorkflowLevel"),
                    CurrentPendingStepOrder = reader.GetNullableIntSafe("CurrentPendingStepOrder"),
                    CurrentPendingUserId = reader.GetNullableIntSafe("CurrentPendingUserId"),
                    CurrentPendingUsername = reader.IsDBNull(reader.GetOrdinal("CurrentPendingUsername")) ? null : reader.GetString(reader.GetOrdinal("CurrentPendingUsername"))
                };

                try
                {
                    int cycleOrdinal = reader.GetOrdinal("CurrentCycle");
                    if (!reader.IsDBNull(cycleOrdinal))
                    {
                        viewModel.CurrentCycle = reader.GetIntSafe(cycleOrdinal);
                    }
                }
                catch { }
            }

            // Result Set 2: The active cycle vertical approval slots
            if (await reader.NextResultAsync())
            {
                while (await reader.ReadAsync())
                {
                    int usernameOrd = -1;
                    try { usernameOrd = reader.GetOrdinal("Username"); } catch { }
                    if (usernameOrd < 0) { try { usernameOrd = reader.GetOrdinal("AssignedUsername"); } catch { } }

                    bool isStageActive = false;
                    try
                    {
                        int stageOrd = reader.GetOrdinal("IsCurrentActiveStage");
                        if (!reader.IsDBNull(stageOrd))
                        {
                            object val = reader.GetValue(stageOrd);
                            isStageActive = val switch
                            {
                                bool b => b,
                                int i => i == 1,
                                byte bt => bt == 1,
                                short s => s == 1,
                                long l => l == 1,
                                _ => Convert.ToInt32(val) == 1
                            };
                        }
                    }
                    catch { }

                    var slot = new ApprovalSlot
                    {
                        AuthId = reader.GetIntSafe("iAuthId"),
                        HeaderId = reader.GetIntSafe("iHeaderId"),
                        AlertType = reader.GetIntSafe("iAlerttype"),
                        Level = reader.GetIntSafe("iLevel"),
                        AssignedUserId = reader.GetIntSafe("iUser"),
                        AssignedUsername = usernameOrd >= 0 && !reader.IsDBNull(usernameOrd) ? reader.GetString(usernameOrd) : string.Empty,
                        Alerts = reader.IsDBNull(reader.GetOrdinal("sAlerts")) ? null : reader.GetString(reader.GetOrdinal("sAlerts")),
                        UserComments = reader.IsDBNull(reader.GetOrdinal("sUsercomments")) ? null : reader.GetString(reader.GetOrdinal("sUsercomments")),
                        StepOrder = reader.GetIntSafe("iStepOrder"),
                        Status = reader.GetIntSafe("iStatus"),
                        StepStatusDescription = reader.GetString(reader.GetOrdinal("StepStatusDescription")),
                        ActionDate = reader.IsDBNull(reader.GetOrdinal("dActionDate")) ? null : reader.GetDateTime(reader.GetOrdinal("dActionDate")),
                        ActionedBy = reader.GetNullableIntSafe("iActionedBy"),
                        ActionedByUsername = reader.IsDBNull(reader.GetOrdinal("ActionedByUsername")) ? null : reader.GetString(reader.GetOrdinal("ActionedByUsername")),
                        IsCurrentActiveStage = isStageActive
                    };

                    try
                    {
                        int cOrd = reader.GetOrdinal("iCycle");
                        if (!reader.IsDBNull(cOrd)) slot.Cycle = reader.GetIntSafe(cOrd);
                    }
                    catch { }

                    viewModel.ApprovalSlots.Add(slot);
                }
            }

            // Result Set 3: Notifications
            if (await reader.NextResultAsync())
            {
                while (await reader.ReadAsync())
                {
                    var notif = new NotificationItem
                    {
                        AuthId = reader.GetIntSafe("iAuthId"),
                        HeaderId = reader.GetIntSafe("iHeaderId"),
                        Level = reader.GetIntSafe("iLevel"),
                        Alerts = reader.IsDBNull(reader.GetOrdinal("sAlerts")) ? null : reader.GetString(reader.GetOrdinal("sAlerts")),
                        UserComments = reader.IsDBNull(reader.GetOrdinal("sUsercomments")) ? null : reader.GetString(reader.GetOrdinal("sUsercomments")),
                        Status = reader.GetIntSafe("iStatus"),
                        ReadStatus = 0,
                        ActionDate = reader.IsDBNull(reader.GetOrdinal("dActionDate")) ? null : reader.GetDateTime(reader.GetOrdinal("dActionDate")),
                        RecipientUserId = reader.GetIntSafe("iUser"),
                        RecipientUsername = reader.GetString(reader.GetOrdinal("Username"))
                    };

                    try
                    {
                        int rOrd = reader.GetOrdinal("iReadStatus");
                        if (!reader.IsDBNull(rOrd)) notif.ReadStatus = reader.GetIntSafe(rOrd);
                    }
                    catch
                    {
                        if (notif.Status == 3) notif.ReadStatus = 1;
                    }

                    try
                    {
                        int cOrd = reader.GetOrdinal("iCycle");
                        if (!reader.IsDBNull(cOrd)) notif.Cycle = reader.GetIntSafe(cOrd);
                    }
                    catch { }

                    viewModel.Notifications.Add(notif);
                }
            }

            // Result Set 4: Full Audit History
            if (await reader.NextResultAsync())
            {
                while (await reader.ReadAsync())
                {
                    var hist = new ApprovalHistoryItem
                    {
                        HistoryId = reader.GetIntSafe("iHistoryId"),
                        HeaderId = reader.GetIntSafe("iHeaderId"),
                        Level = reader.GetIntSafe("iLevel"),
                        StepOrder = reader.GetIntSafe("iStepOrder"),
                        ActionUser = reader.GetIntSafe("iActionUser"),
                        ActionUsername = reader.GetString(reader.GetOrdinal("ActionUsername")),
                        Action = reader.GetString(reader.GetOrdinal("sAction")),
                        Comments = reader.IsDBNull(reader.GetOrdinal("sComments")) ? null : reader.GetString(reader.GetOrdinal("sComments")),
                        ActionDate = reader.GetDateTime(reader.GetOrdinal("dActionDate"))
                    };

                    try
                    {
                        int cOrd = reader.GetOrdinal("iCycle");
                        if (!reader.IsDBNull(cOrd)) hist.Cycle = reader.GetIntSafe(cOrd);
                    }
                    catch { }

                    viewModel.History.Add(hist);
                }
            }

            // Result Set 5: ALL Approval Slots Across ALL Cycles (For Auth Info Modal)
            if (await reader.NextResultAsync())
            {
                while (await reader.ReadAsync())
                {
                    var allSlot = new ApprovalSlot
                    {
                        AuthId = reader.GetIntSafe("iAuthId"),
                        HeaderId = reader.GetIntSafe("iHeaderId"),
                        AlertType = reader.GetIntSafe("iAlerttype"),
                        Level = reader.GetIntSafe("iLevel"),
                        AssignedUserId = reader.GetIntSafe("iUser"),
                        AssignedUsername = reader.GetString(reader.GetOrdinal("Username")),
                        Alerts = reader.IsDBNull(reader.GetOrdinal("sAlerts")) ? null : reader.GetString(reader.GetOrdinal("sAlerts")),
                        UserComments = reader.IsDBNull(reader.GetOrdinal("sUsercomments")) ? null : reader.GetString(reader.GetOrdinal("sUsercomments")),
                        StepOrder = reader.GetIntSafe("iStepOrder"),
                        Status = reader.GetIntSafe("iStatus"),
                        StepStatusDescription = reader.GetString(reader.GetOrdinal("StepStatusDescription")),
                        ActionDate = reader.IsDBNull(reader.GetOrdinal("dActionDate")) ? null : reader.GetDateTime(reader.GetOrdinal("dActionDate")),
                        ActionedBy = reader.GetNullableIntSafe("iActionedBy"),
                        ActionedByUsername = reader.IsDBNull(reader.GetOrdinal("ActionedByUsername")) ? null : reader.GetString(reader.GetOrdinal("ActionedByUsername"))
                    };

                    try
                    {
                        int cOrd = reader.GetOrdinal("iCycle");
                        if (!reader.IsDBNull(cOrd)) allSlot.Cycle = reader.GetIntSafe(cOrd);
                    }
                    catch { }

                    viewModel.AllCycleSlots.Add(allSlot);
                }
            }

            return viewModel;
        }

        public async Task<List<Voucher>> GetRecentVouchersAsync(int count = 50)
        {
            var list = new List<Voucher>();

            using var connection = _connectionFactory.CreateConnection();
            await connection.OpenAsync();

            string query = @"
                SELECT TOP (@Count)
                    h.iHeaderId,
                    h.Svoucherno,
                    h.dDate,
                    h.sNarration,
                    h.Amount,
                    h.iAuthStatus,
                    h.dPostDate,
                    h.CreatedDate,
                    h.CreatedBy,
                    u.Username AS CreatedByUsername,
                    dbo.fn_GetVoucherApprovalLevel(h.Amount) AS WorkflowLevel,
                    CASE h.iAuthStatus
                        WHEN 0 THEN N'Pending'
                        WHEN 1 THEN N'Approved'
                        WHEN 2 THEN N'Rejected'
                        ELSE N'Unknown'
                    END AS AuthStatusDescription
                FROM t_Header h
                LEFT JOIN M_Users u ON h.CreatedBy = u.UserId
                ORDER BY h.iHeaderId DESC;";

            using var command = new SqlCommand(query, connection);
            command.Parameters.Add("@Count", SqlDbType.Int).Value = count;

            using var reader = await command.ExecuteReaderAsync();
            while (await reader.ReadAsync())
            {
                list.Add(new Voucher
                {
                    HeaderId = reader.GetIntSafe("iHeaderId"),
                    VoucherNo = reader.GetString(reader.GetOrdinal("Svoucherno")),
                    Date = reader.GetDateTime(reader.GetOrdinal("dDate")),
                    Narration = reader.IsDBNull(reader.GetOrdinal("sNarration")) ? null : reader.GetString(reader.GetOrdinal("sNarration")),
                    Amount = reader.GetDecimal(reader.GetOrdinal("Amount")),
                    AuthStatus = reader.GetIntSafe("iAuthStatus"),
                    StatusDescription = reader.GetString(reader.GetOrdinal("AuthStatusDescription")),
                    PostDate = reader.IsDBNull(reader.GetOrdinal("dPostDate")) ? null : reader.GetDateTime(reader.GetOrdinal("dPostDate")),
                    CreatedDate = reader.GetDateTime(reader.GetOrdinal("CreatedDate")),
                    CreatedBy = reader.GetNullableIntSafe("CreatedBy"),
                    CreatedByUsername = reader.IsDBNull(reader.GetOrdinal("CreatedByUsername")) ? null : reader.GetString(reader.GetOrdinal("CreatedByUsername")),
                    WorkflowLevel = reader.GetIntSafe("WorkflowLevel")
                });
            }

            return list;
        }
    }
}
