using System.Data;
using ApprovalWorkflow.Data;
using ApprovalWorkflow.Models;
using Microsoft.Data.SqlClient;

namespace ApprovalWorkflow.Services
{
    public class ApprovalService : IApprovalService
    {
        private readonly ISqlConnectionFactory _connectionFactory;
        private readonly ILogger<ApprovalService> _logger;

        public ApprovalService(ISqlConnectionFactory connectionFactory, ILogger<ApprovalService> logger)
        {
            _connectionFactory = connectionFactory;
            _logger = logger;
        }

        public async Task<List<PendingApprovalItem>> GetPendingApprovalsAsync(int userId)
        {
            var items = new List<PendingApprovalItem>();

            using var connection = _connectionFactory.CreateConnection();
            await connection.OpenAsync();

            using var command = new SqlCommand("dbo.usp_GetPendingApprovals", connection)
            {
                CommandType = CommandType.StoredProcedure
            };
            command.Parameters.Add("@UserId", SqlDbType.Int).Value = userId;

            using var reader = await command.ExecuteReaderAsync();
            while (await reader.ReadAsync())
            {
                items.Add(new PendingApprovalItem
                {
                    HeaderId = reader.GetInt32(reader.GetOrdinal("iHeaderId")),
                    VoucherNo = reader.GetString(reader.GetOrdinal("Svoucherno")),
                    Date = reader.GetDateTime(reader.GetOrdinal("dDate")),
                    Narration = reader.IsDBNull(reader.GetOrdinal("sNarration")) ? null : reader.GetString(reader.GetOrdinal("sNarration")),
                    Amount = reader.GetDecimal(reader.GetOrdinal("Amount")),
                    AuthStatus = reader.GetInt32(reader.GetOrdinal("iAuthStatus")),
                    CreatedDate = reader.GetDateTime(reader.GetOrdinal("CreatedDate")),
                    CreatedByUsername = reader.IsDBNull(reader.GetOrdinal("CreatedByUsername")) ? null : reader.GetString(reader.GetOrdinal("CreatedByUsername")),
                    WorkflowLevel = reader.GetInt32(reader.GetOrdinal("WorkflowLevel")),
                    AuthId = reader.GetInt32(reader.GetOrdinal("iAuthId")),
                    Level = reader.GetInt32(reader.GetOrdinal("iLevel")),
                    StepOrder = reader.GetInt32(reader.GetOrdinal("iStepOrder")),
                    Alerts = reader.IsDBNull(reader.GetOrdinal("sAlerts")) ? null : reader.GetString(reader.GetOrdinal("sAlerts")),
                    AssignmentStatus = reader.GetInt32(reader.GetOrdinal("AssignmentStatus"))
                });
            }

            return items;
        }

        public async Task<OperationResult> ApproveVoucherAsync(int headerId, int actingUserId, string? comments)
        {
            try
            {
                using var connection = _connectionFactory.CreateConnection();
                await connection.OpenAsync();

                using var command = new SqlCommand("dbo.usp_ApproveVoucher", connection)
                {
                    CommandType = CommandType.StoredProcedure
                };

                command.Parameters.Add("@iHeaderId", SqlDbType.Int).Value = headerId;
                command.Parameters.Add("@ActingUserId", SqlDbType.Int).Value = actingUserId;
                command.Parameters.Add("@Comments", SqlDbType.NVarChar, 100).Value =
                    string.IsNullOrWhiteSpace(comments) ? (object)DBNull.Value : comments.Trim();

                var pResponseMessage = command.Parameters.Add("@ResponseMessage", SqlDbType.NVarChar, 250);
                pResponseMessage.Direction = ParameterDirection.Output;

                await command.ExecuteNonQueryAsync();

                string responseMessage = pResponseMessage.Value?.ToString() ?? "Voucher approved successfully.";
                _logger.LogInformation("Voucher {HeaderId} approved by User {UserId}", headerId, actingUserId);

                return OperationResult.Ok(responseMessage);
            }
            catch (SqlException ex)
            {
                _logger.LogWarning(ex, "SQL Exception while approving voucher {HeaderId} by User {UserId}", headerId, actingUserId);
                return OperationResult.Fail(ex.Message, ex.Number);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Unexpected error approving voucher {HeaderId}", headerId);
                return OperationResult.Fail("An unexpected error occurred during approval: " + ex.Message);
            }
        }

