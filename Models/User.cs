namespace ApprovalWorkflow.Models
{
    public class User
    {
        public int UserId { get; set; }
        public string Username { get; set; } = string.Empty;
        public string Email { get; set; } = string.Empty;
        public int? UserRole { get; set; }
        public bool? Bactive { get; set; }
        public DateTime CreatedDate { get; set; }
        public DateTime? LastLoginDate { get; set; }

        public string RoleDescription => UserRole switch
        {
            1 => "Administrator / Notification Recipient",
            2 => "Workflow Approver",
            _ => "Standard User"
        };
    }
}
