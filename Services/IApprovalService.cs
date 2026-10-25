using ApprovalWorkflow.Models;

namespace ApprovalWorkflow.Services
{
    public interface IApprovalService
    {
        Task<List<PendingApprovalItem>> GetPendingApprovalsAsync(int userId);
        Task<OperationResult> ApproveVoucherAsync(int headerId, int actingUserId, string? comments);
        Task<OperationResult> RejectVoucherAsync(int headerId, int actingUserId, string comments);
        Task<List<NotificationItem>> GetNotificationsAsync(int userId, string filter = "ALL");
        Task<(int TotalCount, int UnreadCount, int ReadCount)> GetNotificationCountsAsync(int userId);
        Task<OperationResult> MarkNotificationsStatusAsync(int userId, IEnumerable<int> authIds, bool isRead);
        Task<OperationResult> MarkAllNotificationsStatusAsync(int userId, bool isRead);
        Task<OperationResult> SendVoucherNotificationAsync(int headerId, int actingUserId, int targetUserId, string comment);
        Task<List<User>> GetAllUsersAsync();
        Task<User?> GetUserByIdAsync(int userId);
        Task<(bool Success, User? User, string Message)> ValidateUserLoginAsync(string usernameOrEmail, string password);
    }
}
