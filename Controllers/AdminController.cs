using System.Text;
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

        // ----------------------------------------------------------------
        // GET /Admin/ApprovalMatrix
        // ----------------------------------------------------------------
        [HttpGet]
        public async Task<IActionResult> ApprovalMatrix()
        {
            var currentUser = await _userContextService.GetCurrentUserAsync();
            if (currentUser == null)
                return RedirectToAction("Login", "Auth", new { returnUrl = Request.Path });

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

        // ----------------------------------------------------------------
        // POST /Admin/UpdatePolicy  (single-row inline save)
        // ----------------------------------------------------------------
        [HttpPost]
        [ValidateAntiForgeryToken]
        public async Task<IActionResult> UpdatePolicy(ApprovalMatrixPolicyEditModel model)
        {
            var currentUser = await _userContextService.GetCurrentUserAsync();
            if (currentUser == null)
                return RedirectToAction("Login", "Auth", new { returnUrl = Request.Path });

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
                TempData["SuccessMessage"] = result.Message;
            else
                TempData["ErrorMessage"] = "Failed to update policy: " + result.Message;

            return RedirectToAction(nameof(ApprovalMatrix));
        }

        // ----------------------------------------------------------------
        // POST /Admin/ImportMatrixXml
        // ----------------------------------------------------------------
        [HttpPost]
        [ValidateAntiForgeryToken]
        public async Task<IActionResult> ImportMatrixXml(IFormFile xmlFile)
        {
            var currentUser = await _userContextService.GetCurrentUserAsync();
            if (currentUser == null)
                return RedirectToAction("Login", "Auth", new { returnUrl = Request.Path });

            if (currentUser.UserRole != 1)
            {
                TempData["ErrorMessage"] = "Unauthorized: Only administrators can import matrix policies.";
                return RedirectToAction("Index", "Voucher");
            }

            // File presence check
            if (xmlFile == null || xmlFile.Length == 0)
            {
                TempData["ErrorMessage"] = "No file selected. Please choose an XML file to upload.";
                return RedirectToAction(nameof(ApprovalMatrix));
            }

            // Extension check
            var ext = Path.GetExtension(xmlFile.FileName).ToLowerInvariant();
            if (ext != ".xml")
            {
                TempData["ErrorMessage"] = $"Invalid file type '{ext}'. Only .xml files are accepted.";
                return RedirectToAction(nameof(ApprovalMatrix));
            }

            // Size check (2 MB max)
            const long maxBytes = 2 * 1024 * 1024;
            if (xmlFile.Length > maxBytes)
            {
                TempData["ErrorMessage"] = $"File is too large ({xmlFile.Length / 1024} KB). Maximum allowed size is 2 MB.";
                return RedirectToAction(nameof(ApprovalMatrix));
            }

            // Read content
            string xmlContent;
            using (var reader = new StreamReader(xmlFile.OpenReadStream(), Encoding.UTF8))
            {
                xmlContent = await reader.ReadToEndAsync();
            }

            var result = await _approvalService.ImportApprovalMatrixFromXmlAsync(currentUser.UserId, xmlContent);

            if (result.Success)
                TempData["SuccessMessage"] = result.Message;
            else
                TempData["ErrorMessage"] = "Import failed: " + result.Message;

            return RedirectToAction(nameof(ApprovalMatrix));
        }

        // ----------------------------------------------------------------
        // GET /Admin/ExportMatrixXml  — downloads current matrix as XML
        // ----------------------------------------------------------------
        [HttpGet]
        public async Task<IActionResult> ExportMatrixXml()
        {
            var currentUser = await _userContextService.GetCurrentUserAsync();
            if (currentUser == null)
                return RedirectToAction("Login", "Auth", new { returnUrl = Request.Path });

            if (currentUser.UserRole != 1)
            {
                TempData["ErrorMessage"] = "Unauthorized: Only administrators can export matrix policies.";
                return RedirectToAction("Index", "Voucher");
            }

            var (success, xmlContent, message) = await _approvalService.ExportApprovalMatrixAsXmlAsync();

            if (!success)
            {
                TempData["ErrorMessage"] = "Export failed: " + message;
                return RedirectToAction(nameof(ApprovalMatrix));
            }

            string filename = $"ApprovalMatrix_{DateTime.Now:yyyyMMdd_HHmmss}.xml";
            byte[] bytes = Encoding.UTF8.GetBytes(xmlContent);
            return File(bytes, "application/xml", filename);
        }

        // ----------------------------------------------------------------
        // GET /Admin/DownloadMatrixTemplate  — provides a valid starter XML
        // ----------------------------------------------------------------
        [HttpGet]
        public async Task<IActionResult> DownloadMatrixTemplate()
        {
            var currentUser = await _userContextService.GetCurrentUserAsync();
            if (currentUser == null)
                return RedirectToAction("Login", "Auth", new { returnUrl = Request.Path });

            if (currentUser.UserRole != 1)
            {
                TempData["ErrorMessage"] = "Unauthorized.";
                return RedirectToAction("Index", "Voucher");
            }

            // Build a template from current live policies so it's always in sync
            var policies = await _approvalService.GetApprovalMatrixPoliciesAsync();

            var sb = new StringBuilder();
            sb.AppendLine("<?xml version=\"1.0\" encoding=\"utf-8\"?>");
            sb.AppendLine("<ApprovalMatrix xmlns=\"http://approvalworkflow.local/matrix\" version=\"1.0\">");
            sb.AppendLine("  <!--");
            sb.AppendLine("    Approval Matrix Import Template");
            sb.AppendLine("    ================================");
            sb.AppendLine("    Rules:");
            sb.AppendLine("      1. Do NOT add or remove <Policy> elements - only existing levels can be updated.");
            sb.AppendLine("      2. Level ranges must be contiguous: Level[i].MaxAmount + 0.01 == Level[i+1].MinAmount.");
            sb.AppendLine("      3. Only the highest level may have an empty <MaxAmount> (representing unlimited).");
            sb.AppendLine("      4. MinAmount must be >= 0. MaxAmount must be > MinAmount.");
            sb.AppendLine("      5. RequiredApprovers must be a non-negative integer.");
            sb.AppendLine("  -->");

            foreach (var p in policies.OrderBy(x => x.Level))
            {
                sb.AppendLine();
                sb.AppendLine($"  <!-- Level {p.Level}: {p.LevelName} -->");
                sb.AppendLine($"  <Policy level=\"{p.Level}\" name=\"{System.Security.SecurityElement.Escape(p.LevelName)}\">");
                sb.AppendLine($"    <MinAmount>{p.MinAmount:0.00}</MinAmount>");
                sb.AppendLine($"    <MaxAmount>{(p.MaxAmount.HasValue ? p.MaxAmount.Value.ToString("0.00") : string.Empty)}</MaxAmount>");
                sb.AppendLine($"    <RequiredApprovers>{p.RequiredApprovers}</RequiredApprovers>");
                sb.AppendLine($"    <ApproverDescription>{System.Security.SecurityElement.Escape(p.ApproverDescription)}</ApproverDescription>");
                sb.AppendLine($"    <PolicyDescription>{System.Security.SecurityElement.Escape(p.PolicyDescription)}</PolicyDescription>");
                sb.AppendLine($"  </Policy>");
            }

            sb.AppendLine();
            sb.AppendLine("</ApprovalMatrix>");

            byte[] bytes = Encoding.UTF8.GetBytes(sb.ToString());
            return File(bytes, "application/xml", "ApprovalMatrix_Template.xml");
        }
    }
}
