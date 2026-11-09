// The database through rust_g's MySQL pool (replaces BSQL). See hippiestation/code/controllers/subsystem/dbcore.dm.
// The rustg_sql_* calls and RUSTG_JOB_* answers are in code/__DEFINES/rust_g.dm (rust_g 7's own file). Every one returns JSON,
// except sql_query_async (a job id) and sql_check_query (RUSTG_JOB_NO_RESULTS_YET while running).

/// Longest a failed connect waits before the next try (it doubles from 5 s each failure in a row)
#define DB_CONNECT_BACKOFF_MAX (2 MINUTES)
/// A query slower than this is logged to sql.log
#define DB_SLOW_QUERY (1 SECONDS)
/// MassInsert() sends at most this many rows a query
#define DB_MASS_INSERT_ROWS 500
