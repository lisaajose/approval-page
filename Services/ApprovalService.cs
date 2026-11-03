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

        public async Task<List<NotificationItem>> GetNotificationsAsync(int userId, string filter = "ALL")
        {
            var items = new List<NotificationItem>();

            using var connection = _connectionFactory.CreateConnection();
            await connection.OpenAsync();

            using var command = new SqlCommand("dbo.usp_GetNotifications", connection)
            {
                CommandType = CommandType.StoredProcedure
            };
            command.Parameters.Add("@UserId", SqlDbType.Int).Value = userId;
            command.Parameters.Add("@Filter", SqlDbType.NVarChar, 20).Value = string.IsNullOrWhiteSpace(filter) ? "ALL" : filter.Trim().ToUpperInvariant();

            using var reader = await command.ExecuteReaderAsync();
            while (await reader.ReadAsync())
            {
                var actionDateOrdinal = reader.GetOrdinal("dActionDate");
                var actionedByUsernameOrdinal = reader.GetOrdinal("ActionedByUsername");

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
                    CreatedByUsername = reader.IsDBNull(reader.GetOrdinal("CreatedByUsername")) ? null : reader.GetString(reader.GetOrdinal("CreatedByUsername")),
                    ActionDate = reader.IsDBNull(actionDateOrdinal) ? null : reader.GetDateTime(actionDateOrdinal),
                    ActionedByUsername = reader.IsDBNull(actionedByUsernameOrdinal) ? null : reader.GetString(actionedByUsernameOrdinal),
                    RecipientUserId = userId
                });
            }

            return items;
        }

        public async Task<(int TotalCount, int UnreadCount, int ReadCount)> GetNotificationCountsAsync(int userId)
        {
            var all = await GetNotificationsAsync(userId, "ALL");
            int total = all.Count;
            int unread = all.Count(n => !n.IsRead);
            int read = all.Count(n => n.IsRead);
            return (total, unread, read);
        }

        public async Task<OperationResult> MarkNotificationsStatusAsync(int userId, IEnumerable<int> authIds, bool isRead)
        {
            try
            {
                var idList = authIds?.Distinct().ToList() ?? new List<int>();
                if (!idList.Any())
                {
                    return OperationResult.Ok("No notifications selected.");
                }

                string idString = string.Join(",", idList);
                int newStatus = isRead ? 3 : 0; // 3 = Read, 0 = Unread

                using var connection = _connectionFactory.CreateConnection();
                await connection.OpenAsync();

                using var command = new SqlCommand("dbo.usp_UpdateNotificationStatus", connection)
                {
                    CommandType = CommandType.StoredProcedure
                };
                command.Parameters.Add("@UserId", SqlDbType.Int).Value = userId;
                command.Parameters.Add("@AuthIds", SqlDbType.NVarChar, -1).Value = idString;
                command.Parameters.Add("@NewStatus", SqlDbType.Int).Value = newStatus;
                var pCount = command.Parameters.Add("@UpdatedCount", SqlDbType.Int);
                pCount.Direction = ParameterDirection.Output;

                await command.ExecuteNonQueryAsync();

                int updated = pCount.Value != DBNull.Value ? (int)pCount.Value : idList.Count;
                string label = isRead ? "read" : "unread";
                return OperationResult.Ok($"Marked {updated} notification(s) as {label}.");
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error marking notifications status for user {UserId}", userId);
                return OperationResult.Fail("Failed to update notification status: " + ex.Message);
            }
        }

        public async Task<OperationResult> MarkAllNotificationsStatusAsync(int userId, bool isRead)
        {
            try
            {
                int newStatus = isRead ? 3 : 0;

                using var connection = _connectionFactory.CreateConnection();
                await connection.OpenAsync();

                using var command = new SqlCommand("dbo.usp_UpdateNotificationStatus", connection)
                {
                    CommandType = CommandType.StoredProcedure
                };
                command.Parameters.Add("@UserId", SqlDbType.Int).Value = userId;
                command.Parameters.Add("@AuthIds", SqlDbType.NVarChar, -1).Value = "ALL";
                command.Parameters.Add("@NewStatus", SqlDbType.Int).Value = newStatus;
                var pCount = command.Parameters.Add("@UpdatedCount", SqlDbType.Int);
                pCount.Direction = ParameterDirection.Output;

                await command.ExecuteNonQueryAsync();

                int updated = pCount.Value != DBNull.Value ? (int)pCount.Value : 0;
                string label = isRead ? "read" : "unread";
                return OperationResult.Ok($"Marked all ({updated}) notifications as {label}.");
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error marking all notifications status for user {UserId}", userId);
                return OperationResult.Fail("Failed to update all notifications: " + ex.Message);
            }
        }

        public async Task<OperationResult> SendVoucherNotificationAsync(int headerId, int actingUserId, int targetUserId, string comment)
        {
            try
            {
                if (string.IsNullOrWhiteSpace(comment))
                {
                    return OperationResult.Fail("Notification comment cannot be empty.");
                }

                using var connection = _connectionFactory.CreateConnection();
                await connection.OpenAsync();

                using var command = new SqlCommand("dbo.usp_SendVoucherNotification", connection)
                {
                    CommandType = CommandType.StoredProcedure
                };
                command.Parameters.Add("@iHeaderId", SqlDbType.Int).Value = headerId;
                command.Parameters.Add("@ActingUserId", SqlDbType.Int).Value = actingUserId;
                command.Parameters.Add("@TargetUserId", SqlDbType.Int).Value = targetUserId;
                command.Parameters.Add("@Comment", SqlDbType.NVarChar, 250).Value = comment.Trim();

                var pMessage = command.Parameters.Add("@ResponseMessage", SqlDbType.NVarChar, 250);
                pMessage.Direction = ParameterDirection.Output;

                await command.ExecuteNonQueryAsync();

                string msg = pMessage.Value?.ToString() ?? "Notification sent successfully.";
                return OperationResult.Ok(msg);
            }
            catch (SqlException ex)
            {
                _logger.LogError(ex, "SQL Error sending voucher notification for HeaderId {HeaderId}", headerId);
                return OperationResult.Fail(ex.Message, ex.Number);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Unexpected error sending notification for HeaderId {HeaderId}", headerId);
                return OperationResult.Fail("Failed to send notification: " + ex.Message);
            }
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

        public async Task<User?> GetUserByEmailOrUsernameAsync(string emailOrUsername)
        {
            if (string.IsNullOrWhiteSpace(emailOrUsername)) return null;
            var users = await GetAllUsersAsync();
            var target = emailOrUsername.Trim();
            return users.FirstOrDefault(u => 
                string.Equals(u.Email, target, StringComparison.OrdinalIgnoreCase) ||
                string.Equals(u.Username, target, StringComparison.OrdinalIgnoreCase));
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

        public async Task<List<ApprovalMatrixPolicy>> GetApprovalMatrixPoliciesAsync()
        {
            var policies = new List<ApprovalMatrixPolicy>();

            try
            {
                using var connection = _connectionFactory.CreateConnection();
                await connection.OpenAsync();

                using var command = new SqlCommand("dbo.usp_GetApprovalMatrixPolicies", connection)
                {
                    CommandType = CommandType.StoredProcedure
                };

                using var reader = await command.ExecuteReaderAsync();
                while (await reader.ReadAsync())
                {
                    policies.Add(new ApprovalMatrixPolicy
                    {
                        Level = reader.GetInt32(reader.GetOrdinal("iLevel")),
                        LevelName = reader.GetString(reader.GetOrdinal("sLevelName")),
                        MinAmount = reader.GetDecimal(reader.GetOrdinal("mMinAmount")),
                        MaxAmount = reader.IsDBNull(reader.GetOrdinal("mMaxAmount")) ? null : reader.GetDecimal(reader.GetOrdinal("mMaxAmount")),
                        ApproverDescription = reader.GetString(reader.GetOrdinal("sApproverDescription")),
                        PolicyDescription = reader.GetString(reader.GetOrdinal("sPolicyDescription")),
                        RequiredApprovers = reader.GetInt32(reader.GetOrdinal("iRequiredApprovers"))
                    });
                }
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error retrieving approval matrix policies.");
            }

            return policies;
        }

        public async Task<OperationResult> UpdateApprovalMatrixPolicyAsync(int actingUserId, int level, decimal minAmount, decimal? maxAmount)
        {
            try
            {
                using var connection = _connectionFactory.CreateConnection();
                await connection.OpenAsync();

                using var command = new SqlCommand("dbo.usp_UpdateApprovalMatrixPolicy", connection)
                {
                    CommandType = CommandType.StoredProcedure
                };

                command.Parameters.AddWithValue("@ActingUserId", actingUserId);
                command.Parameters.AddWithValue("@Level", level);
                command.Parameters.AddWithValue("@MinAmount", minAmount);
                if (maxAmount.HasValue)
                {
                    command.Parameters.AddWithValue("@MaxAmount", maxAmount.Value);
                }
                else
                {
                    command.Parameters.AddWithValue("@MaxAmount", DBNull.Value);
                }

                var pMessage = command.Parameters.Add("@ResponseMessage", SqlDbType.NVarChar, 250);
                pMessage.Direction = ParameterDirection.Output;

                await command.ExecuteNonQueryAsync();

                string msg = pMessage.Value?.ToString() ?? "Policy updated successfully.";
                return OperationResult.Ok(msg);
            }
            catch (SqlException ex)
            {
                _logger.LogError(ex, "SQL error updating approval matrix policy for Level {Level}", level);
                return OperationResult.Fail(ex.Message, ex.Number);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error updating approval matrix policy for Level {Level}", level);
                return OperationResult.Fail(ex.Message);
            }
        }
        public async Task<OperationResult> ImportApprovalMatrixFromXmlAsync(int actingUserId, string xmlContent)
        {
            // ---- Tier 1: C# pre-flight validation ----
            if (string.IsNullOrWhiteSpace(xmlContent))
                return OperationResult.Fail("XML content is empty.");

            System.Xml.Linq.XDocument doc;
            try
            {
                doc = System.Xml.Linq.XDocument.Parse(xmlContent);
            }
            catch (Exception ex)
            {
                return OperationResult.Fail("The uploaded file is not valid XML: " + ex.Message);
            }

            var policyElements = doc.Root?
                .Elements()
                .Where(e => e.Name.LocalName == "Policy")
                .ToList();

            if (policyElements == null || policyElements.Count == 0)
                return OperationResult.Fail("No <Policy> elements found in the XML document.");

            var parsed = new List<(int Level, decimal MinAmount, decimal? MaxAmount, int RequiredApprovers)>();
            foreach (var el in policyElements)
            {
                string? levelAttr    = el.Attribute("level")?.Value;
                string? minAmountStr = el.Elements().FirstOrDefault(x => x.Name.LocalName == "MinAmount")?.Value;
                string? maxAmountStr = el.Elements().FirstOrDefault(x => x.Name.LocalName == "MaxAmount")?.Value;
                string? reqStr       = el.Elements().FirstOrDefault(x => x.Name.LocalName == "RequiredApprovers")?.Value;

                if (!int.TryParse(levelAttr, out int lvl))
                    return OperationResult.Fail($"A <Policy> element has a missing or non-integer 'level' attribute: '{levelAttr}'.");
                if (!decimal.TryParse(minAmountStr, System.Globalization.NumberStyles.Any, System.Globalization.CultureInfo.InvariantCulture, out decimal minAmt))
                    return OperationResult.Fail($"Level {lvl}: MinAmount '{minAmountStr}' is not a valid decimal.");
                if (!int.TryParse(reqStr, out int req))
                    return OperationResult.Fail($"Level {lvl}: RequiredApprovers '{reqStr}' is not a valid integer.");

                decimal? maxAmt = null;
                if (!string.IsNullOrWhiteSpace(maxAmountStr))
                {
                    if (!decimal.TryParse(maxAmountStr, System.Globalization.NumberStyles.Any, System.Globalization.CultureInfo.InvariantCulture, out decimal parsedMax))
                        return OperationResult.Fail($"Level {lvl}: MaxAmount '{maxAmountStr}' is not a valid decimal.");
                    maxAmt = parsedMax;
                }

                if (minAmt < 0)
                    return OperationResult.Fail($"Level {lvl}: MinAmount cannot be negative.");
                if (maxAmt.HasValue && maxAmt.Value <= minAmt)
                    return OperationResult.Fail($"Level {lvl}: MaxAmount must be greater than MinAmount.");

                parsed.Add((lvl, minAmt, maxAmt, req));
            }

            // Continuity: gap / overlap detection between consecutive levels
            var sorted = parsed.OrderBy(p => p.Level).ToList();
            int maxLevel = sorted.Max(p => p.Level);

            var nullMaxNonTop = sorted.Where(p => p.MaxAmount == null && p.Level != maxLevel).ToList();
            if (nullMaxNonTop.Any())
                return OperationResult.Fail($"Only the highest level may have an unlimited MaxAmount. Level(s) {string.Join(", ", nullMaxNonTop.Select(p => p.Level))} have no MaxAmount.");

            for (int i = 0; i < sorted.Count - 1; i++)
            {
                var current = sorted[i];
                var next    = sorted[i + 1];
                if (!current.MaxAmount.HasValue)
                    return OperationResult.Fail($"Level {current.Level} has no MaxAmount but it is not the highest level.");

                decimal expectedNextMin = current.MaxAmount.Value + 0.01m;
                if (Math.Abs(next.MinAmount - expectedNextMin) > 0.009m)
                    return OperationResult.Fail(
                        $"Gap or overlap detected between Level {current.Level} and Level {next.Level}. " +
                        $"Level {current.Level} ends at {current.MaxAmount.Value:N2}; " +
                        $"Level {next.Level} must start at {expectedNextMin:N2} but starts at {next.MinAmount:N2}.");
            }

            // ---- Tier 2: SQL stored procedure (transactional) ----
            try
            {
                using var connection = _connectionFactory.CreateConnection();
                await connection.OpenAsync();

                using var command = new SqlCommand("dbo.usp_ImportApprovalMatrixFromXml", connection)
                {
                    CommandType    = CommandType.StoredProcedure,
                    CommandTimeout = 30
                };

                command.Parameters.AddWithValue("@ActingUserId", actingUserId);

                var xmlParam   = command.Parameters.Add("@XmlData", SqlDbType.Xml);
                xmlParam.Value = doc.ToString();

                var pMessage       = command.Parameters.Add("@ResponseMessage", SqlDbType.NVarChar, 500);
                pMessage.Direction = ParameterDirection.Output;

                await command.ExecuteNonQueryAsync();

                string msg = pMessage.Value?.ToString() ?? "Import completed successfully.";
                return OperationResult.Ok(msg);
            }
            catch (SqlException ex)
            {
                _logger.LogError(ex, "SQL error importing approval matrix from XML.");
                return OperationResult.Fail(ex.Message, ex.Number);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error importing approval matrix from XML.");
                return OperationResult.Fail(ex.Message);
            }
        }

        public async Task<(bool Success, string XmlContent, string Message)> ExportApprovalMatrixAsXmlAsync()
        {
            try
            {
                using var connection = _connectionFactory.CreateConnection();
                await connection.OpenAsync();

                using var command = new SqlCommand("dbo.usp_ExportApprovalMatrixAsXml", connection)
                {
                    CommandType = CommandType.StoredProcedure
                };

                var raw = await command.ExecuteScalarAsync();
                if (raw == null || raw == DBNull.Value)
                    return (false, string.Empty, "Export failed: no data returned from the database.");

                string xmlContent = raw.ToString()!;
                string fullXml    = "<?xml version=\"1.0\" encoding=\"utf-8\"?>\r\n" + xmlContent;
                return (true, fullXml, "Export successful.");
            }
            catch (SqlException ex)
            {
                _logger.LogError(ex, "SQL error exporting approval matrix as XML.");
                return (false, string.Empty, ex.Message);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error exporting approval matrix as XML.");
                return (false, string.Empty, ex.Message);
            }
        }
    }
}