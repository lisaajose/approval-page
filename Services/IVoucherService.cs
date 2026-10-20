using ApprovalWorkflow.Models;

namespace ApprovalWorkflow.Services
{
    public interface IVoucherService
    {
        Task<SaveVoucherResult> SaveVoucherAsync(CreateVoucherViewModel model, int createdByUserId);
        Task<VoucherDetailsViewModel> GetVoucherDetailsAsync(int headerId, int currentUserId);
        Task<List<Voucher>> GetRecentVouchersAsync(int count = 50);
    }
}
