// The database through rust_g's MySQL pool (replaces BSQL). See hippiestation/code/controllers/subsystem/dbcore.dm.
// Every call_ext here returns JSON, except sql_query_async (a job id) and sql_check_query (RUSTG_JOB_NO_RESULTS_YET while running).

#define rustg_sql_connect_pool(options) call_ext(RUST_G, "sql_connect_pool")(options)
#define rustg_sql_query_async(handle, query, params) call_ext(RUST_G, "sql_query_async")(handle, query, params)
#define rustg_sql_query_blocking(handle, query, params) call_ext(RUST_G, "sql_query_blocking")(handle, query, params)
#define rustg_sql_connected(handle) call_ext(RUST_G, "sql_connected")(handle)
#define rustg_sql_disconnect_pool(handle) call_ext(RUST_G, "sql_disconnect_pool")(handle)
#define rustg_sql_check_query(job_id) call_ext(RUST_G, "sql_check_query")("[job_id]")

#define RUSTG_JOB_NO_RESULTS_YET "NO RESULTS YET"
#define RUSTG_JOB_NO_SUCH_JOB "NO SUCH JOB"
#define RUSTG_JOB_ERROR "JOB PANICKED"

/// Longest a failed connect waits before the next try (it doubles from 5 s each failure in a row)
#define DB_CONNECT_BACKOFF_MAX (2 MINUTES)
/// A query slower than this is logged to sql.log
#define DB_SLOW_QUERY (1 SECONDS)
/// MassInsert() sends at most this many rows a query
#define DB_MASS_INSERT_ROWS 500
