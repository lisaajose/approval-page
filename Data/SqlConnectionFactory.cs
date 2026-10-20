using Microsoft.Data.SqlClient;

namespace ApprovalWorkflow.Data
{
    public interface ISqlConnectionFactory
    {
        SqlConnection CreateConnection();
    }

    public class SqlConnectionFactory : ISqlConnectionFactory
    {
        private readonly string _connectionString;

        public SqlConnectionFactory(IConfiguration configuration)
        {
            _connectionString = configuration.GetConnectionString("ApprovalWorkflowDb")
                ?? throw new InvalidOperationException("Connection string 'ApprovalWorkflowDb' not found in configuration.");
        }

        public SqlConnection CreateConnection()
        {
            return new SqlConnection(_connectionString);
        }
    }
}
