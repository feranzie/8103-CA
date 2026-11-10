SET search_path TO hospital;
ANALYZE;

\echo '=============== AFTER INDEXING ==============='
\timing on
\set explain 'EXPLAIN (ANALYZE, BUFFERS)'
\ir Ola-davies_Oluwaferanmi_301931917_query.sql