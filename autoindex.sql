CREATE OR REPLACE PROCEDURE autoindex()
LANGUAGE plpgsql
AS $$
BEGIN
    -- Subquery to identify tables with potentially missing indexes
    FOR missing_index_row IN (
        SELECT
            relname AS table_name,
            (seq_tup_read * 100)::FLOAT / NULLIF(idx_tup_read, 0) AS seq_vs_idx_read_ratio,
            (idx_scan * 100)::FLOAT / NULLIF(seq_scan, 0) AS idx_vs_seq_scan_ratio,
            string_agg(column_name, ', ') AS missing_columns
        FROM
            pg_stat_all_tables
        LEFT JOIN
            (
                -- Subquery to aggregate missing columns for each index
                SELECT
                    indexrelid,
                    string_agg(attname, ', ') AS column_name
                FROM
                    pg_index
                JOIN
                    pg_attribute ON indrelid = attrelid AND array_position(indkey, attnum) > 0
                GROUP BY
                    indexrelid
            ) AS missing_idx_cols ON missing_idx_cols.indexrelid = pg_stat_all_tables.relid
        WHERE
            schemaname='public' -- or the schema you're interested in
            AND seq_scan > 0
            AND idx_scan = 0
        GROUP BY
            relname, seq_tup_read, idx_tup_read, idx_scan, seq_scan
    )
    LOOP
        -- Generate CREATE INDEX statement for tables with poor ratio
        IF missing_index_row.seq_vs_idx_read_ratio > 60 AND missing_index_row.idx_vs_seq_scan_ratio > 60 THEN
            EXECUTE 'CREATE INDEX idx_' || missing_index_row.table_name || '_missing ON ' || missing_index_row.table_name || ' (' || missing_index_row.missing_columns || ');';
        END IF;
    END LOOP;
END;
$$;
