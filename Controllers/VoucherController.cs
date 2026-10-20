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

                return View(details);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error retrieving voucher details for HeaderId {Id}", id);
                TempData["ErrorMessage"] = "Error retrieving voucher details: " + ex.Message;
                return RedirectToAction(nameof(Index));
            }
        }
    }
}
