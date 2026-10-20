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

                // Master requirement: Unified usp_ApprovalWorkflow procedure for SAVE, APPROVE, REJECT
                using var command = new SqlCommand("dbo.usp_ApprovalWorkflow", connection)
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

        public async Task<VoucherDetailsViewModel> GetVoucherDetailsAsync(int headerId, int currentUserId)
        {
            var viewModel = new VoucherDetailsViewModel
            {
                CurrentUserId = currentUserId
            };

            using var connection = _connectionFactory.CreateConnection();
            await connection.OpenAsync();

            using var command = new SqlCommand("dbo.usp_GetVoucherDetails", connection)
            {
                CommandType = CommandType.StoredProcedure
            };
            command.Parameters.Add("@iHeaderId", SqlDbType.Int).Value = headerId;

            using var reader = await command.ExecuteReaderAsync();

            // Result Set 1: Header information
            if (await reader.ReadAsync())
            {
                viewModel.Header = new Voucher
                {
                    HeaderId = reader.GetInt32(reader.GetOrdinal("iHeaderId")),
                    VoucherNo = reader.GetString(reader.GetOrdinal("Svoucherno")),
                    Date = reader.GetDateTime(reader.GetOrdinal("dDate")),
                    Narration = reader.IsDBNull(reader.GetOrdinal("sNarration")) ? null : reader.GetString(reader.GetOrdinal("sNarration")),
                    Amount = reader.GetDecimal(reader.GetOrdinal("Amount")),
                    AuthStatus = reader.GetInt32(reader.GetOrdinal("iAuthStatus")),
                    PostDate = reader.IsDBNull(reader.GetOrdinal("dPostDate")) ? null : reader.GetDateTime(reader.GetOrdinal("dPostDate")),
                    CreatedDate = reader.GetDateTime(reader.GetOrdinal("CreatedDate")),
                    CreatedBy = reader.IsDBNull(reader.GetOrdinal("CreatedBy")) ? null : reader.GetInt32(reader.GetOrdinal("CreatedBy")),
                    CreatedByUsername = reader.IsDBNull(reader.GetOrdinal("CreatedByUsername")) ? null : reader.GetString(reader.GetOrdinal("CreatedByUsername")),
                    WorkflowLevel = reader.GetInt32(reader.GetOrdinal("WorkflowLevel")),
                    CurrentPendingStepOrder = reader.IsDBNull(reader.GetOrdinal("CurrentPendingStepOrder")) ? null : reader.GetInt32(reader.GetOrdinal("CurrentPendingStepOrder")),
                    CurrentPendingUserId = reader.IsDBNull(reader.GetOrdinal("CurrentPendingUserId")) ? null : reader.GetInt32(reader.GetOrdinal("CurrentPendingUserId")),
                    CurrentPendingUsername = reader.IsDBNull(reader.GetOrdinal("CurrentPendingUsername")) ? null : reader.GetString(reader.GetOrdinal("CurrentPendingUsername"))
                };
            }

            // Result Set 2: The 4 vertical approval slots
            if (await reader.NextResultAsync())
            {
                while (await reader.ReadAsync())
                {
                    viewModel.ApprovalSlots.Add(new ApprovalSlot
                    {
                        AuthId = reader.GetInt32(reader.GetOrdinal("iAuthId")),
                        HeaderId = reader.GetInt32(reader.GetOrdinal("iHeaderId")),
                        AlertType = reader.GetInt32(reader.GetOrdinal("iAlerttype")),
                        Level = reader.GetInt32(reader.GetOrdinal("iLevel")),
                        AssignedUserId = reader.GetInt32(reader.GetOrdinal("iUser")),
                        AssignedUsername = reader.GetString(reader.GetOrdinal("Username")),
                        Alerts = reader.IsDBNull(reader.GetOrdinal("sAlerts")) ? null : reader.GetString(reader.GetOrdinal("sAlerts")),
                        UserComments = reader.IsDBNull(reader.GetOrdinal("sUsercomments")) ? null : reader.GetString(reader.GetOrdinal("sUsercomments")),
                        StepOrder = reader.GetInt32(reader.GetOrdinal("iStepOrder")),
                        Status = reader.GetInt32(reader.GetOrdinal("iStatus")),
                        StepStatusDescription = reader.GetString(reader.GetOrdinal("StepStatusDescription")),
                        ActionDate = reader.IsDBNull(reader.GetOrdinal("dActionDate")) ? null : reader.GetDateTime(reader.GetOrdinal("dActionDate")),
                        ActionedBy = reader.IsDBNull(reader.GetOrdinal("iActionedBy")) ? null : reader.GetInt32(reader.GetOrdinal("iActionedBy")),
                        ActionedByUsername = reader.IsDBNull(reader.GetOrdinal("ActionedByUsername")) ? null : reader.GetString(reader.GetOrdinal("ActionedByUsername")),
                        IsCurrentActiveStage = reader.GetInt32(reader.GetOrdinal("IsCurrentActiveStage")) == 1
                    });
                }
            }

            // Result Set 3: Notifications
            if (await reader.NextResultAsync())
            {
                while (await reader.ReadAsync())
                {
                    viewModel.Notifications.Add(new NotificationItem
                    {
                        AuthId = reader.GetInt32(reader.GetOrdinal("iAuthId")),
                        HeaderId = reader.GetInt32(reader.GetOrdinal("iHeaderId")),
                        Level = reader.GetInt32(reader.GetOrdinal("iLevel")),
                        Alerts = reader.IsDBNull(reader.GetOrdinal("sAlerts")) ? null : reader.GetString(reader.GetOrdinal("sAlerts")),
                        UserComments = reader.IsDBNull(reader.GetOrdinal("sUsercomments")) ? null : reader.GetString(reader.GetOrdinal("sUsercomments")),
                        Status = reader.GetInt32(reader.GetOrdinal("iStatus")),
                        ActionDate = reader.IsDBNull(reader.GetOrdinal("dActionDate")) ? null : reader.GetDateTime(reader.GetOrdinal("dActionDate")),
                        RecipientUserId = reader.GetInt32(reader.GetOrdinal("iUser")),
                        RecipientUsername = reader.GetString(reader.GetOrdinal("Username"))
                    });
                }
            }

            // Result Set 4: Full Audit History
            if (await reader.NextResultAsync())
            {
                while (await reader.ReadAsync())
                {
                    viewModel.History.Add(new ApprovalHistoryItem
                    {
                        HistoryId = reader.GetInt32(reader.GetOrdinal("iHistoryId")),
                        HeaderId = reader.GetInt32(reader.GetOrdinal("iHeaderId")),
                        Level = reader.GetInt32(reader.GetOrdinal("iLevel")),
                        StepOrder = reader.GetInt32(reader.GetOrdinal("iStepOrder")),
                        ActionUser = reader.GetInt32(reader.GetOrdinal("iActionUser")),
                        ActionUsername = reader.GetString(reader.GetOrdinal("ActionUsername")),
                        Action = reader.GetString(reader.GetOrdinal("sAction")),
                        Comments = reader.IsDBNull(reader.GetOrdinal("sComments")) ? null : reader.GetString(reader.GetOrdinal("sComments")),
                        ActionDate = reader.GetDateTime(reader.GetOrdinal("dActionDate"))
                    });
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
                    HeaderId = reader.GetInt32(reader.GetOrdinal("iHeaderId")),
                    VoucherNo = reader.GetString(reader.GetOrdinal("Svoucherno")),
                    Date = reader.GetDateTime(reader.GetOrdinal("dDate")),
                    Narration = reader.IsDBNull(reader.GetOrdinal("sNarration")) ? null : reader.GetString(reader.GetOrdinal("sNarration")),
                    Amount = reader.GetDecimal(reader.GetOrdinal("Amount")),
                    AuthStatus = reader.GetInt32(reader.GetOrdinal("iAuthStatus")),
                    StatusDescription = reader.GetString(reader.GetOrdinal("AuthStatusDescription")),
                    PostDate = reader.IsDBNull(reader.GetOrdinal("dPostDate")) ? null : reader.GetDateTime(reader.GetOrdinal("dPostDate")),
                    CreatedDate = reader.GetDateTime(reader.GetOrdinal("CreatedDate")),
                    CreatedBy = reader.IsDBNull(reader.GetOrdinal("CreatedBy")) ? null : reader.GetInt32(reader.GetOrdinal("CreatedBy")),
                    CreatedByUsername = reader.IsDBNull(reader.GetOrdinal("CreatedByUsername")) ? null : reader.GetString(reader.GetOrdinal("CreatedByUsername")),
                    WorkflowLevel = reader.GetInt32(reader.GetOrdinal("WorkflowLevel"))
                });
            }

            return list;
        }
    }
}
