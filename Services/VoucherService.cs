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

                using var command = new SqlCommand("dbo.usp_SaveVoucher", connection)
                {
                    CommandType = CommandType.StoredProcedure
                };

                command.Parameters.Add("@Svoucherno", SqlDbType.NVarChar, 50).Value = model.VoucherNo.Trim();
                command.Parameters.Add("@dDate", SqlDbType.Date).Value = model.Date;
                command.Parameters.Add("@sNarration", SqlDbType.NVarChar, 100).Value =
                    string.IsNullOrWhiteSpace(model.Narration) ? DBNull.Value : model.Narration.Trim();

                var amountParam = command.Parameters.Add("@Amount", SqlDbType.Decimal);
                amountParam.Precision = 18;
                amountParam.Scale = 2;
                amountParam.Value = model.Amount;

                command.Parameters.Add("@CreatedByUserId", SqlDbType.Int).Value = createdByUserId;

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

                _logger.LogInformation("Voucher {VoucherNo} saved successfully. HeaderId: {HeaderId}, Level: {Level}",
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
                    StatusDescription = reader.GetString(reader.GetOrdinal("StatusDescription")),
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

            // Result Set 2: Approval Slots (The 4 stages)
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
                        StepOrder = reader.GetInt32(reader.GetOrdinal("iStepOrder")),
                        AssignedUserId = reader.GetInt32(reader.GetOrdinal("iUser")),
                        AssignedUsername = reader.IsDBNull(reader.GetOrdinal("Username")) ? "N/A" : reader.GetString(reader.GetOrdinal("Username")),
                        Alerts = reader.IsDBNull(reader.GetOrdinal("sAlerts")) ? null : reader.GetString(reader.GetOrdinal("sAlerts")),
                        UserComments = reader.IsDBNull(reader.GetOrdinal("sUsercomments")) ? null : reader.GetString(reader.GetOrdinal("sUsercomments")),
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
                        AlertType = reader.GetInt32(reader.GetOrdinal("iAlerttype")),
                        Level = reader.GetInt32(reader.GetOrdinal("iLevel")),
                        Alerts = reader.IsDBNull(reader.GetOrdinal("sAlerts")) ? null : reader.GetString(reader.GetOrdinal("sAlerts")),
                        UserComments = reader.IsDBNull(reader.GetOrdinal("sUsercomments")) ? null : reader.GetString(reader.GetOrdinal("sUsercomments")),
                        Status = reader.GetInt32(reader.GetOrdinal("iStatus")),
                        CreatedByUsername = reader.IsDBNull(reader.GetOrdinal("Username")) ? null : reader.GetString(reader.GetOrdinal("Username"))
                    });
                }
            }

            // Result Set 4: History
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
                        ActionUsername = reader.IsDBNull(reader.GetOrdinal("ActionUsername")) ? "System" : reader.GetString(reader.GetOrdinal("ActionUsername")),
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

            string sql = $@"
                SELECT TOP ({count})
                    iHeaderId, Svoucherno, dDate, sNarration, Amount, iAuthStatus,
                    StatusDescription, dPostDate, CreatedDate, CreatedBy, CreatedByUsername,
                    WorkflowLevel, CurrentPendingStepOrder, CurrentPendingUserId, CurrentPendingUsername
                FROM dbo.vw_VoucherSummary
                ORDER BY CreatedDate DESC, iHeaderId DESC;";

            using var command = new SqlCommand(sql, connection);
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
                    StatusDescription = reader.GetString(reader.GetOrdinal("StatusDescription")),
                    PostDate = reader.IsDBNull(reader.GetOrdinal("dPostDate")) ? null : reader.GetDateTime(reader.GetOrdinal("dPostDate")),
                    CreatedDate = reader.GetDateTime(reader.GetOrdinal("CreatedDate")),
                    CreatedBy = reader.IsDBNull(reader.GetOrdinal("CreatedBy")) ? null : reader.GetInt32(reader.GetOrdinal("CreatedBy")),
                    CreatedByUsername = reader.IsDBNull(reader.GetOrdinal("CreatedByUsername")) ? null : reader.GetString(reader.GetOrdinal("CreatedByUsername")),
                    WorkflowLevel = reader.GetInt32(reader.GetOrdinal("WorkflowLevel")),
                    CurrentPendingStepOrder = reader.IsDBNull(reader.GetOrdinal("CurrentPendingStepOrder")) ? null : reader.GetInt32(reader.GetOrdinal("CurrentPendingStepOrder")),
                    CurrentPendingUserId = reader.IsDBNull(reader.GetOrdinal("CurrentPendingUserId")) ? null : reader.GetInt32(reader.GetOrdinal("CurrentPendingUserId")),
                    CurrentPendingUsername = reader.IsDBNull(reader.GetOrdinal("CurrentPendingUsername")) ? null : reader.GetString(reader.GetOrdinal("CurrentPendingUsername"))
                });
            }

            return list;
        }
    }
}