        public async Task<OperationResult> RejectVoucherAsync(int headerId, int actingUserId, string comments)
        {
            try
            {
                if (string.IsNullOrWhiteSpace(comments))
                {
                    return OperationResult.Fail("Comments are mandatory when rejecting a voucher.");
                }

                using var connection = _connectionFactory.CreateConnection();
                await connection.OpenAsync();

                using var command = new SqlCommand("dbo.usp_RejectVoucher", connection)
                {
                    CommandType = CommandType.StoredProcedure
                };

                command.Parameters.Add("@iHeaderId", SqlDbType.Int).Value = headerId;
                command.Parameters.Add("@ActingUserId", SqlDbType.Int).Value = actingUserId;
                command.Parameters.Add("@Comments", SqlDbType.NVarChar, 100).Value = comments.Trim();

                var pResponseMessage = command.Parameters.Add("@ResponseMessage", SqlDbType.NVarChar, 250);
                pResponseMessage.Direction = ParameterDirection.Output;

                await command.ExecuteNonQueryAsync();

                string responseMessage = pResponseMessage.Value?.ToString() ?? "Voucher rejected successfully.";
                _logger.LogInformation("Voucher {HeaderId} rejected by User {UserId}", headerId, actingUserId);

                return OperationResult.Ok(responseMessage);
            }
            catch (SqlException ex)
            {
                _logger.LogWarning(ex, "SQL Exception while rejecting voucher {HeaderId} by User {UserId}", headerId, actingUserId);
                return OperationResult.Fail(ex.Message, ex.Number);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Unexpected error rejecting voucher {HeaderId}", headerId);
                return OperationResult.Fail("An unexpected error occurred during rejection: " + ex.Message);
            }
        }

        public async Task<List<NotificationItem>> GetNotificationsAsync(int userId)
        {
            var items = new List<NotificationItem>();

            using var connection = _connectionFactory.CreateConnection();
            await connection.OpenAsync();

            using var command = new SqlCommand("dbo.usp_GetNotifications", connection)
            {
                CommandType = CommandType.StoredProcedure
            };
            command.Parameters.Add("@UserId", SqlDbType.Int).Value = userId;

            using var reader = await command.ExecuteReaderAsync();
            while (await reader.ReadAsync())
            {
                items.Add(new NotificationItem
                {
                    AuthId = reader.GetInt32(reader.GetOrdinal("iAuthId")),
                    HeaderId = reader.GetInt32(reader.GetOrdinal("iHeaderId")),
                    VoucherNo = reader.GetString(reader.GetOrdinal("Svoucherno")),
                    Date = reader.GetDateTime(reader.GetOrdinal("dDate")),
                    Amount = reader.GetDecimal(reader.GetOrdinal("Amount")),
                    AuthStatus = reader.GetInt32(reader.GetOrdinal("iAuthStatus")),
                    HeaderStatusDescription = reader.GetString(reader.GetOrdinal("HeaderStatusDescription")),
                    Level = reader.GetInt32(reader.GetOrdinal("iLevel")),
                    Alerts = reader.IsDBNull(reader.GetOrdinal("sAlerts")) ? null : reader.GetString(reader.GetOrdinal("sAlerts")),
                    UserComments = reader.IsDBNull(reader.GetOrdinal("sUsercomments")) ? null : reader.GetString(reader.GetOrdinal("sUsercomments")),
                    Status = reader.GetInt32(reader.GetOrdinal("iStatus")),
                    CreatedDate = reader.GetDateTime(reader.GetOrdinal("CreatedDate")),
                    CreatedByUsername = reader.IsDBNull(reader.GetOrdinal("CreatedByUsername")) ? null : reader.GetString(reader.GetOrdinal("CreatedByUsername"))
                });
            }

            return items;
        }

        public async Task<List<User>> GetAllUsersAsync()
        {
            var list = new List<User>();

            using var connection = _connectionFactory.CreateConnection();
            await connection.OpenAsync();

            using var command = new SqlCommand("dbo.usp_GetAllUsers", connection)
            {
                CommandType = CommandType.StoredProcedure
            };

            using var reader = await command.ExecuteReaderAsync();
            while (await reader.ReadAsync())
            {
                list.Add(new User
                {
                    UserId = reader.GetInt32(reader.GetOrdinal("UserId")),
                    Username = reader.GetString(reader.GetOrdinal("Username")),
                    Email = reader.GetString(reader.GetOrdinal("Email")),
                    UserRole = reader.IsDBNull(reader.GetOrdinal("UserRole")) ? null : reader.GetInt32(reader.GetOrdinal("UserRole")),
                    Bactive = reader.IsDBNull(reader.GetOrdinal("Bactive")) ? null : reader.GetBoolean(reader.GetOrdinal("Bactive")),
                    CreatedDate = reader.GetDateTime(reader.GetOrdinal("CreatedDate")),
                    LastLoginDate = reader.IsDBNull(reader.GetOrdinal("LastLoginDate")) ? null : reader.GetDateTime(reader.GetOrdinal("LastLoginDate"))
                });
            }

            return list;
        }

        public async Task<User?> GetUserByIdAsync(int userId)
        {
            var users = await GetAllUsersAsync();
            return users.FirstOrDefault(u => u.UserId == userId);
        }
    }
}
