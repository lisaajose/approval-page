namespace ApprovalWorkflow.Models
{
    public class Voucher
    {
        public int HeaderId { get; set; }
        public string VoucherNo { get; set; } = string.Empty;
        public DateTime Date { get; set; }
        public string? Narration { get; set; }
        public decimal Amount { get; set; }
        public int AuthStatus { get; set; }
        public string StatusDescription { get; set; } = string.Empty;
        public DateTime? PostDate { get; set; }
        public DateTime CreatedDate { get; set; }
        public int? CreatedBy { get; set; }
        public string? CreatedByUsername { get; set; }
        public int WorkflowLevel { get; set; }

        public int? CurrentPendingStepOrder { get; set; }
        public int? CurrentPendingUserId { get; set; }
        public string? CurrentPendingUsername { get; set; }

        public string StatusBadgeClass => AuthStatus switch
        {
            1 => "bg-success text-white",
            2 => "bg-danger text-white",
            _ => "bg-warning text-dark"
        };
    }
}
