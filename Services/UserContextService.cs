using System.Security.Claims;
using ApprovalWorkflow.Models;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Authentication.Cookies;

namespace ApprovalWorkflow.Services
{
    public interface IUserContextService
    {
        Task<User?> GetCurrentUserAsync();
        Task SignInAsync(User user);
        Task SignOutAsync();
        bool IsAuthenticated();
    }

    public class UserContextService : IUserContextService
    {
        private readonly IHttpContextAccessor _httpContextAccessor;
        private readonly IApprovalService _approvalService;

        public UserContextService(IHttpContextAccessor httpContextAccessor, IApprovalService approvalService)
        {
            _httpContextAccessor = httpContextAccessor;
            _approvalService = approvalService;
        }

        public bool IsAuthenticated()
        {
            var user = _httpContextAccessor.HttpContext?.User;
            return user?.Identity?.IsAuthenticated == true;
        }

        public async Task<User?> GetCurrentUserAsync()
        {
            var context = _httpContextAccessor.HttpContext;
            if (context?.User?.Identity?.IsAuthenticated != true)
            {
                return null;
            }

            var userIdClaim = context.User.FindFirst(ClaimTypes.NameIdentifier)?.Value;
            if (int.TryParse(userIdClaim, out int userId))
            {
                var user = await _approvalService.GetUserByIdAsync(userId);
                if (user != null && user.Bactive == true)
                {
                    return user;
                }
            }

            return null;
        }

        public async Task SignInAsync(User user)
        {
            var context = _httpContextAccessor.HttpContext;
            if (context == null) return;

            var claims = new List<Claim>
            {
                new Claim(ClaimTypes.NameIdentifier, user.UserId.ToString()),
                new Claim(ClaimTypes.Name, user.Username),
                new Claim(ClaimTypes.Email, user.Email),
                new Claim(ClaimTypes.Role, user.UserRole == 1 ? "Admin" : "Approver")
            };

            var claimsIdentity = new ClaimsIdentity(claims, CookieAuthenticationDefaults.AuthenticationScheme);
            var authProperties = new AuthenticationProperties
            {
                IsPersistent = true,
                ExpiresUtc = DateTimeOffset.UtcNow.AddHours(8)
            };

            await context.SignInAsync(
                CookieAuthenticationDefaults.AuthenticationScheme,
                new ClaimsPrincipal(claimsIdentity),
                authProperties);
        }

        public async Task SignOutAsync()
        {
            var context = _httpContextAccessor.HttpContext;
            if (context != null)
            {
                await context.SignOutAsync(CookieAuthenticationDefaults.AuthenticationScheme);
            }
        }
    }
}
