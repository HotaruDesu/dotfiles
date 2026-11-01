-- Defaults are promoted independently after the recorded end-to-end benchmark.
-- The original finder is always available while an index is warming or a query
-- needs semantics that the native adapter does not support.
return {
  files = "snacks",
  grep = "snacks",
  page_size = 200,
  max_threads = 4,
}
