using ApprovalWorkflow.Models;

namespace ApprovalWorkflow.Services
{
    public interface IUserContextService
    {
        Task<User> GetCurrentUserAsync();
        void SetCurrentUser(int userId);
    }

    public class UserContextService : IUserContextService
    {
        private const string UserCookieName = "ActiveWorkflowUserId";
        private const int DefaultUserId = 1; // Default to JP

        private readonly IHttpContextAccessor _httpContextAccessor;
        private readonly IApprovalService _approvalService;

        public UserContextService(IHttpContextAccessor httpContextAccessor, IApprovalService approvalService)
        {
            _httpContextAccessor = httpContextAccessor;
            _approvalService = approvalService;
        }

        public async Task<User> GetCurrentUserAsync()
        {
            var context = _httpContextAccessor.HttpContext;
            int userId = DefaultUserId;

            if (context != null && context.Request.Cookies.TryGetValue(UserCookieName, out var cookieVal))
            {
                if (int.TryParse(cookieVal, out int parsedId))
                {
                    userId = parsedId;
                }
            }

            var user = await _approvalService.GetUserByIdAsync(userId);
            if (user != null)
            {
                return user;
            }

            // Fallback
            var allUsers = await _approvalService.GetAllUsersAsync();
            return allUsers.FirstOrDefault() ?? new User { UserId = 1, Username = "JP" };
        }

        public void SetCurrentUser(int userId)
        {
            var context = _httpContextAccessor.HttpContext;
            if (context != null)
            {
                context.Response.Cookies.Append(UserCookieName, userId.ToString(), new CookieOptions
                {
                    Expires = DateTimeOffset.Now.AddDays(7),
                    HttpOnly = true,
                    SameSite = SameSiteMode.Lax
                });
            }
        }
    }
}
