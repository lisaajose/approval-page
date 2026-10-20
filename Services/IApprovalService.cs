using ApprovalWorkflow.Models;

namespace ApprovalWorkflow.Services
{
    public interface IApprovalService
    {
        Task<List<PendingApprovalItem>> GetPendingApprovalsAsync(int userId);
        Task<OperationResult> ApproveVoucherAsync(int headerId, int actingUserId, string? comments);
        Task<OperationResult> RejectVoucherAsync(int headerId, int actingUserId, string comments);
        Task<List<NotificationItem>> GetNotificationsAsync(int userId);
        Task<List<User>> GetAllUsersAsync();
        Task<User?> GetUserByIdAsync(int userId);
    }
}
