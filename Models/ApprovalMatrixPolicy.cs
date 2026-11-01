namespace ApprovalWorkflow.Models
{
    public class ApprovalMatrixPolicy
    {
        public int Level { get; set; }
        public string LevelName { get; set; } = string.Empty;
        public decimal MinAmount { get; set; }
        public decimal? MaxAmount { get; set; }
        public string ApproverDescription { get; set; } = string.Empty;
        public string PolicyDescription { get; set; } = string.Empty;
        public int RequiredApprovers { get; set; }

        public string AmountRangeFormatted => MaxAmount.HasValue
            ? $"₹{MinAmount:N2} – ₹{MaxAmount.Value:N2}"
            : $"> ₹{MinAmount:N2}";
    }

    public class ApprovalMatrixPolicyEditModel
    {
        public int Level { get; set; }
        public decimal MinAmount { get; set; }
        public decimal? MaxAmount { get; set; }
    }

    public class AdminApprovalMatrixViewModel
    {
        public List<ApprovalMatrixPolicy> Policies { get; set; } = new();
    }
}
