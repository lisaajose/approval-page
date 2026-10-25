namespace ApprovalWorkflow.Models
{
    public class ApprovalSlot
    {
        public int AuthId { get; set; }
        public int HeaderId { get; set; }
        public int AlertType { get; set; }
        public int Level { get; set; }
        public int StepOrder { get; set; }
        public int UserType { get; set; } = 1;
        public int AssignedUserId { get; set; }
        public string AssignedUsername { get; set; } = string.Empty;
        public string? Alerts { get; set; }
        public string? UserComments { get; set; }
        public int Status { get; set; }
        public string StepStatusDescription { get; set; } = string.Empty;
        public string StatusDescription => !string.IsNullOrEmpty(StepStatusDescription) ? StepStatusDescription : Status switch
        {
            1 => "Approved",
            2 => "Rejected",
            _ when IsCurrentActiveStage => "Pending (Active)",
            _ => "Waiting"
        };
        public DateTime? ActionDate { get; set; }
        public int? ActionedBy { get; set; }
        public int? ActionedByUserId { get => ActionedBy; set => ActionedBy = value; }
        public string? ActionedByUsername { get; set; }
        public bool IsCurrentActiveStage { get; set; }
        public int Cycle { get; set; } = 1;

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
