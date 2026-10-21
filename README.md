# FindAttractors.jl

Cycle-entry and overflow detection for nonnegative integer sequences. Julia 1.10+;
no external dependencies.

## Examples

```sh
julia --project=. --threads=8 examples/collatz_3n1.jl 100000000000
julia --project=. --threads=8 examples/collatz_5n3.jl 1000000
```

The examples use odd-to-odd rules. `collatz_3n1.jl` tests `3:4:stop`;
`collatz_5n3.jl` tests `1:2:stop`. The default stop is 1,000,000.
Each file is self-contained and can also be included without running a search.

## API

```julia
using FindAttractors

next_value(n) = n ÷ 2
max_input(::Type{T}) where T = typemax(T)

summary = find_attractors(next_value, max_input, UInt64(0):UInt64(1000);
                          extended_type=UInt128)
```

`next_value` must preserve integer type and be deterministic, thread-safe, and
non-yielding. `max_input(T)::T` bounds safe input, including intermediate
arithmetic. Reachable values must be nonnegative. Both types must be fixed-width
integers that represent 128; the extended type must contain the starting type.

The search stops at a cycle, a value below its start, or an arithmetic bound.
`overflow` means the orbit exceeded the supported arithmetic bounds; the unsafe
operation is not executed. No per-orbit iteration limit is imposed.

| Keyword | Default | Purpose |
| --- | --- | --- |
| `extended_type` | `eltype(starts)` | Type used for larger orbit values |
| `log_iter_freq` | `10_000` | Initial starts per thread per target second |
| `log_time_freq` | `2` | Target batch duration in seconds |
| `on_batch` | `report_batch` | Callback after each batch |

`SearchSummary` contains `processed`, `cycles`, `overflow`, and `elapsed`.
`cycles` counts reported starting-value / cycle-entry pairs.

`AttractorBatch` contains `starts`, `cycle_from`, `cycle_to`, `overflow`,
`elapsed`, and `batch_time`. Result vectors are indexed by thread ID and reused
after the callback returns. Copy any results you retain:

```julia
entries = Tuple{UInt64,UInt128}[]
overflow = UInt64[]

function collect_batch(batch)
    for thread_id in eachindex(batch.cycle_from)
        append!(entries, zip(batch.cycle_from[thread_id], batch.cycle_to[thread_id]))
        append!(overflow, batch.overflow[thread_id])
    end
end

summary = find_attractors(next_value, max_input, UInt64(0):UInt64(1000);
                          extended_type=UInt128, on_batch=collect_batch)
```

Use `on_batch = _ -> nothing` for a silent search, or
`on_batch = b -> report_batch(b; show_overflow=true)` to print overflow starts.
The log's `speed` measures numeric span per second; `starts` measures tested
starts per second. Both use `[M/s]`.

Call from thread 1 outside another threaded loop. Interrupts wait for a batch;
global signal handling belongs to the application.

## Development

Functions and fields use `snake_case`; modules and types use `PascalCase`.
The implementation is in `src/FindAttractors.jl`.

```sh
julia --project=. --threads=8 -e 'using Pkg; Pkg.test()'
```

Before publication, set author metadata in `Project.toml` and review `LICENSE`.
