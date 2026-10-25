using ApprovalWorkflow.Models;
using ApprovalWorkflow.Services;
using Microsoft.AspNetCore.Mvc;

namespace ApprovalWorkflow.Controllers
{
    public class ApprovalController : Controller
    {
        private readonly IApprovalService _approvalService;
        private readonly IUserContextService _userContextService;
        private readonly ILogger<ApprovalController> _logger;

        public ApprovalController(
            IApprovalService approvalService,
            IUserContextService userContextService,
            ILogger<ApprovalController> logger)
        {
            _approvalService = approvalService;
            _userContextService = userContextService;
            _logger = logger;
        }

        [HttpGet]
        public async Task<IActionResult> Pending()
        {
            var currentUser = await _userContextService.GetCurrentUserAsync();
            if (currentUser == null)
            {
                return RedirectToAction("Login", "Auth", new { returnUrl = Request.Path });
            }
            ViewBag.CurrentUser = currentUser;

            var items = await _approvalService.GetPendingApprovalsAsync(currentUser.UserId);
            return View(items);
        }

        [HttpPost]
        [ValidateAntiForgeryToken]
        public async Task<IActionResult> Approve(ApprovalActionInputModel model)
        {
            var currentUser = await _userContextService.GetCurrentUserAsync();
            if (currentUser == null)
            {
                return RedirectToAction("Login", "Auth", new { returnUrl = Request.Path });
            }

            var result = await _approvalService.ApproveVoucherAsync(model.HeaderId, currentUser.UserId, model.Comments);

            if (result.Success)
            {
                TempData["SuccessMessage"] = result.Message;
            }
            else
            {
                TempData["ErrorMessage"] = "Approval Failed: " + result.Message;
            }

            return RedirectToAction("Details", "Voucher", new { id = model.HeaderId });
        }

        [HttpPost]
        [ValidateAntiForgeryToken]
        public async Task<IActionResult> Reject(ApprovalActionInputModel model)
        {
            var currentUser = await _userContextService.GetCurrentUserAsync();
            if (currentUser == null)
            {
                return RedirectToAction("Login", "Auth", new { returnUrl = Request.Path });
            }

            if (string.IsNullOrWhiteSpace(model.Comments))
            {
                TempData["ErrorMessage"] = "Rejection requires mandatory comments explaining the reason.";
                return RedirectToAction("Details", "Voucher", new { id = model.HeaderId });
            }

            var result = await _approvalService.RejectVoucherAsync(model.HeaderId, currentUser.UserId, model.Comments);

            if (result.Success)
            {
                TempData["SuccessMessage"] = result.Message;
            }
            else
            {
                TempData["ErrorMessage"] = "Rejection Failed: " + result.Message;
            }

            return RedirectToAction("Details", "Voucher", new { id = model.HeaderId });
        }

        [HttpGet]
        public async Task<IActionResult> Notifications(string filter = "ALL")
        {
            var currentUser = await _userContextService.GetCurrentUserAsync();
            if (currentUser == null)
            {
                return RedirectToAction("Login", "Auth", new { returnUrl = Request.Path });
            }
            ViewBag.CurrentUser = currentUser;

            string normalizedFilter = string.IsNullOrWhiteSpace(filter) ? "ALL" : filter.Trim().ToUpperInvariant();
            var counts = await _approvalService.GetNotificationCountsAsync(currentUser.UserId);
            var items = await _approvalService.GetNotificationsAsync(currentUser.UserId, normalizedFilter);

            var viewModel = new NotificationsPageViewModel
            {
                Notifications = items,
                CurrentFilter = normalizedFilter,
                TotalCount = counts.TotalCount,
                UnreadCount = counts.UnreadCount,
                ReadCount = counts.ReadCount
            };

            return View(viewModel);
        }

        [HttpPost]
        [ValidateAntiForgeryToken]
        public async Task<IActionResult> MarkNotifications(MarkNotificationInputModel model)
        {
            var currentUser = await _userContextService.GetCurrentUserAsync();
            if (currentUser == null)
            {
                return RedirectToAction("Login", "Auth", new { returnUrl = Request.Path });
            }

            OperationResult result;
            string action = (model.ActionType ?? "READ").Trim().ToUpperInvariant();

            if (action == "READ_ALL")
            {
                result = await _approvalService.MarkAllNotificationsStatusAsync(currentUser.UserId, true);
            }
            else if (action == "UNREAD_ALL")
            {
                result = await _approvalService.MarkAllNotificationsStatusAsync(currentUser.UserId, false);
            }
            else if (action == "UNREAD")
            {
                result = await _approvalService.MarkNotificationsStatusAsync(currentUser.UserId, model.AuthIds, false);
            }
            else
            {
                // Default READ
                result = await _approvalService.MarkNotificationsStatusAsync(currentUser.UserId, model.AuthIds, true);
            }

            if (result.Success)
            {
                TempData["SuccessMessage"] = result.Message;
            }
            else
            {
                TempData["ErrorMessage"] = result.Message;
            }

            return RedirectToAction(nameof(Notifications), new { filter = model.CurrentFilter });
        }

        [HttpPost]
        [ValidateAntiForgeryToken]
        public async Task<IActionResult> ToggleSingleNotification(int authId, bool makeRead, string filter = "ALL")
        {
            var currentUser = await _userContextService.GetCurrentUserAsync();
            if (currentUser == null)
            {
                return RedirectToAction("Login", "Auth", new { returnUrl = Request.Path });
            }

            var result = await _approvalService.MarkNotificationsStatusAsync(currentUser.UserId, new[] { authId }, makeRead);
            if (result.Success)
            {
                TempData["SuccessMessage"] = result.Message;
            }
            else
            {
                TempData["ErrorMessage"] = result.Message;
            }

            return RedirectToAction(nameof(Notifications), new { filter });
        }
    }
}
