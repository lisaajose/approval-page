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
        public bool IsRead => Status == 3;
        public DateTime CreatedDate { get; set; }
        public string? CreatedByUsername { get; set; }
        public DateTime? ActionDate { get; set; }
        public int RecipientUserId { get; set; }
        public string RecipientUsername { get; set; } = string.Empty;
        public string? ActionedByUsername { get; set; }
        public int Cycle { get; set; } = 1;
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
        public int Cycle { get; set; } = 1;
    }

    public class NotificationsPageViewModel
    {
        public List<NotificationItem> Notifications { get; set; } = new();
        public string CurrentFilter { get; set; } = "ALL"; // ALL, UNREAD, READ
        public int TotalCount { get; set; }
        public int UnreadCount { get; set; }
        public int ReadCount { get; set; }
    }

    public class SendNotificationInputModel
    {
        public int HeaderId { get; set; }
        public int TargetUserId { get; set; }
        public string Comment { get; set; } = string.Empty;
    }

    public class MarkNotificationInputModel
    {
        public List<int> AuthIds { get; set; } = new();
        public string ActionType { get; set; } = "READ"; // "READ", "UNREAD", "READ_ALL"
        public string CurrentFilter { get; set; } = "ALL";
    }
}
