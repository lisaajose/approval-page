namespace ApprovalWorkflow.Models
{
    public class ApprovalSlot
    {
        public int AuthId { get; set; }
        public int HeaderId { get; set; }
        public int AlertType { get; set; }
        public int Level { get; set; }
        public int StepOrder { get; set; }
        public int AssignedUserId { get; set; }
        public string AssignedUsername { get; set; } = string.Empty;
        public string? Alerts { get; set; }
        public string? UserComments { get; set; }
        public int Status { get; set; }
        public string StepStatusDescription { get; set; } = string.Empty;
        public DateTime? ActionDate { get; set; }
        public int? ActionedBy { get; set; }
        public string? ActionedByUsername { get; set; }
        public bool IsCurrentActiveStage { get; set; }

        public string AlertTypeDescription => AlertType switch
        {
            0 => "Notification",
            1 => "Approval Alert",
            _ => "Unknown"
        };

        public string StatusBadgeClass => Status switch
        {
            1 => "bg-success text-white",
            2 => "bg-danger text-white",
            _ when IsCurrentActiveStage => "bg-primary text-white",
            _ => "bg-secondary text-white"
        };
    }
}
