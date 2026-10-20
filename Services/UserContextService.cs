using ApprovalWorkflow.Models;

namespace ApprovalWorkflow.Services
{
    public interface IUserContextService
    {
        Task<User?> GetCurrentUserAsync();
        void SetCurrentUser(int userId);
        void ClearCurrentUser();
        bool IsAuthenticated();
    }

    public class UserContextService : IUserContextService
    {
        public const string UserCookieName = "ActiveWorkflowUserId";
        private const int FallbackDefaultUserId = 1; // JP

        private readonly IHttpContextAccessor _httpContextAccessor;
        private readonly IApprovalService _approvalService;

        public UserContextService(IHttpContextAccessor httpContextAccessor, IApprovalService approvalService)
        {
            _httpContextAccessor = httpContextAccessor;
            _approvalService = approvalService;
        }

        public bool IsAuthenticated()
        {
            var context = _httpContextAccessor.HttpContext;
            if (context != null && context.Request.Cookies.TryGetValue(UserCookieName, out var cookieVal))
            {
                return int.TryParse(cookieVal, out _);
            }
            return false;
        }

        public async Task<User?> GetCurrentUserAsync()
        {
            var context = _httpContextAccessor.HttpContext;
            int? userId = null;

            if (context != null && context.Request.Cookies.TryGetValue(UserCookieName, out var cookieVal))
            {
                if (int.TryParse(cookieVal, out int parsedId))
                {
                    userId = parsedId;
                }
            }

            if (userId.HasValue)
            {
                var user = await _approvalService.GetUserByIdAsync(userId.Value);
                if (user != null && user.Bactive == true)
                {
                    return user;
                }
            }

            return null;
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
                    SameSite = SameSiteMode.Lax,
                    Path = "/"
                });
            }
        }

        public void ClearCurrentUser()
        {
            var context = _httpContextAccessor.HttpContext;
            if (context != null)
            {
                context.Response.Cookies.Delete(UserCookieName, new CookieOptions
                {
                    Path = "/"
                });
            }
        }
    }
}
