module FindAttractors

export find_attractors, AttractorBatch, SearchSummary, report_batch

"""
Batch results: `starts`, per-thread `cycle_from`, `cycle_to`, and `overflow`,
plus `elapsed` and `batch_time` in seconds. Copy results before the callback returns.
"""
struct AttractorBatch{T,W,R}
    starts::R
    cycle_from::Vector{Vector{T}}
    cycle_to::Vector{Vector{W}}
    overflow::Vector{Vector{T}}
    elapsed::Float64
    batch_time::Float64
end

"""Search totals: `processed`, `cycles`, `overflow`, and `elapsed` in seconds."""
struct SearchSummary{N}
    processed::N
    cycles::Int
    overflow::Int
    elapsed::Float64
end

function trace_orbit(next_value::F, max_input::B, value::T, lower_bound::T) where {F,B,T}
    upper_bound = max_input(T)
    max_iter = T(128)
    cycle_candidate = (value == lower_bound ? typemax(T) : value)
    candidate_valid = value != lower_bound

    while true
        for _ in T(0):max_iter
            value = next_value(value)
            if (value <= lower_bound) || (value == cycle_candidate && candidate_valid) ||
               (value > upper_bound)
                return (value, candidate_valid ? cycle_candidate : lower_bound)
            end
            cycle_candidate = min(cycle_candidate, value)
            candidate_valid = true
        end
        max_iter += min(max_iter, typemax(T) - max_iter)
        cycle_candidate = value
        candidate_valid = true
    end
end

function classify_orbit!(next_value::F, max_input::B, n::T, cycle_from::Vector{T},
                         cycle_to::Vector{W}, overflow::Vector{T}) where {F,B,T,W}
    value = n
    if value <= max_input(T)
        (value, cycle_candidate) = trace_orbit(next_value, max_input, value, n)
        if (value == n) || (value == cycle_candidate)
            push!(cycle_from, n)
            push!(cycle_to, value)
            return nothing
        elseif value <= n
            return nothing
        end
    end

    if T == W || value > max_input(W)
        push!(overflow, n)
    else
        (value, cycle_candidate) = trace_orbit(next_value, max_input, W(value), W(n))
        if (value == n) || (value == cycle_candidate)
            push!(cycle_from, n)
            push!(cycle_to, value)
        elseif value > n
            push!(overflow, n)
        end
    end
    return nothing
end

"""
    report_batch(batch; io=stdout, show_overflow=false)

Print progress, cycle entries, and overflow results. Both rates use millions per second.
"""
function report_batch(batch::AttractorBatch; io::IO=stdout, show_overflow::Bool=false)
    span_speed = 1e-6 * (last(batch.starts) - first(batch.starts)) / batch.batch_time
    start_speed = 1e-6 * length(batch.starts) / batch.batch_time
    println(io, "LOG: n=", Float64(last(batch.starts)), ", time=", batch.elapsed,
            ", speed=", span_speed, " [M/s], starts=", start_speed, " [M/s]")
    for thread_id in eachindex(batch.cycle_from)
        for (from, to) in zip(batch.cycle_from[thread_id], batch.cycle_to[thread_id])
            println(io, string(from; base=10), " -> ", string(to; base=10))
        end
    end
    if show_overflow
        for values in batch.overflow, from in values
            println(io, string(from; base=10), " -> overflow")
        end
    else
        count = sum(length, batch.overflow)
        count == 0 || println(io, count, " overflow")
    end
    return nothing
end

function search_batch!(next_value::F, max_input::B, starts::R, cycle_from::Vector{Vector{T}},
                       cycle_to::Vector{Vector{W}}, overflow::Vector{Vector{T}}) where {F,B,R,T,W}
    Threads.@threads :static for n in starts
        thread_id = Threads.threadid()
        classify_orbit!(next_value, max_input, T(n), cycle_from[thread_id],
                        cycle_to[thread_id], overflow[thread_id])
    end
    return nothing
end

