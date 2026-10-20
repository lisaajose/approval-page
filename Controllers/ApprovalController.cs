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
        public async Task<IActionResult> Notifications()
        {
            var currentUser = await _userContextService.GetCurrentUserAsync();
            if (currentUser == null)
            {
                return RedirectToAction("Login", "Auth", new { returnUrl = Request.Path });
            }
            ViewBag.CurrentUser = currentUser;

            var notifications = await _approvalService.GetNotificationsAsync(currentUser.UserId);
            return View(notifications);
        }
    }
}
