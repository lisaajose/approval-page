using ApprovalWorkflow.Models;
using ApprovalWorkflow.Services;
using Microsoft.AspNetCore.Mvc;

namespace ApprovalWorkflow.Controllers
{
    public class AuthController : Controller
    {
        private readonly IApprovalService _approvalService;
        private readonly IUserContextService _userContextService;
        private readonly ILogger<AuthController> _logger;

        public AuthController(
            IApprovalService approvalService,
            IUserContextService userContextService,
            ILogger<AuthController> logger)
        {
            _approvalService = approvalService;
            _userContextService = userContextService;
            _logger = logger;
        }

        [HttpGet]
        public async Task<IActionResult> Login(string? returnUrl = null)
        {
            var currentUser = await _userContextService.GetCurrentUserAsync();
            if (currentUser != null)
            {
                if (!string.IsNullOrEmpty(returnUrl) && Url.IsLocalUrl(returnUrl))
                {
                    return Redirect(returnUrl);
                }
                return RedirectToAction("Index", "Voucher");
            }

            var allUsers = await _approvalService.GetAllUsersAsync();
            var model = new LoginViewModel
            {
                ReturnUrl = returnUrl,
                AvailableUsers = allUsers.Where(u => u.Bactive == true).ToList()
            };

            return View(model);
        }

        [HttpPost]
        [ValidateAntiForgeryToken]
        public async Task<IActionResult> Login(LoginViewModel model)
        {
            var allUsers = await _approvalService.GetAllUsersAsync();
            model.AvailableUsers = allUsers.Where(u => u.Bactive == true).ToList();

            if (string.IsNullOrWhiteSpace(model.UsernameOrEmail) || string.IsNullOrWhiteSpace(model.Password))
            {
                ModelState.AddModelError(string.Empty, "Please enter both username/email and password.");
                return View(model);
            }

            var result = await _approvalService.ValidateUserLoginAsync(model.UsernameOrEmail, model.Password);
            if (!result.Success || result.User == null)
            {
                ModelState.AddModelError(string.Empty, result.Message);
                return View(model);
            }

            _userContextService.SetCurrentUser(result.User.UserId);
            TempData["SuccessMessage"] = $"Welcome back, {result.User.Username}! You are logged in as {result.User.RoleDescription}.";

            if (!string.IsNullOrEmpty(model.ReturnUrl) && Url.IsLocalUrl(model.ReturnUrl))
            {
                return Redirect(model.ReturnUrl);
            }

            return RedirectToAction("Index", "Voucher");
        }

        [HttpPost]
        [ValidateAntiForgeryToken]
        public async Task<IActionResult> QuickLogin(int userId, string? returnUrl = null)
        {
            var user = await _approvalService.GetUserByIdAsync(userId);
            if (user == null || user.Bactive != true)
            {
                TempData["ErrorMessage"] = "The selected user account is not active or does not exist.";
                return RedirectToAction(nameof(Login));
            }

            _userContextService.SetCurrentUser(user.UserId);
            TempData["SuccessMessage"] = $"Successfully switched actor to {user.Username} ({user.RoleDescription}).";

            if (!string.IsNullOrEmpty(returnUrl) && Url.IsLocalUrl(returnUrl))
            {
                return Redirect(returnUrl);
            }

            return RedirectToAction("Index", "Voucher");
        }

        [HttpGet]
        [HttpPost]
        public IActionResult Logout()
        {
            _userContextService.ClearCurrentUser();
            TempData["SuccessMessage"] = "You have been logged out successfully.";
            return RedirectToAction(nameof(Login));
        }
    }
}
