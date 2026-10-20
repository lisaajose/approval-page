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

                // Master requirement: Unified usp_ApprovalWorkflow procedure for SAVE, APPROVE, REJECT
                using var command = new SqlCommand("dbo.usp_ApprovalWorkflow", connection)
                {
                    CommandType = CommandType.StoredProcedure
                };

                command.Parameters.Add("@Action", SqlDbType.NVarChar, 10).Value = "APPROVE";
                command.Parameters.Add("@HeaderId", SqlDbType.Int).Value = headerId;
                command.Parameters.Add("@UserId", SqlDbType.Int).Value = actingUserId;
                command.Parameters.Add("@UserComment", SqlDbType.NVarChar, 100).Value =
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
                    return OperationResult.Fail("Mandatory comments are required when rejecting a voucher.");
                }

                using var connection = _connectionFactory.CreateConnection();
                await connection.OpenAsync();

                // Master requirement: Unified usp_ApprovalWorkflow procedure for SAVE, APPROVE, REJECT
                using var command = new SqlCommand("dbo.usp_ApprovalWorkflow", connection)
                {
                    CommandType = CommandType.StoredProcedure
                };

                command.Parameters.Add("@Action", SqlDbType.NVarChar, 10).Value = "REJECT";
                command.Parameters.Add("@HeaderId", SqlDbType.Int).Value = headerId;
                command.Parameters.Add("@UserId", SqlDbType.Int).Value = actingUserId;
                command.Parameters.Add("@UserComment", SqlDbType.NVarChar, 100).Value = comments.Trim();

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

        public async Task<(bool Success, User? User, string Message)> ValidateUserLoginAsync(string usernameOrEmail, string password)
        {
            try
            {
                using var connection = _connectionFactory.CreateConnection();
                await connection.OpenAsync();

                using var command = new SqlCommand("dbo.usp_ValidateUserLogin", connection)
                {
                    CommandType = CommandType.StoredProcedure
                };

                command.Parameters.Add("@UsernameOrEmail", SqlDbType.NVarChar, 50).Value = usernameOrEmail.Trim();
                command.Parameters.Add("@Password", SqlDbType.NVarChar, 256).Value = password;

                var pSuccess = command.Parameters.Add("@Success", SqlDbType.Bit);
                pSuccess.Direction = ParameterDirection.Output;

                var pUserId = command.Parameters.Add("@UserId", SqlDbType.Int);
                pUserId.Direction = ParameterDirection.Output;

                var pUsername = command.Parameters.Add("@Username", SqlDbType.NVarChar, 20);
                pUsername.Direction = ParameterDirection.Output;

                var pUserRole = command.Parameters.Add("@UserRole", SqlDbType.Int);
                pUserRole.Direction = ParameterDirection.Output;

                var pMessage = command.Parameters.Add("@Message", SqlDbType.NVarChar, 250);
                pMessage.Direction = ParameterDirection.Output;

                await command.ExecuteNonQueryAsync();

                bool success = pSuccess.Value != DBNull.Value && (bool)pSuccess.Value;
                string message = pMessage.Value?.ToString() ?? "Unknown login response.";

                if (success && pUserId.Value != DBNull.Value)
                {
                    int userId = (int)pUserId.Value;
                    var user = await GetUserByIdAsync(userId);
                    return (true, user, message);
                }

                return (false, null, message);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error validating user login for {Username}", usernameOrEmail);
                return (false, null, "Authentication service error: " + ex.Message);
            }
        }
    }
}
