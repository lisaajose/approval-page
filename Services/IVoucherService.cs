using ApprovalWorkflow.Models;

namespace ApprovalWorkflow.Services
{
    public interface IVoucherService
    {
        Task<SaveVoucherResult> SaveVoucherAsync(CreateVoucherViewModel model, int createdByUserId);
        Task<OperationResult> ResubmitVoucherAsync(EditVoucherViewModel model, int actingUserId);
        Task<VoucherDetailsViewModel> GetVoucherDetailsAsync(int headerId, int currentUserId);
        Task<List<Voucher>> GetRecentVouchersAsync(int count = 50);
    }
}
