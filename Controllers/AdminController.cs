using ApprovalWorkflow.Models;
using ApprovalWorkflow.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace ApprovalWorkflow.Controllers
{
    [Authorize]
    public class AdminController : Controller
    {
        private readonly IApprovalService _approvalService;
        private readonly IUserContextService _userContextService;
        private readonly ILogger<AdminController> _logger;

        public AdminController(
            IApprovalService approvalService,
            IUserContextService userContextService,
            ILogger<AdminController> logger)
        {
            _approvalService = approvalService;
            _userContextService = userContextService;
            _logger = logger;
        }

        [HttpGet]
        public async Task<IActionResult> ApprovalMatrix()
        {
            var currentUser = await _userContextService.GetCurrentUserAsync();
            if (currentUser == null)
            {
                return RedirectToAction("Login", "Auth", new { returnUrl = Request.Path });
            }

            if (currentUser.UserRole != 1)
            {
                TempData["ErrorMessage"] = "Unauthorized: Access to the Administration page is restricted to administrators.";
                return RedirectToAction("Index", "Voucher");
            }

            var policies = await _approvalService.GetApprovalMatrixPoliciesAsync();
            var model = new AdminApprovalMatrixViewModel
            {
                Policies = policies
            };

            return View(model);
        }

        [HttpPost]
        [ValidateAntiForgeryToken]
        public async Task<IActionResult> UpdatePolicy(ApprovalMatrixPolicyEditModel model)
        {
            var currentUser = await _userContextService.GetCurrentUserAsync();
            if (currentUser == null)
            {
                return RedirectToAction("Login", "Auth", new { returnUrl = Request.Path });
            }

            if (currentUser.UserRole != 1)
            {
                TempData["ErrorMessage"] = "Unauthorized: Access to this action is restricted to administrators.";
                return RedirectToAction("Index", "Voucher");
            }

            if (model.MinAmount < 0)
            {
                TempData["ErrorMessage"] = "Minimum amount cannot be negative.";
                return RedirectToAction(nameof(ApprovalMatrix));
            }

            if (model.MaxAmount.HasValue && model.MaxAmount.Value < model.MinAmount)
            {
                TempData["ErrorMessage"] = "Maximum amount cannot be less than the minimum amount.";
                return RedirectToAction(nameof(ApprovalMatrix));
            }

            var result = await _approvalService.UpdateApprovalMatrixPolicyAsync(
                currentUser.UserId,
                model.Level,
                model.MinAmount,
                model.MaxAmount);

            if (result.Success)
            {
                TempData["SuccessMessage"] = result.Message;
            }
            else
            {
                TempData["ErrorMessage"] = "Failed to update policy: " + result.Message;
            }

            return RedirectToAction(nameof(ApprovalMatrix));
        }
    }
}
