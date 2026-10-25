using ApprovalWorkflow.Models;
using ApprovalWorkflow.Services;
using Microsoft.AspNetCore.Mvc;

namespace ApprovalWorkflow.Controllers
{
    public class VoucherController : Controller
    {
        private readonly IVoucherService _voucherService;
        private readonly IUserContextService _userContextService;
        private readonly IApprovalService _approvalService;
        private readonly ILogger<VoucherController> _logger;

        public VoucherController(
            IVoucherService voucherService,
            IUserContextService userContextService,
            IApprovalService approvalService,
            ILogger<VoucherController> logger)
        {
            _voucherService = voucherService;
            _userContextService = userContextService;
            _approvalService = approvalService;
            _logger = logger;
        }

        public async Task<IActionResult> Index()
        {
            var currentUser = await _userContextService.GetCurrentUserAsync();
            if (currentUser == null)
            {
                return RedirectToAction("Login", "Auth", new { returnUrl = Request.Path });
            }
            ViewBag.CurrentUser = currentUser;

            var vouchers = await _voucherService.GetRecentVouchersAsync(100);
            return View(vouchers);
        }

        [HttpGet]
        public async Task<IActionResult> Create()
        {
            var currentUser = await _userContextService.GetCurrentUserAsync();
            if (currentUser == null)
            {
                return RedirectToAction("Login", "Auth", new { returnUrl = Request.Path });
            }
            ViewBag.CurrentUser = currentUser;

            var model = new CreateVoucherViewModel
            {
                Date = DateTime.Today,
                VoucherNo = "VOUCH-" + DateTime.Now.ToString("yyyyMMdd-HHmmss")
            };

            return View(model);
        }

        [HttpPost]
        [ValidateAntiForgeryToken]
        public async Task<IActionResult> Create(CreateVoucherViewModel model)
        {
            var currentUser = await _userContextService.GetCurrentUserAsync();
            if (currentUser == null)
            {
                return RedirectToAction("Login", "Auth", new { returnUrl = Request.Path });
            }
            ViewBag.CurrentUser = currentUser;

            if (!ModelState.IsValid)
            {
                return View(model);
            }

            var result = await _voucherService.SaveVoucherAsync(model, currentUser.UserId);

            if (!result.Success)
            {
                ModelState.AddModelError(string.Empty, result.Message);
                return View(model);
            }

            TempData["SuccessMessage"] = result.Message;
            return RedirectToAction(nameof(Details), new { id = result.HeaderId });
        }

        [HttpGet]
        public async Task<IActionResult> Details(int id)
        {
            var currentUser = await _userContextService.GetCurrentUserAsync();
            if (currentUser == null)
            {
                return RedirectToAction("Login", "Auth", new { returnUrl = Request.Path });
            }
            ViewBag.CurrentUser = currentUser;

            try
            {
                var details = await _voucherService.GetVoucherDetailsAsync(id, currentUser.UserId);
                if (details.Header == null || details.Header.HeaderId == 0)
                {
                    TempData["ErrorMessage"] = "Voucher not found.";
                    return RedirectToAction(nameof(Index));
                }

                details.CurrentUserRole = currentUser.UserRole ?? 2;
                return View(details);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error retrieving voucher details for HeaderId {Id}", id);
                TempData["ErrorMessage"] = "An error occurred while retrieving the voucher details. Please try again later.";
                return RedirectToAction(nameof(Index));
            }
        }

        [HttpGet]
        public async Task<IActionResult> Edit(int id)
        {
            var currentUser = await _userContextService.GetCurrentUserAsync();
            if (currentUser == null)
            {
                return RedirectToAction("Login", "Auth", new { returnUrl = Request.Path });
            }
            ViewBag.CurrentUser = currentUser;

            var details = await _voucherService.GetVoucherDetailsAsync(id, currentUser.UserId);
            if (details.Header == null || details.Header.HeaderId == 0)
            {
                TempData["ErrorMessage"] = "Voucher not found.";
                return RedirectToAction(nameof(Index));
            }

            if (details.Header.AuthStatus != 2)
            {
                TempData["ErrorMessage"] = "Only rejected vouchers can be edited and resubmitted.";
                return RedirectToAction(nameof(Details), new { id });
            }

            // Only creator or admin can edit
            if (details.Header.CreatedBy != currentUser.UserId && currentUser.UserRole != 1)
            {
                TempData["ErrorMessage"] = "Unauthorized: Only the creator of the voucher can edit and resubmit it.";
                return RedirectToAction(nameof(Details), new { id });
            }

            var lastRejection = details.History
                .Where(h => h.Action == "REJECTED")
                .OrderByDescending(h => h.ActionDate)
                .FirstOrDefault();

            var model = new EditVoucherViewModel
            {
                HeaderId = details.Header.HeaderId,
                VoucherNo = details.Header.VoucherNo,
                Date = details.Header.Date,
                Narration = details.Header.Narration,
                Amount = details.Header.Amount,
                PreviousWorkflowLevel = details.Header.WorkflowLevel,
                LastRejectionReason = lastRejection?.Comments
            };

            return View(model);
        }

        [HttpPost]
        [ValidateAntiForgeryToken]
        public async Task<IActionResult> Edit(EditVoucherViewModel model)
        {
            var currentUser = await _userContextService.GetCurrentUserAsync();
            if (currentUser == null)
            {
                return RedirectToAction("Login", "Auth", new { returnUrl = Request.Path });
            }
            ViewBag.CurrentUser = currentUser;

            if (!ModelState.IsValid)
            {
                return View(model);
            }

            var result = await _voucherService.ResubmitVoucherAsync(model, currentUser.UserId);
            if (!result.Success)
            {
                ModelState.AddModelError(string.Empty, result.Message);
                return View(model);
            }

            TempData["SuccessMessage"] = result.Message;
            return RedirectToAction(nameof(Details), new { id = model.HeaderId });
        }

        [HttpPost]
        [ValidateAntiForgeryToken]
        public async Task<IActionResult> SendNotification(SendNotificationInputModel model)
        {
            var currentUser = await _userContextService.GetCurrentUserAsync();
            if (currentUser == null)
            {
                return RedirectToAction("Login", "Auth", new { returnUrl = Request.Path });
            }

            if (model.HeaderId <= 0 || model.TargetUserId <= 0 || string.IsNullOrWhiteSpace(model.Comment))
            {
                TempData["ErrorMessage"] = "Recipient and remarks/comments are required to send a notification.";
                return RedirectToAction(nameof(Details), new { id = model.HeaderId });
            }

            var result = await _approvalService.SendVoucherNotificationAsync(
                model.HeaderId,
                currentUser.UserId,
                model.TargetUserId,
                model.Comment);

            if (result.Success)
            {
                TempData["SuccessMessage"] = result.Message;
            }
            else
            {
                TempData["ErrorMessage"] = "Failed to send notification: " + result.Message;
            }

            return RedirectToAction(nameof(Details), new { id = model.HeaderId });
        }
    }
}
