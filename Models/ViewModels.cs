using System.ComponentModel.DataAnnotations;

namespace ApprovalWorkflow.Models
{
    public class PendingApprovalItem
    {
        public int HeaderId { get; set; }
        public string VoucherNo { get; set; } = string.Empty;
        public DateTime Date { get; set; }
        public string? Narration { get; set; }
        public decimal Amount { get; set; }
        public int AuthStatus { get; set; }
        public DateTime CreatedDate { get; set; }
        public string? CreatedByUsername { get; set; }
        public int WorkflowLevel { get; set; }
        public int AuthId { get; set; }
        public int Level { get; set; }
        public int StepOrder { get; set; }
        public string? Alerts { get; set; }
        public int AssignmentStatus { get; set; }
    }

    public class CreateVoucherViewModel
    {
        [Required(ErrorMessage = "Voucher number is required.")]
        [StringLength(50, ErrorMessage = "Voucher number cannot exceed 50 characters.")]
        [Display(Name = "Voucher Number")]
        public string VoucherNo { get; set; } = string.Empty;

        [Required(ErrorMessage = "Voucher date is required.")]
        [DataType(DataType.Date)]
        [Display(Name = "Voucher Date")]
        public DateTime Date { get; set; } = DateTime.Today;

        [StringLength(100, ErrorMessage = "Narration cannot exceed 100 characters.")]
        [Display(Name = "Narration / Description")]
        public string? Narration { get; set; }

        [Required(ErrorMessage = "Amount is required.")]
        [Range(0.00, 999999999.99, ErrorMessage = "Amount must be a non-negative number.")]
        [Display(Name = "Amount (₹)")]
        public decimal Amount { get; set; }
    }

    public class VoucherDetailsViewModel
    {
        public Voucher Header { get; set; } = new Voucher();
        public List<ApprovalSlot> ApprovalSlots { get; set; } = new List<ApprovalSlot>();
        public List<ApprovalSlot> AllCycleSlots { get; set; } = new List<ApprovalSlot>();
        public List<NotificationItem> Notifications { get; set; } = new List<NotificationItem>();
        public List<ApprovalHistoryItem> History { get; set; } = new List<ApprovalHistoryItem>();

        public int CurrentUserId { get; set; }
        public string CurrentUsername { get; set; } = string.Empty;
        public int CurrentUserRole { get; set; }
        public int CurrentCycle { get; set; } = 1;

        public bool CanCurrentUserAct =>
            Header.AuthStatus == 0 &&
            ApprovalSlots.Any(s => s.IsCurrentActiveStage && s.AssignedUserId == CurrentUserId);

        public ApprovalSlot? ActiveSlotForCurrentUser =>
            ApprovalSlots.FirstOrDefault(s => s.IsCurrentActiveStage && s.AssignedUserId == CurrentUserId);

        public bool CanCurrentUserEdit =>
            Header.AuthStatus == 2 &&
            (Header.CreatedBy == CurrentUserId || CurrentUserRole == 1);
    }

    public class EditVoucherViewModel
    {
        [Required]
        public int HeaderId { get; set; }

        public string VoucherNo { get; set; } = string.Empty;

        [Required(ErrorMessage = "Voucher date is required.")]
        [DataType(DataType.Date)]
        [Display(Name = "Voucher Date")]
        public DateTime Date { get; set; } = DateTime.Today;

        [StringLength(100, ErrorMessage = "Narration cannot exceed 100 characters.")]
        [Display(Name = "Narration / Description")]
        public string? Narration { get; set; }

        [Required(ErrorMessage = "Amount is required.")]
        [Range(0.00, 999999999.99, ErrorMessage = "Amount must be a non-negative number.")]
        [Display(Name = "Amount (₹)")]
        public decimal Amount { get; set; }

        public int PreviousWorkflowLevel { get; set; }
        public string? LastRejectionReason { get; set; }
    }

    public class ApprovalActionInputModel
    {
        [Required]
        public int HeaderId { get; set; }

        [StringLength(100, ErrorMessage = "Comments cannot exceed 100 characters.")]
        public string? Comments { get; set; }
    }

    public class OperationResult
    {
        public bool Success { get; set; }
        public string Message { get; set; } = string.Empty;
        public int? ErrorCode { get; set; }

        public static OperationResult Ok(string message) => new() { Success = true, Message = message };
        public static OperationResult Fail(string message, int? errorCode = null) =>
            new() { Success = false, Message = message, ErrorCode = errorCode };
    }

    public class SaveVoucherResult : OperationResult
    {
        public int? HeaderId { get; set; }
        public int? WorkflowLevel { get; set; }
        public int? AuthStatus { get; set; }
    }

    public class LoginViewModel
    {
        [Required(ErrorMessage = "Username or Email is required.")]
        [Display(Name = "Username or Email")]
        public string UsernameOrEmail { get; set; } = string.Empty;

        [Required(ErrorMessage = "Password is required.")]
        [DataType(DataType.Password)]
        public string Password { get; set; } = string.Empty;

        public string? ReturnUrl { get; set; }
        public List<User> AvailableUsers { get; set; } = new();
    }
}
