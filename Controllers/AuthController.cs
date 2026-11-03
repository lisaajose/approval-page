using Microsoft.AspNetCore.Authentication;
using ApprovalWorkflow.Models;
using ApprovalWorkflow.Services;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;

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

            var model = new LoginViewModel
            {
                ReturnUrl = returnUrl
            };

            return View(model);
        }

        [HttpPost]
        [ValidateAntiForgeryToken]
        [EnableRateLimiting("LoginLimiter")]
        public async Task<IActionResult> Login(LoginViewModel model)
        {
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

            await _userContextService.SignInAsync(result.User);
            TempData["SuccessMessage"] = $"Welcome back, {result.User.Username}!";

            if (!string.IsNullOrEmpty(model.ReturnUrl) && Url.IsLocalUrl(model.ReturnUrl))
            {
                return Redirect(model.ReturnUrl);
            }

            return RedirectToAction("Index", "Voucher");
        }

        [HttpGet]
        [HttpPost]
        public async Task<IActionResult> Logout()
        {
            await _userContextService.SignOutAsync();
            TempData["SuccessMessage"] = "You have been logged out successfully.";
            return RedirectToAction(nameof(Login));
        }

        [HttpGet]
        public async Task<IActionResult> ExternalLogin(string provider, string? returnUrl = null)
        {
            if (string.IsNullOrWhiteSpace(provider))
            {
                TempData["ErrorMessage"] = "Invalid SSO provider specified.";
                return RedirectToAction(nameof(Login));
            }

            var schemeProvider = HttpContext.RequestServices.GetRequiredService<IAuthenticationSchemeProvider>();
            var scheme = await schemeProvider.GetSchemeAsync(provider);
            if (scheme == null)
            {
                TempData["ErrorMessage"] = $"{provider} Single Sign-On (SSO) is not configured yet. Please configure the ClientId and ClientSecret in appsettings.json or log in using your username and password.";
                return RedirectToAction(nameof(Login), new { returnUrl });
            }

            var redirectUrl = Url.Action(nameof(ExternalLoginCallback), "Auth", new { returnUrl });
            var properties = new AuthenticationProperties
            {
                RedirectUri = redirectUrl
            };
            return Challenge(properties, provider);
        }

        [HttpGet]
        public async Task<IActionResult> ExternalLoginCallback(string? returnUrl = null, string? remoteError = null)
        {
            if (!string.IsNullOrEmpty(remoteError))
            {
                TempData["ErrorMessage"] = $"SSO Authentication error: {remoteError}";
                return RedirectToAction(nameof(Login));
            }

            // Retrieve claims from external identity provider
            var authenticateResult = await HttpContext.AuthenticateAsync(Microsoft.AspNetCore.Authentication.Cookies.CookieAuthenticationDefaults.AuthenticationScheme);
            if (!authenticateResult.Succeeded || authenticateResult.Principal == null)
            {
                TempData["ErrorMessage"] = "Could not authenticate with external SSO provider.";
                return RedirectToAction(nameof(Login));
            }

            var email = authenticateResult.Principal.FindFirst(System.Security.Claims.ClaimTypes.Email)?.Value
                        ?? authenticateResult.Principal.FindFirst(System.Security.Claims.ClaimTypes.Upn)?.Value
                        ?? authenticateResult.Principal.FindFirst("email")?.Value
                        ?? authenticateResult.Principal.FindFirst("preferred_username")?.Value;

            var name = authenticateResult.Principal.FindFirst(System.Security.Claims.ClaimTypes.Name)?.Value
                       ?? authenticateResult.Principal.FindFirst("name")?.Value;

            if (string.IsNullOrWhiteSpace(email))
            {
                await _userContextService.SignOutAsync();
                TempData["ErrorMessage"] = "Your external SSO account did not provide an email address.";
                return RedirectToAction(nameof(Login));
            }

            // Look up the user by email or username in the database
            var user = await _approvalService.GetUserByEmailOrUsernameAsync(email);
            if (user == null)
            {
                // Sign out of the temporary external cookie ticket
                await _userContextService.SignOutAsync();
                TempData["ErrorMessage"] = $"No workflow account found matching your email ({email}). Please contact your system administrator.";
                return RedirectToAction(nameof(Login));
            }

            if (user.Bactive != true)
            {
                await _userContextService.SignOutAsync();
                TempData["ErrorMessage"] = "Your account is currently disabled. Please contact your administrator.";
                return RedirectToAction(nameof(Login));
            }

            // Sign in with proper workflow claims and roles
            await _userContextService.SignInAsync(user);
            TempData["SuccessMessage"] = $"Signed in via SSO as {user.Username} ({email})";

            if (!string.IsNullOrEmpty(returnUrl) && Url.IsLocalUrl(returnUrl))
            {
                return Redirect(returnUrl);
            }

            return RedirectToAction("Index", "Voucher");
        }
    }
}
