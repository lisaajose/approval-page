namespace ApprovalWorkflow.Models
{
    public class NotificationItem
    {
        public int AuthId { get; set; }
        public int HeaderId { get; set; }
        public string VoucherNo { get; set; } = string.Empty;
        public DateTime Date { get; set; }
        public decimal Amount { get; set; }
        public int AuthStatus { get; set; }
        public string HeaderStatusDescription { get; set; } = string.Empty;
        public int AlertType { get; set; }
        public int Level { get; set; }
        public string? Alerts { get; set; }
        public string? UserComments { get; set; }
        public int Status { get; set; }
        public DateTime CreatedDate { get; set; }
        public string? CreatedByUsername { get; set; }
        public DateTime? ActionDate { get; set; }
        public int RecipientUserId { get; set; }
        public string RecipientUsername { get; set; } = string.Empty;
    }

    public class ApprovalHistoryItem
    {
        public int HistoryId { get; set; }
        public int HeaderId { get; set; }
        public int Level { get; set; }
        public int StepOrder { get; set; }
        public int ActionUser { get; set; }
        public int ActionUserId { get => ActionUser; set => ActionUser = value; }
        public string ActionUsername { get; set; } = string.Empty;
        public string Action { get; set; } = string.Empty;
        public string? Comments { get; set; }
        public DateTime ActionDate { get; set; }
    }
}