function validate_inputs(max_input, starts, ::Type{T}, ::Type{W},
                         log_iter_freq, log_time_freq) where {T,W}
    for S in (T, W)
        (isconcretetype(S) && isbitstype(S) && S <: Integer && S !== Bool) ||
            throw(ArgumentError("use fixed-width integer types other than Bool"))
        typemax(S) >= 128 || throw(ArgumentError("integer types must represent 128"))
        bound = max_input(S)
        (bound isa S && bound >= zero(S)) ||
            throw(ArgumentError("max_input($S) must return a nonnegative $S"))
    end
    (typemin(W) <= typemin(T) && typemax(W) >= typemax(T)) ||
        throw(ArgumentError("extended_type must represent every value of the starting type"))
    step(starts) > 0 || throw(ArgumentError("starts must have a positive step"))
    isempty(starts) || first(starts) >= 0 ||
        throw(ArgumentError("starting values must be nonnegative"))
    (log_iter_freq isa Integer && 0 < log_iter_freq <= typemax(Int)) ||
        throw(ArgumentError("log_iter_freq must be a positive machine-sized integer"))
    (isfinite(log_time_freq) && log_time_freq > 0) ||
        throw(ArgumentError("log_time_freq must be finite and positive"))
    return nothing
end

"""
    find_attractors(next_value, max_input, starts; extended_type=eltype(starts),
                   log_iter_freq=10_000, log_time_freq=2, on_batch=report_batch)

Search an increasing range of nonnegative fixed-width integers. `next_value`
must preserve type and be deterministic, thread-safe, and non-yielding.
`max_input(T)::T` bounds safe input, including intermediate arithmetic.
Both integer types must represent 128; `extended_type` must contain the starting type.

`on_batch` receives an `AttractorBatch` before its buffers are cleared.
Returns a `SearchSummary`. Overflow denotes exceeding the supported arithmetic
bounds. Call from thread 1 outside another threaded loop; interrupts wait for a batch.
"""
function find_attractors(next_value::F, max_input::B, starts::AbstractRange{T};
                        extended_type::Type{W}=T, log_iter_freq=10_000,
                        log_time_freq=2, max_time=Inf, on_batch::C=report_batch) where {F,B,T,W,C}
    validate_inputs(max_input, starts, T, W, log_iter_freq, log_time_freq)
    start_time = time()
    elapsed = 0.0
    count = length(starts)
    count == 0 && return SearchSummary(count, 0, 0, time() - start_time)

    thread_count = Threads.maxthreadid()
    cycle_from = [Vector{T}() for _ in 1:thread_count]
    cycle_to = [Vector{W}() for _ in 1:thread_count]
    overflow = [Vector{T}() for _ in 1:thread_count]
    cycle_count = overflow_count = 0

    batch_start = one(count)
    max_batch = typemax(Int) ÷ 10
    initial = Float64(log_time_freq) * log_iter_freq * Threads.nthreads()
    batch_size = max(1, floor(Int, min(Float64(max_batch), initial)))

    while elapsed <= max_time
        batch_count = Int(min(batch_size, count - batch_start + 1))
        batch_end = batch_start + (batch_count - 1)
        batch_range = T(starts[batch_start]):step(starts):T(starts[batch_end])
        batch_start_time = time()
        Base.disable_sigint() do
            search_batch!(next_value, max_input, batch_range, cycle_from, cycle_to, overflow)
        end
        batch_time = time() - batch_start_time
        elapsed = time() - start_time
        cycle_count += sum(length, cycle_from)
        overflow_count += sum(length, overflow)
        on_batch(AttractorBatch(batch_range, cycle_from, cycle_to, overflow,
                              elapsed, batch_time))
        for thread_id in 1:thread_count
            empty!(cycle_from[thread_id])
            empty!(cycle_to[thread_id])
            empty!(overflow[thread_id])
        end
        batch_end == count && break
        batch_start = batch_end + 1
        target = (log_time_freq / max(batch_time, eps(Float64))) * batch_size
        batch_size = max(1, round(Int, min(Float64(max_batch), 10.0 * batch_size, target)))
    end

    elapsed = time() - start_time
    return SearchSummary(count, cycle_count, overflow_count, elapsed)
end

end
