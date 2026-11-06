using System;
using Microsoft.Data.SqlClient;

namespace ApprovalWorkflow.Data
{
    public static class SqlDataReaderExtensions
    {
        public static int GetIntSafe(this SqlDataReader reader, string columnName)
        {
            int ordinal = reader.GetOrdinal(columnName);
            return Convert.ToInt32(reader.GetValue(ordinal));
        }

        public static int? GetNullableIntSafe(this SqlDataReader reader, string columnName)
        {
            int ordinal = reader.GetOrdinal(columnName);
            if (reader.IsDBNull(ordinal)) return null;
            return Convert.ToInt32(reader.GetValue(ordinal));
        }

        public static int GetIntSafe(this SqlDataReader reader, int ordinal)
        {
            return Convert.ToInt32(reader.GetValue(ordinal));
        }

        public static int? GetNullableIntSafe(this SqlDataReader reader, int ordinal)
        {
            if (reader.IsDBNull(ordinal)) return null;
            return Convert.ToInt32(reader.GetValue(ordinal));
        }
    }
}

